## Central game state: hero, inventory, flags, quests, region persistence, save/load,
## plus the condition checker and effect interpreter used by dialogue, quests,
## Yaksha doors and shrines. Everything here is plain data so it serialises to JSON.
extends Node

## Where saves and settings live. Test runs (--smoke, --systems) point this at a scratch folder so they never touch real saves.
var save_dir := "user://saves"
const SAVE_SLOTS := 6   # slot 0 = quick save and autosave, 1-5 = chosen by the player
const KARMA_MIN := -1000
const KARMA_MAX := 1000
const FIST_BALA_MULT := 1.5   # Mushti Yuddha: a kill with bare fists gives this much more Bala tapas
const ARMOR_SLOTS := ["head", "chest", "hands", "legs", "feet"]
const EQUIP_SLOTS := ["melee", "ranged", "head", "chest", "hands", "legs", "feet", "hair", "beard", "tattoo"]

var hero: Dictionary = {}
var state: Dictionary = {}
var settings: Dictionary = {"lang": "nl", "mouse_sens": 1.0, "pad_sens": 1.0, "time_speed": 1.0, "quality": "high", "music": 0.5, "sfx": 0.8, "invert_y": false, "show_fps": false, "rumble": true, "bindings": {}}
const QuestSystemScript = preload("res://scripts/systems/Quests.gd")
const Bindings = preload("res://scripts/systems/Bindings.gd")
var quests: QuestSystemScript
var world = null
## True once the last thing the player touched was a gamepad: hints then name gamepad buttons (UI.gd keeps it up to date).
var pad_active: bool = false
var player = null
var in_game: bool = false
var buffs: Array = []
var paused_for_ui: bool = false
var arena_running: bool = false

func _ready() -> void:
	quests = QuestSystemScript.new()
	quests.name = "Quests"
	add_child(quests)
	load_settings()
	Bindings.setup(settings)   # the player's own keys over the defaults of project.godot
	Loc.set_lang(settings.get("lang", "nl"))

# =====================================================================
# New game
# =====================================================================
func new_game(hero_name: String) -> void:
	hero = _new_hero(hero_name)
	for m in Data.mudras.keys():
		if Data.mudras[m].get("unlock", "start") == "start":
			hero.mudras.append(m)
	state = _new_state()
	buffs = []
	hero.equipment["melee"] = "lathi"
	give("lathi", 1, true)
	in_game = true
	Events.hero_changed.emit()

## A fresh hero. load_game() also uses it to fill in whatever an older save does not have.
func _new_hero(hero_name: String) -> Dictionary:
	return {
		"name": hero_name if hero_name.strip_edges() != "" else "Vira",
		"age": 10.0,
		"stats": {"deha": 1, "prana": 1, "kavacha": 1, "vega": 1, "lakshya": 1, "chaturya": 1, "siddhibala": 1, "ojas": 1},
		"hp": 100.0, "ojas": 60.0,
		"tapas": {"general": 0, "bala": 0, "kaushala": 0, "shakti": 0},
		"tapas_total": 0,
		"karma": 0, "yasha": 0, "gold": 0,
		"siddhis": {}, "hotbar": ["", "", "", "", "", ""],
		"inventory": {}, "equipment": {"melee": "", "ranged": "", "head": "", "chest": "", "hands": "", "legs": "", "feet": "", "hair": "", "beard": "", "tattoo": ""},
		"augments": {},
		"panth": "", "spouse": "", "houses": [],
		"mudras": [], "counters": {"keys_found": 0, "kills": 0, "fish": 0, "chests": 0, "donated": 0, "yaksha": 0},
		"drunk": 0.0, "poison": 0.0, "scars": 0,
		"ranged_stance": false,
		"water": 0,   # sips left in the kamandalu
	}

func _new_state() -> Dictionary:
	return {
		"flags": {}, "quests": {}, "regions": {}, "affection": {}, "followers": [],
		"region": "vatagram_bachpan", "entry": "", "pos": [0, 0, 0],
		"time": 9.0, "day": 1, "play_time": 0.0,
		"tirthas": [], "slot": 0, "version": SD_VERSION,
	}

const SD_VERSION := "1.0.0"

# =====================================================================
# Derived stats
# =====================================================================
func stat(id: String) -> int:
	return int(hero.stats.get(id, 1))

func hp_max() -> float:
	var v := 100.0 + 35.0 * (stat("prana") - 1)
	v += aug_total("health")
	v += panth_bonus("hp_max")
	v += float(hero.get("hp_bonus", 0))
	return v

func ojas_max() -> float:
	var v := 60.0 + 30.0 * (stat("ojas") - 1)
	for s in ARMOR_SLOTS:
		var it := Data.item(hero.equipment.get(s, ""))
		v += float(it.get("ojas", 0))
	v += panth_bonus("ojas_max")
	return v

func melee_mult() -> float:
	var m := 1.0 + 0.3 * (stat("deha") - 1) + panth_bonus("melee_mult")
	m *= buff_mult("damage")
	m *= ugra_mult()
	return m

func ranged_mult() -> float:
	var m := 1.0 + 0.3 * (stat("lakshya") - 1) + panth_bonus("ranged_mult")
	m *= buff_mult("damage")
	return m

func siddhi_mult() -> float:
	return (1.0 + 0.3 * (stat("siddhibala") - 1) + panth_bonus("siddhi_mult") + ashrama_bonus("siddhi_mult")) * buff_mult("damage")

func siddhi_cost_mult() -> float:
	return 1.0 + panth_bonus("siddhi_cost")

func dmg_reduction() -> float:
	var r := 0.06 * (stat("kavacha") - 1) + total_def() / 100.0
	return clampf(r, 0.0, 0.75)

func total_def() -> float:
	var d := 0.0
	for s in ARMOR_SLOTS:
		d += float(Data.item(hero.equipment.get(s, "")).get("def", 0))
	return d

func armor_weight() -> float:
	var w := 0.0
	for s in ARMOR_SLOTS:
		w += float(Data.item(hero.equipment.get(s, "")).get("weight", 0))
	return w

func speed_mult() -> float:
	var m := 1.0 + 0.07 * (stat("vega") - 1) + panth_bonus("speed_mult") + ashrama_bonus("speed_mult")
	m -= armor_weight() * 0.02
	m *= buff_mult("speed")
	if hero.drunk > 10.0:
		m *= 0.85
	return maxf(0.5, m)

func price_mult() -> float:
	return maxf(0.6, 1.0 - 0.05 * (stat("chaturya") - 1))

func ojas_regen() -> float:
	var r := 1.5 + 0.5 * (stat("ojas") - 1)
	r += aug_total("ojas")
	r += panth_bonus("ojas_regen") * 2.0 + ashrama_bonus("ojas_regen") * 2.0
	if has("rudraksha_mala"):
		r += 1.5
	r *= buff_mult("ojas_regen")
	return r

func hp_regen() -> float:
	return 0.2 + 0.1 * (stat("prana") - 1)

func saundarya() -> int:
	var v := 0
	for s in EQUIP_SLOTS:
		v += int(Data.item(hero.equipment.get(s, "")).get("saundarya", 0))
	v += int(clampf(hero.karma / 100.0, 0, 10))
	v -= int(hero.get("scars", 0))
	return v

func bhaya() -> int:
	var v := 0
	for s in EQUIP_SLOTS:
		v += int(Data.item(hero.equipment.get(s, "")).get("bhaya", 0))
	v += int(clampf(-hero.karma / 100.0, 0, 10))
	v += int(hero.get("scars", 0))
	return v

func ashrama() -> Dictionary:
	for a in Data.misc.get("ashramas", []):
		if hero.age >= float(a["min_age"]) and hero.age < float(a["max_age"]):
			return a
	return Data.misc.get("ashramas", [{}])[0]

func ashrama_bonus(key: String) -> float:
	return float(ashrama().get("bonus", {}).get(key, 0.0))

func panth_bonus(key: String) -> float:
	if hero.panth == "":
		return 0.0
	var p := Data.panth(hero.panth)
	var v = p.get("bonus", {}).get(key, 0.0)
	return float(v) if (v is float or v is int) else 0.0

func panth_flag(key: String) -> bool:
	if hero.panth == "":
		return false
	return bool(Data.panth(hero.panth).get("bonus", {}).get(key, false))

func karma_title() -> String:
	for t in Data.misc.get("karma_titles", []):
		if hero.karma >= int(t["min"]):
			return Loc.t(t["name"])
	return ""

func yasha_title() -> String:
	for t in Data.misc.get("yasha_titles", []):
		if hero.yasha >= int(t["min"]):
			return Loc.t(t["name"])
	return ""

func is_child() -> bool:
	return hero.age < 14.0

# ---------- buffs ----------
func add_buff(stat_id: String, mult: float, duration: float) -> void:
	buffs.append({"stat": stat_id, "mult": mult, "until": state.play_time + duration})

func buff_mult(stat_id: String) -> float:
	var m := 1.0
	for b in buffs:
		if b["stat"] == stat_id and b["until"] > state.play_time:
			m *= float(b["mult"])
	return m

func buff_active(stat_id: String) -> bool:
	for b in buffs:
		if b["stat"] == stat_id and b["until"] > state.play_time:
			return true
	return false

func buff_remaining(stat_id: String) -> float:
	var t := 0.0
	for b in buffs:
		if b["stat"] == stat_id:
			t = maxf(t, b["until"] - state.play_time)
	return t

func ugra_mult() -> float:
	return buff_mult("ugra")

func tick(delta: float) -> void:
	state.play_time += delta
	if buffs.size() > 0:
		buffs = buffs.filter(func(b): return b["until"] > state.play_time)
	# time of day: 1 game hour per 60 real seconds at speed 1
	var prev := int(state.time)
	state.time += delta * float(settings.get("time_speed", 1.0)) / 60.0
	if state.time >= 24.0:
		state.time -= 24.0
		state.day += 1
	if int(state.time) != prev:
		Events.time_changed.emit(state.time)
	if hero.drunk > 0.0:
		hero.drunk = maxf(0.0, hero.drunk - delta * 0.6)
	if hero.poison > 0.0:
		hero.poison = maxf(0.0, hero.poison - delta)
		damage_hero(delta * 2.0, "poison", true)

func is_night() -> bool:
	return state.time >= 19.5 or state.time < 5.0

func time_string() -> String:
	var h := int(state.time)
	var m := int((state.time - h) * 60.0)
	return "%02d:%02d" % [h, m]

# =====================================================================
# Tapas / progression
# =====================================================================
func add_tapas(kind: String, amount: int) -> void:
	if amount <= 0:
		return
	var mult := 1.0 + aug_total("tapas") + panth_bonus("tapas_mult") + ashrama_bonus("tapas_mult")
	var a := int(round(amount * mult))
	hero.tapas[kind] = int(hero.tapas.get(kind, 0)) + a
	hero.tapas_total = int(hero.tapas_total) + a
	Events.tapas_gained.emit(kind, a)
	Events.hero_changed.emit()

func stat_cost(level: int) -> int:
	var costs: Array = Data.misc.get("stat_costs", [150, 560, 1200, 2100, 3200, 4500])
	if level - 1 < costs.size():
		return int(costs[level - 1])
	return -1

func can_raise(stat_id: String) -> bool:
	var lvl := stat(stat_id)
	if lvl >= 7:
		return false
	var cost := stat_cost(lvl)
	var disc: String = Data.misc.stats.get(stat_id, {}).get("discipline", "bala")
	return int(hero.tapas.get(disc, 0)) + int(hero.tapas.general) >= cost

func raise_stat(stat_id: String) -> bool:
	if not can_raise(stat_id):
		return false
	var lvl := stat(stat_id)
	var cost := stat_cost(lvl)
	var disc: String = Data.misc.stats.get(stat_id, {}).get("discipline", "bala")
	_pay_tapas(disc, cost)
	hero.stats[stat_id] = lvl + 1
	hero.age += float(Data.misc.get("age_per_level", 0.4))
	if stat_id == "prana":
		hero.hp = minf(hero.hp + 35.0, hp_max())
	if stat_id == "ojas":
		hero.ojas = minf(hero.ojas + 30.0, ojas_max())
	Events.stat_raised.emit(stat_id, lvl + 1)
	Events.notify.emit(Loc.t("UI_LEVEL_UP", {"stat": Loc.t(Data.misc.stats[stat_id]["name"]), "level": lvl + 1}), "good")
	Audio.play("levelup")
	Events.hero_changed.emit()
	return true

func _pay_tapas(disc: String, cost: int) -> void:
	var from_disc := mini(cost, int(hero.tapas.get(disc, 0)))
	hero.tapas[disc] = int(hero.tapas.get(disc, 0)) - from_disc
	hero.tapas.general = int(hero.tapas.general) - (cost - from_disc)

# ---------- siddhis ----------
func siddhi_level(id: String) -> int:
	return int(hero.siddhis.get(id, 0))

func siddhi_next_cost(id: String) -> int:
	var lvl := siddhi_level(id)
	if lvl >= 4:
		return -1
	return int(Data.siddhi(id)["levels"][lvl]["tapas"])

func can_learn_siddhi(id: String) -> bool:
	var cost := siddhi_next_cost(id)
	if cost < 0:
		return false
	return int(hero.tapas.shakti) + int(hero.tapas.general) >= cost

func learn_siddhi(id: String, free: bool = false) -> bool:
	var lvl := siddhi_level(id)
	if lvl >= 4:
		return false
	if not free:
		if not can_learn_siddhi(id):
			return false
		_pay_tapas("shakti", siddhi_next_cost(id))
	hero.siddhis[id] = lvl + 1
	if lvl == 0:
		for i in 6:
			if hero.hotbar[i] == "":
				hero.hotbar[i] = id
				break
	Events.notify.emit(Loc.t("UI_SIDDHI_LEARNED", {"name": Loc.t(Data.siddhi(id)["name"]), "level": lvl + 1}), "good")
	Audio.play("levelup")
	Events.hero_changed.emit()
	return true

func siddhi_params(id: String) -> Dictionary:
	var lvl := siddhi_level(id)
	if lvl <= 0:
		return {}
	var p: Dictionary = Data.siddhi(id)["levels"][lvl - 1].duplicate()
	p["level"] = lvl
	return p

func set_hotbar(slot: int, id: String) -> void:
	hero.hotbar[slot] = id
	Events.hero_changed.emit()

# ---------- panth ----------
func can_initiate(panth_id: String) -> Dictionary:
	var p := Data.panth(panth_id)
	if p.is_empty():
		return {"ok": false, "why": "?"}
	if hero.panth == panth_id:
		return {"ok": false, "why": Loc.t("UI_ALREADY_INITIATED")}
	var req: Dictionary = p.get("requires", {})
	if req.has("stat_min") and stat(req["stat_min"][0]) < int(req["stat_min"][1]):
		return {"ok": false, "why": Loc.t("UI_REQ_STAT", {"stat": Loc.t(Data.misc.stats[req["stat_min"][0]]["name"]), "level": req["stat_min"][1]})}
	if req.has("quest_done") and not quests.is_done(req["quest_done"]):
		return {"ok": false, "why": Loc.t("UI_REQ_QUEST", {"name": Loc.t(Data.quest(req["quest_done"]).get("name", {}))})}
	if req.has("karma_min") and hero.karma < int(req["karma_min"]):
		return {"ok": false, "why": Loc.t("UI_REQ_KARMA", {"value": req["karma_min"]})}
	if hero.gold < int(p.get("cost", 0)):
		return {"ok": false, "why": Loc.t("UI_NOT_ENOUGH_GOLD")}
	return {"ok": true, "why": ""}

func initiate(panth_id: String) -> bool:
	var c := can_initiate(panth_id)
	if not c["ok"]:
		return false
	spend_gold(int(Data.panth(panth_id).get("cost", 0)))
	hero.panth = panth_id
	Events.panth_initiated.emit(panth_id)
	Events.notify.emit(Loc.t("UI_INITIATED", {"name": Loc.t(Data.panth(panth_id)["name"])}), "good")
	Audio.play("bell")
	Events.hero_changed.emit()
	return true

# =====================================================================
# Karma, renown, gold
# =====================================================================
func add_karma(delta: int) -> void:
	if delta == 0:
		return
	hero.karma = clampi(int(hero.karma) + delta, KARMA_MIN, KARMA_MAX)
	Events.karma_changed.emit(delta, hero.karma)
	Events.notify.emit(("+%d " % delta if delta > 0 else "%d " % delta) + Loc.t("UI_KARMA"), "karma_up" if delta > 0 else "karma_down")
	Events.hero_changed.emit()

func add_yasha(delta: int) -> void:
	if delta == 0:
		return
	var d := int(round(delta * (1.0 + panth_bonus("yasha_mult")))) if delta > 0 else delta
	hero.yasha = maxi(0, int(hero.yasha) + d)
	Events.yasha_changed.emit(hero.yasha)
	Events.notify.emit("+%d %s" % [d, Loc.t("UI_YASHA")], "good")
	Events.hero_changed.emit()

func add_gold(delta: int) -> void:
	if delta == 0:
		return
	hero.gold = maxi(0, int(hero.gold) + delta)
	Events.gold_changed.emit(hero.gold)
	if delta > 0:
		Events.notify.emit("+%d %s" % [delta, Loc.t("UI_GOLD")], "gold")
	Events.hero_changed.emit()

func spend_gold(amount: int) -> bool:
	if hero.gold < amount:
		Events.notify.emit(Loc.t("UI_NOT_ENOUGH_GOLD"), "bad")
		return false
	hero.gold -= amount
	Events.gold_changed.emit(hero.gold)
	Events.hero_changed.emit()
	return true

# =====================================================================
# Inventory & equipment
# =====================================================================
func count(item_id: String) -> int:
	return int(hero.inventory.get(item_id, 0))

func has(item_id: String, n: int = 1) -> bool:
	return count(item_id) >= n

func give(item_id: String, n: int = 1, silent: bool = false) -> void:
	if not Data.items.has(item_id):
		push_warning("give: unknown item " + item_id)
		return
	var had := count(item_id)
	hero.inventory[item_id] = had + n
	if item_id == "kamandalu" and had == 0:
		hero.water = water_max()   # a pot you get comes full
	if item_id == "rajat_kunji":
		hero.counters.keys_found = int(hero.counters.keys_found) + n
	if not silent:
		Events.notify.emit(Loc.t("UI_ITEM_GET", {"name": Loc.t(Data.item(item_id)["name"]), "count": n}), "item")
		Audio.play("pickup")
	Events.item_picked.emit(item_id, n)
	Events.hero_changed.emit()

func take(item_id: String, n: int = 1) -> bool:
	if count(item_id) < n:
		return false
	hero.inventory[item_id] = count(item_id) - n
	if hero.inventory[item_id] <= 0:
		hero.inventory.erase(item_id)
		for s in EQUIP_SLOTS:
			if hero.equipment.get(s, "") == item_id:
				hero.equipment[s] = ""
	Events.hero_changed.emit()
	return true

func equipped(slot: String) -> String:
	return hero.equipment.get(slot, "")

func equipped_item(slot: String) -> Dictionary:
	return Data.item(equipped(slot))

func slot_for(it: Dictionary) -> String:
	var cat: String = it.get("cat", "")
	if cat in ["melee", "ranged", "head", "chest", "hands", "legs", "feet", "hair", "beard", "tattoo"]:
		return cat
	return ""

func equip(item_id: String) -> bool:
	var it := Data.item(item_id)
	var slot := slot_for(it)
	if slot == "" or not has(item_id):
		return false
	if is_child() and it.get("cat", "") in ["melee", "ranged"] and item_id != "lathi":
		return false
	hero.equipment[slot] = item_id
	if slot == "ranged":
		hero.ranged_stance = false
	Events.equipment_changed.emit()
	Events.hero_changed.emit()
	Audio.play("equip")
	return true

func unequip(slot: String) -> void:
	hero.equipment[slot] = ""
	Events.equipment_changed.emit()
	Events.hero_changed.emit()

func wearing_armor() -> bool:
	for s in ARMOR_SLOTS:
		if hero.equipment.get(s, "") != "":
			return true
	return false

func item_buy_price(item_id: String, shop_mult: float = 1.0) -> int:
	var v := int(Data.item(item_id).get("value", 10))
	return maxi(1, int(round(v * shop_mult * price_mult())))

func item_sell_price(item_id: String) -> int:
	var v := int(Data.item(item_id).get("value", 10))
	return int(round(v * 0.4 * (2.0 - price_mult())))

func drop_item(item_id: String) -> void:
	if take(item_id, 1):
		Events.notify.emit(Loc.t("UI_DROPPED", {"name": Loc.t(Data.item(item_id)["name"])}), "item")

## Use a consumable (potion / food / book / tool with use-block).
func use_item(item_id: String) -> bool:
	var it := Data.item(item_id)
	if it.is_empty() or not has(item_id):
		return false
	var u: Dictionary = it.get("use", {})
	if u.is_empty():
		if Data.is_weapon(it) or Data.is_armor(it) or Data.is_cosmetic(it):
			return equip(item_id)
		return false
	var consume := bool(u.get("consume", true))
	if it.get("refill", false):
		if int(hero.water) <= 0:
			Events.notify.emit(Loc.t("UI_KAMANDALU_EMPTY"), "bad")
			return false
		if hero.hp >= hp_max() and hero.ojas >= ojas_max():
			Events.notify.emit(Loc.t("UI_PRANA_FULL"), "info")   # no sip wasted on a full hero
			return false
		hero.water = int(hero.water) - 1
		Events.notify.emit(Loc.t("UI_KAMANDALU_SIP", {"n": int(hero.water), "max": water_max()}), "item")
	if it.get("cat", "") == "book":
		var fl := "read_" + item_id
		if flag(fl):
			Events.notify.emit(Loc.t("UI_ALREADY_READ"), "info")
			return false
		set_flag(fl, true)
		consume = false
	if u.has("heal"):
		heal(float(u["heal"]))
	if u.has("ojas"):
		hero.ojas = minf(ojas_max(), hero.ojas + float(u["ojas"]))
	if u.has("tapas"):
		add_tapas("general", int(u["tapas"]))
	for k in ["bala", "kaushala", "shakti"]:
		if u.has("tapas_" + k):
			add_tapas(k, int(u["tapas_" + k]))
	if u.has("karma"):
		add_karma(int(u["karma"]))
	if u.has("yasha"):
		add_yasha(int(u["yasha"]))
	if u.has("age"):
		hero.age = maxf(18.0, hero.age + float(u["age"]))
	if u.has("hp_max"):
		hero["hp_bonus"] = int(hero.get("hp_bonus", 0)) + int(u["hp_max"])
	if u.has("cure"):
		hero.poison = 0.0
	if u.has("drunk"):
		hero.drunk = minf(100.0, hero.drunk + float(u["drunk"]))
		if hero.drunk > 25.0:
			Events.notify.emit(Loc.t("UI_DRUNK"), "info")
	if u.has("buff"):
		var b: Dictionary = u["buff"]
		add_buff(b["stat"], float(b["mult"]), float(b["duration"]))
	if u.has("mudra"):
		add_mudra(u["mudra"])
	if u.has("set_flag"):
		set_flag(u["set_flag"], true)
	if u.has("lore"):
		set_flag("lore_" + str(u["lore"]), true)
	if u.has("resurrect"):
		return false  # handled on death
	if it.get("cat", "") == "food":
		Audio.play("eat")
		set_flag("ate_" + str(it.get("guna", "sattva")), true)
		Events.ate.emit(item_id)
	else:
		Audio.play("drink")
	Events.item_used.emit(item_id)
	if consume:
		take(item_id, 1)
	Events.hero_changed.emit()
	return true

## Sips a full kamandalu holds.
func water_max() -> int:
	return int(Data.item("kamandalu").get("charges", 3))

## Fill the kamandalu at water (E at a lake, river, well or fountain). False when there is nothing to fill.
func refill_water() -> bool:
	if not has("kamandalu"):
		return false
	if int(hero.water) >= water_max():
		Events.notify.emit(Loc.t("UI_KAMANDALU_FULL"), "info")
		return false
	hero.water = water_max()
	Audio.play("splash")
	Events.notify.emit(Loc.t("UI_KAMANDALU_FILLED"), "good")
	Events.hero_changed.emit()
	return true

## Elixirs that restore `stat_key` ("heal" = Prana, "ojas"): {item id: amount}. Antidotes (cure)
## are left out, they are for poison.
func potions_for(stat_key: String) -> Dictionary:
	var out := {}
	for id in hero.inventory.keys():
		var it := Data.item(id)
		var u: Dictionary = it.get("use", {})
		if it.get("cat", "") == "potion" and u.has(stat_key) and not u.has("cure"):
			out[id] = float(u[stat_key])
	return out

func potion_count(stat_key: String) -> int:
	var n := 0
	for id in potions_for(stat_key).keys():
		n += count(id)
	return n

## The elixir a hotkey drinks: the smallest one that fills what is missing, else the biggest.
func best_potion(stat_key: String) -> String:
	var missing := (hp_max() - float(hero.hp)) if stat_key == "heal" else (ojas_max() - float(hero.ojas))
	var best := ""
	var best_amt := 0.0
	for id in potions_for(stat_key).keys():
		var amt: float = potions_for(stat_key)[id]
		var fits := amt >= missing
		var best_fits := best_amt >= missing
		if best == "" or (fits and (not best_fits or amt < best_amt)) or (not fits and not best_fits and amt > best_amt):
			best = id
			best_amt = amt
	return best

## R / T: drink an elixir for Prana ("heal") or Ojas ("ojas"). Never wastes one on a full bar.
func quaff(stat_key: String) -> bool:
	var is_prana := stat_key == "heal"
	var missing := (hp_max() - float(hero.hp)) if is_prana else (ojas_max() - float(hero.ojas))
	if missing < 1.0:
		Events.notify.emit(Loc.t("UI_PRANA_FULL" if is_prana else "UI_OJAS_FULL"), "info")
		return false
	var id := best_potion(stat_key)
	if id == "":
		Events.notify.emit(Loc.t("UI_NO_PRANA_RASA" if is_prana else "UI_NO_OJAS_RASA"), "bad")
		return false
	if not use_item(id):
		return false
	Events.notify.emit(Loc.t("UI_DRANK", {"name": Loc.t(Data.item(id)["name"])}), "item")
	return true

# ---------- augmentation gems ----------
func weapon_augs(weapon_id: String) -> Array:
	var out := []
	var it := Data.item(weapon_id)
	var inherent = it.get("aug", [])
	if inherent is Dictionary:
		out.append(inherent)
	elif inherent is Array:
		for a in inherent:
			out.append(a)
	for gem in hero.augments.get(weapon_id, []):
		var g := Data.item(gem)
		if g.has("aug"):
			out.append(g["aug"])
	return out

func aug_total(type: String) -> float:
	var t := 0.0
	for wid in [equipped("melee"), equipped("ranged")]:
		if wid == "":
			continue
		for a in weapon_augs(wid):
			if a.get("type", "") == type:
				t += float(a.get("power", 0))
	return t

func socket_gem(weapon_id: String, gem_id: String) -> bool:
	var it := Data.item(weapon_id)
	var slots := int(it.get("slots", 0))
	var cur: Array = hero.augments.get(weapon_id, [])
	if cur.size() >= slots or not has(gem_id) or not has(weapon_id):
		return false
	cur.append(gem_id)
	hero.augments[weapon_id] = cur
	take(gem_id, 1)
	Audio.play("equip")
	Events.hero_changed.emit()
	return true

# =====================================================================
# Health
# =====================================================================
func heal(amount: float) -> void:
	hero.hp = minf(hp_max(), hero.hp + amount)
	Events.hero_changed.emit()

func damage_hero(amount: float, source: String = "", silent: bool = false) -> void:
	if amount <= 0.0 or hero.hp <= 0.0:   # a dead hero (poison keeps ticking) must not die again
		return
	hero.hp -= amount
	if not silent:
		Events.player_damaged.emit(amount)
	if hero.hp <= 0.0:
		hero.hp = 0.0
		on_player_death()

func on_player_death() -> void:
	if has("amrita_phial"):
		take("amrita_phial", 1)
		hero.hp = hp_max()
		hero.ojas = ojas_max()
		Events.notify.emit(Loc.t("UI_AMRITA_USED"), "good")
		Audio.play("heal")
		Events.hero_changed.emit()
		return
	Events.player_died.emit()

func respawn_penalty() -> void:
	hero.hp = hp_max()
	hero.ojas = ojas_max() * 0.5
	hero.gold = int(hero.gold * 0.9)
	hero.scars = int(hero.get("scars", 0)) + 1
	Events.hero_changed.emit()

# =====================================================================
# Flags, affection, followers, houses, marriage
# =====================================================================
func flag(name: String) -> bool:
	return bool(state.flags.get(name, false))

func set_flag(name: String, value = true) -> void:
	if value is bool and not value:
		state.flags.erase(name)
	else:
		state.flags[name] = value
	Events.flag_set.emit(name, value)
	if world != null and world.has_method("refresh_conditionals"):
		world.refresh_conditionals()

func clear_flag(name: String) -> void:
	set_flag(name, false)

func affection(npc: String) -> int:
	return int(state.affection.get(npc, 0))

func add_affection(npc: String, delta: int) -> void:
	var d := int(round(delta * (1.0 + panth_bonus("affection_mult")))) if delta > 0 else delta
	state.affection[npc] = clampi(affection(npc) + d, -100, 200)
	if d != 0:
		Events.notify.emit("%s %+d %s" % [Loc.t(Data.character(npc).get("name", {})), d, Loc.t("UI_AFFECTION")], "info")

func is_following(npc: String) -> bool:
	return state.followers.has(npc)

func follow(npc: String) -> void:
	if not state.followers.has(npc):
		state.followers.append(npc)
	if world != null and world.has_method("set_follower"):
		world.set_follower(npc, true)

func unfollow(npc: String) -> void:
	state.followers.erase(npc)
	if world != null and world.has_method("set_follower"):
		world.set_follower(npc, false)

func add_mudra(id: String) -> void:
	if not hero.mudras.has(id) and Data.mudras.has(id):
		hero.mudras.append(id)
		Events.notify.emit(Loc.t("UI_MUDRA_LEARNED", {"name": Loc.t(Data.mudras[id]["name"])}), "good")

func mudra_available(id: String) -> Dictionary:
	var m: Dictionary = Data.mudras.get(id, {})
	var u: String = m.get("unlock", "start")
	if hero.mudras.has(id):
		if u.begins_with("item:") and not has(u.substr(5)):
			return {"ok": false, "why": Loc.t("UI_NEED_ITEM", {"name": Loc.t(Data.item(u.substr(5))["name"])})}
		return {"ok": true, "why": ""}
	if u.begins_with("item:"):
		if has(u.substr(5)):
			return {"ok": true, "why": ""}
		return {"ok": false, "why": Loc.t("UI_NEED_ITEM", {"name": Loc.t(Data.item(u.substr(5))["name"])})}
	if u.begins_with("yasha:"):
		if hero.yasha >= int(u.substr(6)):
			return {"ok": true, "why": ""}
		return {"ok": false, "why": Loc.t("UI_REQ_YASHA", {"value": u.substr(6)})}
	if u.begins_with("karma:"):
		if hero.karma >= int(u.substr(6)):
			return {"ok": true, "why": ""}
		return {"ok": false, "why": Loc.t("UI_REQ_KARMA", {"value": u.substr(6)})}
	if u.begins_with("bhaya:"):
		if bhaya() >= int(u.substr(6)):
			return {"ok": true, "why": ""}
		return {"ok": false, "why": Loc.t("UI_REQ_BHAYA", {"value": u.substr(6)})}
	if u.begins_with("book:"):
		return {"ok": false, "why": Loc.t("UI_REQ_BOOK", {"name": Loc.t(Data.item(u.substr(5))["name"])})}
	return {"ok": u == "start", "why": ""}

func perform_mudra(id: String) -> bool:
	var av := mudra_available(id)
	if not av["ok"]:
		Events.notify.emit(av["why"], "bad")
		return false
	Events.mudra_performed.emit(id)
	Audio.play("mudra")
	return true

func buy_house(region_id: String) -> void:
	if not hero.houses.has(region_id):
		hero.houses.append(region_id)
		Events.notify.emit(Loc.t("UI_HOUSE_BOUGHT"), "good")

func marry(npc: String) -> void:
	hero.spouse = npc
	Events.notify.emit(Loc.t("UI_MARRIED", {"name": Loc.t(Data.character(npc).get("name", {}))}), "good")
	Audio.play("bell")

func sleep() -> void:
	state.time = 6.0
	state.day += 1
	hero.hp = hp_max()
	hero.ojas = ojas_max()
	hero.drunk = 0.0
	hero.poison = 0.0
	Events.time_changed.emit(state.time)
	Events.notify.emit(Loc.t("UI_SLEPT"), "info")
	Events.hero_changed.emit()
	save_game(0, true)

# =====================================================================
# Region persistence
# =====================================================================
func region_state(id: String) -> Dictionary:
	if not state.regions.has(id):
		state.regions[id] = {"chests": [], "picked": [], "keys": [], "dug": [], "yaksha": false, "visited": false, "killed_once": [], "first_enter_done": false}
	return state.regions[id]

func unlock_tirtha(id: String) -> void:
	if not state.tirthas.has(id) and Data.regions.has(id):
		state.tirthas.append(id)
		Events.notify.emit(Loc.t("UI_TIRTHA_UNLOCKED", {"name": Loc.t(Data.region(id)["name"])}), "good")

# =====================================================================
# Conditions
# =====================================================================
func check(cond) -> bool:
	if cond == null:
		return true
	if cond is Array:
		for c in cond:
			if not check(c):
				return false
		return true
	if not cond is Dictionary:
		return true
	var c: Dictionary = cond
	for key in c.keys():
		var v = c[key]
		match key:
			"all":
				for sub in v:
					if not check(sub):
						return false
			"any":
				var ok := false
				for sub in v:
					if check(sub):
						ok = true
						break
				if not ok:
					return false
			"not":
				if check(v):
					return false
			"flag":
				var list: Array = v if v is Array else [v]
				for f in list:
					if not flag(f):
						return false
			"not_flag":
				var list2: Array = v if v is Array else [v]
				for f in list2:
					if flag(f):
						return false
			"quest_active":
				if not quests.is_active(v):
					return false
			"quest_done":
				if not quests.is_done(v):
					return false
			"quest_inactive":
				if not quests.is_inactive(v):
					return false
			"quest_failed":
				if quests.state_of(v) != "failed":
					return false
			"quest_stage":
				if not (quests.is_active(v[0]) and quests.stage_of(v[0]) == int(v[1])):
					return false
			"quest_stage_min":
				if not (quests.is_active(v[0]) and quests.stage_of(v[0]) >= int(v[1])):
					return false
			"karma_min":
				if hero.karma < int(v):
					return false
			"karma_max":
				if hero.karma > int(v):
					return false
			"karma_abs":
				if absi(int(hero.karma)) < int(v):
					return false
			"yasha_min":
				if hero.yasha < int(v):
					return false
			"gold_min":
				if hero.gold < int(v):
					return false
			"has_item":
				if v is Array:
					if not has(v[0], int(v[1])):
						return false
				elif not has(v):
					return false
			"not_has_item":
				if has(v):
					return false
			"night":
				if is_night() != bool(v):
					return false
			"day":
				if is_night() == bool(v):
					return false
			"panth":
				if hero.panth != v:
					return false
			"married":
				if (hero.spouse != "") != bool(v):
					return false
			"region":
				if state.region != v:
					return false
			"affection_min":
				if affection(v[0]) < int(v[1]):
					return false
			"stat_min":
				var sname: String = v[0]
				var val := int(hero.counters.get(sname, 0)) if hero.counters.has(sname) else stat(sname)
				if val < int(v[1]):
					return false
			"siddhi_min":
				if siddhi_level(v[0]) < int(v[1]):
					return false
			"house_owned":
				if not hero.houses.has(v):
					return false
			"age_min":
				if hero.age < float(v):
					return false
			"killed_min":
				if int(hero.counters.get("kill_" + str(v[0]), 0)) < int(v[1]):
					return false
			"no_armor":
				if wearing_armor() == bool(v):
					return false
			"drunk":
				if (hero.drunk > 25.0) != bool(v):
					return false
			"mudra_known":
				if not hero.mudras.has(v):
					return false
			"following":
				if not is_following(v):
					return false
			_:
				pass
	return true

# =====================================================================
# Effects (dialogue choices, quest completions, yaksha rewards...)
# =====================================================================
const EFFECT_ORDER := ["cost", "start_quest", "advance_quest", "complete_quest", "fail_quest", "set_flag", "clear_flag",
	"karma", "gold", "yasha", "tapas", "tapas_bala", "tapas_kaushala", "tapas_shakti", "give", "take", "heal",
	"learn_siddhi", "add_mudra", "initiate", "age", "affection", "follow", "unfollow", "marry", "buy_house",
	"unlock_tirtha", "set_time", "sleep", "remove_npc", "hostile", "spawn", "spawn2", "teleport", "cutscene",
	"open_shop", "open_trainer", "open_sadhana", "gift_menu", "shrine", "arena_start", "clear_childhood"]

## Returns false if a "cost" could not be paid (choice should then not proceed).
func apply_effects(e: Dictionary, npc_id: String = "") -> bool:
	if e.is_empty():
		return true
	if e.has("cost") and not spend_gold(int(e["cost"])):
		return false
	for key in EFFECT_ORDER:
		if not e.has(key):
			continue
		var v = e[key]
		match key:
			"cost":
				pass
			"start_quest":
				if quests.is_inactive(v):
					quests.start(v)
					var qd := Data.quest(v)
					if qd.get("boasts", []).size() > 0:
						Events.panel_requested.emit("boasts", v)
			"advance_quest":
				quests.advance(v)
			"complete_quest":
				quests.complete(v)
			"fail_quest":
				quests.fail(v)
			"set_flag":
				for f in (v if v is Array else [v]):
					set_flag(f, true)
			"clear_flag":
				for f in (v if v is Array else [v]):
					set_flag(f, false)
			"karma":
				add_karma(int(v))
			"gold":
				add_gold(int(v))
			"yasha":
				add_yasha(int(v))
			"tapas":
				add_tapas("general", int(v))
			"tapas_bala":
				add_tapas("bala", int(v))
			"tapas_kaushala":
				add_tapas("kaushala", int(v))
			"tapas_shakti":
				add_tapas("shakti", int(v))
			"give":
				for it in (v if v is Array else [v]):
					if it is String:
						give(it, 1)
					else:
						give(it.get("item", ""), int(it.get("count", 1)))
			"take":
				for it in (v if v is Array else [v]):
					if it is String:
						take(it, 1)
					else:
						take(it.get("item", ""), int(it.get("count", 1)))
			"heal":
				heal(hp_max())
				hero.ojas = ojas_max()
			"learn_siddhi":
				if siddhi_level(v) == 0:
					learn_siddhi(v, true)
			"add_mudra":
				add_mudra(v)
			"initiate":
				initiate(v)
			"age":
				hero.age = float(v) if float(v) > 5.0 else hero.age + float(v)
			"affection":
				add_affection(v[0], int(v[1]))
			"follow":
				follow(v)
			"unfollow":
				unfollow(v)
			"marry":
				marry(v)
			"buy_house":
				buy_house(v)
			"unlock_tirtha":
				for t in (v if v is Array else [v]):
					unlock_tirtha(t)
			"set_time":
				state.time = float(v)
				Events.time_changed.emit(state.time)
			"sleep":
				sleep()
			"remove_npc":
				if world != null and npc_id != "":
					world.remove_npc(npc_id)
			"hostile":
				if world != null:
					world.make_hostile(v if v is String else npc_id)
			"spawn", "spawn2":
				if world != null:
					world.spawn_group(v)
			"teleport":
				if world != null:
					world.travel(v, "")
			"cutscene":
				var cs: Dictionary = Data.misc.get("cutscenes", {}).get(v, {}) if v is String else v
				if not cs.is_empty():
					Events.cutscene_requested.emit(Loc.t(cs.get("title", {})), cs.get("pages", []), Callable())
			"open_shop":
				Events.panel_requested.emit("shop", v)
			"open_trainer":
				Events.panel_requested.emit("trainer", v)
			"open_sadhana":
				Events.panel_requested.emit("sadhana", null)
			"gift_menu":
				Events.panel_requested.emit("gift", v)
			"shrine":
				Events.panel_requested.emit("shrine", v)
			"arena_start":
				if world != null:
					world.start_arena()
			"clear_childhood":
				set_flag("childhood_over", true)
	Events.hero_changed.emit()
	return true

# =====================================================================
# Save / load
# =====================================================================
func save_path(slot: int) -> String:
	return "%s/slot_%d.json" % [save_dir, slot]

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(save_path(slot))

## The slot saved most recently, or -1 when there is no save at all.
func latest_save_slot() -> int:
	var best := -1
	var best_t := ""
	for slot in SAVE_SLOTS:
		if not has_save(slot):
			continue
		var at := str(save_meta(slot).get("saved_at", ""))
		if best < 0 or at > best_t:
			best = slot
			best_t = at
	return best

func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(save_path(slot))

func save_game(slot: int, silent: bool = false) -> bool:
	if not in_game:
		return false
	DirAccess.make_dir_recursive_absolute(save_dir)
	if player != null:
		var p: Vector3 = player.global_position
		state.pos = [p.x, p.y, p.z]
	state.slot = slot
	var data := {"hero": hero, "state": state, "buffs": buffs, "saved_at": Time.get_datetime_string_from_system(), "version": SD_VERSION, "lang": Loc.lang}
	var f := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save " + save_path(slot))
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if not silent:
		Events.notify.emit(Loc.t("UI_SAVED"), "info")
	Events.game_saved.emit()
	return true

func load_game(slot: int) -> bool:
	var f := FileAccess.open(save_path(slot), FileAccess.READ)
	if f == null:
		return false
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		push_error("Corrupt save")
		return false
	f.close()
	# Check everything before touching the running game, so a bad file leaves it alone.
	var d = json.data
	if not d is Dictionary or not d.get("hero") is Dictionary or not d.get("state") is Dictionary \
			or not d["hero"].has("stats") or not d["hero"].has("inventory") or not d["state"].has("region"):
		push_error("Save file lacks hero or state data")
		return false
	var had_water: bool = d["hero"].has("water")
	hero = _fill_defaults(d["hero"], _new_hero(str(d["hero"].get("name", "Vira"))))
	hero.water = int(hero.water)
	if not had_water and has("kamandalu"):
		hero.water = water_max()   # a save from before the pot could run dry
	state = _fill_defaults(d["state"], _new_state())
	buffs = d.get("buffs", []) if d.get("buffs") is Array else []
	# JSON gives every number back as a float, and [0.0].has(0) is false: the lists of slot numbers
	# the regions remember (opened chests, picked-up items, killed bosses...) must be ints again.
	for rid in state.regions.keys():
		var rs = state.regions[rid]
		if not rs is Dictionary:
			continue
		for k in ["chests", "picked", "keys", "dug", "killed_once"]:
			if rs.get(k) is Array:
				rs[k] = rs[k].map(func(v): return int(v))
	var hb := []
	for h in hero.hotbar:
		hb.append(str(h))
	hero.hotbar = hb
	in_game = true
	Events.game_loaded.emit()
	Events.hero_changed.emit()
	return true

## Adds to `d` every key `defaults` has and `d` lacks (older saves), down through nested dictionaries.
func _fill_defaults(d: Dictionary, defaults: Dictionary) -> Dictionary:
	for k in defaults.keys():
		if not d.has(k) or typeof(d[k]) != typeof(defaults[k]) and not (d[k] is float and defaults[k] is int) and not (d[k] is int and defaults[k] is float):
			d[k] = defaults[k]
		elif defaults[k] is Dictionary:
			_fill_defaults(d[k], defaults[k])
	return d

func save_meta(slot: int) -> Dictionary:
	var f := FileAccess.open(save_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		return {}
	f.close()
	var d: Dictionary = json.data
	return {"name": d.get("hero", {}).get("name", "?"), "region": d.get("state", {}).get("region", ""), "day": int(d.get("state", {}).get("day", 1)), "saved_at": d.get("saved_at", ""), "age": d.get("hero", {}).get("age", 0)}

func save_settings() -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var f := FileAccess.open(save_dir + "/settings.json", FileAccess.WRITE)
	if f:
		settings["lang"] = Loc.lang
		f.store_string(JSON.stringify(settings))
		f.close()

func load_settings() -> void:
	var f := FileAccess.open(save_dir + "/settings.json", FileAccess.READ)
	if f == null:
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) == OK and json.data is Dictionary:
		for k in json.data.keys():
			settings[k] = json.data[k]
	f.close()
