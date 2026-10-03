## A world object the player can interact with by pressing E nearby:
## chest, pickup, silver key, region exit, tirtha gate, yaksha door, shrine,
## dig spot, fishing spot, bed, boat, signpost, training dummy.
extends Node3D

const Props = preload("res://scripts/world/Props.gd")

var kind: String = ""
var data: Dictionary = {}
var region_id: String = ""
var index: int = 0
var used: bool = false
var interact_radius: float = 2.6
var bob_t: float = 0.0
var visual: Node3D
var busy: bool = false

func setup(kind_: String, data_: Dictionary, region_id_: String, index_: int) -> void:
	kind = kind_
	data = data_
	region_id = region_id_
	index = index_
	name = "%s_%d" % [kind, index]
	_build_visual()

func _build_visual() -> void:
	match kind:
		"chest":
			visual = Props.chest_visual(int(data.get("locked", 0)) > 0)
			interact_radius = 2.4
		"pickup":
			var it := Data.item(data.get("item", ""))
			visual = Props.pickup_visual(Color(it.get("color", "#ffffff")))
			interact_radius = 2.0
		"key":
			visual = Props.key_visual()
			interact_radius = 2.0
		"exit":
			visual = Node3D.new()
			var lbl := Label3D.new()
			lbl.text = Loc.t(Data.region(data.get("to", "")).get("name", {}))
			lbl.font_size = 64
			lbl.pixel_size = 0.012
			lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			lbl.modulate = Color("#ffe9b0")
			lbl.outline_size = 12
			lbl.position = Vector3(0, 3.2, 0)
			visual.add_child(lbl)
			var post := Props.cyl(0.08, 0.1, 2.0, Color("#5a3d23"), Vector3(0, 1.0, 0))
			visual.add_child(post)
			visual.add_child(Props.box(Vector3(1.2, 0.4, 0.08), Color("#a8865a"), Vector3(0, 2.0, 0)))
			interact_radius = 4.0
		"tirtha":
			visual = Props.tirtha_gate()
			interact_radius = 4.5
		"yaksha":
			visual = Props.yaksha_door()
			interact_radius = 5.0
		"shrine":
			visual = Node3D.new()
			interact_radius = 4.0
		"dig":
			visual = Props.dig_mound()
			interact_radius = 2.2
		"fish":
			visual = Props.fishing_marker()
			interact_radius = 3.0
		"bed":
			visual = Props.bed()
			interact_radius = 2.6
		"boat":
			visual = Node3D.new()
			interact_radius = 4.5
		"sign":
			visual = Node3D.new()
			interact_radius = 2.5
		"dummy":
			visual = Node3D.new()
			interact_radius = 2.5
		_:
			visual = Node3D.new()
	add_child(visual)

func _process(delta: float) -> void:
	if kind in ["pickup", "key"] and visual != null and not used:
		bob_t += delta
		visual.position.y = sin(bob_t * 2.0) * 0.12
		visual.rotation.y += delta * 1.2
	elif kind == "tirtha" and visual != null:
		var core := visual.get_node_or_null("Core")
		if core:
			core.rotation.y += delta * 0.8
			core.scale = Vector3.ONE * (1.0 + 0.06 * sin(bob_t * 2.5))
		bob_t += delta

## Text shown in the HUD when the player is close enough.
func hint_text() -> String:
	if used and kind in ["chest", "pickup", "key", "dig"]:
		return ""
	match kind:
		"chest":
			var locked := int(data.get("locked", 0))
			if locked > 0:
				return Loc.t("HINT_CHEST_SILVER", {"n": locked})
			return Loc.t("HINT_CHEST")
		"pickup":
			return Loc.t("HINT_PICKUP", {"name": Loc.t(Data.item(data.get("item", "")).get("name", {}))})
		"key":
			return Loc.t("HINT_PICKUP", {"name": Loc.t(Data.item("rajat_kunji")["name"])})
		"exit":
			return Loc.t("HINT_EXIT", {"name": Loc.t(Data.region(data.get("to", "")).get("name", {}))})
		"tirtha":
			return Loc.t("HINT_TIRTHA")
		"yaksha":
			return "" if Game.region_state(region_id).get("yaksha", false) else Loc.t("HINT_YAKSHA")
		"shrine":
			return Loc.t("HINT_SHRINE")
		"dig":
			return Loc.t("HINT_DIG")
		"fish":
			return Loc.t("HINT_FISH")
		"bed":
			return Loc.t("HINT_BED")
		"boat":
			return Loc.t("HINT_BOAT")
		"sign":
			return Loc.t("HINT_SIGN")
		"dummy":
			return Loc.t("HINT_DUMMY")
	return ""

func can_interact() -> bool:
	if kind in ["chest", "pickup", "key", "dig"] and used:
		return false
	if kind == "yaksha" and Game.region_state(region_id).get("yaksha", false):
		return false
	return not busy

## Called by the player. World is passed for travel/teleport operations.
func interact(world: Node) -> void:
	if not can_interact():
		return
	match kind:
		"chest":
			_open_chest()
		"pickup":
			used = true
			Game.give(data.get("item", ""), 1)
			if index >= 0:   # enemy drops have no slot (index -1): they are gone with the region
				Game.region_state(region_id).picked.append(index)
			visual.visible = false
		"key":
			used = true
			Game.give("rajat_kunji", 1)
			Events.notify.emit(Loc.t("UI_SILVER_KEY_FOUND"), "good")
			Game.region_state(region_id).keys.append(index)
			visual.visible = false
		"exit":
			var to: String = data.get("to", "")
			var lock = data.get("locked", null)
			if lock != null and not Game.check(lock):
				Events.notify.emit(Loc.t(lock.get("msg", {})), "bad")
				return
			var target := Data.region(to)
			var rlock = target.get("locked", null)
			if rlock != null:
				if rlock.has("yasha") and Game.hero.yasha < int(rlock["yasha"]):
					Events.notify.emit(Loc.t(rlock.get("msg", {})), "bad")
					return
				if rlock.has("flag") and not Game.flag(rlock["flag"]):
					Events.notify.emit(Loc.t(rlock.get("msg", {})), "bad")
					return
			busy = true
			world.travel(to, data.get("dir", ""))
		"tirtha":
			Events.panel_requested.emit("map", "tirtha")
		"yaksha":
			Events.panel_requested.emit("yaksha", {"door": data.get("door", ""), "node": self})
		"shrine":
			Events.panel_requested.emit("shrine", data.get("shrine", "dharma"))
		"dig":
			_dig(world)
		"fish":
			_fish(world)
		"bed":
			if Game.hero.houses.has(region_id) or region_id == "vira_akhara":
				Game.sleep()
			else:
				Events.notify.emit(Loc.t("UI_LOCKED"), "bad")
		"boat":
			var b: Dictionary = data
			if b.has("when") and not Game.check(b["when"]):
				Events.notify.emit(Loc.t("UI_LOCKED"), "bad")
				return
			busy = true
			Audio.play("splash")
			world.travel(b.get("to", ""), "")
		"sign":
			var r := Data.region(region_id)
			var txt := Loc.t(r.get("name", {})) + "\n"
			for ex in r.get("exits", []):
				txt += "%s: %s\n" % [ex["dir"], Loc.t(Data.region(ex["to"]).get("name", {}))]
			Events.cutscene_requested.emit(Loc.t(r.get("name", {})), [{"nl": txt, "en": txt}], Callable())
		"dummy":
			pass

func _open_chest() -> void:
	var locked := int(data.get("locked", 0))
	if locked > 0:
		if Game.count("rajat_kunji") < locked:
			Events.notify.emit(Loc.t("UI_NEED_KEYS", {"n": locked}), "bad")
			Audio.play("block")
			return
		Game.take("rajat_kunji", locked)
	used = true
	Audio.play("chest")
	var lid := visual.get_node_or_null("Lid")
	if lid:
		lid.rotation.x = -1.2
		lid.position.z = -0.35
	for it in data.get("items", []):
		Game.give(it, 1)
	var gold := int(data.get("gold", 0))
	if gold > 0:
		Game.add_gold(int(round(gold * (1.0 + 0.1 * (Game.stat("chaturya") - 1)))))
	Game.hero.counters.chests = int(Game.hero.counters.get("chests", 0)) + 1
	Game.region_state(region_id).chests.append(index)
	Events.chest_opened.emit(region_id, index)

func _dig(world: Node) -> void:
	var has_tool := Game.has("kudala") or Game.has("bhumi_kudala") or Game.equipped("melee") == "bhumi_kudala"
	if not has_tool:
		Events.notify.emit(Loc.t("HINT_DIG"), "bad")
		return
	busy = true
	Audio.play("dig")
	var t := 1.4 if not (Game.has("bhumi_kudala")) else 0.6
	await get_tree().create_timer(t).timeout
	Audio.play("dig")
	used = true
	busy = false
	if data.has("item") and data["item"] != "":
		Game.give(data["item"], 1)
	if int(data.get("gold", 0)) > 0:
		Game.add_gold(int(data["gold"]))
	Game.region_state(region_id).dug.append(index)
	visual.visible = false

var fish_state: int = 0  # 0 idle, 1 waiting, 2 bite window
var fish_timer: float = 0.0

func _fish(world: Node) -> void:
	if not Game.has("bansi"):
		Events.notify.emit(Loc.t("HINT_FISH"), "bad")
		return
	if fish_state == 0:
		fish_state = 1
		busy = false
		Events.notify.emit(Loc.t("UI_FISH_WAIT"), "info")
		Audio.play("splash")
		var wait := randf_range(2.0, 5.0)
		await get_tree().create_timer(wait).timeout
		if fish_state != 1:
			return
		fish_state = 2
		Events.notify.emit(Loc.t("UI_FISH_NOW"), "good")
		Audio.play("pickup")
		await get_tree().create_timer(0.9).timeout
		if fish_state == 2:
			fish_state = 0
			Events.notify.emit(Loc.t("UI_FISH_LOST"), "bad")
	elif fish_state == 2:
		fish_state = 0
		Audio.play("splash")
		var item := "matsya"
		var r := randf()
		if region_id == "mahavana_hrada" and Game.is_night() and r < 0.2:
			item = "suvarna_matsya"
		elif region_id == "ankusha_tata" and r < 0.12 and not Game.flag("nilakantha_fished"):
			item = "nilakantha_talwar"
			Game.set_flag("nilakantha_fished", true)
		Game.give(item, 1)
		Game.hero.counters.fish = int(Game.hero.counters.get("fish", 0)) + 1
		Events.notify.emit(Loc.t("UI_FISH_CAUGHT", {"name": Loc.t(Data.item(item)["name"])}), "good")
	elif fish_state == 1:
		fish_state = 0
		Events.notify.emit(Loc.t("UI_FISH_LOST"), "bad")
