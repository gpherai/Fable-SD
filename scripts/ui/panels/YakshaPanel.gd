## A Yaksha door (payload {"door": id, "node": Interactable}). data/yaksha.json gives a greeting
## and one demand: riddle, sattva_meal, karma_abs, drunk, mudra, item, no_armor, gold_show or
## yasha_min. Meeting it opens the door for good, pays the reward and hides the Yaksha's mouth.
extends "res://scripts/ui/UIPanel.gd"

var door_id: String = ""
var yaksha: Dictionary = {}
var demand: Dictionary = {}
var message: String = ""
var open_now: bool = false
var _ate_sattva: bool = false

func init() -> void:
	kind = "yaksha"
	live = false
	door_id = str((payload as Dictionary).get("door", "")) if payload is Dictionary else ""
	yaksha = Data.yaksha.get(door_id, {})
	demand = yaksha.get("demand", {})
	win_size = Vector2(820, 580)
	set_title(Loc.t(yaksha.get("name", {})))

func build() -> void:
	body.add_child(T.para(Loc.t(yaksha.get("greeting", {})), 20))
	body.add_child(T.hsep())
	var area := T.vbox(8)
	match str(demand.get("type", "")):
		"riddle":
			var opts: Array = demand.get("options", [])
			for i in opts.size():
				area.add_child(T.button(Loc.t(opts[i]), func(): _try(i == int(demand.get("answer", -1))), 0, 44))
		"sattva_meal":
			area.add_child(T.label(Loc.t("UI_YAKSHA_WATCHES"), 17, T.GOLD))
			var any := false
			for id in Game.hero.inventory.keys():
				var it := Data.item(id)
				if it.get("cat", "") == "food" and it.get("guna", "sattva") == "sattva":
					any = true
					area.add_child(T.button("%s  x%d" % [Loc.t(it.get("name", {})), Game.count(id)], func(): _eat(id), 0, 40))
			if not any:
				area.add_child(T.label(Loc.t("UI_YAKSHA_NO_SATTVA"), 16, T.DIM))
		"drunk":
			area.add_child(T.label(Loc.t("UI_YAKSHA_DRINK"), 17, T.GOLD))
			for id in Game.hero.inventory.keys():
				var it := Data.item(id)
				if it.get("use", {}).has("drunk"):
					area.add_child(T.button("%s  x%d" % [Loc.t(it.get("name", {})), Game.count(id)], func(): _drink(id), 0, 40))
			area.add_child(T.button(Loc.t("UI_YAKSHA_SHOW"), func(): _try(Game.hero.drunk > 25.0), 0, 40))
		"mudra":
			var mid: String = str(demand.get("mudra", ""))
			var m: Dictionary = Data.mudras.get(mid, {})
			var label := Loc.t("UI_YAKSHA_PERFORM", {"name": Loc.t(m.get("name", {}))}) + (" " + Loc.t("UI_YAKSHA_NIGHT_ONLY") if bool(demand.get("night", false)) else "")
			var b := T.button(label, func(): _perform(mid), 0, 44)
			b.disabled = not bool(Game.mudra_available(mid)["ok"])
			area.add_child(b)
		"item":
			var iid: String = str(demand.get("item", ""))
			var need := int(demand.get("count", 1))
			var b := T.button(Loc.t("UI_YAKSHA_GIVE", {"name": Loc.t(Data.item(iid).get("name", {}))}), func(): _give(iid, need), 0, 44)
			b.disabled = not Game.has(iid, need)
			area.add_child(b)
		"gold_show":
			area.add_child(T.button(Loc.t("UI_YAKSHA_SHOW_GOLD"), func(): _try(Game.hero.gold >= int(demand.get("amount", 0))), 0, 44))
		_:
			area.add_child(T.button(Loc.t("UI_YAKSHA_SHOW"), func(): _try(_demand_met()), 0, 44))
	body.add_child(area)
	body.add_child(T.spacer(0, 0, true))
	if message != "":
		body.add_child(T.para(message, 19, T.GOOD if open_now else T.BAD))
	var row := T.hbox(8)
	row.add_child(T.spacer(0, 0, true))
	row.add_child(T.button(Loc.t("UI_YAKSHA_LEAVE") if not open_now else Loc.t("UI_CLOSE"), close, 160, 44))
	body.add_child(row)

func _demand_met() -> bool:
	match str(demand.get("type", "")):
		"karma_abs":
			return absi(int(Game.hero.karma)) >= int(demand.get("value", 0))
		"no_armor":
			return not Game.wearing_armor()
		"yasha_min":
			return int(Game.hero.yasha) >= int(demand.get("value", 0))
		"gold_show":
			return int(Game.hero.gold) >= int(demand.get("amount", 0))
		"drunk":
			return Game.hero.drunk > 25.0
		"sattva_meal":
			return _ate_sattva
	return false

func _try(ok: bool) -> void:
	if open_now:
		return
	if ok:
		_open_door()
	else:
		message = Loc.t(yaksha.get("fail", {}))
		Audio.play("block", -6.0)
		rebuild()

func _eat(id: String) -> void:
	if Game.use_item(id):
		_ate_sattva = true
	_try(_ate_sattva)

func _drink(id: String) -> void:
	Game.use_item(id)
	if Game.hero.drunk > 25.0:
		_try(true)
	else:
		rebuild()

func _perform(mid: String) -> void:
	if bool(demand.get("night", false)) and not Game.is_night():
		_try(false)
		return
	if Game.perform_mudra(mid):
		_try(true)

func _give(iid: String, n: int) -> void:
	if Game.take(iid, n):
		_try(true)

func _open_door() -> void:
	open_now = true
	message = Loc.t(yaksha.get("success", {}))
	var rid: String = str(Game.state.get("region", ""))
	var node = (payload as Dictionary).get("node", null) if payload is Dictionary else null
	if node != null and is_instance_valid(node):
		rid = node.region_id
		var mouth: Node3D = node.visual.get_node_or_null("Mouth")
		if mouth:
			mouth.visible = false
	Game.region_state(rid).yaksha = true
	var rw: Dictionary = yaksha.get("reward", {})
	for it in rw.get("items", []):
		Game.give(it, 1)
	if int(rw.get("gold", 0)) > 0:
		Game.add_gold(int(rw["gold"]))
	if int(rw.get("tapas", 0)) > 0:
		Game.add_tapas("general", int(rw["tapas"]))
	Game.hero.counters.yaksha = int(Game.hero.counters.get("yaksha", 0)) + 1
	Events.yaksha_opened.emit(door_id)
	Events.notify.emit(Loc.t("UI_YAKSHA_OPENED"), "good")
	Audio.play("chest")
	rebuild()
