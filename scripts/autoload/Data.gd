## Loads every JSON content file in res://data and expands generated items
## (weapon types x tiers, armor sets x pieces). All lookups go through here.
extends Node

var items: Dictionary = {}
var weapon_types: Dictionary = {}
var tiers: Dictionary = {}
var armor_sets: Dictionary = {}
var armor_pieces: Dictionary = {}
var siddhis: Dictionary = {}
var moves: Dictionary = {}
var mudras: Dictionary = {}
var enemies: Dictionary = {}
var characters: Dictionary = {}
var regions: Dictionary = {}
var yaksha: Dictionary = {}
var quests: Dictionary = {}
var misc: Dictionary = {}

var loaded: bool = false
var load_errors: Array[String] = []

const FILES := {
	"items": "res://data/items.json",
	"siddhis": "res://data/siddhis.json",
	"moves": "res://data/moves.json",
	"mudras": "res://data/mudras.json",
	"enemies": "res://data/enemies.json",
	"characters": "res://data/characters",
	"regions": "res://data/regions.json",
	"yaksha": "res://data/yaksha.json",
	"quests": "res://data/quests.json",
	"misc": "res://data/misc.json",
}

func _ready() -> void:
	load_all()

func _read_json(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_errors.append("Cannot open " + path)
		return null
	var txt := f.get_as_text()
	f.close()
	var json := JSON.new()
	var err := json.parse(txt)
	if err != OK:
		load_errors.append("%s: JSON error line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func _read_json_dir(path: String) -> Dictionary:
	# Merge every *.json file in a directory into one dictionary.
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		load_errors.append("Cannot open dir " + path)
		return out
	var names: Array[String] = []
	dir.list_dir_begin()
	var n := dir.get_next()
	while n != "":
		if not dir.current_is_dir() and n.ends_with(".json"):
			names.append(n)
		n = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for name in names:
		var d = _read_json(path.path_join(name))
		if d is Dictionary:
			for k in d.keys():
				if out.has(k):
					load_errors.append("Duplicate id %s in %s" % [k, name])
				out[k] = d[k]
	return out

func load_all() -> void:
	load_errors.clear()
	var raw := {}
	for k in FILES.keys():
		var path: String = FILES[k]
		var d
		if path.ends_with(".json"):
			d = _read_json(path)
		else:
			d = _read_json_dir(path)
		raw[k] = d if d != null else {}
	siddhis = raw["siddhis"]
	moves = raw["moves"]
	mudras = raw["mudras"]
	enemies = raw["enemies"]
	characters = raw["characters"]
	regions = raw["regions"]
	yaksha = raw["yaksha"]
	quests = raw["quests"]
	misc = raw["misc"]
	_build_items(raw["items"])
	_stamp_ids()
	loaded = true
	if load_errors.size() > 0:
		for e in load_errors:
			push_error("Data: " + e)

func _build_items(src: Dictionary) -> void:
	tiers = src.get("tiers", {})
	weapon_types = src.get("weapon_types", {})
	armor_sets = src.get("armor_sets", {})
	armor_pieces = src.get("armor_pieces", {})
	items = {}
	# Weapons: type x tier
	for wt_id in weapon_types.keys():
		var wt: Dictionary = weapon_types[wt_id]
		if wt.get("no_tiers", false):
			continue
		for t_id in tiers.keys():
			var t: Dictionary = tiers[t_id]
			var id := "%s_%s" % [wt_id, t_id]
			var it := {
				"id": id,
				"name": {"nl": "%s %s" % [t["name"]["nl"], wt["name"]["nl"]], "en": "%s %s" % [t["name"]["en"], wt["name"]["en"]]},
				"cat": wt.get("class", "melee"),
				"wtype": wt_id,
				"tier": t_id,
				"dmg": int(round(float(wt.get("dmg", 5)) * float(t.get("mult", 1.0)))),
				"speed": wt.get("speed", 1.0),
				"reach": wt.get("reach", 1.5),
				"range": wt.get("range", 0),
				"value": int(round(float(wt.get("price", 50)) * float(t.get("price", 1.0)))),
				"slots": int(t.get("slots", 0)),
				"desc": wt.get("desc", {}),
				"shape": wt.get("shape", "sword"),
				"color": t.get("color", "#999999"),
				"two_handed": wt.get("two_handed", false),
				"stun": wt.get("stun", 0.0),
				"arc": wt.get("arc", 100),
				"pierce": wt.get("pierce", false),
				"projectile": wt.get("projectile", "arrow"),
				"generated": true,
			}
			items[id] = it
	# Armor: set x piece
	for set_id in armor_sets.keys():
		var s: Dictionary = armor_sets[set_id]
		for p_id in armor_pieces.keys():
			var p: Dictionary = armor_pieces[p_id]
			var id := "%s_%s" % [set_id, p_id]
			var m := float(p.get("mult", 1.0))
			var it := {
				"id": id,
				"name": {"nl": "%s %s" % [s["name"]["nl"], p["name"]["nl"]], "en": "%s %s" % [s["name"]["en"], p["name"]["en"]]},
				"cat": p.get("slot", "chest"),
				"aset": set_id,
				"piece": p_id,
				"def": int(round(float(s.get("def", 0)) * m)),
				"weight": float(s.get("weight", 0)) * m,
				"saundarya": int(round(float(s.get("saundarya", 0)) * m)),
				"bhaya": int(round(float(s.get("bhaya", 0)) * m)),
				"ojas": int(round(float(s.get("ojas", 0)) * m)),
				"value": int(round(float(s.get("price", 10)) * m)),
				"desc": s.get("desc", {}),
				"colors": s.get("colors", {}),
				"style": s.get("style", "cloth"),
				"generated": true,
			}
			items[id] = it
	# Explicit items (override generated if same id)
	var explicit: Dictionary = src.get("items", {})
	for id in explicit.keys():
		var it: Dictionary = explicit[id].duplicate(true)
		it["id"] = id
		items[id] = it

func _stamp_ids() -> void:
	for dict in [siddhis, moves, mudras, enemies, characters, regions, yaksha, quests]:
		for id in dict.keys():
			if dict[id] is Dictionary:
				dict[id]["id"] = id

# ---------- lookups ----------
func item(id: String) -> Dictionary:
	return items.get(id, {})

func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})

func region(id: String) -> Dictionary:
	return regions.get(id, {})

func character(id: String) -> Dictionary:
	return characters.get(id, {})

func siddhi(id: String) -> Dictionary:
	return siddhis.get(id, {})

func quest(id: String) -> Dictionary:
	return quests.get(id, {})

func shop(id: String) -> Dictionary:
	return misc.get("shops", {}).get(id, {})

func panth(id: String) -> Dictionary:
	return misc.get("panths", {}).get(id, {})

func items_by_cat(cat: String) -> Array:
	var out := []
	for id in items.keys():
		if items[id].get("cat", "") == cat:
			out.append(items[id])
	out.sort_custom(func(a, b): return int(a.get("value", 0)) < int(b.get("value", 0)))
	return out

func is_weapon(it: Dictionary) -> bool:
	return it.get("cat", "") in ["melee", "ranged"]

func is_armor(it: Dictionary) -> bool:
	return it.get("cat", "") in ["head", "chest", "hands", "legs", "feet"]

func is_consumable(it: Dictionary) -> bool:
	return it.get("cat", "") in ["potion", "food", "book"]

func is_cosmetic(it: Dictionary) -> bool:
	return it.get("cat", "") in ["hair", "tattoo", "beard"]

func stat_defs() -> Dictionary:
	return misc.get("stats", {})

# ---------- validation (used by tools/validate.gd and tests) ----------
func validate() -> Array[String]:
	var errs: Array[String] = []
	for e in load_errors:
		errs.append(e)
	var all_items := items
	var map_spots := {}
	# Regions
	for rid in regions.keys():
		var r: Dictionary = regions[rid]
		for ex in r.get("exits", []):
			if not regions.has(ex.get("to", "")):
				errs.append("region %s exit -> unknown region %s" % [rid, ex.get("to", "")])
		for n in r.get("npcs", []):
			var nid: String = n if n is String else str(n.get("id", ""))
			if not characters.has(nid):
				errs.append("region %s: unknown npc %s" % [rid, nid])
		for sp in r.get("spawns", []):
			if not enemies.has(sp.get("enemy", "")):
				errs.append("region %s: unknown enemy %s" % [rid, sp.get("enemy", "")])
		for ch in r.get("chests", []):
			for it in ch.get("items", []):
				if not all_items.has(it):
					errs.append("region %s chest: unknown item %s" % [rid, it])
		for pk in r.get("pickups", []):
			if not all_items.has(pk.get("item", "")):
				errs.append("region %s pickup: unknown item %s" % [rid, pk.get("item", "")])
		for dg in r.get("dig_spots", []):
			if not all_items.has(dg.get("item", "")):
				errs.append("region %s dig: unknown item %s" % [rid, dg.get("item", "")])
		if r.has("yaksha") and not yaksha.has(r["yaksha"]):
			errs.append("region %s: unknown yaksha door %s" % [rid, r["yaksha"]])
		for key in ["name", "desc", "biome"]:
			if not r.has(key):
				errs.append("region %s: missing %s" % [rid, key])
		# where the region sits on the map (grid units, y grows southward); no two regions share a spot
		var mp = r.get("map")
		if not (mp is Array and mp.size() == 2 and (mp[0] is float or mp[0] is int) and (mp[1] is float or mp[1] is int)):
			errs.append("region %s: map must be [x, y]" % rid)
		else:
			var spot := Vector2(float(mp[0]), float(mp[1]))
			if map_spots.has(spot):
				errs.append("region %s: same map spot as %s" % [rid, map_spots[spot]])
			map_spots[spot] = rid
	# Characters
	for cid in characters.keys():
		var c: Dictionary = characters[cid]
		if c.has("shop") and c["shop"] != null and not misc.get("shops", {}).has(c["shop"]):
			errs.append("character %s: unknown shop %s" % [cid, c["shop"]])
		if c.has("home") and not regions.has(c["home"]):
			errs.append("character %s: unknown home region %s" % [cid, c["home"]])
		_validate_dialogue(cid, c.get("dialogue", []), errs)
	# Shops
	for sid in misc.get("shops", {}).keys():
		for it in misc["shops"][sid].get("items", []):
			if not all_items.has(it):
				errs.append("shop %s: unknown item %s" % [sid, it])
	# Enemies
	for eid in enemies.keys():
		var e: Dictionary = enemies[eid]
		for d in e.get("drops", []):
			if not all_items.has(d.get("item", "")):
				errs.append("enemy %s: unknown drop %s" % [eid, d.get("item", "")])
		for s in e.get("summons", []):
			if not enemies.has(s):
				errs.append("enemy %s: unknown summon %s" % [eid, s])
	# Quests
	for qid in quests.keys():
		var q: Dictionary = quests[qid]
		if q.has("giver") and q["giver"] != "" and not characters.has(q["giver"]):
			errs.append("quest %s: unknown giver %s" % [qid, q["giver"]])
		for st in q.get("stages", []):
			var o: Dictionary = st.get("objective", {})
			match o.get("type", ""):
				"kill", "kill_boss":
					if not enemies.has(o.get("enemy", "")):
						errs.append("quest %s: unknown enemy %s" % [qid, o.get("enemy", "")])
				"reach":
					if not regions.has(o.get("region", "")):
						errs.append("quest %s: unknown region %s" % [qid, o.get("region", "")])
				"talk", "deliver", "escort":
					if not characters.has(o.get("npc", "")):
						errs.append("quest %s: unknown npc %s" % [qid, o.get("npc", "")])
				"collect":
					if not all_items.has(o.get("item", "")):
						errs.append("quest %s: unknown item %s" % [qid, o.get("item", "")])
				"flag", "flags", "survive", "choice", "mudra", "yaksha", "stat", "siddhi", "gold", "karma":
					pass
				_:
					errs.append("quest %s: unknown objective type %s" % [qid, o.get("type", "")])
			if o.get("type", "") == "escort" and not regions.has(o.get("region", "")):
				errs.append("quest %s escort: unknown region %s" % [qid, o.get("region", "")])
		for it in q.get("rewards", {}).get("items", []):
			if not all_items.has(it):
				errs.append("quest %s reward: unknown item %s" % [qid, it])
		for rq in q.get("requires", {}).get("quests_done", []):
			if not quests.has(rq):
				errs.append("quest %s requires unknown quest %s" % [qid, rq])
	# Yaksha doors
	for yid in yaksha.keys():
		var y: Dictionary = yaksha[yid]
		for it in y.get("reward", {}).get("items", []):
			if not all_items.has(it):
				errs.append("yaksha %s reward: unknown item %s" % [yid, it])
		var dm: Dictionary = y.get("demand", {})
		if dm.get("type", "") == "item" and not all_items.has(dm.get("item", "")):
			errs.append("yaksha %s demand: unknown item %s" % [yid, dm.get("item", "")])
		if dm.get("type", "") == "mudra" and not mudras.has(dm.get("mudra", "")):
			errs.append("yaksha %s demand: unknown mudra %s" % [yid, dm.get("mudra", "")])
	# Siddhis
	for sid in siddhis.keys():
		var s: Dictionary = siddhis[sid]
		if s.get("levels", []).size() != 4:
			errs.append("siddhi %s: needs 4 levels" % sid)
	# Mudras unlocks referencing books
	for mid in mudras.keys():
		var m: Dictionary = mudras[mid]
		var u: String = m.get("unlock", "start")
		if u.begins_with("book:") and not all_items.has(u.substr(5)):
			errs.append("mudra %s: unknown book %s" % [mid, u.substr(5)])
	# Trainers
	for tid in misc.get("trainers", {}).keys():
		for s in misc["trainers"][tid].get("siddhis", []):
			if not siddhis.has(s):
				errs.append("trainer %s: unknown siddhi %s" % [tid, s])
	# Panths
	for pid in misc.get("panths", {}).keys():
		var p: Dictionary = misc["panths"][pid]
		if p.has("teacher") and not characters.has(p["teacher"]):
			errs.append("panth %s: unknown teacher %s" % [pid, p["teacher"]])
	return errs

func _validate_dialogue(cid: String, dlg: Array, errs: Array[String]) -> void:
	for node in dlg:
		if not node is Dictionary:
			continue
		for ch in node.get("choices", []):
			_validate_effect(cid, ch, errs)
			for sub in ch.get("lines", []):
				pass
		_validate_effect(cid, node.get("effects", {}), errs)

func _validate_effect(cid: String, e: Dictionary, errs: Array[String]) -> void:
	for key in ["give", "take"]:
		if e.has(key):
			var v = e[key]
			var list: Array = v if v is Array else [v]
			for it in list:
				var iid: String = it if it is String else it.get("item", "")
				if not items.has(iid):
					errs.append("character %s dialogue %s: unknown item %s" % [cid, key, iid])
	for key in ["start_quest", "advance_quest", "complete_quest", "fail_quest"]:
		if e.has(key) and not quests.has(e[key]):
			errs.append("character %s dialogue: unknown quest %s" % [cid, e[key]])
	if e.has("open_shop") and not misc.get("shops", {}).has(e["open_shop"]):
		errs.append("character %s dialogue: unknown shop %s" % [cid, e["open_shop"]])
	if e.has("teleport") and not regions.has(e["teleport"]):
		errs.append("character %s dialogue: unknown teleport region %s" % [cid, e["teleport"]])
	if e.has("initiate") and not misc.get("panths", {}).has(e["initiate"]):
		errs.append("character %s dialogue: unknown panth %s" % [cid, e["initiate"]])
	if e.has("learn_siddhi") and not siddhis.has(e["learn_siddhi"]):
		errs.append("character %s dialogue: unknown siddhi %s" % [cid, e["learn_siddhi"]])

func summary() -> String:
	return "items=%d (weapons types %d, armor sets %d) siddhis=%d moves=%d mudras=%d enemies=%d characters=%d regions=%d yaksha=%d quests=%d shops=%d panths=%d" % [
		items.size(), weapon_types.size(), armor_sets.size(), siddhis.size(), moves.size(), mudras.size(),
		enemies.size(), characters.size(), regions.size(), yaksha.size(), quests.size(),
		misc.get("shops", {}).size(), misc.get("panths", {}).size()]
