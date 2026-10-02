## Procedural prop builders. Every function returns a Node3D rooted at ground level (y = 0).
## Materials are cached per colour so hundreds of props share a handful of materials.
extends RefCounted

static var _mats: Dictionary = {}
static var _shader_cache: Dictionary = {}

static func mat(color: Color, rough: float = 0.85, metal: float = 0.0, emission: Color = Color(0, 0, 0, 0), alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), rough, metal, emission.to_html(), alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission.a > 0.0:
		m.emission_enabled = true
		m.emission = Color(emission.r, emission.g, emission.b)
		m.emission_energy_multiplier = emission.a * 3.0
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = alpha
	_mats[key] = m
	return m

static func shader_mat(path: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	if not _shader_cache.has(path):
		_shader_cache[path] = load(path)
	m.shader = _shader_cache[path]
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	return m

static func mesh_node(mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, rough: float = 0.85, metal: float = 0.0, emission: Color = Color(0, 0, 0, 0), alpha: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color, rough, metal, emission, alpha)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	return mi

static func box(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, rough: float = 0.85, metal: float = 0.0, emission: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return mesh_node(m, color, pos, rot, Vector3.ONE, rough, metal, emission)

static func cyl(rt: float, rb: float, h: float, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, sides: int = 10, rough: float = 0.85, metal: float = 0.0, emission: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = rt
	m.bottom_radius = rb
	m.height = h
	m.radial_segments = sides
	return mesh_node(m, color, pos, rot, Vector3.ONE, rough, metal, emission)

static func sphere(r: float, color: Color, pos: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE, rough: float = 0.85, metal: float = 0.0, emission: Color = Color(0, 0, 0, 0), alpha: float = 1.0) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 12
	m.rings = 6
	return mesh_node(m, color, pos, Vector3.ZERO, scl, rough, metal, emission, alpha)

static func cone(r: float, h: float, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, sides: int = 10, rough: float = 0.85) -> MeshInstance3D:
	return cyl(0.0, r, h, color, pos, rot, sides, rough)

static func prism(size: Vector3, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, rough: float = 0.85) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = size
	return mesh_node(m, color, pos, rot, Vector3.ONE, rough)

static func torus(inner: float, outer: float, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, rough: float = 0.6, metal: float = 0.3, emission: Color = Color(0, 0, 0, 0)) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 24
	m.ring_segments = 10
	return mesh_node(m, color, pos, rot, Vector3.ONE, rough, metal, emission)

static func capsule(r: float, h: float, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, rough: float = 0.8, metal: float = 0.0, emission: Color = Color(0, 0, 0, 0), alpha: float = 1.0) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	return mesh_node(m, color, pos, rot, Vector3.ONE, rough, metal, emission, alpha)

static func plane(size: Vector2, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, rough: float = 0.9) -> MeshInstance3D:
	var m := PlaneMesh.new()
	m.size = size
	return mesh_node(m, color, pos, rot, Vector3.ONE, rough)

static func omni(root: Node3D, color: Color, energy: float, rng: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	l.position = pos
	root.add_child(l)
	return l

static func collider(root: Node3D, shape: Shape3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = pos
	cs.rotation = rot
	sb.add_child(cs)
	root.add_child(sb)
	return sb

static func box_col(root: Node3D, size: Vector3, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> StaticBody3D:
	var s := BoxShape3D.new()
	s.size = size
	return collider(root, s, pos, rot)

static func cyl_col(root: Node3D, r: float, h: float, pos: Vector3) -> StaticBody3D:
	var s := CylinderShape3D.new()
	s.radius = r
	s.height = h
	return collider(root, s, pos)

static func _root(name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	return n

# =====================================================================
# Trees (single instances; forests use multimeshes built in WorldGen)
# =====================================================================
static func tree(kind: String, rng: RandomNumberGenerator, s: float = 1.0) -> Node3D:
	var r := _root("Tree")
	var trunk := Color("#5a3d23")
	match kind:
		"pine":
			r.add_child(cyl(0.18 * s, 0.3 * s, 2.0 * s, trunk, Vector3(0, 1.0 * s, 0)))
			for i in 3:
				var h := (2.2 + i * 1.3) * s
				r.add_child(cone((2.2 - i * 0.55) * s, 2.2 * s, Color("#2f5f3a").lerp(Color("#4f8f4a"), rng.randf()), Vector3(0, h, 0)))
			cyl_col(r, 0.3 * s, 3.0 * s, Vector3(0, 1.5 * s, 0))
		"palm":
			var lean := rng.randf_range(-0.2, 0.2)
			r.add_child(cyl(0.16 * s, 0.26 * s, 6.0 * s, Color("#8a6a3a"), Vector3(lean * 3.0, 3.0 * s, 0), Vector3(0, 0, lean)))
			for i in 7:
				var a := i * TAU / 7.0
				var leaf := box(Vector3(0.5 * s, 0.06, 3.0 * s), Color("#3f8f3a").lerp(Color("#7fbf4a"), rng.randf()), Vector3(lean * 6.0 + cos(a) * 1.3 * s, 6.0 * s, sin(a) * 1.3 * s), Vector3(0.35, -a + PI / 2.0, 0))
				r.add_child(leaf)
			r.add_child(sphere(0.3 * s, Color("#7a5a2a"), Vector3(lean * 6.0, 5.9 * s, 0)))
			cyl_col(r, 0.25 * s, 6.0 * s, Vector3(lean * 3.0, 3.0 * s, 0))
		"dead":
			var c := Color("#2a2420")
			r.add_child(cyl(0.12 * s, 0.4 * s, 4.0 * s, c, Vector3(0, 2.0 * s, 0)))
			for i in 4:
				var a := rng.randf() * TAU
				r.add_child(cyl(0.03 * s, 0.1 * s, 2.0 * s, c, Vector3(cos(a) * 0.8 * s, (3.2 + i * 0.3) * s, sin(a) * 0.8 * s), Vector3(cos(a) * 0.9, 0, sin(a) * 0.9)))
			cyl_col(r, 0.35 * s, 4.0 * s, Vector3(0, 2.0 * s, 0))
		"purple":
			r.add_child(cyl(0.2 * s, 0.35 * s, 3.0 * s, Color("#3a2a3a"), Vector3(0, 1.5 * s, 0)))
			r.add_child(sphere(1.9 * s, Color("#6a3a8a").lerp(Color("#a05ac8"), rng.randf()), Vector3(0, 4.0 * s, 0), Vector3(1, 0.8, 1)))
			r.add_child(sphere(1.2 * s, Color("#8a4aa8"), Vector3(0.8 * s, 4.9 * s, 0.4 * s)))
			omni(r, Color("#b06ae8"), 0.6, 6.0 * s, Vector3(0, 4.0 * s, 0))
			cyl_col(r, 0.35 * s, 3.0 * s, Vector3(0, 1.5 * s, 0))
		"mango":
			r.add_child(cyl(0.25 * s, 0.4 * s, 2.2 * s, trunk, Vector3(0, 1.1 * s, 0)))
			r.add_child(sphere(2.4 * s, Color("#2f7a2a").lerp(Color("#4f9a3a"), rng.randf()), Vector3(0, 3.4 * s, 0), Vector3(1.2, 0.8, 1.2)))
			for i in 5:
				r.add_child(sphere(0.12 * s, Color("#e8a020"), Vector3(rng.randf_range(-1.8, 1.8) * s, (2.6 + rng.randf()) * s, rng.randf_range(-1.8, 1.8) * s)))
			cyl_col(r, 0.4 * s, 2.5 * s, Vector3(0, 1.2 * s, 0))
		"banyan":
			r.add_child(cyl(1.0 * s, 1.6 * s, 4.0 * s, Color("#6a5240"), Vector3(0, 2.0 * s, 0), Vector3.ZERO, 14))
			r.add_child(sphere(6.0 * s, Color("#2f6b2a"), Vector3(0, 7.0 * s, 0), Vector3(1.3, 0.6, 1.3)))
			r.add_child(sphere(4.0 * s, Color("#3f7f32"), Vector3(2.0 * s, 8.5 * s, 1.0 * s), Vector3(1.2, 0.6, 1.2)))
			for i in 10:
				var a := i * TAU / 10.0 + rng.randf() * 0.3
				var rr := (3.0 + rng.randf() * 3.0) * s
				r.add_child(cyl(0.12 * s, 0.2 * s, 5.0 * s, Color("#7a6250"), Vector3(cos(a) * rr, 2.5 * s, sin(a) * rr)))
			cyl_col(r, 1.6 * s, 4.0 * s, Vector3(0, 2.0 * s, 0))
		_:
			r.add_child(cyl(0.2 * s, 0.32 * s, 2.6 * s, trunk, Vector3(0, 1.3 * s, 0)))
			var g := Color("#2f7a2a").lerp(Color("#5aa83a"), rng.randf())
			r.add_child(sphere(1.9 * s, g, Vector3(0, 3.8 * s, 0)))
			r.add_child(sphere(1.3 * s, g.lightened(0.1), Vector3(0.9 * s, 4.4 * s, 0.5 * s)))
			r.add_child(sphere(1.2 * s, g.darkened(0.08), Vector3(-0.8 * s, 4.2 * s, -0.6 * s)))
			cyl_col(r, 0.32 * s, 2.6 * s, Vector3(0, 1.3 * s, 0))
	return r

static func rock(rng: RandomNumberGenerator, color: Color, s: float = 1.0) -> Node3D:
	var r := _root("Rock")
	var sc := Vector3(rng.randf_range(0.8, 1.6), rng.randf_range(0.5, 1.0), rng.randf_range(0.8, 1.4)) * s
	r.add_child(sphere(1.0, color.lerp(color.darkened(0.2), rng.randf()), Vector3(0, sc.y * 0.5, 0), sc, 0.95))
	r.add_child(sphere(0.6, color.lightened(0.05), Vector3(sc.x * 0.4, sc.y * 0.4, 0), sc * 0.7, 0.95))
	var col := SphereShape3D.new()
	col.radius = 0.9 * s
	collider(r, col, Vector3(0, sc.y * 0.5, 0))
	return r

# =====================================================================
# Buildings
# =====================================================================
static func building(w: float, d: float, h: float, wall: Color, roof: Color, roof_kind: String = "prism", door: bool = true) -> Node3D:
	var r := _root("Building")
	r.add_child(box(Vector3(w, h, d), wall, Vector3(0, h / 2.0, 0)))
	match roof_kind:
		"prism":
			r.add_child(prism(Vector3(w + 0.6, h * 0.55, d + 0.6), roof, Vector3(0, h + h * 0.275, 0)))
		"flat":
			r.add_child(box(Vector3(w + 0.4, 0.3, d + 0.4), roof, Vector3(0, h + 0.15, 0)))
			for i in 4:
				r.add_child(box(Vector3(0.3, 0.6, 0.3), roof, Vector3((-w / 2.0 + 0.2) + i * (w - 0.4) / 3.0, h + 0.6, d / 2.0)))
		"dome":
			r.add_child(sphere(w * 0.55, roof, Vector3(0, h, 0), Vector3(1, 0.8, 1)))
		"cone":
			r.add_child(cone(w * 0.72, h * 0.7, roof, Vector3(0, h + h * 0.35, 0), Vector3.ZERO, 12))
	if door:
		r.add_child(box(Vector3(0.9, 1.9, 0.1), Color("#3a2410"), Vector3(0, 0.95, d / 2.0 + 0.03)))
		r.add_child(box(Vector3(0.7, 0.7, 0.08), Color("#1a2a3a"), Vector3(w * 0.3, h * 0.6, d / 2.0 + 0.03)))
		r.add_child(box(Vector3(0.7, 0.7, 0.08), Color("#1a2a3a"), Vector3(-w * 0.3, h * 0.6, d / 2.0 + 0.03)))
	box_col(r, Vector3(w, h, d), Vector3(0, h / 2.0, 0))
	return r

static func house(rng: RandomNumberGenerator) -> Node3D:
	var walls := [Color("#d8c8a0"), Color("#c8a878"), Color("#e8dcc0"), Color("#b89868")]
	var roofs := [Color("#8a6a3a"), Color("#a05a2a"), Color("#6a4a2a")]
	return building(rng.randf_range(5.0, 7.0), rng.randf_range(5.0, 7.0), rng.randf_range(2.8, 3.6), walls[rng.randi() % walls.size()], roofs[rng.randi() % roofs.size()], "prism")

static func hut(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Hut")
	var rad := rng.randf_range(2.2, 3.0)
	r.add_child(cyl(rad, rad, 2.4, Color("#c8a070"), Vector3(0, 1.2, 0), Vector3.ZERO, 12))
	r.add_child(cone(rad + 0.6, 2.2, Color("#8a7a4a"), Vector3(0, 3.5, 0), Vector3.ZERO, 12))
	r.add_child(box(Vector3(0.8, 1.7, 0.1), Color("#3a2410"), Vector3(0, 0.85, rad)))
	cyl_col(r, rad, 2.4, Vector3(0, 1.2, 0))
	return r

static func stone_house(rng: RandomNumberGenerator) -> Node3D:
	return building(rng.randf_range(5.0, 6.5), rng.randf_range(5.0, 6.5), 3.0, Color("#8a8a8a"), Color("#e8f0f8"), "prism")

static func mansion(rng: RandomNumberGenerator) -> Node3D:
	var r := building(rng.randf_range(9.0, 12.0), rng.randf_range(8.0, 10.0), 6.0, Color("#f0e8d8"), Color("#8a4a2a"), "flat")
	r.add_child(box(Vector3(4.0, 7.5, 4.0), Color("#f0e8d8"), Vector3(3.0, 3.75, -2.0)))
	r.add_child(sphere(2.2, Color("#c8a040"), Vector3(3.0, 7.6, -2.0), Vector3(1, 0.8, 1), 0.4, 0.5))
	for i in 5:
		r.add_child(cyl(0.2, 0.2, 5.0, Color("#ffffff"), Vector3(-5.0 + i * 2.5, 2.5, 4.5)))
	return r

static func haveli(ruin: bool = false) -> Node3D:
	var wall := Color("#6a6a70") if ruin else Color("#e8d8c0")
	var r := building(14.0, 10.0, 7.0, wall, Color("#5a3a2a") if not ruin else Color("#3a3a3a"), "flat")
	for i in 4:
		r.add_child(box(Vector3(1.6, 2.2, 0.2), Color("#3a2a4a"), Vector3(-5.0 + i * 3.3, 4.5, 5.1)))
	for i in 2:
		r.add_child(sphere(1.6, Color("#8a6a4a") if not ruin else Color("#4a4a4a"), Vector3(-4.5 + i * 9.0, 7.4, 0), Vector3(1, 0.7, 1)))
	if ruin:
		r.add_child(box(Vector3(3.0, 2.0, 2.0), wall, Vector3(6.0, 1.0, 7.0), Vector3(0, 0.5, 0.3)))
	return r

static func akhara_hall() -> Node3D:
	var r := _root("AkharaHall")
	r.add_child(box(Vector3(26.0, 0.8, 18.0), Color("#b8a080"), Vector3(0, 0.4, 0)))
	for i in 7:
		for j in 2:
			r.add_child(cyl(0.4, 0.5, 6.0, Color("#d8c8a8"), Vector3(-12.0 + i * 4.0, 3.8, -7.0 + j * 14.0), Vector3.ZERO, 10))
	r.add_child(box(Vector3(27.0, 0.6, 19.0), Color("#8a5a3a"), Vector3(0, 7.1, 0)))
	r.add_child(prism(Vector3(27.5, 4.0, 19.5), Color("#a0522d"), Vector3(0, 9.4, 0)))
	for i in 3:
		r.add_child(cone(1.2 - i * 0.3, 2.0, Color("#e3b341"), Vector3(0, 11.4 + i * 1.6, 0), Vector3.ZERO, 8, 0.4))
	r.add_child(box(Vector3(6.0, 1.2, 4.0), Color("#8a4a2a"), Vector3(0, 1.4, -4.0)))
	box_col(r, Vector3(26.0, 0.8, 18.0), Vector3(0, 0.4, 0))
	box_col(r, Vector3(6.0, 1.2, 4.0), Vector3(0, 1.4, -4.0))
	for i in 7:
		for j in 2:
			cyl_col(r, 0.5, 6.0, Vector3(-12.0 + i * 4.0, 3.8, -7.0 + j * 14.0))
	return r

static func temple(kind: String = "sun") -> Node3D:
	var r := _root("Temple")
	var stone := Color("#e8d8b0")
	var accent := Color("#e3b341")
	match kind:
		"dark":
			stone = Color("#2a2030")
			accent = Color("#8e44ad")
		"ruin":
			stone = Color("#7a7466")
			accent = Color("#5a5a50")
		"small":
			stone = Color("#f0e0c0")
	var base := 10.0 if kind != "small" else 5.0
	r.add_child(box(Vector3(base, 1.0, base), stone, Vector3(0, 0.5, 0)))
	r.add_child(box(Vector3(base * 0.8, 0.8, base * 0.8), stone.lightened(0.05), Vector3(0, 1.4, 0)))
	var h := 4.0 if kind != "small" else 2.5
	r.add_child(box(Vector3(base * 0.5, h, base * 0.5), stone, Vector3(0, 1.8 + h / 2.0, 0)))
	# shikhara (curvilinear tower) as stacked tapering boxes
	var levels := 6 if kind != "small" else 3
	for i in levels:
		var t := float(i) / levels
		var w := base * 0.5 * (1.0 - t * 0.75)
		r.add_child(box(Vector3(w, 1.1, w), stone.darkened(t * 0.15) if kind != "dark" else stone.lightened(t * 0.1), Vector3(0, 1.8 + h + 0.55 + i * 1.05, 0)))
	var top := 1.8 + h + levels * 1.05 + 0.6
	r.add_child(sphere(0.9 if kind != "small" else 0.5, accent, Vector3(0, top, 0), Vector3.ONE, 0.3, 0.6))
	r.add_child(cyl(0.05, 0.08, 1.5, accent, Vector3(0, top + 1.0, 0), Vector3.ZERO, 6, 0.3, 0.6))
	if kind == "ruin":
		r.add_child(box(Vector3(3.0, 1.5, 1.5), stone, Vector3(5.0, 0.75, 6.0), Vector3(0.2, 0.4, 0.1)))
	# door opening + steps
	r.add_child(box(Vector3(1.6, 2.4, 0.3), Color("#1a1010"), Vector3(0, 3.0, base * 0.25 + 0.1)))
	r.add_child(box(Vector3(base * 0.4, 0.5, 2.0), stone, Vector3(0, 0.25, base * 0.5 + 1.0)))
	if kind == "sun":
		omni(r, Color("#ffd27a"), 1.2, 14.0, Vector3(0, 4.0, base * 0.5 + 2.0))
	elif kind == "dark":
		omni(r, Color("#8e44ad"), 1.4, 14.0, Vector3(0, 3.0, base * 0.5 + 2.0))
	box_col(r, Vector3(base, 1.8, base), Vector3(0, 0.9, 0))
	box_col(r, Vector3(base * 0.5, h + 8.0, base * 0.5), Vector3(0, 1.8 + (h + 8.0) / 2.0, 0))
	return r

static func pillar(h: float = 5.0, color: Color = Color("#d8c8a8")) -> Node3D:
	var r := _root("Pillar")
	r.add_child(box(Vector3(1.2, 0.4, 1.2), color.darkened(0.1), Vector3(0, 0.2, 0)))
	r.add_child(cyl(0.35, 0.45, h, color, Vector3(0, 0.4 + h / 2.0, 0), Vector3.ZERO, 10))
	r.add_child(box(Vector3(1.1, 0.4, 1.1), color.darkened(0.1), Vector3(0, h + 0.6, 0)))
	cyl_col(r, 0.5, h + 0.8, Vector3(0, (h + 0.8) / 2.0, 0))
	return r

static func torch() -> Node3D:
	var r := _root("Torch")
	r.add_child(cyl(0.06, 0.08, 2.2, Color("#3a2a1a"), Vector3(0, 1.1, 0), Vector3.ZERO, 6))
	r.add_child(sphere(0.22, Color("#ff8a2a"), Vector3(0, 2.35, 0), Vector3(1, 1.4, 1), 0.5, 0.0, Color(1.0, 0.5, 0.1, 1.0)))
	var l := omni(r, Color("#ffa040"), 1.6, 9.0, Vector3(0, 2.6, 0))
	l.name = "Flame"
	return r

static func campfire() -> Node3D:
	var r := _root("Campfire")
	for i in 6:
		var a := i * TAU / 6.0
		r.add_child(sphere(0.35, Color("#6a6a66"), Vector3(cos(a) * 1.1, 0.2, sin(a) * 1.1), Vector3(1, 0.6, 1)))
	for i in 3:
		r.add_child(cyl(0.1, 0.12, 1.4, Color("#3a2410"), Vector3(0, 0.3, 0), Vector3(0.6, i * 2.1, 0)))
	r.add_child(sphere(0.45, Color("#ff9a2a"), Vector3(0, 0.6, 0), Vector3(1, 1.6, 1), 0.5, 0.0, Color(1.0, 0.45, 0.05, 1.2)))
	var l := omni(r, Color("#ffa040"), 2.2, 12.0, Vector3(0, 1.4, 0))
	l.name = "Flame"
	return r

static func dhuni() -> Node3D:
	var r := campfire()
	r.name = "Dhuni"
	r.add_child(cyl(0.9, 1.0, 0.4, Color("#8a7a6a"), Vector3(0, 0.1, 0), Vector3.ZERO, 12))
	r.add_child(cyl(0.05, 0.05, 2.5, Color("#c0392b"), Vector3(1.2, 1.25, 0)))
	r.add_child(box(Vector3(0.9, 0.6, 0.02), Color("#f28c28"), Vector3(1.65, 2.1, 0)))
	return r

static func well() -> Node3D:
	var r := _root("Well")
	r.add_child(cyl(1.1, 1.2, 1.0, Color("#8a8278"), Vector3(0, 0.5, 0), Vector3.ZERO, 12))
	r.add_child(cyl(0.8, 0.8, 0.1, Color("#1a3a4a"), Vector3(0, 0.95, 0), Vector3.ZERO, 12))
	r.add_child(cyl(0.08, 0.08, 2.4, Color("#5a3d23"), Vector3(-1.0, 1.7, 0)))
	r.add_child(cyl(0.08, 0.08, 2.4, Color("#5a3d23"), Vector3(1.0, 1.7, 0)))
	r.add_child(prism(Vector3(2.8, 0.7, 1.8), Color("#6a4a2a"), Vector3(0, 3.1, 0)))
	cyl_col(r, 1.2, 1.0, Vector3(0, 0.5, 0))
	return r

static func fence_segment(len: float = 4.0, color: Color = Color("#7a5a3a")) -> Node3D:
	var r := _root("Fence")
	r.add_child(box(Vector3(len, 0.12, 0.08), color, Vector3(0, 0.6, 0)))
	r.add_child(box(Vector3(len, 0.12, 0.08), color, Vector3(0, 1.1, 0)))
	r.add_child(box(Vector3(0.14, 1.4, 0.14), color.darkened(0.1), Vector3(-len / 2.0, 0.7, 0)))
	r.add_child(box(Vector3(0.14, 1.4, 0.14), color.darkened(0.1), Vector3(len / 2.0, 0.7, 0)))
	box_col(r, Vector3(len, 1.4, 0.3), Vector3(0, 0.7, 0))
	return r

static func palisade_segment(len: float = 4.0) -> Node3D:
	var r := _root("Palisade")
	var n := int(len / 0.5)
	for i in n:
		r.add_child(cyl(0.2, 0.24, 3.2 + (i % 2) * 0.3, Color("#5a3d23"), Vector3(-len / 2.0 + i * 0.5 + 0.25, 1.6, 0), Vector3.ZERO, 6))
	box_col(r, Vector3(len, 3.4, 0.5), Vector3(0, 1.7, 0))
	return r

static func gate_arch(color: Color = Color("#a89070")) -> Node3D:
	var r := _root("GateArch")
	r.add_child(box(Vector3(0.9, 5.0, 0.9), color, Vector3(-3.0, 2.5, 0)))
	r.add_child(box(Vector3(0.9, 5.0, 0.9), color, Vector3(3.0, 2.5, 0)))
	r.add_child(box(Vector3(7.5, 0.8, 1.2), color.darkened(0.1), Vector3(0, 5.3, 0)))
	r.add_child(prism(Vector3(8.0, 1.2, 1.6), Color("#8a4a2a"), Vector3(0, 6.3, 0)))
	box_col(r, Vector3(0.9, 5.0, 0.9), Vector3(-3.0, 2.5, 0))
	box_col(r, Vector3(0.9, 5.0, 0.9), Vector3(3.0, 2.5, 0))
	return r

static func signpost() -> Node3D:
	var r := _root("Signpost")
	r.add_child(cyl(0.08, 0.1, 2.4, Color("#5a3d23"), Vector3(0, 1.2, 0)))
	r.add_child(box(Vector3(1.4, 0.4, 0.08), Color("#a8865a"), Vector3(0.4, 2.1, 0), Vector3(0, 0, 0)))
	r.add_child(box(Vector3(1.2, 0.4, 0.08), Color("#a8865a"), Vector3(-0.3, 1.6, 0), Vector3(0, 1.2, 0)))
	return r

static func watchtower() -> Node3D:
	var r := _root("Watchtower")
	for i in 4:
		var a := i * TAU / 4.0 + PI / 4.0
		r.add_child(cyl(0.18, 0.22, 8.0, Color("#5a3d23"), Vector3(cos(a) * 2.0, 4.0, sin(a) * 2.0), Vector3(0, 0, 0)))
	r.add_child(box(Vector3(4.6, 0.3, 4.6), Color("#7a5a3a"), Vector3(0, 8.0, 0)))
	r.add_child(prism(Vector3(5.2, 1.8, 5.2), Color("#6a4a2a"), Vector3(0, 9.3, 0)))
	for i in 4:
		var a := i * TAU / 4.0
		r.add_child(box(Vector3(4.6, 0.8, 0.1), Color("#7a5a3a"), Vector3(cos(a) * 2.3, 8.6, sin(a) * 2.3), Vector3(0, -a, 0)))
	box_col(r, Vector3(4.6, 8.0, 4.6), Vector3(0, 4.0, 0))
	return r

static func lighthouse() -> Node3D:
	var r := _root("Lighthouse")
	r.add_child(cyl(1.6, 2.4, 16.0, Color("#f0f0f0"), Vector3(0, 8.0, 0), Vector3.ZERO, 14))
	for i in 3:
		r.add_child(cyl(2.0 - i * 0.2, 2.1 - i * 0.2, 1.0, Color("#c0392b"), Vector3(0, 3.0 + i * 5.0, 0), Vector3.ZERO, 14))
	r.add_child(cyl(1.8, 1.8, 2.5, Color("#1a2a3a"), Vector3(0, 17.2, 0), Vector3.ZERO, 14))
	r.add_child(sphere(1.0, Color("#ffe080"), Vector3(0, 17.2, 0), Vector3.ONE, 0.3, 0.0, Color(1.0, 0.85, 0.4, 2.0)))
	r.add_child(cone(2.2, 1.5, Color("#8a2a1a"), Vector3(0, 19.2, 0), Vector3.ZERO, 14))
	omni(r, Color("#ffe8a0"), 3.0, 40.0, Vector3(0, 17.5, 0))
	cyl_col(r, 2.4, 16.0, Vector3(0, 8.0, 0))
	return r

static func jetty(len: float = 10.0) -> Node3D:
	var r := _root("Jetty")
	r.add_child(box(Vector3(2.4, 0.25, len), Color("#8a6a4a"), Vector3(0, 0.6, len / 2.0)))
	for i in int(len / 2.5):
		r.add_child(cyl(0.12, 0.14, 2.5, Color("#5a3d23"), Vector3(-1.1, -0.2, i * 2.5 + 1.0)))
		r.add_child(cyl(0.12, 0.14, 2.5, Color("#5a3d23"), Vector3(1.1, -0.2, i * 2.5 + 1.0)))
	box_col(r, Vector3(2.4, 0.25, len), Vector3(0, 0.6, len / 2.0))
	return r

static func boat() -> Node3D:
	var r := _root("Boat")
	r.add_child(box(Vector3(2.0, 0.8, 5.0), Color("#6a4a2a"), Vector3(0, 0.1, 0)))
	r.add_child(prism(Vector3(2.0, 0.9, 1.5), Color("#6a4a2a"), Vector3(0, 0.15, 3.0), Vector3(PI / 2.0, 0, 0)))
	r.add_child(cyl(0.06, 0.08, 4.0, Color("#5a3d23"), Vector3(0, 2.3, 0)))
	r.add_child(box(Vector3(0.05, 3.0, 2.2), Color("#f0e8d0"), Vector3(0.1, 2.6, 0)))
	box_col(r, Vector3(2.0, 1.0, 5.0), Vector3(0, 0.5, 0))
	return r

static func bridge(len: float = 10.0, width: float = 4.0) -> Node3D:
	var r := _root("Bridge")
	r.add_child(box(Vector3(width, 0.4, len), Color("#8a7a5a"), Vector3(0, 0.2, 0)))
	r.add_child(box(Vector3(0.2, 1.0, len), Color("#5a3d23"), Vector3(-width / 2.0, 0.8, 0)))
	r.add_child(box(Vector3(0.2, 1.0, len), Color("#5a3d23"), Vector3(width / 2.0, 0.8, 0)))
	box_col(r, Vector3(width, 0.4, len), Vector3(0, 0.2, 0))
	return r

static func weir(len: float = 12.0) -> Node3D:
	var r := _root("Weir")
	r.add_child(box(Vector3(len, 2.0, 2.0), Color("#6a6a60"), Vector3(0, 0.0, 0)))
	r.add_child(box(Vector3(len, 0.3, 2.4), Color("#7a7a70"), Vector3(0, 1.1, 0)))
	box_col(r, Vector3(len, 2.3, 2.4), Vector3(0, 0.15, 0))
	return r

static func stone(rng: RandomNumberGenerator, color: Color = Color("#8a8a86")) -> Node3D:
	return rock(rng, color, rng.randf_range(0.6, 1.3))

static func standing_stone(h: float = 3.0, color: Color = Color("#6a6a70")) -> Node3D:
	var r := _root("StandingStone")
	r.add_child(box(Vector3(1.0, h, 0.7), color, Vector3(0, h / 2.0, 0), Vector3(0, 0, 0.05)))
	box_col(r, Vector3(1.0, h, 0.7), Vector3(0, h / 2.0, 0))
	return r

static func grave(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Grave")
	if rng.randf() < 0.5:
		r.add_child(box(Vector3(0.8, 1.2, 0.2), Color("#8a8a80"), Vector3(0, 0.6, 0)))
		r.add_child(sphere(0.4, Color("#8a8a80"), Vector3(0, 1.2, 0), Vector3(1, 0.5, 0.5)))
	else:
		r.add_child(box(Vector3(1.6, 0.5, 2.4), Color("#7a7a70"), Vector3(0, 0.25, 0)))
		r.add_child(sphere(0.6, Color("#9a9a90"), Vector3(0, 0.8, 0), Vector3(1, 0.8, 1)))
	return r

static func pyre() -> Node3D:
	var r := _root("Pyre")
	for i in 5:
		r.add_child(cyl(0.12, 0.14, 2.0, Color("#3a2a1a"), Vector3(0, 0.15 + i * 0.12, 0), Vector3(0, i * 0.6, 0)))
	r.add_child(sphere(0.5, Color("#ff8a2a"), Vector3(0, 0.9, 0), Vector3(1.2, 1.5, 1.2), 0.5, 0.0, Color(1.0, 0.4, 0.05, 1.2)))
	var l := omni(r, Color("#ff9a40"), 1.6, 9.0, Vector3(0, 1.5, 0))
	l.name = "Flame"
	return r

static func stupa() -> Node3D:
	var r := _root("Stupa")
	r.add_child(cyl(2.4, 2.6, 0.8, Color("#e8e0d0"), Vector3(0, 0.4, 0), Vector3.ZERO, 16))
	r.add_child(sphere(2.0, Color("#f4f0e8"), Vector3(0, 1.8, 0)))
	r.add_child(box(Vector3(0.9, 0.9, 0.9), Color("#e3b341"), Vector3(0, 3.9, 0)))
	r.add_child(cone(0.5, 1.6, Color("#e3b341"), Vector3(0, 5.1, 0), Vector3.ZERO, 8, 0.4))
	cyl_col(r, 2.4, 3.0, Vector3(0, 1.5, 0))
	return r

static func gallows() -> Node3D:
	var r := _root("Gallows")
	r.add_child(box(Vector3(4.0, 1.0, 3.0), Color("#5a4a3a"), Vector3(0, 0.5, 0)))
	r.add_child(cyl(0.15, 0.18, 4.0, Color("#3a2a1a"), Vector3(-1.5, 3.0, 0)))
	r.add_child(box(Vector3(3.0, 0.2, 0.2), Color("#3a2a1a"), Vector3(0, 5.0, 0)))
	r.add_child(cyl(0.03, 0.03, 1.5, Color("#a89070"), Vector3(1.0, 4.2, 0)))
	box_col(r, Vector3(4.0, 1.0, 3.0), Vector3(0, 0.5, 0))
	return r

static func arena_ring(radius: float = 22.0) -> Node3D:
	var r := _root("ArenaRing")
	var n := 28
	for i in n:
		var a := i * TAU / n
		var w := radius * TAU / n
		var seg := box(Vector3(w * 1.02, 4.0, 2.0), Color("#a08a66"), Vector3(cos(a) * radius, 2.0, sin(a) * radius), Vector3(0, -a, 0))
		r.add_child(seg)
		var tier := box(Vector3(w * 1.05, 3.0, 3.0), Color("#b8a080"), Vector3(cos(a) * (radius + 2.5), 5.0, sin(a) * (radius + 2.5)), Vector3(0, -a, 0))
		r.add_child(tier)
		box_col(r, Vector3(w, 6.0, 2.0), Vector3(cos(a) * radius, 3.0, sin(a) * radius), Vector3(0, -a, 0))
	# royal box
	r.add_child(box(Vector3(8.0, 0.5, 4.0), Color("#8e44ad"), Vector3(0, 8.1, -radius - 2.0)))
	r.add_child(box(Vector3(8.0, 3.0, 0.3), Color("#e3b341"), Vector3(0, 9.6, -radius - 4.0)))
	return r

static func cell() -> Node3D:
	var r := _root("Cell")
	r.add_child(box(Vector3(4.0, 3.0, 0.3), Color("#3a3a40"), Vector3(0, 1.5, -2.0)))
	r.add_child(box(Vector3(0.3, 3.0, 4.0), Color("#3a3a40"), Vector3(-2.0, 1.5, 0)))
	r.add_child(box(Vector3(0.3, 3.0, 4.0), Color("#3a3a40"), Vector3(2.0, 1.5, 0)))
	for i in 7:
		r.add_child(cyl(0.05, 0.05, 3.0, Color("#5a5a60"), Vector3(-1.8 + i * 0.6, 1.5, 2.0), Vector3.ZERO, 6, 0.4, 0.8))
	r.add_child(box(Vector3(1.6, 0.4, 0.8), Color("#5a4a3a"), Vector3(0.8, 0.3, -1.2)))
	box_col(r, Vector3(4.0, 3.0, 0.3), Vector3(0, 1.5, -2.0))
	box_col(r, Vector3(0.3, 3.0, 4.0), Vector3(-2.0, 1.5, 0))
	box_col(r, Vector3(0.3, 3.0, 4.0), Vector3(2.0, 1.5, 0))
	return r

static func cage() -> Node3D:
	var r := _root("Cage")
	for i in 8:
		var a := i * TAU / 8.0
		r.add_child(cyl(0.04, 0.04, 2.4, Color("#4a4a4a"), Vector3(cos(a) * 1.0, 1.2, sin(a) * 1.0), Vector3.ZERO, 6, 0.4, 0.8))
	r.add_child(torus(0.05, 1.05, Color("#4a4a4a"), Vector3(0, 2.4, 0)))
	r.add_child(torus(0.05, 1.05, Color("#4a4a4a"), Vector3(0, 0.05, 0)))
	return r

static func statue(color: Color = Color("#c8b890")) -> Node3D:
	var r := _root("Statue")
	r.add_child(box(Vector3(2.0, 1.0, 2.0), color.darkened(0.15), Vector3(0, 0.5, 0)))
	r.add_child(capsule(0.5, 2.2, color, Vector3(0, 2.3, 0)))
	r.add_child(sphere(0.4, color, Vector3(0, 3.8, 0)))
	for i in 4:
		var a := i * PI / 2.0 - PI / 4.0
		r.add_child(capsule(0.14, 1.4, color, Vector3(cos(a) * 0.7, 2.6, sin(a) * 0.5), Vector3(0.6, 0, cos(a) * 1.2)))
	box_col(r, Vector3(2.0, 4.5, 2.0), Vector3(0, 2.25, 0))
	return r

static func naga_statue() -> Node3D:
	var r := _root("NagaStatue")
	r.add_child(cyl(0.6, 0.9, 1.0, Color("#3a5a3a"), Vector3(0, 0.5, 0), Vector3.ZERO, 10))
	r.add_child(capsule(0.3, 2.4, Color("#2e8b57"), Vector3(0, 2.0, 0)))
	r.add_child(sphere(0.6, Color("#2e8b57"), Vector3(0, 3.6, 0), Vector3(1.6, 1.2, 0.5)))
	r.add_child(sphere(0.1, Color("#ffd700"), Vector3(-0.25, 3.7, 0.3), Vector3.ONE, 0.3, 0.0, Color(1.0, 0.85, 0.0, 1.0)))
	r.add_child(sphere(0.1, Color("#ffd700"), Vector3(0.25, 3.7, 0.3), Vector3.ONE, 0.3, 0.0, Color(1.0, 0.85, 0.0, 1.0)))
	cyl_col(r, 0.9, 4.0, Vector3(0, 2.0, 0))
	return r

static func altar(dark: bool = false) -> Node3D:
	var r := _root("Altar")
	var c := Color("#2a1a2a") if dark else Color("#e8d8b0")
	r.add_child(box(Vector3(3.0, 1.0, 1.6), c, Vector3(0, 0.5, 0)))
	r.add_child(box(Vector3(3.4, 0.2, 2.0), c.lightened(0.1), Vector3(0, 1.1, 0)))
	if dark:
		r.add_child(sphere(0.3, Color("#8e44ad"), Vector3(0, 1.5, 0), Vector3.ONE, 0.3, 0.0, Color(0.6, 0.2, 0.8, 1.5)))
		omni(r, Color("#9a4ad8"), 1.4, 8.0, Vector3(0, 2.0, 0))
	else:
		r.add_child(sphere(0.3, Color("#ffd27a"), Vector3(0, 1.5, 0), Vector3.ONE, 0.3, 0.0, Color(1.0, 0.8, 0.3, 1.5)))
		omni(r, Color("#ffd27a"), 1.4, 8.0, Vector3(0, 2.0, 0))
	box_col(r, Vector3(3.4, 1.2, 2.0), Vector3(0, 0.6, 0))
	return r

static func totem() -> Node3D:
	var r := _root("Totem")
	r.add_child(cyl(0.4, 0.5, 4.0, Color("#6a3a1a"), Vector3(0, 2.0, 0), Vector3.ZERO, 8))
	var tcols: Array[Color] = [Color("#c0392b"), Color("#e3b341"), Color("#2e86de")]
	for i in 3:
		r.add_child(sphere(0.5, tcols[i], Vector3(0, 0.8 + i * 1.2, 0), Vector3(1.2, 0.8, 1.2)))
		r.add_child(sphere(0.1, Color("#000000"), Vector3(-0.2, 0.9 + i * 1.2, 0.5)))
		r.add_child(sphere(0.1, Color("#000000"), Vector3(0.2, 0.9 + i * 1.2, 0.5)))
	cyl_col(r, 0.5, 4.0, Vector3(0, 2.0, 0))
	return r

static func lotus(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Lotus")
	for i in 5:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.5, 3.0)
		var p := Vector3(cos(a) * d, 0.02, sin(a) * d)
		r.add_child(cyl(0.6, 0.6, 0.04, Color("#2f6f3a"), p, Vector3.ZERO, 10))
		if rng.randf() < 0.6:
			r.add_child(sphere(0.2, Color("#f49ac2"), p + Vector3(0.3, 0.2, 0.2), Vector3(1, 1.3, 1)))
	return r

static func throne() -> Node3D:
	var r := _root("Throne")
	r.add_child(box(Vector3(3.0, 0.6, 3.0), Color("#5a4a3a"), Vector3(0, 0.3, 0)))
	r.add_child(box(Vector3(1.6, 1.0, 1.4), Color("#8b0000"), Vector3(0, 1.1, 0)))
	r.add_child(box(Vector3(1.6, 2.4, 0.3), Color("#8b0000"), Vector3(0, 2.0, -0.7)))
	for i in 7:
		r.add_child(box(Vector3(0.12, 2.6, 0.05), Color("#9aa3ad"), Vector3(-0.9 + i * 0.3, 2.6, -0.9), Vector3(0, 0, (i - 3) * 0.1), 0.3, 0.9))
	box_col(r, Vector3(3.0, 0.6, 3.0), Vector3(0, 0.3, 0))
	return r

static func big_tent() -> Node3D:
	var r := _root("BigTent")
	r.add_child(cone(8.0, 7.0, Color("#8b0000"), Vector3(0, 3.5, 0), Vector3.ZERO, 12))
	r.add_child(cyl(0.12, 0.12, 8.0, Color("#3a2a1a"), Vector3(0, 4.0, 0)))
	r.add_child(box(Vector3(0.9, 1.5, 0.05), Color("#e3b341"), Vector3(0, 7.6, 0)))
	cyl_col(r, 7.5, 3.0, Vector3(0, 1.5, 0))
	return r

static func tent(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Tent")
	var cols: Array[Color] = [Color("#8a6a4a"), Color("#6a5a4a"), Color("#8b3a2a"), Color("#5a5a4a")]
	var c: Color = cols[rng.randi() % 4]
	r.add_child(prism(Vector3(3.6, 2.4, 4.0), c, Vector3(0, 1.2, 0)))
	r.add_child(cyl(0.05, 0.05, 2.4, Color("#3a2a1a"), Vector3(0, 1.2, 2.0)))
	box_col(r, Vector3(3.4, 2.2, 3.6), Vector3(0, 1.1, 0))
	return r

static func waterwheel() -> Node3D:
	var r := _root("Waterwheel")
	r.add_child(torus(0.2, 2.2, Color("#5a3d23"), Vector3(0, 2.0, 0), Vector3(0, 0, PI / 2.0), 0.9, 0.0))
	for i in 8:
		var a := i * TAU / 8.0
		r.add_child(box(Vector3(0.15, 4.2, 0.6), Color("#7a5a3a"), Vector3(0, 2.0, 0), Vector3(a, 0, 0)))
	r.add_child(box(Vector3(1.0, 2.0, 1.0), Color("#8a8278"), Vector3(0.8, 1.0, 0)))
	box_col(r, Vector3(1.0, 4.4, 4.4), Vector3(0, 2.2, 0))
	return r

static func farm_rows(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("FarmRows")
	for i in 5:
		for j in 8:
			var p := Vector3(-8.0 + i * 4.0, 0.0, -8.0 + j * 2.2)
			r.add_child(box(Vector3(0.5, 0.3, 1.8), Color("#5a3d23"), p + Vector3(0, 0.15, 0)))
			r.add_child(sphere(0.35, Color("#4a8a2a").lerp(Color("#7ab83a"), rng.randf()), p + Vector3(0, 0.6, 0)))
	return r

static func picnic_cloth(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Picnic")
	var cloths: Array[Color] = [Color("#c0392b"), Color("#2e86de"), Color("#f1c40f")]
	r.add_child(box(Vector3(2.6, 0.04, 2.6), cloths[rng.randi() % 3], Vector3(0, 0.03, 0)))
	r.add_child(cyl(0.3, 0.25, 0.3, Color("#e8d8b0"), Vector3(0.5, 0.2, 0.3)))
	r.add_child(sphere(0.15, Color("#e8a020"), Vector3(-0.4, 0.15, -0.2)))
	return r

static func wasp_nest() -> Node3D:
	var r := _root("WaspNest")
	r.add_child(cyl(0.3, 0.45, 5.0, Color("#5a3d23"), Vector3(0, 2.5, 0)))
	r.add_child(sphere(2.2, Color("#8a6a2a"), Vector3(0, 6.0, 0), Vector3(1, 1.3, 1)))
	r.add_child(sphere(1.3, Color("#a88a4a"), Vector3(0, 3.3, 0), Vector3(1, 1.6, 1), 0.95))
	r.add_child(sphere(0.3, Color("#1a1a1a"), Vector3(0, 2.6, 1.1)))
	cyl_col(r, 1.0, 5.0, Vector3(0, 2.5, 0))
	return r

static func sarcophagus() -> Node3D:
	var r := _root("Sarcophagus")
	r.add_child(box(Vector3(1.4, 1.0, 3.0), Color("#8a8a80"), Vector3(0, 0.5, 0)))
	r.add_child(box(Vector3(1.5, 0.3, 3.1), Color("#6a6a60"), Vector3(0, 1.15, 0)))
	r.add_child(capsule(0.35, 2.0, Color("#9a9a90"), Vector3(0, 1.35, 0), Vector3(PI / 2.0, 0, 0)))
	box_col(r, Vector3(1.5, 1.3, 3.1), Vector3(0, 0.65, 0))
	return r

static func mausoleum() -> Node3D:
	var r := building(6.0, 6.0, 4.5, Color("#9aa8b8"), Color("#6a7a8a"), "dome", true)
	for i in 2:
		r.add_child(cyl(0.3, 0.35, 4.0, Color("#b8c4d0"), Vector3(-1.8 + i * 3.6, 2.0, 3.6)))
	return r

static func frozen_person(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Frozen")
	r.add_child(capsule(0.35, 1.5, Color("#9ab8d0"), Vector3(0, 1.1, 0), Vector3.ZERO, 0.2, 0.0, Color(0.6, 0.8, 1.0, 0.3), 0.85))
	r.add_child(sphere(0.3, Color("#a8c4dc"), Vector3(0, 2.1, 0), Vector3.ONE, 0.2, 0.0, Color(0.6, 0.8, 1.0, 0.3), 0.85))
	r.add_child(box(Vector3(1.4, 2.8, 1.4), Color("#cfe8ff"), Vector3(0, 1.4, 0), Vector3(0, rng.randf() * 0.5, 0), 0.1, 0.0, Color(0.7, 0.9, 1.0, 0.2)))
	r.get_child(2).material_override = mat(Color("#cfe8ff"), 0.1, 0.0, Color(0.7, 0.9, 1.0, 0.2), 0.35)
	box_col(r, Vector3(1.4, 2.8, 1.4), Vector3(0, 1.4, 0))
	return r

static func bones(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Bones")
	for i in 6:
		var a := rng.randf() * TAU
		r.add_child(cyl(0.05, 0.06, rng.randf_range(0.5, 1.2), Color("#e8e4d0"), Vector3(rng.randf_range(-1, 1), 0.06, rng.randf_range(-1, 1)), Vector3(PI / 2.0, a, 0), 6))
	r.add_child(sphere(0.25, Color("#e8e4d0"), Vector3(0.3, 0.25, 0.2)))
	return r

static func reeds(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Reeds")
	for i in 9:
		r.add_child(cyl(0.02, 0.04, rng.randf_range(1.2, 2.2), Color("#5a7a3a"), Vector3(rng.randf_range(-0.8, 0.8), 0.8, rng.randf_range(-0.8, 0.8)), Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), 5))
	return r

static func wisp(color: Color = Color("#8ae8ff")) -> Node3D:
	var r := _root("Wisp")
	r.add_child(sphere(0.25, color, Vector3(0, 1.5, 0), Vector3.ONE, 0.3, 0.0, Color(color.r, color.g, color.b, 1.5), 0.8))
	omni(r, color, 0.8, 6.0, Vector3(0, 1.5, 0))
	return r

static func crystal(rng: RandomNumberGenerator, color: Color = Color("#a06ae8")) -> Node3D:
	var r := _root("Crystal")
	for i in 3:
		var h := rng.randf_range(1.2, 3.0)
		r.add_child(cone(rng.randf_range(0.25, 0.5), h, color, Vector3(rng.randf_range(-0.6, 0.6), h / 2.0, rng.randf_range(-0.6, 0.6)), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), 6, 0.2))
		r.get_child(i).material_override = mat(color, 0.15, 0.0, Color(color.r, color.g, color.b, 0.6), 0.9)
	omni(r, color, 0.9, 7.0, Vector3(0, 1.5, 0))
	cyl_col(r, 0.7, 2.0, Vector3(0, 1.0, 0))
	return r

static func stalagmite(rng: RandomNumberGenerator, color: Color = Color("#6a5e54")) -> Node3D:
	var r := _root("Stalagmite")
	var h := rng.randf_range(1.5, 4.0)
	r.add_child(cone(rng.randf_range(0.4, 0.9), h, color, Vector3(0, h / 2.0, 0), Vector3.ZERO, 8, 0.95))
	cyl_col(r, 0.5, h, Vector3(0, h / 2.0, 0))
	return r

static func fallen_log() -> Node3D:
	var r := _root("Log")
	r.add_child(cyl(0.4, 0.45, 5.0, Color("#5a3d23"), Vector3(0, 0.4, 0), Vector3(0, 0, PI / 2.0), 8))
	box_col(r, Vector3(5.0, 0.8, 0.9), Vector3(0, 0.4, 0))
	return r

static func rose_bush(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("RoseBush")
	r.add_child(sphere(0.9, Color("#2f6b2a"), Vector3(0, 0.7, 0), Vector3(1.2, 0.9, 1.2)))
	for i in 6:
		r.add_child(sphere(0.12, Color("#e0115f"), Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(0.6, 1.3), rng.randf_range(-0.8, 0.8))))
	return r

static func training_dummy() -> Node3D:
	var r := _root("Dummy")
	r.add_child(cyl(0.1, 0.12, 1.4, Color("#5a3d23"), Vector3(0, 0.7, 0)))
	r.add_child(cyl(0.45, 0.45, 1.2, Color("#c8a070"), Vector3(0, 1.6, 0), Vector3.ZERO, 10))
	r.add_child(sphere(0.3, Color("#c8a070"), Vector3(0, 2.5, 0)))
	r.add_child(box(Vector3(1.6, 0.15, 0.15), Color("#5a3d23"), Vector3(0, 1.9, 0)))
	cyl_col(r, 0.5, 2.8, Vector3(0, 1.4, 0))
	return r

static func archery_target() -> Node3D:
	var r := _root("Target")
	r.add_child(cyl(0.08, 0.1, 1.5, Color("#5a3d23"), Vector3(0, 0.75, 0)))
	r.add_child(cyl(0.9, 0.9, 0.15, Color("#f0e8d0"), Vector3(0, 1.8, 0), Vector3(PI / 2.0, 0, 0), 14))
	r.add_child(cyl(0.6, 0.6, 0.17, Color("#c0392b"), Vector3(0, 1.8, 0), Vector3(PI / 2.0, 0, 0), 14))
	r.add_child(cyl(0.3, 0.3, 0.19, Color("#f1c40f"), Vector3(0, 1.8, 0), Vector3(PI / 2.0, 0, 0), 14))
	cyl_col(r, 0.9, 2.7, Vector3(0, 1.35, 0))
	return r

static func cottage() -> Node3D:
	var r := building(6.0, 5.0, 2.8, Color("#e8dcc0"), Color("#7a4a2a"), "prism")
	r.add_child(cyl(0.3, 0.3, 1.2, Color("#8a8278"), Vector3(1.8, 3.8, -1.0)))
	return r

static func farmhouse() -> Node3D:
	var r := building(8.0, 6.0, 3.2, Color("#d8c8a0"), Color("#8a6a3a"), "prism")
	r.add_child(box(Vector3(3.0, 2.0, 3.0), Color("#a08a60"), Vector3(6.0, 1.0, 0)))
	box_col(r, Vector3(3.0, 2.0, 3.0), Vector3(6.0, 1.0, 0))
	return r

static func loot_pile(rng: RandomNumberGenerator) -> Node3D:
	var r := _root("Loot")
	for i in 5:
		var lcols: Array[Color] = [Color("#8a6a3a"), Color("#e3b341"), Color("#9b59b6")]
		r.add_child(box(Vector3(0.6, 0.5, 0.5), lcols[rng.randi() % 3], Vector3(rng.randf_range(-0.6, 0.6), 0.25 + i * 0.25, rng.randf_range(-0.6, 0.6)), Vector3(0, rng.randf() * PI, 0)))
	return r

static func bell() -> Node3D:
	var r := _root("Bell")
	r.add_child(box(Vector3(0.3, 3.0, 0.3), Color("#8a6a3a"), Vector3(-1.2, 1.5, 0)))
	r.add_child(box(Vector3(0.3, 3.0, 0.3), Color("#8a6a3a"), Vector3(1.2, 1.5, 0)))
	r.add_child(box(Vector3(2.7, 0.3, 0.3), Color("#8a6a3a"), Vector3(0, 3.1, 0)))
	r.add_child(cyl(0.3, 0.55, 0.8, Color("#c8a040"), Vector3(0, 2.3, 0), Vector3.ZERO, 12, 0.3, 0.8))
	return r

static func yantra_floor() -> Node3D:
	var r := _root("Yantra")
	r.add_child(cyl(9.0, 9.0, 0.08, Color("#4a2a4a"), Vector3(0, 0.05, 0), Vector3.ZERO, 32))
	for i in 9:
		var a := i * TAU / 9.0
		r.add_child(box(Vector3(0.3, 0.02, 14.0), Color("#c0392b"), Vector3(0, 0.1, 0), Vector3(0, a, 0), 0.5, 0.0, Color(0.9, 0.2, 0.2, 0.5)))
	r.add_child(torus(0.15, 6.0, Color("#e3b341"), Vector3(0, 0.12, 0), Vector3.ZERO, 0.4, 0.6, Color(0.9, 0.7, 0.2, 0.5)))
	return r

static func oracle_cave() -> Node3D:
	var r := _root("OracleCave")
	r.add_child(sphere(7.0, Color("#8aa8c8"), Vector3(0, 3.0, -4.0), Vector3(1.2, 0.9, 1.0), 0.6))
	r.add_child(box(Vector3(4.0, 4.0, 3.0), Color("#1a2a3a"), Vector3(0, 2.0, 2.2)))
	for i in 5:
		r.add_child(cone(0.4, 2.5, Color("#aee7ff"), Vector3(-3.0 + i * 1.5, 1.2, 3.5), Vector3.ZERO, 6, 0.1))
		r.get_child(r.get_child_count() - 1).material_override = mat(Color("#aee7ff"), 0.1, 0.0, Color(0.6, 0.9, 1.0, 0.6), 0.9)
	omni(r, Color("#aee7ff"), 1.5, 14.0, Vector3(0, 3.0, 3.0))
	var col := SphereShape3D.new()
	col.radius = 6.5
	collider(r, col, Vector3(0, 3.0, -5.0))
	return r

static func ghat_steps(width: float = 16.0) -> Node3D:
	var r := _root("Ghat")
	for i in 6:
		r.add_child(box(Vector3(width, 0.4, 1.4), Color("#c8b890").darkened(i * 0.04), Vector3(0, -0.2 - i * 0.4 + 0.4, i * 1.4)))
		box_col(r, Vector3(width, 0.4, 1.4), Vector3(0, -0.2 - i * 0.4 + 0.4, i * 1.4))
	return r

static func fountain() -> Node3D:
	var r := _root("Fountain")
	r.add_child(cyl(3.0, 3.2, 0.8, Color("#e8e0d0"), Vector3(0, 0.4, 0), Vector3.ZERO, 16))
	r.add_child(cyl(2.6, 2.6, 0.1, Color("#3a8fa0"), Vector3(0, 0.75, 0), Vector3.ZERO, 16, 0.1))
	r.add_child(cyl(0.3, 0.4, 2.0, Color("#e8e0d0"), Vector3(0, 1.6, 0)))
	r.add_child(cyl(1.0, 0.8, 0.3, Color("#e8e0d0"), Vector3(0, 2.6, 0), Vector3.ZERO, 12))
	cyl_col(r, 3.2, 0.8, Vector3(0, 0.4, 0))
	return r

static func stones_circle(rng: RandomNumberGenerator, radius: float = 8.0, color: Color = Color("#6a6a70")) -> Node3D:
	var r := _root("StoneCircle")
	var n := 9
	for i in n:
		var a := i * TAU / n
		var s := standing_stone(rng.randf_range(2.5, 4.0), color)
		s.position = Vector3(cos(a) * radius, 0, sin(a) * radius)
		s.rotation.y = -a
		r.add_child(s)
	return r

static func shrine_small() -> Node3D:
	var r := _root("Shrine")
	r.add_child(box(Vector3(1.6, 1.0, 1.4), Color("#d8c8a0"), Vector3(0, 0.5, 0)))
	r.add_child(box(Vector3(1.2, 1.2, 1.0), Color("#c0392b"), Vector3(0, 1.6, 0)))
	r.add_child(cone(0.9, 1.0, Color("#e3b341"), Vector3(0, 2.7, 0), Vector3.ZERO, 8, 0.4))
	r.add_child(sphere(0.12, Color("#ff9a2a"), Vector3(0, 1.2, 0.6), Vector3.ONE, 0.5, 0.0, Color(1.0, 0.5, 0.1, 1.0)))
	omni(r, Color("#ffb060"), 0.6, 5.0, Vector3(0, 1.4, 0.8))
	box_col(r, Vector3(1.6, 2.5, 1.4), Vector3(0, 1.25, 0))
	return r

# ---------- interactable visuals ----------
static func chest_visual(silver: bool) -> Node3D:
	var r := _root("ChestVisual")
	var c := Color("#c0c8d0") if silver else Color("#7a4a1f")
	r.add_child(box(Vector3(1.2, 0.7, 0.8), c, Vector3(0, 0.35, 0), Vector3.ZERO, 0.5 if silver else 0.85, 0.8 if silver else 0.0))
	var lid := box(Vector3(1.24, 0.35, 0.84), c.darkened(0.15), Vector3(0, 0.85, 0), Vector3.ZERO, 0.5 if silver else 0.85, 0.8 if silver else 0.0)
	lid.name = "Lid"
	r.add_child(lid)
	r.add_child(box(Vector3(0.2, 0.3, 0.1), Color("#e3b341"), Vector3(0, 0.6, 0.42), Vector3.ZERO, 0.3, 0.9))
	box_col(r, Vector3(1.2, 1.0, 0.8), Vector3(0, 0.5, 0))
	return r

static func pickup_visual(color: Color) -> Node3D:
	var r := _root("PickupVisual")
	r.add_child(sphere(0.28, color, Vector3(0, 0.7, 0), Vector3.ONE, 0.4, 0.2, Color(color.r, color.g, color.b, 0.5)))
	omni(r, color, 0.4, 3.0, Vector3(0, 0.9, 0))
	return r

static func key_visual() -> Node3D:
	var r := _root("KeyVisual")
	r.add_child(torus(0.05, 0.22, Color("#e8e8f0"), Vector3(0, 0.8, 0), Vector3(PI / 2.0, 0, 0), 0.25, 0.95, Color(0.9, 0.9, 1.0, 0.6)))
	r.add_child(box(Vector3(0.08, 0.5, 0.08), Color("#e8e8f0"), Vector3(0, 0.45, 0), Vector3.ZERO, 0.25, 0.95, Color(0.9, 0.9, 1.0, 0.6)))
	omni(r, Color("#d0d8ff"), 0.6, 4.0, Vector3(0, 0.9, 0))
	return r

static func yaksha_door() -> Node3D:
	var r := _root("YakshaDoor")
	var rockc := Color("#5a5a60")
	r.add_child(sphere(5.0, rockc, Vector3(0, 2.5, -2.5), Vector3(1.6, 1.2, 1.0), 0.95))
	r.add_child(sphere(0.7, Color("#e8e0d0"), Vector3(-1.6, 4.2, 1.6), Vector3(1.2, 1, 0.6)))
	r.add_child(sphere(0.7, Color("#e8e0d0"), Vector3(1.6, 4.2, 1.6), Vector3(1.2, 1, 0.6)))
	r.add_child(sphere(0.3, Color("#1a1a1a"), Vector3(-1.6, 4.2, 2.0)))
	r.add_child(sphere(0.3, Color("#1a1a1a"), Vector3(1.6, 4.2, 2.0)))
	r.add_child(cone(0.6, 1.4, rockc.darkened(0.1), Vector3(0, 3.2, 2.0), Vector3(PI / 2.0, 0, 0), 8))
	var mouth := box(Vector3(2.6, 3.0, 0.6), Color("#120a12"), Vector3(0, 1.5, 1.9))
	mouth.name = "Mouth"
	r.add_child(mouth)
	for i in 6:
		r.add_child(cone(0.2, 0.6, Color("#e8e0d0"), Vector3(-1.1 + i * 0.44, 2.7, 2.1), Vector3(PI, 0, 0), 6))
	var col := SphereShape3D.new()
	col.radius = 4.5
	collider(r, col, Vector3(0, 2.5, -2.5))
	return r

static func tirtha_gate() -> Node3D:
	var r := _root("TirthaGate")
	r.add_child(cyl(3.2, 3.4, 0.4, Color("#8a8a86"), Vector3(0, 0.2, 0), Vector3.ZERO, 16))
	for i in 6:
		var a := i * TAU / 6.0
		r.add_child(box(Vector3(0.7, 3.5, 0.5), Color("#7a7a80"), Vector3(cos(a) * 2.8, 1.9, sin(a) * 2.8), Vector3(0, -a, 0)))
	r.add_child(torus(0.12, 2.0, Color("#7fdbff"), Vector3(0, 2.6, 0), Vector3(PI / 2.0, 0, 0), 0.2, 0.3, Color(0.4, 0.9, 1.0, 1.2)))
	var core := sphere(1.4, Color("#7fdbff"), Vector3(0, 2.6, 0), Vector3.ONE, 0.2, 0.0, Color(0.4, 0.8, 1.0, 0.8), 0.35)
	core.name = "Core"
	r.add_child(core)
	omni(r, Color("#7fdbff"), 1.5, 10.0, Vector3(0, 2.8, 0))
	return r

static func dig_mound() -> Node3D:
	var r := _root("DigMound")
	r.add_child(sphere(0.8, Color("#5a3a1a"), Vector3(0, 0.1, 0), Vector3(1.4, 0.35, 1.4), 0.95))
	r.add_child(box(Vector3(0.1, 0.5, 0.1), Color("#8a6a3a"), Vector3(0.3, 0.3, 0.3), Vector3(0.4, 0, 0.3)))
	return r

static func fishing_marker() -> Node3D:
	var r := _root("FishSpot")
	r.add_child(box(Vector3(0.4, 0.1, 0.4), Color("#8a6a4a"), Vector3(0, 0.05, 0)))
	r.add_child(cyl(0.05, 0.06, 1.2, Color("#5a3d23"), Vector3(0, 0.6, 0)))
	r.add_child(sphere(0.12, Color("#c0392b"), Vector3(0, 1.25, 0)))
	return r

static func bed() -> Node3D:
	var r := _root("Bed")
	r.add_child(box(Vector3(1.6, 0.5, 2.6), Color("#8a6a4a"), Vector3(0, 0.25, 0)))
	r.add_child(box(Vector3(1.5, 0.2, 2.4), Color("#e8e0d0"), Vector3(0, 0.6, 0)))
	r.add_child(box(Vector3(1.2, 0.2, 0.5), Color("#f4f0e8"), Vector3(0, 0.8, -0.9)))
	box_col(r, Vector3(1.6, 0.8, 2.6), Vector3(0, 0.4, 0))
	return r

static func sword_mesh(shape: String, color: Color, s: float = 1.0) -> Node3D:
	## Weapon visual, origin at grip, blade pointing +Y.
	var r := _root("Weapon")
	var steel := color
	match shape:
		"curved":
			r.add_child(box(Vector3(0.08, 0.9 * s, 0.025), steel, Vector3(0.04, 0.55 * s, 0), Vector3(0, 0, -0.12), 0.35, 0.9))
			r.add_child(box(Vector3(0.14, 0.25 * s, 0.025), steel, Vector3(0.1, 0.95 * s, 0), Vector3(0, 0, -0.4), 0.35, 0.9))
			r.add_child(box(Vector3(0.25, 0.04, 0.06), Color("#e3b341"), Vector3(0, 0.08, 0), Vector3.ZERO, 0.3, 0.9))
			r.add_child(cyl(0.025, 0.03, 0.22, Color("#3a2410"), Vector3(0, -0.05, 0)))
		"straight":
			r.add_child(box(Vector3(0.11, 1.25 * s, 0.03), steel, Vector3(0, 0.75 * s, 0), Vector3.ZERO, 0.35, 0.9))
			r.add_child(prism(Vector3(0.11, 0.15, 0.03), steel, Vector3(0, 1.45 * s, 0), Vector3.ZERO, 0.35))
			r.add_child(box(Vector3(0.3, 0.05, 0.06), Color("#e3b341"), Vector3(0, 0.1, 0), Vector3.ZERO, 0.3, 0.9))
			r.add_child(cyl(0.03, 0.035, 0.32, Color("#3a2410"), Vector3(0, -0.08, 0)))
		"mace":
			r.add_child(cyl(0.03, 0.035, 0.9 * s, Color("#5a3d23"), Vector3(0, 0.4 * s, 0)))
			r.add_child(sphere(0.2 * s, steel, Vector3(0, 0.95 * s, 0), Vector3.ONE, 0.4, 0.8))
			for i in 6:
				var a := i * TAU / 6.0
				r.add_child(cone(0.05, 0.12, steel, Vector3(cos(a) * 0.2 * s, 0.95 * s, sin(a) * 0.2 * s), Vector3(PI / 2.0 * sin(a), 0, -PI / 2.0 * cos(a)), 4))
		"axe":
			r.add_child(cyl(0.03, 0.035, 1.0 * s, Color("#5a3d23"), Vector3(0, 0.45 * s, 0)))
			r.add_child(box(Vector3(0.45, 0.4, 0.04), steel, Vector3(0.2, 0.85 * s, 0), Vector3.ZERO, 0.35, 0.9))
			r.add_child(box(Vector3(0.45, 0.4, 0.04), steel, Vector3(-0.2, 0.85 * s, 0), Vector3.ZERO, 0.35, 0.9))
		"trident", "staff":
			r.add_child(cyl(0.025, 0.03, 1.8 * s, Color("#5a3d23"), Vector3(0, 0.8 * s, 0)))
			if shape == "trident":
				for i in 3:
					r.add_child(cone(0.03, 0.35, steel, Vector3(-0.12 + i * 0.12, 1.85 * s, 0), Vector3.ZERO, 5, 0.35))
				r.add_child(box(Vector3(0.3, 0.04, 0.04), steel, Vector3(0, 1.68 * s, 0), Vector3.ZERO, 0.35, 0.9))
			else:
				r.add_child(sphere(0.07, steel, Vector3(0, 1.72 * s, 0)))
		"dagger", "knuckle":
			r.add_child(box(Vector3(0.07, 0.45 * s, 0.02), steel, Vector3(0, 0.3 * s, 0), Vector3.ZERO, 0.35, 0.9))
			r.add_child(box(Vector3(0.18, 0.04, 0.05), Color("#3a2410"), Vector3(0, 0.05, 0)))
		"whip":
			for i in 8:
				r.add_child(box(Vector3(0.05, 0.18, 0.015), steel, Vector3(sin(i * 0.5) * 0.08, 0.1 + i * 0.17, 0), Vector3(0, 0, sin(i * 0.5) * 0.3), 0.35, 0.9))
			r.add_child(cyl(0.025, 0.03, 0.2, Color("#3a2410"), Vector3(0, -0.05, 0)))
		"pick":
			r.add_child(cyl(0.03, 0.035, 0.9 * s, Color("#5a3d23"), Vector3(0, 0.4 * s, 0)))
			r.add_child(box(Vector3(0.7, 0.08, 0.06), steel, Vector3(0, 0.85 * s, 0), Vector3.ZERO, 0.4, 0.8))
			r.add_child(cone(0.04, 0.2, steel, Vector3(0.4, 0.85 * s, 0), Vector3(0, 0, -PI / 2.0), 5))
		"bow", "longbow":
			var h := 1.2 * s if shape == "bow" else 1.7 * s
			for i in 7:
				var t := float(i) / 6.0 - 0.5
				r.add_child(box(Vector3(0.04, h / 6.5, 0.04), Color("#8a6a3a"), Vector3(-(1.0 - abs(t * 2.0)) * 0.22 * s, t * h, 0), Vector3(0, 0, -t * 0.8)))
			r.add_child(box(Vector3(0.01, h, 0.01), Color("#e8e0d0"), Vector3(0.05, 0, 0)))
		"disc":
			r.add_child(torus(0.04, 0.32 * s, steel, Vector3(0, 0.1, 0), Vector3(PI / 2.0, 0, 0), 0.3, 0.9))
		_:
			r.add_child(cyl(0.03, 0.03, 1.4, Color("#a8865a"), Vector3(0, 0.6, 0)))
	return r
