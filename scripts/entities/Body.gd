## Procedural character models built from Props primitives. Models face -Z (Godot forward).
## Humanoids expose named joints (LegL, LegR, ArmL, ArmR, Head, Torso, WeaponHand) so
## animation code can pose them without rebuilding the model.
extends RefCounted

const Props = preload("res://scripts/world/Props.gd")

static func col(v, fallback: String = "#cccccc") -> Color:
	if v is Color:
		return v
	if v is String and v != "":
		return Color.html(v)
	return Color.html(fallback)

static func _joint(parent: Node3D, nm: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = nm
	j.position = pos
	parent.add_child(j)
	return j

# =====================================================================
# Humanoid (player, NPCs, most enemies)
# =====================================================================
## b: body dictionary (skin, cloth, cloth2, hair, beard, thin, big, small, child, female,
## hood, cape, armor, mask, staff, bow, jata, shikha, ghost, glow, skull, third_eye, ash,
## sitting, scale, hair_style). o: extra options (hunch, ears, snout, eye, head_scale,
## arms_forward, bone, skirt).
static func humanoid(b: Dictionary, o: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var skin := col(b.get("skin", b.get("color")), "#c68a5a")
	if b.get("ash", false):
		skin = skin.lerp(Color("#d8d8d0"), 0.6)
	var cloth := col(b.get("cloth", b.get("color2")), "#c8b48a")
	var cloth2 := col(b.get("cloth2", b.get("color2")), "#8a6d3b")
	var hair := col(b.get("hair"), "#1a1a1a")
	var legs_col: Color = col(b["legs"]) if b.has("legs") else cloth2
	var sc: float = float(b.get("scale", 1.0))
	if b.get("big", false):
		sc *= 1.25
	if b.get("small", false):
		sc *= 0.82
	if b.get("child", false):
		sc *= 0.68
	root.scale = Vector3.ONE * sc
	var w: float = 0.82 if b.get("thin", false) else 1.0
	var sitting: bool = b.get("sitting", false)
	var hip := 0.12 if sitting else 0.85
	var hunch: float = float(o.get("hunch", 0.3 if b.get("old", false) else 0.0))
	var head_scale: float = float(o.get("head_scale", 1.0))
	var bone: bool = o.get("bone", false)
	# legs
	for side in [-1, 1]:
		var leg := _joint(root, "LegL" if side < 0 else "LegR", Vector3(side * 0.12 * w, hip, 0))
		leg.add_child(Props.cyl(0.075, 0.062, 0.85, legs_col, Vector3(0, -0.425, 0), Vector3.ZERO, 8))
		leg.add_child(Props.box(Vector3(0.12, 0.07, 0.22), Color("#3a2410"), Vector3(0, -0.83, -0.04)))
		if sitting:
			leg.rotation.x = PI / 2.0
	if b.get("female", false) or o.get("skirt", false):
		root.add_child(Props.cone(0.34, 0.6, cloth2, Vector3(0, hip + 0.0, 0), Vector3.ZERO, 12))
	# torso (head and arms hang off it so a hunch moves them too)
	var torso := _joint(root, "Torso", Vector3(0, hip, 0))
	torso.rotation.x = -hunch
	torso.add_child(Props.box(Vector3(0.5 * w, 0.62, 0.26), cloth, Vector3(0, 0.33, 0)))
	torso.add_child(Props.box(Vector3(0.52 * w, 0.07, 0.28), cloth2, Vector3(0, 0.03, 0)))
	if bone:
		for i in 3:
			torso.add_child(Props.box(Vector3(0.44 * w, 0.025, 0.2), Color("#2a2a2a"), Vector3(0, 0.2 + i * 0.14, -0.02)))
	if b.get("armor", false):
		torso.add_child(Props.box(Vector3(0.54 * w, 0.5, 0.3), Color("#8c8c94"), Vector3(0, 0.36, 0), Vector3.ZERO, 0.4, 0.8))
		for side in [-1, 1]:
			torso.add_child(Props.sphere(0.12, Color("#8c8c94"), Vector3(side * 0.31 * w, 0.62, 0), Vector3.ONE, 0.4, 0.8))
	if b.get("cape", false):
		torso.add_child(Props.box(Vector3(0.5 * w, 0.85, 0.03), cloth2, Vector3(0, 0.25, 0.17), Vector3(0.08, 0, 0)))
	if b.get("skull", false):
		torso.add_child(Props.sphere(0.06, Color("#e8e0d0"), Vector3(0.2, 0.0, -0.15)))
	# head
	var head := _joint(torso, "Head", Vector3(0, 0.74, 0))
	head.add_child(Props.sphere(0.14 * head_scale, skin, Vector3(0, 0.14 * head_scale, 0)))
	var eye_col := col(o.get("eye", "#1a1008"))
	var eye_glow := Color(eye_col.r, eye_col.g, eye_col.b, 0.8) if o.has("eye") else Color(0, 0, 0, 0)
	for side in [-1, 1]:
		head.add_child(Props.sphere(0.022, eye_col, Vector3(side * 0.05 * head_scale, 0.16 * head_scale, -0.125 * head_scale), Vector3.ONE, 0.5, 0.0, eye_glow))
	if b.get("third_eye", false):
		head.add_child(Props.sphere(0.02, Color("#d62828"), Vector3(0, 0.22 * head_scale, -0.135 * head_scale), Vector3.ONE, 0.5, 0.0, Color(1, 0.1, 0.1, 0.8)))
	if o.get("ears", false):
		for side in [-1, 1]:
			head.add_child(Props.cone(0.04, 0.2, skin, Vector3(side * 0.17 * head_scale, 0.17 * head_scale, 0), Vector3(0, 0, -side * 1.2), 5))
	if o.get("snout", false):
		head.add_child(Props.cone(0.07, 0.2, skin.darkened(0.15), Vector3(0, 0.1 * head_scale, -0.2 * head_scale), Vector3(-PI / 2.0, 0, 0), 6))
		for side in [-1, 1]:
			head.add_child(Props.cone(0.04, 0.12, skin, Vector3(side * 0.09, 0.28, 0.0), Vector3.ZERO, 4))
	_add_hair(head, b, hair)
	if b.get("beard", false) and not bone:
		var bcol := hair if not b.get("old", false) else hair.lerp(Color("#d8d8d8"), 0.5)
		head.add_child(Props.sphere(0.1, bcol, Vector3(0, 0.05, -0.07), Vector3(0.9, 1.5, 0.7)))
	if b.get("hood", false):
		head.add_child(Props.sphere(0.2, cloth, Vector3(0, 0.15, 0.03), Vector3(1, 1.05, 1.1)))
	if b.get("mask", false):
		head.add_child(Props.box(Vector3(0.22, 0.26, 0.03), Color("#c8b890"), Vector3(0, 0.14, -0.14)))
	# arms
	for side in [-1, 1]:
		var arm := _joint(torso, "ArmL" if side < 0 else "ArmR", Vector3(side * (0.25 * w + 0.07), 0.62, 0))
		arm.add_child(Props.cyl(0.055, 0.05, 0.58, cloth, Vector3(0, -0.29, 0), Vector3.ZERO, 8))
		arm.add_child(Props.sphere(0.06, skin, Vector3(0, -0.6, 0)))
		if o.get("arms_forward", false):
			arm.rotation.x = PI / 2.2
		if side > 0:
			var hand := _joint(arm, "WeaponHand", Vector3(0, -0.6, 0))
			hand.rotation.x = -PI / 2.0
		else:
			if b.get("staff", false):
				var st := Props.sword_mesh("staff", Color("#8a6a3a"), 0.9)
				st.position = Vector3(0, -0.6, 0)
				arm.add_child(st)
			if b.get("bow", false):
				var bw := Props.sword_mesh("bow", Color("#8a6a3a"), 0.8)
				bw.position = Vector3(0, -0.6, 0)
				arm.add_child(bw)
	if b.get("ghost", false):
		ghostify(root, 0.55)
	return root

static func _add_hair(head: Node3D, b: Dictionary, hair: Color) -> void:
	var style: String = str(b.get("hair_style", ""))
	if b.get("jata", false):
		style = "jata"
	elif b.get("shikha", false):
		style = "shikha"
	if style in ["mundan", "bald", "none"] or (b.get("hood", false) and style == ""):
		return
	head.add_child(Props.sphere(0.15, hair, Vector3(0, 0.19, 0.02), Vector3(1, 0.75, 1.05)))
	match style:
		"shikha":
			head.add_child(Props.sphere(0.06, hair, Vector3(0, 0.34, 0.02)))
		"jata":
			head.add_child(Props.sphere(0.09, hair, Vector3(0, 0.33, 0.0)))
			for i in 6:
				var a := i * TAU / 6.0
				head.add_child(Props.cyl(0.03, 0.02, 0.4, hair, Vector3(cos(a) * 0.1, 0.0, 0.06 + sin(a) * 0.08), Vector3.ZERO, 5))
		"choti", "lamba", "kesari":
			head.add_child(Props.cyl(0.04, 0.03, 0.5, hair, Vector3(0, -0.02, 0.15), Vector3(0.1, 0, 0), 6))
		_:
			if b.get("female", false):
				head.add_child(Props.box(Vector3(0.28, 0.45, 0.1), hair, Vector3(0, -0.02, 0.12)))

## Rewrites every mesh material in the subtree to a translucent, softly glowing version.
static func ghostify(n: Node, alpha: float) -> void:
	var mi := n as MeshInstance3D
	if mi != null:
		var m := mi.material_override as StandardMaterial3D
		if m != null:
			var c := m.albedo_color
			mi.material_override = Props.mat(Color(c.r, c.g, c.b), 0.6, 0.0, Color(c.r, c.g, c.b, 0.25), alpha)
	for ch in n.get_children():
		ghostify(ch, alpha)

# =====================================================================
# Creatures
# =====================================================================
static func quadruped(b: Dictionary, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := col(b.get("color"), "#7a6a5a")
	var c2 := col(b.get("color2"), "#3a3028")
	var eye := col(b.get("eye"), "#ffcc00")
	var s: float = float(b.get("scale", 1.0))
	root.scale = Vector3.ONE * s
	var big := kind == "dragon"
	var len_z := 1.4 if big else 1.0
	var h := 0.9 if big else 0.55
	root.add_child(Props.box(Vector3(0.5 if not big else 0.8, 0.42 if not big else 0.7, len_z), c, Vector3(0, h, 0)))
	var head := _joint(root, "Head", Vector3(0, h + 0.12, -len_z * 0.55))
	head.add_child(Props.box(Vector3(0.28, 0.26, 0.3), c, Vector3(0, 0.05, -0.08)))
	head.add_child(Props.box(Vector3(0.16, 0.14, 0.22), c2, Vector3(0, -0.02, -0.28)))
	for side in [-1, 1]:
		head.add_child(Props.sphere(0.025, eye, Vector3(side * 0.09, 0.1, -0.2), Vector3.ONE, 0.5, 0.0, Color(eye.r, eye.g, eye.b, 0.8)))
		head.add_child(Props.cone(0.05, 0.14, c, Vector3(side * 0.1, 0.24, 0.0), Vector3.ZERO, 4))
	var leg_h := h - 0.2
	var idx := 0
	for z in [-1, 1]:
		for x in [-1, 1]:
			var lg := _joint(root, "Leg%d" % idx, Vector3(x * 0.18, h - 0.1, z * len_z * 0.38))
			lg.add_child(Props.cyl(0.06, 0.045, leg_h + 0.1, c2, Vector3(0, -(leg_h + 0.1) / 2.0, 0), Vector3.ZERO, 6))
			idx += 1
	root.add_child(Props.cyl(0.05, 0.02, 0.8 if not big else 1.5, c2, Vector3(0, h + 0.05, len_z * 0.5 + 0.3), Vector3(PI / 2.5, 0, 0), 5))
	if kind == "tiger":
		for i in 5:
			root.add_child(Props.box(Vector3(0.52, 0.06, 0.06), c2, Vector3(0, h + 0.2, -0.4 + i * 0.2)))
	if big:
		for side in [-1, 1]:
			root.add_child(Props.prism(Vector3(1.4, 0.04, 0.9), c2, Vector3(side * 0.9, h + 0.55, 0.1), Vector3(0, 0, side * 0.5)))
		for side in [-1, 1]:
			head.add_child(Props.cone(0.05, 0.3, Color("#e8e0d0"), Vector3(side * 0.12, 0.3, 0.05), Vector3(-0.4, 0, side * 0.3), 5))
	return root

static func insect(b: Dictionary, kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := col(b.get("color"), "#d8a820")
	var c2 := col(b.get("color2"), "#222222")
	var eye := col(b.get("eye"), "#ff3300")
	root.scale = Vector3.ONE * float(b.get("scale", 1.0))
	root.add_child(Props.sphere(0.22, c, Vector3(0, 0.45, 0.2), Vector3(1, 0.9, 1.5)))
	for i in 3:
		root.add_child(Props.box(Vector3(0.4, 0.08, 0.1), c2, Vector3(0, 0.45, 0.1 + i * 0.16)))
	root.add_child(Props.sphere(0.14, c2, Vector3(0, 0.5, -0.12)))
	var head := _joint(root, "Head", Vector3(0, 0.55, -0.3))
	head.add_child(Props.sphere(0.11, c))
	for side in [-1, 1]:
		head.add_child(Props.sphere(0.045, eye, Vector3(side * 0.07, 0.02, -0.07), Vector3.ONE, 0.4, 0.0, Color(eye.r, eye.g, eye.b, 0.8)))
	if kind == "wasp":
		for side in [-1, 1]:
			root.add_child(Props.box(Vector3(0.5, 0.01, 0.2), Color(0.9, 0.95, 1.0), Vector3(side * 0.35, 0.7, 0.0), Vector3(0, side * 0.3, side * 0.2)))
		root.add_child(Props.cone(0.03, 0.18, c2, Vector3(0, 0.4, 0.55), Vector3(PI / 2.0, 0, 0), 4))
	else:
		root.add_child(Props.sphere(0.3, c, Vector3(0, 0.45, 0.05), Vector3(1.1, 0.7, 1.4), 0.3, 0.6))
		head.add_child(Props.cone(0.04, 0.2, c2, Vector3(0, 0.1, -0.1), Vector3(-0.6, 0, 0), 5))
		for i in 3:
			for side in [-1, 1]:
				root.add_child(Props.cyl(0.015, 0.015, 0.4, c2, Vector3(side * 0.28, 0.2, -0.1 + i * 0.2), Vector3(0, 0, side * 0.9), 4))
	return root

static func wisp(b: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := col(b.get("color"), "#8ae8ff")
	root.scale = Vector3.ONE * float(b.get("scale", 1.0))
	root.add_child(Props.sphere(0.28, c, Vector3(0, 0.5, 0), Vector3.ONE, 0.5, 0.0, Color(c.r, c.g, c.b, 0.8), 0.55))
	root.add_child(Props.sphere(0.14, Color.WHITE, Vector3(0, 0.5, 0), Vector3.ONE, 0.5, 0.0, Color(1, 1, 1, 1.0)))
	root.add_child(Props.cone(0.16, 0.5, c, Vector3(0, 0.1, 0), Vector3(PI, 0, 0), 8, 0.5))
	ghostify(root.get_child(2), 0.45)
	return root

static func naga(b: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var c := col(b.get("color"), "#2f6b3a")
	var c2 := col(b.get("color2"), "#d8c050")
	var eye := col(b.get("eye"), "#ffee00")
	root.scale = Vector3.ONE * float(b.get("scale", 1.0))
	for i in 8:
		var a := i * 0.8
		var r := 0.2 - i * 0.015
		root.add_child(Props.sphere(r, c if i % 2 == 0 else c2, Vector3(sin(a) * 0.5, r, 0.4 + cos(a) * 0.5 + i * 0.1)))
	root.add_child(Props.cyl(0.18, 0.2, 0.9, c, Vector3(0, 0.5, 0)))
	var head := _joint(root, "Head", Vector3(0, 1.05, 0))
	head.add_child(Props.sphere(0.14, c, Vector3(0, 0.05, 0), Vector3(1, 0.9, 1.2)))
	head.add_child(Props.sphere(0.3, c2, Vector3(0, 0.0, 0.1), Vector3(1, 1, 0.15)))
	for side in [-1, 1]:
		head.add_child(Props.sphere(0.025, eye, Vector3(side * 0.06, 0.08, -0.14), Vector3.ONE, 0.4, 0.0, Color(eye.r, eye.g, eye.b, 0.8)))
	return root

static func floating_sword(b: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var sw := Props.sword_mesh("straight", col(b.get("color"), "#b8c0d0"), 1.2)
	sw.position = Vector3(0, 0.3, 0)
	sw.rotation.x = PI
	root.add_child(sw)
	root.scale = Vector3.ONE * float(b.get("scale", 1.0))
	return root

# =====================================================================
# Enemy dispatcher
# =====================================================================
static func enemy(body: Dictionary) -> Node3D:
	var shape: String = body.get("shape", "humanoid")
	var b := body.duplicate()
	var model: Node3D
	match shape:
		"wolf", "tiger", "dragon":
			model = quadruped(b, shape)
		"wasp", "beetle":
			model = insect(b, shape)
		"wisp", "spirit":
			model = wisp(b)
		"naga":
			model = naga(b)
		"sword":
			model = floating_sword(b)
		"goblin":
			b["skin"] = b.get("color")
			b["cloth"] = b.get("color2")
			b["cloth2"] = b.get("color2")
			model = humanoid(b, {"hunch": 0.35, "ears": true, "head_scale": 1.3, "eye": b.get("eye", "#ffee00")})
		"wolfman":
			b["skin"] = b.get("color")
			b["cloth"] = b.get("color2")
			model = humanoid(b, {"hunch": 0.25, "snout": true, "eye": b.get("eye", "#ffaa00")})
		"zombie", "ghoul":
			b["skin"] = b.get("color")
			b["cloth"] = b.get("color2")
			model = humanoid(b, {"hunch": 0.4, "arms_forward": true, "eye": b.get("eye", "#e8e8a0")})
		"skeleton":
			b["skin"] = "#e8e0d0"
			b["cloth"] = "#e8e0d0"
			b["cloth2"] = "#cfc8b8"
			b["thin"] = true
			model = humanoid(b, {"bone": true, "eye": b.get("eye", "#ff4400")})
		"ghost":
			b["skin"] = b.get("color")
			b["cloth"] = b.get("color")
			b["cloth2"] = b.get("color2", b.get("color"))
			b["ghost"] = true
			model = humanoid(b, {"skirt": true, "eye": b.get("eye", "#ffffff")})
		"robed", "screamer":
			b["skin"] = b.get("color2", "#a07a5a")
			b["cloth"] = b.get("color")
			b["cloth2"] = b.get("color")
			b["hood"] = b.get("hood", shape == "robed")
			model = humanoid(b, {"skirt": true, "eye": b.get("eye", "#ff4400")})
		"armored":
			b["skin"] = b.get("color2", "#a07a5a")
			b["cloth"] = b.get("color")
			b["cloth2"] = b.get("color2")
			b["armor"] = true
			model = humanoid(b, {"eye": b.get("eye", "#ffcc00")})
		_:
			# humanoid, giant and anything unknown
			b["skin"] = b.get("skin", b.get("color2", "#a07a5a"))
			b["cloth"] = b.get("color")
			b["cloth2"] = b.get("color2")
			model = humanoid(b, {"eye": b.get("eye", "#ffcc00")})
	# held weapon for humanoid-like enemies
	var wep: String = str(body.get("weapon", ""))
	if wep != "":
		var hand := model.find_child("WeaponHand", true, false)
		if hand != null:
			hand.add_child(Props.sword_mesh(wep, Color("#b0b0b8"), 0.9))
	return model

# =====================================================================
# Posing
# =====================================================================
static func joints(model: Node3D) -> Dictionary:
	if model.has_meta("joints"):
		return model.get_meta("joints")
	var d := {}
	for nm in ["LegL", "LegR", "ArmL", "ArmR", "Torso", "Head", "WeaponHand"]:
		var j := model.find_child(nm, true, false)
		if j != null:
			d[nm] = j
	model.set_meta("joints", d)
	return d

## Swings legs and arms; amp 0 returns to the rest pose.
static func pose_walk(model: Node3D, phase: float, amp: float) -> void:
	var j := joints(model)
	var s := sin(phase) * amp
	if j.has("LegL"):
		j["LegL"].rotation.x = s
	if j.has("LegR"):
		j["LegR"].rotation.x = -s
	if j.has("ArmL"):
		j["ArmL"].rotation.x = -s * 0.8
	if j.has("ArmR"):
		j["ArmR"].rotation.x = s * 0.8

## Overhead swing with the right arm. t runs 0..1: wind-up (0-0.4), strike (0.4-0.6), recover.
## Returns false when the model has no arms (animals, insects) so the caller can lunge instead.
static func pose_attack(model: Node3D, t: float, heavy: bool = false) -> bool:
	var j := joints(model)
	if not j.has("ArmR"):
		return false
	var up := 2.9 if heavy else 2.6
	var arm: Node3D = j["ArmR"]
	var ang: float
	var twist: float
	if t < 0.4:
		var k := t / 0.4
		ang = lerpf(0.0, up, k * k)
		twist = lerpf(0.0, 0.45, k)
	elif t < 0.6:
		var k2 := (t - 0.4) / 0.2
		ang = lerpf(up, 1.1, k2)
		twist = lerpf(0.45, -0.5, k2)
	else:
		var k3 := (t - 0.6) / 0.4
		ang = lerpf(1.1, 0.0, k3)
		twist = lerpf(-0.5, 0.0, k3)
	arm.rotation.x = ang
	arm.rotation.z = 0.0
	if j.has("ArmL"):
		j["ArmL"].rotation.x = -0.4 * sin(clampf(t, 0.0, 1.0) * PI)
	if j.has("Torso"):
		j["Torso"].rotation.y = twist
	return true

## Guard: both forearms raised in front of the chest.
static func pose_block(model: Node3D) -> void:
	var j := joints(model)
	if j.has("ArmL"):
		j["ArmL"].rotation.x = 1.35
		j["ArmL"].rotation.z = -0.5
	if j.has("ArmR"):
		j["ArmR"].rotation.x = 1.35
		j["ArmR"].rotation.z = 0.5

## Drawing a bow: left arm out front holding it, right arm pulled back by `draw` (0..1).
static func pose_draw(model: Node3D, draw: float) -> void:
	var j := joints(model)
	if j.has("ArmL"):
		j["ArmL"].rotation.x = 1.45
		j["ArmL"].rotation.z = 0.0
	if j.has("ArmR"):
		j["ArmR"].rotation.x = lerpf(1.45, 0.9, draw)
		j["ArmR"].rotation.z = lerpf(0.0, -0.7, draw)

## Casting: both arms thrown up and pulsing; t is seconds since the cast began.
static func pose_cast(model: Node3D, t: float) -> void:
	var j := joints(model)
	var lift := 2.2 + 0.15 * sin(t * 18.0)
	for nm in ["ArmL", "ArmR"]:
		if j.has(nm):
			j[nm].rotation.x = lift
			j[nm].rotation.z = -0.25 if nm == "ArmL" else 0.25

## Dhyana: sits down cross-legged with the hands resting on the knees. k blends 0 (standing)..1.
## The model is lowered so the hips rest on the ground; pose_sit(model, 0.0) stands it up again.
static func pose_sit(model: Node3D, k: float) -> void:
	var j := joints(model)
	model.position.y = -0.73 * model.scale.y * k
	for nm in ["LegL", "LegR"]:
		if j.has(nm):
			j[nm].rotation.x = lerpf(0.0, PI / 2.0 - 0.15, k)
			j[nm].rotation.z = (-0.5 if nm == "LegL" else 0.5) * k
	for nm in ["ArmL", "ArmR"]:
		if j.has(nm):
			j[nm].rotation.x = lerpf(0.0, 0.85, k)
			j[nm].rotation.z = 0.0

## Undo the combat poses (keeps the torso hunch that some enemy bodies have).
static func pose_reset(model: Node3D) -> void:
	var j := joints(model)
	for nm in ["ArmL", "ArmR"]:
		if j.has(nm):
			j[nm].rotation.x = 0.0
			j[nm].rotation.z = 0.0
	if j.has("Torso"):
		j["Torso"].rotation.y = 0.0
