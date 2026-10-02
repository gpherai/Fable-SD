## Quest runtime. State lives in Game.state.quests so it is saved with the game.
## Objective types handled automatically: kill, kill_boss, reach, collect, flag, flags,
## stat, escort, mudra, gold, karma. talk/deliver/choice are advanced by dialogue effects.
extends Node

func _ready() -> void:
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.region_entered.connect(_on_region_entered)
	Events.item_picked.connect(func(_i, _c): _recheck_all())
	Events.hero_changed.connect(_recheck_all)
	Events.flag_set.connect(func(_f, _v): _recheck_all())
	Events.mudra_performed.connect(_on_mudra)
	Events.karma_changed.connect(func(_d, _t): _recheck_all())
	Events.gold_changed.connect(func(_t): _recheck_all())
	Events.equipment_changed.connect(_on_equipment_changed)
	Events.item_used.connect(_on_item_used)
	Events.siddhi_cast.connect(func(_s, _l): _break_boast("no_siddhi"))
	Events.npc_killed.connect(_on_npc_killed)

# ---------- state helpers ----------
func _q(id: String) -> Dictionary:
	if not Game.state.quests.has(id):
		Game.state.quests[id] = {"state": "inactive", "stage": 0, "counters": {}, "boasts": [], "broken": [], "mudras": [], "start_day": 0}
	return Game.state.quests[id]

func state_of(id: String) -> String:
	return _q(id)["state"]

func stage_of(id: String) -> int:
	return int(_q(id)["stage"])

func is_active(id: String) -> bool:
	return state_of(id) == "active"

func is_done(id: String) -> bool:
	return state_of(id) == "done"

func is_inactive(id: String) -> bool:
	return state_of(id) == "inactive"

func active_quests() -> Array[String]:
	var out: Array[String] = []
	for id in Game.state.quests.keys():
		if Game.state.quests[id]["state"] == "active":
			out.append(id)
	return out

func current_stage(id: String) -> Dictionary:
	var qd := Data.quest(id)
	var stages: Array = qd.get("stages", [])
	var i := stage_of(id)
	if i >= 0 and i < stages.size():
		return stages[i]
	return {}

func can_start(id: String) -> bool:
	var qd := Data.quest(id)
	if qd.is_empty():
		return false
	var req: Dictionary = qd.get("requires", {})
	for rq in req.get("quests_done", []):
		if not is_done(rq):
			return false
	for f in req.get("flags", []):
		if not Game.flag(f):
			return false
	return true

# ---------- transitions ----------
func start(id: String, boasts: Array = []) -> bool:
	var qd := Data.quest(id)
	if qd.is_empty():
		push_warning("Unknown quest " + id)
		return false
	var q := _q(id)
	if q["state"] != "inactive":
		return false
	q["state"] = "active"
	q["stage"] = 0
	q["counters"] = {}
	q["boasts"] = boasts.duplicate()
	q["broken"] = []
	q["mudras"] = []
	q["start_day"] = Game.state.day
	for ex in qd.get("excludes", []):
		var other := _q(ex)
		if other["state"] == "inactive":
			other["state"] = "failed"
	Events.quest_started.emit(id)
	Events.notify.emit(Loc.t("UI_QUEST_STARTED", {"name": Loc.t(qd["name"])}), "quest")
	Audio.play("quest")
	_recheck(id)
	return true

func advance(id: String) -> void:
	var q := _q(id)
	if q["state"] != "active":
		return
	var qd := Data.quest(id)
	var stages: Array = qd.get("stages", [])
	q["stage"] = int(q["stage"]) + 1
	q["counters"] = {}
	q["mudras"] = []
	if q["stage"] >= stages.size():
		complete(id)
		return
	Events.quest_advanced.emit(id, q["stage"])
	var st: Dictionary = stages[q["stage"]]
	Events.notify.emit(Loc.t("UI_QUEST_ADVANCED", {"text": Loc.t(st.get("text", {}))}), "quest")
	Audio.play("quest")
	_recheck(id)

func complete(id: String) -> void:
	var q := _q(id)
	if q["state"] != "active":
		return
	var qd := Data.quest(id)
	q["state"] = "done"
	# Rewards
	var rw: Dictionary = qd.get("rewards", {})
	var gold := int(rw.get("gold", 0))
	var yasha := int(rw.get("yasha", 0))
	# Boasts
	for b in q["boasts"]:
		if not q["broken"].has(b):
			var bd: Dictionary = Data.misc.get("boasts", {}).get(b, {})
			gold += int(bd.get("gold", 0))
			yasha += int(bd.get("yasha", 0))
	if gold != 0:
		Game.add_gold(int(round(gold * (1.0 + Game.ashrama_bonus("gold_mult")))))
	if yasha != 0:
		Game.add_yasha(yasha)
	if rw.has("tapas"):
		Game.add_tapas("general", int(rw["tapas"]))
	for k in ["bala", "kaushala", "shakti"]:
		if rw.has("tapas_" + k):
			Game.add_tapas(k, int(rw["tapas_" + k]))
	if rw.has("karma"):
		Game.add_karma(int(rw["karma"]))
	for it in rw.get("items", []):
		Game.give(it, 1)
	for t in rw.get("take", []):
		Game.take(t.get("item", ""), int(t.get("count", 1)))
	Events.quest_completed.emit(id)
	Events.notify.emit(Loc.t("UI_QUEST_COMPLETED", {"name": Loc.t(qd["name"])}), "quest")
	Audio.play("levelup")
	Game.apply_effects(qd.get("on_complete", {}))
	Game.save_game(0, true)

func fail(id: String) -> void:
	var q := _q(id)
	if q["state"] != "active":
		return
	q["state"] = "failed"
	Events.quest_failed.emit(id)
	Events.notify.emit(Loc.t("UI_QUEST_FAILED", {"name": Loc.t(Data.quest(id).get("name", {}))}), "bad")

func _break_boast(boast: String) -> void:
	for id in active_quests():
		var q := _q(id)
		if q["boasts"].has(boast) and not q["broken"].has(boast):
			q["broken"].append(boast)
			Events.boast_broken.emit(id, boast)
			Events.notify.emit(Loc.t("UI_BOAST_BROKEN", {"name": Loc.t(Data.misc["boasts"][boast]["name"])}), "bad")

func boast_intact(id: String, boast: String) -> bool:
	var q := _q(id)
	return q["boasts"].has(boast) and not q["broken"].has(boast)

# ---------- objective checks ----------
func _recheck_all() -> void:
	for id in active_quests():
		_recheck(id)

func _recheck(id: String) -> void:
	var q := _q(id)
	if q["state"] != "active":
		return
	var st := current_stage(id)
	var o: Dictionary = st.get("objective", {})
	if _objective_met(id, o):
		advance(id)

func _objective_met(id: String, o: Dictionary) -> bool:
	var q := _q(id)
	match o.get("type", ""):
		"flag":
			return Game.flag(o.get("flag", ""))
		"flags":
			for f in o.get("flags", []):
				if not Game.flag(f):
					return false
			return true
		"collect":
			return Game.count(o.get("item", "")) >= int(o.get("count", 1))
		"kill":
			return int(q["counters"].get("kill", 0)) >= int(o.get("count", 1))
		"kill_boss":
			return int(q["counters"].get("kill_boss", 0)) >= 1
		"stat":
			return int(Game.hero.counters.get(o.get("stat", ""), 0)) >= int(o.get("min", 1))
		"gold":
			return Game.hero.gold >= int(o.get("min", 0))
		"karma":
			if o.has("min") and Game.hero.karma < int(o["min"]):
				return false
			if o.has("max") and Game.hero.karma > int(o["max"]):
				return false
			return true
		"mudra":
			for m in o.get("mudras", []):
				if not q["mudras"].has(m):
					return false
			return true
		"reach":
			return bool(q["counters"].get("reached", false))
		"escort":
			return bool(q["counters"].get("escorted", false))
	return false

func _on_enemy_killed(enemy_id: String, region_id: String, is_boss: bool) -> void:
	for id in active_quests():
		var q := _q(id)
		var o: Dictionary = current_stage(id).get("objective", {})
		var t: String = o.get("type", "")
		if t == "kill" and o.get("enemy", "") == enemy_id and (not o.has("region") or o["region"] == region_id):
			q["counters"]["kill"] = int(q["counters"].get("kill", 0)) + 1
			var need := int(o.get("count", 1))
			var have := int(q["counters"]["kill"])
			if have < need:
				Events.notify.emit("%s %d/%d" % [Loc.t(Data.enemy(enemy_id).get("name", {})), have, need], "quest")
			_recheck(id)
		elif t == "kill_boss" and o.get("enemy", "") == enemy_id:
			q["counters"]["kill_boss"] = 1
			_recheck(id)

func _on_region_entered(region_id: String) -> void:
	for id in active_quests():
		var q := _q(id)
		var o: Dictionary = current_stage(id).get("objective", {})
		var t: String = o.get("type", "")
		if t == "reach" and o.get("region", "") == region_id:
			q["counters"]["reached"] = true
			_recheck(id)
		elif t == "escort" and o.get("region", "") == region_id and Game.is_following(o.get("npc", "")):
			q["counters"]["escorted"] = true
			_recheck(id)

func _on_mudra(mudra_id: String) -> void:
	for id in active_quests():
		var q := _q(id)
		if not q["mudras"].has(mudra_id):
			q["mudras"].append(mudra_id)
		_recheck(id)

func _on_equipment_changed() -> void:
	if Game.wearing_armor():
		_break_boast("no_armor")

func _on_item_used(item_id: String) -> void:
	var it := Data.item(item_id)
	if it.get("cat", "") == "potion":
		_break_boast("no_potion")

func ranged_used() -> void:
	_break_boast("melee_only")

func _on_npc_killed(npc_id: String) -> void:
	for id in active_quests():
		var qd := Data.quest(id)
		if qd.get("fail_on_npc_death", "") == npc_id:
			fail(id)
		var o: Dictionary = current_stage(id).get("objective", {})
		if o.get("type", "") == "escort" and o.get("npc", "") == npc_id:
			fail(id)

## Progress text for the HUD / quest panel.
func progress_text(id: String) -> String:
	var q := _q(id)
	var o: Dictionary = current_stage(id).get("objective", {})
	match o.get("type", ""):
		"kill":
			return "%d/%d" % [int(q["counters"].get("kill", 0)), int(o.get("count", 1))]
		"collect":
			return "%d/%d" % [Game.count(o.get("item", "")), int(o.get("count", 1))]
		"stat":
			return "%d/%d" % [int(Game.hero.counters.get(o.get("stat", ""), 0)), int(o.get("min", 1))]
		"mudra":
			return "%d/%d" % [q["mudras"].size(), o.get("mudras", []).size()]
	return ""
