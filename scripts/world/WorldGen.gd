## Builds one region: terrain mesh + collision, water, vegetation, buildings and
## returns placement points for interactables, NPCs and enemies.
## Everything is deterministic per region seed so regions look the same on every visit.
extends RefCounted

const Biomes = preload("res://scripts/world/Biomes.gd")
const Props = preload("res://scripts/world/Props.gd")

var region: Dictionary
var biome: Dictionary
var size: float = 160.0
var half: float = 80.0
var res: float = 2.0
var n: int = 81
var heights: PackedFloat32Array
var pathness: PackedFloat32Array
var water_level: float = -100.0
var has_water: bool = false
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()
var root: Node3D
var points: Dictionary = {}
var occupied: Array = []      # [Vector2, radius]
var path_segments: Array = [] # [Vector2, Vector2]
var quality: String = "high"
var interior: bool = false
var lake_center := Vector2.ZERO
var lake_radius := 0.0
var river_x: float = 0.0
var water_kind: String = "none"
var exits_v2: Dictionary = {}
var tree_kind: String = "deciduous"
var logger: Callable

func lg(m: String) -> void:
	if logger.is_valid():
		logger.call(m)

# =====================================================================
func build(region_data: Dictionary, quality_: String = "high") -> Node3D:
	region = region_data
	quality = quality_
	biome = Biomes.get_biome(region.get("biome", "forest"))
	interior = bool(biome.get("interior", false))
	size = float(region.get("size", 160))
	half = size / 2.0
	res = 2.0 if size <= 170 else 2.5
	n = int(size / res) + 1
	rng.seed = int(region.get("seed", 1)) * 7919 + 13
	noise.seed = int(region.get("seed", 1))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	noise2.seed = int(region.get("seed", 1)) + 99
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise2.frequency = 0.05
	root = Node3D.new()
	root.name = "Region_" + str(region.get("id", "x"))
	points = {"exits": {}, "npc": [], "enemy": [], "chest": [], "pickup": [], "key": [], "dig": [], "fish": [], "dummies": [], "targets": [], "house_doors": [], "torches": []}
	tree_kind = biome.get("tree_kind", "deciduous")
	lg("exits")
	_compute_exits()
	lg("paths")
	_compute_paths()
	lg("water")
	_decide_water()
	lg("heights")
	_compute_heights()
	lg("terrain")
	_build_terrain()
	if has_water:
		lg("water mesh")
		_build_water()
	if interior:
		lg("interior")
		_build_interior_shell()
	lg("features")
	_place_features()
	lg("vegetation")
	_place_vegetation()
	lg("points")
	_place_interactable_points()
	lg("boundary")
	_build_boundary()
	lg("built")
	return root

# =====================================================================
# Geometry helpers
# =====================================================================
func idx(i: int, j: int) -> int:
	return j * n + i

func world_x(i: int) -> float:
	return -half + i * res

func world_z(j: int) -> float:
	return -half + j * res

func height_at(x: float, z: float) -> float:
	var fx := (x + half) / res
	var fz := (z + half) / res
	var i := clampi(int(floor(fx)), 0, n - 2)
	var j := clampi(int(floor(fz)), 0, n - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var h00 := heights[idx(i, j)]
	var h10 := heights[idx(i + 1, j)]
	var h01 := heights[idx(i, j + 1)]
	var h11 := heights[idx(i + 1, j + 1)]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func is_water_at(x: float, z: float) -> bool:
	return has_water and height_at(x, z) < water_level

func pathness_at(x: float, z: float) -> float:
	var fx := (x + half) / res
	var fz := (z + half) / res
	var i := clampi(int(round(fx)), 0, n - 1)
	var j := clampi(int(round(fz)), 0, n - 1)
	return pathness[idx(i, j)]

func dist_to_paths(p: Vector2) -> float:
	var d := 1e9
	for seg in path_segments:
		d = minf(d, _seg_dist(p, seg[0], seg[1]))
	return d

func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	if ab.length_squared() > 0.0001:
		t = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)

func slope_at(x: float, z: float) -> float:
	var d := 1.0
	var dx := height_at(x + d, z) - height_at(x - d, z)
	var dz := height_at(x, z + d) - height_at(x, z - d)
	return Vector2(dx, dz).length() / (2.0 * d)

func inside(p: Vector2, margin: float = 6.0) -> bool:
	return absf(p.x) < half - margin and absf(p.y) < half - margin

func is_free(p: Vector2, radius: float) -> bool:
	for o in occupied:
		if p.distance_to(o[0]) < radius + o[1]:
			return false
	return true

func occupy(p: Vector2, radius: float) -> void:
	occupied.append([p, radius])

func free_spot(radius: float, min_path: float = 3.0, tries: int = 60, margin: float = 8.0, min_center: float = 0.0, max_slope: float = 0.6, allow_water: bool = false) -> Variant:
	for t in tries:
		var p := Vector2(rng.randf_range(-half + margin, half - margin), rng.randf_range(-half + margin, half - margin))
		if p.length() < min_center:
			continue
		if not allow_water and is_water_at(p.x, p.y):
			continue
		if dist_to_paths(p) < min_path:
			continue
		if not is_free(p, radius):
			continue
		if slope_at(p.x, p.y) > max_slope:
			continue
		var near_exit := false
		for d in exits_v2.keys():
			if p.distance_to(exits_v2[d]) < 10.0:
				near_exit = true
		if near_exit:
			continue
		return p
	return null

func v3(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.y) + lift, p.y)

# =====================================================================
# Exits & paths
# =====================================================================
func _compute_exits() -> void:
	for ex in region.get("exits", []):
		var pos := float(ex.get("pos", 0.5))
		var t := lerpf(-half + 16.0, half - 16.0, pos)
		var inset := half - 5.0
		var p := Vector2.ZERO
		match ex.get("dir", "N"):
			"N": p = Vector2(t, -inset)
			"S": p = Vector2(t, inset)
			"E": p = Vector2(inset, t)
			"W": p = Vector2(-inset, t)
		exits_v2[ex["dir"]] = p
		points.exits[ex["dir"]] = p
	if exits_v2.is_empty():
		# childhood village and other sealed regions still need a spawn point
		points.exits["spawn"] = Vector2(0, half * 0.6)
		exits_v2["spawn"] = Vector2(0, half * 0.6)

func _compute_paths() -> void:
	var hub := Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
	points["hub"] = hub
	for d in exits_v2.keys():
		var a: Vector2 = exits_v2[d]
		var mid := (a + hub) * 0.5 + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		path_segments.append([a, mid])
		path_segments.append([mid, hub])

# =====================================================================
# Water
# =====================================================================
func _decide_water() -> void:
	water_kind = region.get("water", "none")
	has_water = water_kind not in ["none", "fountain"]
	match water_kind:
		"lake", "pond":
			lake_radius = size * (0.17 if water_kind == "lake" else 0.07)
			var best := Vector2.ZERO
			var best_d := -1.0
			for k in 24:
				var a := k * TAU / 24.0
				var c := Vector2(cos(a), sin(a)) * size * 0.27
				var d := dist_to_paths(c)
				for e in exits_v2.values():
					d = minf(d, c.distance_to(e) - 8.0)
				if d > best_d:
					best_d = d
					best = c
			lake_center = best
			water_level = -0.8
		"river":
			river_x = -size * 0.18 if rng.randf() < 0.5 else size * 0.18
			water_level = -1.0
		"stream":
			river_x = size * 0.3 * (1.0 if rng.randf() < 0.5 else -1.0)
			water_level = -0.35
		"sea_east":
			water_level = -0.6
		"marsh":
			water_level = -0.35

func _water_depth(x: float, z: float) -> float:
	## Returns how much to lower terrain for water bodies (positive = deeper).
	match water_kind:
		"lake", "pond":
			var d := Vector2(x, z).distance_to(lake_center)
			var t := clampf((lake_radius + 5.0 - d) / 8.0, 0.0, 1.0)
			return smoothstep(0.0, 1.0, t) * 3.8
		"river":
			var dx := absf(x - river_x) + sin(z * 0.08) * 2.5
			var t := clampf((7.0 - dx) / 5.0, 0.0, 1.0)
			return smoothstep(0.0, 1.0, t) * 3.2
		"stream":
			var dx := absf(x - river_x + sin(z * 0.1) * 3.0)
			var t := clampf((3.0 - dx) / 2.0, 0.0, 1.0)
			return smoothstep(0.0, 1.0, t) * 1.2
		"sea_east":
			var t := clampf((x - (half - 26.0) + sin(z * 0.06) * 4.0) / 18.0, 0.0, 1.0)
			return smoothstep(0.0, 1.0, t) * 5.0
		"marsh":
			var v := noise2.get_noise_2d(x * 1.3, z * 1.3)
			var t := clampf((v - 0.15) / 0.2, 0.0, 1.0)
			return smoothstep(0.0, 1.0, t) * 1.4
	return 0.0

# =====================================================================
# Heights
# =====================================================================
func _base_height(x: float, z: float) -> float:
	var profile: String = region.get("elevation", "gentle")
	var h := 0.0
	var low := noise.get_noise_2d(x * 0.5, z * 0.5) * 2.0
	match profile:
		"flat":
			h = low * 0.6
		"gentle":
			h = low * 1.6 + noise.get_noise_2d(x, z) * 1.6
		"hill":
			var d := Vector2(x, z).length() / half
			h = (1.0 - smoothstep(0.0, 1.0, d)) * 9.0 + low * 2.0 + noise.get_noise_2d(x, z) * 1.5
		"gorge":
			var dx := absf(x) / half
			h = smoothstep(0.1, 0.6, dx) * 9.0 + low * 1.5
		"cave":
			h = low * 0.8 + noise.get_noise_2d(x * 1.5, z * 1.5) * 0.8
	return h

func _compute_heights() -> void:
	heights.resize(n * n)
	pathness.resize(n * n)
	for j in n:
		for i in n:
			var x := world_x(i)
			var z := world_z(j)
			var p := Vector2(x, z)
			var dpath := dist_to_paths(p)
			var pn := 1.0 - smoothstep(2.2, 4.5, dpath)
			var h := _base_height(x, z)
			var detail := noise.get_noise_2d(x * 2.3, z * 2.3) * 0.6
			h += detail * (1.0 - pn)
			# natural rim (hills) near the border, carved at exits
			if not interior:
				var edge := maxf(absf(x), absf(z)) - (half - 12.0)
				if edge > 0.0:
					var carve := 1.0
					for e in exits_v2.values():
						carve = minf(carve, smoothstep(6.0, 14.0, p.distance_to(e)))
					h += smoothstep(0.0, 12.0, edge) * 7.0 * carve
			h -= _water_depth(x, z)
			# paths are flat-ish: blend toward the low frequency base
			var smooth_h := _base_height(x, z) - _water_depth(x, z)
			h = lerpf(h, smooth_h, pn * 0.8)
			heights[idx(i, j)] = h
			pathness[idx(i, j)] = pn

func _vertex_color(x: float, z: float, h: float, slope: float, pn: float) -> Color:
	var g1: Color = biome.ground
	var g2: Color = biome.ground2
	var c := g1.lerp(g2, clampf(noise2.get_noise_2d(x * 0.6, z * 0.6) * 0.5 + 0.5, 0.0, 1.0))
	if bool(biome.get("snow", false)) and not interior:
		c = c.lerp(Color("#f4f8fc"), clampf(h / 6.0 + 0.4, 0.0, 1.0))
	if slope > 0.55:
		c = c.lerp(biome.rock, clampf((slope - 0.55) / 0.5, 0.0, 1.0))
	if has_water:
		var above := h - water_level
		if above < 1.2:
			var sand: Color = biome.sand if water_kind in ["sea_east", "lake", "pond"] else biome.ground.darkened(0.25)
			c = c.lerp(sand, clampf((1.2 - above) / 1.2, 0.0, 1.0))
	c = c.lerp(biome.path, pn)
	var v := noise2.get_noise_2d(x * 3.0, z * 3.0) * 0.08
	return Color(c.r + v, c.g + v, c.b + v)

func _build_terrain() -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	norms.resize(n * n)
	cols.resize(n * n)
	uvs.resize(n * n)
	for j in n:
		for i in n:
			var x := world_x(i)
			var z := world_z(j)
			var h := heights[idx(i, j)]
			verts[idx(i, j)] = Vector3(x, h, z)
			uvs[idx(i, j)] = Vector2(float(i) / n, float(j) / n)
	for j in n:
		for i in n:
			var il := maxi(i - 1, 0)
			var ir := mini(i + 1, n - 1)
			var jd := maxi(j - 1, 0)
			var ju := mini(j + 1, n - 1)
			var dx := (heights[idx(ir, j)] - heights[idx(il, j)]) / ((ir - il) * res)
			var dz := (heights[idx(i, ju)] - heights[idx(i, jd)]) / ((ju - jd) * res)
			var nrm := Vector3(-dx, 1.0, -dz).normalized()
			norms[idx(i, j)] = nrm
			var slope := Vector2(dx, dz).length()
			cols[idx(i, j)] = _vertex_color(world_x(i), world_z(j), heights[idx(i, j)], slope, pathness[idx(i, j)])
	for j in n - 1:
		for i in n - 1:
			var a := idx(i, j)
			var b := idx(i + 1, j)
			var c := idx(i, j + 1)
			var d := idx(i + 1, j + 1)
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = Props.shader_mat("res://shaders/terrain.gdshader", {"detail_strength": 0.12 if interior else 0.22})
	root.add_child(mi)
	mi.create_trimesh_collision()
	for ch in mi.get_children():
		if ch is StaticBody3D:
			ch.collision_layer = 1
			ch.collision_mask = 0

func _build_water() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(size + 4.0, size + 4.0)
	pm.subdivide_width = 40
	pm.subdivide_depth = 40
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = pm
	mi.material_override = Props.shader_mat("res://shaders/water.gdshader", {"shallow_color": biome.water_shallow, "deep_color": biome.water_deep})
	mi.position.y = water_level
	root.add_child(mi)

func _build_interior_shell() -> void:
	var ceil_h := 7.5
	var ceil := Props.plane(Vector2(size + 4.0, size + 4.0), biome.ceiling, Vector3(0, ceil_h, 0), Vector3(PI, 0, 0), 0.95)
	root.add_child(ceil)
	var wallc: Color = biome.rock
	for k in 4:
		var a := k * PI / 2.0
		var dirn := Vector2(cos(a), sin(a))
		var center := dirn * (half + 1.0)
		var wall := Props.box(Vector3(2.0, ceil_h + 2.0, size + 4.0), wallc, Vector3(center.x, ceil_h / 2.0, center.y), Vector3(0, -a, 0), 0.95)
		root.add_child(wall)
	# stalactites hanging from the ceiling
	for i in 24:
		var p := Vector2(rng.randf_range(-half + 6, half - 6), rng.randf_range(-half + 6, half - 6))
		root.add_child(Props.cone(rng.randf_range(0.3, 0.8), rng.randf_range(1.0, 3.0), wallc.darkened(0.1), Vector3(p.x, ceil_h - 0.5, p.y), Vector3(PI, 0, 0), 6))

func _build_boundary() -> void:
	var h := 20.0
	for k in 4:
		var a := k * PI / 2.0
		var dirn := Vector2(cos(a), sin(a))
		var center := dirn * (half + 0.5)
		Props.box_col(root, Vector3(1.0, h, size + 2.0), Vector3(center.x, h / 2.0 - 5.0, center.y), Vector3(0, -a, 0))

# =====================================================================
# Features
# =====================================================================
func _place_at(node: Node3D, p: Vector2, yaw: float = 0.0, radius: float = 3.0, lift: float = 0.0) -> Node3D:
	node.position = v3(p, lift)
	node.rotation.y = yaw
	root.add_child(node)
	occupy(p, radius)
	return node

func _facing_center(p: Vector2) -> float:
	var hub: Vector2 = points.hub
	var d := hub - p
	return atan2(d.x, d.y)

func _ring_positions(count: int, radius: float, jitter: float = 4.0) -> Array:
	var out := []
	var start := rng.randf() * TAU
	for i in count:
		var a := start + i * TAU / count + rng.randf_range(-0.2, 0.2)
		var p: Vector2 = points.hub + Vector2(cos(a), sin(a)) * (radius + rng.randf_range(-jitter, jitter))
		var tries := 0
		while (is_water_at(p.x, p.y) or height_at(p.x, p.y) - water_level < 1.0 and has_water) and tries < 6:
			tries += 1
			p = points.hub + Vector2(cos(a), sin(a)) * (radius * (1.0 - 0.12 * tries))
		out.append(p)
	return out

func _place_features() -> void:
	var feats: Array = region.get("features", [])
	var center_slots := 0
	for f in feats:
		var parts: String = f
		var fname := parts
		var count := 1
		if ":" in parts:
			fname = parts.split(":")[0]
			count = int(parts.split(":")[1])
		match fname:
			"houses":
				for p in _ring_positions(count, size * 0.22, 5.0):
					var hse := Props.house(rng)
					_place_at(hse, p, _facing_center(p), 5.0)
					points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 4.5)
			"huts":
				for p in _ring_positions(count, size * 0.2, 5.0):
					_place_at(Props.hut(rng), p, _facing_center(p), 3.5)
					points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 4.0)
			"stone_houses":
				for p in _ring_positions(count, size * 0.22, 5.0):
					_place_at(Props.stone_house(rng), p, _facing_center(p), 5.0)
					points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 4.5)
			"mansions":
				for p in _ring_positions(count, size * 0.26, 4.0):
					_place_at(Props.mansion(rng), p, _facing_center(p), 8.0)
					points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 7.0)
			"tents":
				for p in _ring_positions(count, size * 0.18, 6.0):
					_place_at(Props.tent(rng), p, _facing_center(p) + rng.randf_range(-0.5, 0.5), 3.0)
					points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 3.0)
			"mausoleums":
				for p in _ring_positions(count, size * 0.24, 6.0):
					_place_at(Props.mausoleum(), p, _facing_center(p), 5.0)
			"cells":
				for i in count:
					var p: Vector2 = points.hub + Vector2(-half * 0.6 + i * 5.0 if i < count / 2 else -half * 0.6 + (i - count / 2) * 5.0, -18.0 if i < count / 2 else 18.0)
					_place_at(Props.cell(), p, PI if i < count / 2 else 0.0, 3.0)
			"banyan":
				_place_center(Props.tree("banyan", rng, 1.2), 8.0)
			"well", "fountain":
				_place_center(Props.well() if fname == "well" else Props.fountain(), 3.0)
			"market":
				for i in 4:
					var p: Vector2 = points.hub + Vector2(cos(i * TAU / 4.0 + 0.4), sin(i * TAU / 4.0 + 0.4)) * 10.0
					var stall := Node3D.new()
					var scols: Array[Color] = [Color("#c0392b"), Color("#e3b341"), Color("#2e86de"), Color("#27ae60")]
					stall.add_child(Props.box(Vector3(3.0, 0.9, 1.4), Color("#7a5a3a"), Vector3(0, 0.45, 0)))
					stall.add_child(Props.prism(Vector3(3.4, 0.8, 2.2), scols[i], Vector3(0, 2.4, 0)))
					stall.add_child(Props.cyl(0.06, 0.06, 2.4, Color("#5a3d23"), Vector3(-1.4, 1.2, 0.8)))
					stall.add_child(Props.cyl(0.06, 0.06, 2.4, Color("#5a3d23"), Vector3(1.4, 1.2, 0.8)))
					Props.box_col(stall, Vector3(3.0, 1.0, 1.4), Vector3(0, 0.5, 0))
					_place_at(stall, p, _facing_center(p) + PI, 2.5)
					points.npc.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * -2.5)
			"temple":
				var t := Props.temple("sun")
				_place_center(t, 8.0, true)
				points["shrine"] = points.get("center_last", points.hub) + Vector2(0, 8.0)
			"temple_dark":
				_place_center(Props.temple("dark"), 8.0, true)
				points["shrine"] = points.get("center_last", points.hub) + Vector2(0, 8.0)
			"temple_ruin":
				_place_center(Props.temple("ruin"), 8.0, true)
			"temple_small":
				_place_center(Props.temple("small"), 4.0, true)
			"shrine_small":
				var p = free_spot(2.0, 4.0, 40, 12.0)
				if p != null:
					_place_at(Props.shrine_small(), p, rng.randf() * TAU, 2.0)
			"akhara_hall":
				_place_center(Props.akhara_hall(), 15.0, true)
				points["bed"] = points.hub + Vector2(10.0, -4.0)
			"haveli":
				_place_center(Props.haveli(false), 9.0, true)
			"haveli_ruin":
				_place_center(Props.haveli(true), 9.0, true)
			"big_tent":
				_place_center(Props.big_tent(), 9.0, true)
			"throne":
				_place_center(Props.throne(), 2.5)
			"altar":
				_place_center(Props.altar(region.get("shrine", "") == "asura" or fname == "altar" and region.get("biome") == "chamber"), 2.5)
				points["shrine"] = points.get("center_last", points.hub) + Vector2(0, 2.5)
			"campfire":
				_place_center(Props.campfire(), 2.5)
				points.torches.append(points.get("center_last", points.hub))
			"dhuni":
				_place_center(Props.dhuni(), 2.5)
			"stupa":
				_place_center(Props.stupa(), 3.5, true)
			"statue":
				_place_center(Props.statue(), 2.0, true)
			"statue_asura":
				_place_center(Props.statue(Color("#2a1a2a")), 2.0, true)
			"totem":
				_place_center(Props.totem(), 1.5, true)
			"bell":
				_place_center(Props.bell(), 1.5, true)
			"yantra_floor":
				var y := Props.yantra_floor()
				y.position = v3(points.hub, 0.05)
				root.add_child(y)
			"oracle_cave":
				_place_center(Props.oracle_cave(), 8.0, true)
				points["oracle"] = points.get("center_last", points.hub) + Vector2(0, 4.0)
			"arena_ring":
				var ar := Props.arena_ring(22.0)
				ar.position = v3(points.hub)
				root.add_child(ar)
				points["arena_center"] = points.hub
				occupy(points.hub, 3.0)
			"gate_arch":
				for d in exits_v2.keys():
					var p: Vector2 = exits_v2[d]
					var yaw := 0.0
					match d:
						"N", "S": yaw = 0.0
						"E", "W": yaw = PI / 2.0
					var g := Props.gate_arch()
					g.position = v3(p + (points.hub - p).normalized() * 4.0)
					g.rotation.y = yaw
					root.add_child(g)
			"signpost":
				var p: Vector2 = points.hub + Vector2(5.0, 5.0)
				_place_at(Props.signpost(), p, rng.randf() * TAU, 1.0)
				points["sign"] = p
			"watchtower":
				var best: Vector2 = points.hub
				var bh := -1e9
				for k in 40:
					var p := Vector2(rng.randf_range(-half * 0.6, half * 0.6), rng.randf_range(-half * 0.6, half * 0.6))
					var h := height_at(p.x, p.y)
					if h > bh and dist_to_paths(p) > 5.0 and not is_water_at(p.x, p.y):
						bh = h
						best = p
				_place_at(Props.watchtower(), best, 0.0, 4.0)
			"lighthouse":
				var p := _water_edge_point(Vector2(half * 0.7, -half * 0.5))
				_place_at(Props.lighthouse(), p, 0.0, 4.0)
			"jetty":
				var p := _water_edge_point(Vector2.ZERO)
				if p != Vector2.ZERO:
					var j := Props.jetty(10.0)
					var dir := _water_dir(p)
					j.position = v3(p, 0.0)
					j.position.y = water_level + 0.2
					j.rotation.y = atan2(dir.x, dir.y)
					root.add_child(j)
					occupy(p, 3.0)
					points.fish.append(p + dir * 9.0)
					points["boat"] = p + dir * 11.0
			"boat":
				var p := _water_edge_point(Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20)))
				if p != Vector2.ZERO:
					var b := Props.boat()
					var dir := _water_dir(p)
					b.position = v3(p + dir * 3.5)
					b.position.y = water_level + 0.3
					b.rotation.y = rng.randf() * TAU
					root.add_child(b)
					if not points.has("boat"):
						points["boat"] = p + dir * 3.0
			"ghat":
				var p := _water_edge_point(Vector2.ZERO)
				if p != Vector2.ZERO:
					var g := Props.ghat_steps(16.0)
					var dir := _water_dir(p)
					g.position = v3(p - dir * 2.0)
					g.rotation.y = atan2(dir.x, dir.y)
					root.add_child(g)
					occupy(p, 6.0)
					points.fish.append(p + dir * 6.0)
			"bridge":
				if water_kind == "river":
					for seg in path_segments:
						var a: Vector2 = seg[0]
						var b: Vector2 = seg[1]
						if (a.x - river_x) * (b.x - river_x) < 0.0:
							var t := (river_x - a.x) / (b.x - a.x)
							var cross := a.lerp(b, t)
							var br := Props.bridge(18.0, 4.5)
							br.position = Vector3(cross.x, water_level + 1.6, cross.y)
							br.rotation.y = PI / 2.0 + atan2(b.y - a.y, b.x - a.x) * 0.0
							root.add_child(br)
			"weir":
				if water_kind == "river":
					var w := Props.weir(16.0)
					w.position = Vector3(river_x, water_level + 0.5, half * 0.3)
					w.rotation.y = PI / 2.0
					root.add_child(w)
			"pillars":
				for p in _ring_positions(count, size * 0.13, 1.0):
					if not is_water_at(p.x, p.y):
						_place_at(Props.pillar(5.0, Color("#d8c8a8") if not interior else biome.rock.lightened(0.2)), p, 0.0, 1.0)
			"torches":
				for p in _ring_positions(count, size * 0.16, 2.0):
					if not is_water_at(p.x, p.y):
						_place_at(Props.torch(), p, 0.0, 0.6)
						points.torches.append(p)
			"graves", "sarcophagi", "bones", "stalagmites", "crystals", "fallen_logs", "rose_bushes", "loot_piles", "picnic_cloths", "frozen_people", "pyres", "stones", "wisps", "naga_statues":
				for i in count:
					var p = free_spot(2.0, 2.5, 40, 8.0, 4.0)
					if p == null:
						continue
					var node: Node3D
					match fname:
						"graves": node = Props.grave(rng)
						"sarcophagi": node = Props.sarcophagus()
						"bones": node = Props.bones(rng)
						"stalagmites": node = Props.stalagmite(rng, biome.rock)
						"crystals": node = Props.crystal(rng, Color("#a06ae8") if region.get("biome") != "ice_cave" else Color("#8ad8ff"))
						"fallen_logs": node = Props.fallen_log()
						"rose_bushes": node = Props.rose_bush(rng)
						"loot_piles": node = Props.loot_pile(rng)
						"picnic_cloths": node = Props.picnic_cloth(rng)
						"frozen_people": node = Props.frozen_person(rng)
						"pyres": node = Props.pyre()
						"stones": node = Props.stone(rng, biome.rock)
						"wisps": node = Props.wisp(Color("#8ae8ff") if region.get("biome") != "witchwood" else Color("#d08aff"))
						"naga_statues": node = Props.naga_statue()
					_place_at(node, p, rng.randf() * TAU, 1.5)
					if fname == "pyres":
						points.torches.append(p)
			"dead_trees", "pines", "palms", "purple_trees", "mango_trees":
				var kinds: Dictionary = {"dead_trees": "dead", "pines": "pine", "palms": "palm", "purple_trees": "purple", "mango_trees": "mango"}
				var kind: String = kinds[fname]
				for i in count:
					var p = free_spot(2.5, 4.0, 40, 8.0, 6.0)
					if p == null:
						continue
					_place_at(Props.tree(kind, rng, rng.randf_range(0.8, 1.3)), p, rng.randf() * TAU, 2.0)
			"wasp_nest":
				var p = free_spot(3.0, 6.0, 60, 14.0, 10.0)
				if p != null:
					_place_at(Props.wasp_nest(), p, 0.0, 3.0)
					points["boss"] = p
			"stones_circle":
				var sc := Props.stones_circle(rng, 9.0, biome.rock if region.get("biome") != "witchwood" else Color("#4a3a6a"))
				sc.position = v3(points.hub)
				root.add_child(sc)
				occupy(points.hub, 2.0)
			"fence", "palisade":
				var r := size * 0.32
				var segs := int(TAU * r / 4.0)
				for i in segs:
					var a := i * TAU / segs
					var p: Vector2 = points.hub + Vector2(cos(a), sin(a)) * r
					if not inside(p, 4.0) or is_water_at(p.x, p.y) or dist_to_paths(p) < 3.5:
						continue
					var seg := Props.palisade_segment(4.2) if fname == "palisade" else Props.fence_segment(4.2)
					seg.position = v3(p)
					seg.rotation.y = -a + PI / 2.0
					root.add_child(seg)
			"farm_rows":
				var fr := Props.farm_rows(rng)
				var p: Vector2 = points.hub + Vector2(-14.0, 12.0)
				fr.position = v3(p)
				root.add_child(fr)
				occupy(p, 10.0)
			"farmhouse":
				var p: Vector2 = points.hub + Vector2(12.0, -12.0)
				_place_at(Props.farmhouse(), p, _facing_center(p), 7.0)
				points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 5.0)
				points["bed"] = p
			"cottage":
				var p: Vector2 = points.hub + Vector2(8.0, -8.0)
				_place_at(Props.cottage(), p, _facing_center(p), 5.0)
				points.house_doors.append(p + Vector2(sin(_facing_center(p)), cos(_facing_center(p))) * 4.0)
				points["bed"] = p
			"waterwheel":
				var p := _water_edge_point(Vector2.ZERO)
				if p != Vector2.ZERO:
					_place_at(Props.waterwheel(), p, atan2(_water_dir(p).x, _water_dir(p).y), 3.0)
					points.key.append(p - _water_dir(p) * 3.0)
			"training_dummies":
				for i in count:
					var p: Vector2 = points.hub + Vector2(-20.0 + i * 5.0, 22.0)
					_place_at(Props.training_dummy(), p, 0.0, 1.0)
					points.dummies.append(p)
			"archery_targets":
				for i in count:
					var p: Vector2 = points.hub + Vector2(22.0, -16.0 + i * 6.0)
					_place_at(Props.archery_target(), p, -PI / 2.0, 1.0)
					points.targets.append(p)
			"gallows":
				var p = free_spot(4.0, 5.0, 40, 12.0, 8.0)
				if p != null:
					_place_at(Props.gallows(), p, rng.randf() * TAU, 3.0)
			"cage":
				var p: Vector2 = points.hub + Vector2(6.0, -6.0)
				_place_at(Props.cage(), p, 0.0, 1.5)
				points["cage"] = p
			"lotus":
				if has_water:
					var lp := Props.lotus(rng)
					var c := lake_center if water_kind in ["lake", "pond"] else Vector2(river_x, 0)
					lp.position = Vector3(c.x, water_level + 0.02, c.y)
					root.add_child(lp)
			"reeds":
				for i in count:
					var p := _water_edge_point(Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
					if p != Vector2.ZERO and is_free(p, 1.0):
						_place_at(Props.reeds(rng), p, 0.0, 0.5)
			"grave_bhadra":
				var p: Vector2 = points.hub + Vector2(-18.0, -14.0)
				var g := Props.grave(rng)
				_place_at(g, p, 0.0, 2.0)
				var lbl := Label3D.new()
				lbl.text = "Bhadra"
				lbl.font_size = 48
				lbl.pixel_size = 0.01
				lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.position = Vector3(0, 2.0, 0)
				g.add_child(lbl)
			"beach_edge", "wisps_none":
				pass
			_:
				pass

func _place_center(node: Node3D, radius: float, big: bool = false) -> void:
	var hub: Vector2 = points.hub
	var p := hub
	if not is_free(hub, radius):
		for k in 8:
			var a := k * TAU / 8.0
			var cand := hub + Vector2(cos(a), sin(a)) * (radius + 10.0)
			if is_free(cand, radius) and not is_water_at(cand.x, cand.y):
				p = cand
				break
	node.position = v3(p)
	if big:
		# flatten terrain under large structures by sinking them slightly into the ground
		node.position.y = height_at(p.x, p.y) - 0.3
	node.rotation.y = 0.0
	root.add_child(node)
	occupy(p, radius)
	points["center_last"] = p
	if not points.has("center"):
		points["center"] = p

func _water_edge_point(prefer: Vector2) -> Vector2:
	if not has_water:
		return Vector2.ZERO
	var best := Vector2.ZERO
	var best_d := 1e9
	for k in 300:
		var p := Vector2(rng.randf_range(-half + 8, half - 8), rng.randf_range(-half + 8, half - 8))
		if is_water_at(p.x, p.y):
			continue
		var h := height_at(p.x, p.y) - water_level
		if h > 1.2 or h < 0.1:
			continue
		var dir := _water_dir(p)
		if dir == Vector2.ZERO:
			continue
		var d := p.distance_to(prefer)
		if d < best_d and is_free(p, 3.0):
			best_d = d
			best = p
	return best

func _water_dir(p: Vector2) -> Vector2:
	## Direction from a shore point toward the water.
	for k in 8:
		var a := k * TAU / 8.0
		var d := Vector2(cos(a), sin(a))
		if is_water_at(p.x + d.x * 3.0, p.y + d.y * 3.0):
			return d
	return Vector2.ZERO

# =====================================================================
# Vegetation (multimesh) and rocks
# =====================================================================
func _place_vegetation() -> void:
	var area_factor := (size / 160.0) * (size / 160.0)
	var tree_density := float(biome.get("tree_density", 0.3))
	var qmul := 1.0 if quality == "high" else 0.6
	if tree_kind != "none" and tree_density > 0.0:
		var count := int(tree_density * 220.0 * area_factor)
		var placed := []
		for i in count:
			var p = free_spot(2.2, 4.5, 20, 6.0, 3.0, 0.9)
			if p == null:
				continue
			occupy(p, 1.6)
			placed.append(p)
		_build_tree_multimesh(placed)
	var rock_density := float(biome.get("rock_density", 0.3))
	var rcount := int(rock_density * 36.0 * area_factor)
	for i in rcount:
		var p = free_spot(1.5, 3.0, 20, 6.0, 4.0, 1.5)
		if p == null:
			continue
		_place_at(Props.rock(rng, biome.rock, rng.randf_range(0.6, 1.6)), p, rng.randf() * TAU, 1.2)
	var gd := float(biome.get("grass_density", 0.5)) * qmul
	if gd > 0.0 and not interior:
		_build_grass(int(gd * 2600.0 * area_factor))

func _build_tree_multimesh(placed: Array) -> void:
	if placed.is_empty():
		return
	var trunk_mesh: Mesh
	var canopy_mesh: Mesh
	var trunk_col: Color = Color("#5a3d23")
	var canopy_col: Color = Color("#3a7a2a")
	var canopy_off := 3.6
	var trunk_h := 2.6
	var light := false
	match tree_kind:
		"pine":
			var c := CylinderMesh.new(); c.top_radius = 0.15; c.bottom_radius = 0.3; c.height = 2.5; c.radial_segments = 7
			trunk_mesh = c
			var cone := CylinderMesh.new(); cone.top_radius = 0.0; cone.bottom_radius = 2.0; cone.height = 5.5; cone.radial_segments = 8
			canopy_mesh = cone
			canopy_col = Color("#2f5f3a")
			canopy_off = 4.5
			trunk_h = 2.5
		"palm":
			var c := CylinderMesh.new(); c.top_radius = 0.16; c.bottom_radius = 0.26; c.height = 6.0; c.radial_segments = 7
			trunk_mesh = c
			var s := SphereMesh.new(); s.radius = 1.9; s.height = 1.4; s.radial_segments = 8; s.rings = 4
			canopy_mesh = s
			trunk_col = Color("#8a6a3a")
			canopy_col = Color("#4f9f3a")
			canopy_off = 6.0
			trunk_h = 6.0
		"dead":
			var c := CylinderMesh.new(); c.top_radius = 0.12; c.bottom_radius = 0.4; c.height = 4.5; c.radial_segments = 6
			trunk_mesh = c
			var s := SphereMesh.new(); s.radius = 0.9; s.height = 1.2; s.radial_segments = 6; s.rings = 3
			canopy_mesh = s
			trunk_col = Color("#2a2420")
			canopy_col = Color("#3a3a30")
			canopy_off = 4.4
			trunk_h = 4.5
		"purple":
			var c := CylinderMesh.new(); c.top_radius = 0.2; c.bottom_radius = 0.35; c.height = 3.0; c.radial_segments = 7
			trunk_mesh = c
			var s := SphereMesh.new(); s.radius = 1.9; s.height = 3.0; s.radial_segments = 8; s.rings = 4
			canopy_mesh = s
			trunk_col = Color("#3a2a3a")
			canopy_col = Color("#7a3aa0")
			canopy_off = 4.0
			trunk_h = 3.0
			light = true
		"mango":
			var c := CylinderMesh.new(); c.top_radius = 0.25; c.bottom_radius = 0.4; c.height = 2.2; c.radial_segments = 7
			trunk_mesh = c
			var s := SphereMesh.new(); s.radius = 2.4; s.height = 3.6; s.radial_segments = 8; s.rings = 4
			canopy_mesh = s
			canopy_col = Color("#2f7a2a")
			canopy_off = 3.4
			trunk_h = 2.2
		_:
			var c := CylinderMesh.new(); c.top_radius = 0.2; c.bottom_radius = 0.32; c.height = 2.6; c.radial_segments = 7
			trunk_mesh = c
			var s := SphereMesh.new(); s.radius = 2.0; s.height = 3.6; s.radial_segments = 8; s.rings = 4
			canopy_mesh = s
			canopy_col = Color("#3a7a2a")
			canopy_off = 3.8
			trunk_h = 2.6
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color.WHITE
	tm.vertex_color_use_as_albedo = true
	tm.roughness = 0.9
	trunk_mesh.material = tm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color.WHITE
	cm.vertex_color_use_as_albedo = true
	cm.roughness = 0.85
	canopy_mesh.material = cm
	var mm_t := MultiMesh.new()
	mm_t.transform_format = MultiMesh.TRANSFORM_3D
	mm_t.use_colors = true
	mm_t.mesh = trunk_mesh
	mm_t.instance_count = placed.size()
	var mm_c := MultiMesh.new()
	mm_c.transform_format = MultiMesh.TRANSFORM_3D
	mm_c.use_colors = true
	mm_c.mesh = canopy_mesh
	mm_c.instance_count = placed.size()
	var colroot := Node3D.new()
	colroot.name = "TreeColliders"
	root.add_child(colroot)
	for i in placed.size():
		var p: Vector2 = placed[i]
		var s := rng.randf_range(0.8, 1.35)
		var y := height_at(p.x, p.y)
		var yaw := rng.randf() * TAU
		var tb := Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s, s, s))
		mm_t.set_instance_transform(i, Transform3D(tb, Vector3(p.x, y + trunk_h * s * 0.5, p.y)))
		mm_t.set_instance_color(i, trunk_col.lerp(trunk_col.darkened(0.25), rng.randf()))
		var cb := Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(s * rng.randf_range(0.9, 1.15), s * rng.randf_range(0.85, 1.1), s * rng.randf_range(0.9, 1.15)))
		mm_c.set_instance_transform(i, Transform3D(cb, Vector3(p.x, y + canopy_off * s, p.y)))
		mm_c.set_instance_color(i, canopy_col.lerp(canopy_col.lightened(0.25), rng.randf()))
		var shape := CylinderShape3D.new()
		shape.radius = 0.35 * s
		shape.height = trunk_h * s
		Props.collider(colroot, shape, Vector3(p.x, y + trunk_h * s * 0.5, p.y))
		if light and i % 4 == 0:
			Props.omni(root, Color("#b06ae8"), 0.5, 6.0, Vector3(p.x, y + 3.5, p.y))
	var mi_t := MultiMeshInstance3D.new()
	mi_t.name = "Trunks"
	mi_t.multimesh = mm_t
	root.add_child(mi_t)
	var mi_c := MultiMeshInstance3D.new()
	mi_c.name = "Canopies"
	mi_c.multimesh = mm_c
	root.add_child(mi_c)

func _blade_mesh() -> ArrayMesh:
	## Three crossed tapered blades; UV.y = 0 at the tip, 1 at the root (used by the shader).
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx_arr := PackedInt32Array()
	var h := 1.0
	for k in 3:
		var a := k * PI / 3.0
		var dir := Vector3(cos(a), 0, sin(a))
		var base := verts.size()
		verts.append(dir * -0.1)
		verts.append(dir * 0.1)
		verts.append(dir * -0.045 + Vector3(0, h * 0.55, 0))
		verts.append(dir * 0.045 + Vector3(0, h * 0.55, 0))
		verts.append(Vector3(0, h, 0) + dir * 0.0)
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(0, 0.45), Vector2(1, 0.45), Vector2(0.5, 0)])
		for i in 5:
			norms.append(Vector3.UP)
		idx_arr.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2, base + 2, base + 3, base + 4])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx_arr
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

func _build_grass(count: int) -> void:
	if count <= 0:
		return
	var quad := _blade_mesh()
	var gmat := Props.shader_mat("res://shaders/grass.gdshader", {"base_color": biome.get("grass_base", Color("#2d6a1e")), "tip_color": biome.get("grass_tip", Color("#8fc14a"))})
	quad.surface_set_material(0, gmat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = count
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 3:
		tries += 1
		var p := Vector2(rng.randf_range(-half + 6, half - 6), rng.randf_range(-half + 6, half - 6))
		if is_water_at(p.x, p.y) or pathness_at(p.x, p.y) > 0.25 or slope_at(p.x, p.y) > 0.8:
			continue
		var y := height_at(p.x, p.y)
		var s := rng.randf_range(0.7, 1.4)
		var b := Basis.from_euler(Vector3(0, rng.randf() * TAU, 0)).scaled(Vector3(s, s, s))
		mm.set_instance_transform(placed, Transform3D(b, Vector3(p.x, y - 0.05, p.y)))
		mm.set_instance_color(placed, Color(1, 1, 1).lerp(Color(0.8, 0.9, 0.7), rng.randf()))
		placed += 1
	mm.instance_count = placed
	var mi := MultiMeshInstance3D.new()
	mi.name = "Grass"
	mi.multimesh = mm
	root.add_child(mi)

# =====================================================================
# Interactable / NPC / enemy points
# =====================================================================
func _place_interactable_points() -> void:
	# Tirtha gate
	if bool(region.get("tirtha", false)):
		var p = free_spot(4.0, 5.0, 80, 12.0, 12.0, 0.5)
		if p == null:
			p = points.hub + Vector2(16.0, 16.0)
		points["tirtha"] = p
		occupy(p, 4.0)
	# Yaksha door: on an edge without an exit
	if region.has("yaksha"):
		var dirs := ["N", "E", "S", "W"]
		var best := ""
		for d in dirs:
			if not exits_v2.has(d):
				best = d
				break
		if best == "":
			best = "N"
		var inset := half - 10.0
		var p := Vector2.ZERO
		var yaw := 0.0
		match best:
			"N": p = Vector2(rng.randf_range(-half * 0.4, half * 0.4), -inset); yaw = 0.0
			"S": p = Vector2(rng.randf_range(-half * 0.4, half * 0.4), inset); yaw = PI
			"E": p = Vector2(inset, rng.randf_range(-half * 0.4, half * 0.4)); yaw = -PI / 2.0
			"W": p = Vector2(-inset, rng.randf_range(-half * 0.4, half * 0.4)); yaw = PI / 2.0
		points["yaksha"] = p
		points["yaksha_yaw"] = yaw
		occupy(p, 6.0)
	# Chests
	for c in region.get("chests", []):
		var p = free_spot(1.5, 5.0, 80, 10.0, 6.0)
		if p == null:
			p = points.hub + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		points.chest.append(p)
		occupy(p, 1.5)
	# Silver keys: hidden far from paths
	for k in int(region.get("silver_keys", 0)):
		var p = free_spot(1.0, 10.0, 120, 9.0, 10.0, 1.0)
		if p == null:
			p = free_spot(1.0, 4.0, 60, 9.0, 4.0, 1.0)
		if p != null:
			points.key.append(p)
			occupy(p, 1.0)
	# Pickups near paths
	for pk in region.get("pickups", []):
		for i in int(pk.get("count", 1)):
			var p = null
			for t in 60:
				var cand := Vector2(rng.randf_range(-half + 8, half - 8), rng.randf_range(-half + 8, half - 8))
				var dp := dist_to_paths(cand)
				if dp > 2.0 and dp < 9.0 and not is_water_at(cand.x, cand.y) and is_free(cand, 1.0):
					p = cand
					break
			if p == null:
				p = free_spot(1.0, 2.0, 40, 8.0)
			if p != null:
				points.pickup.append(p)
				occupy(p, 0.8)
	# Dig spots
	for d in region.get("dig_spots", []):
		var p = free_spot(1.0, 6.0, 80, 10.0, 8.0, 0.8)
		if p != null:
			points.dig.append(p)
			occupy(p, 1.0)
	# Fishing spots
	if bool(region.get("fishing", false)) and has_water and points.fish.is_empty():
		for i in 3:
			var p := _water_edge_point(Vector2(rng.randf_range(-half, half), rng.randf_range(-half, half)))
			if p != Vector2.ZERO:
				points.fish.append(p + _water_dir(p) * 1.0)
				occupy(p, 1.0)
	# NPC points: house doors first, then a loose ring around the hub
	var npc_count: int = region.get("npcs", []).size()
	var ring := _ring_positions(maxi(npc_count, 1), 11.0, 3.0)
	var idx_r := 0
	while points.npc.size() < npc_count + 2:
		if points.house_doors.size() > points.npc.size():
			points.npc.append(points.house_doors[points.npc.size()])
		elif idx_r < ring.size():
			var p: Vector2 = ring[idx_r]
			idx_r += 1
			if is_water_at(p.x, p.y):
				continue
			points.npc.append(p)
		else:
			var p2 = free_spot(1.0, 1.0, 40, 10.0)
			points.npc.append(p2 if p2 != null else points.hub)
	# Enemy points
	var total_enemies := 0
	for sp in region.get("spawns", []):
		total_enemies += int(sp.get("count", 1))
	var min_center := 14.0 if int(region.get("danger", 0)) >= 3 else 20.0
	for i in maxi(total_enemies + 6, 10):
		var p = free_spot(1.5, 0.0, 60, 12.0, min_center, 0.9)
		if p == null:
			p = free_spot(1.5, 0.0, 60, 10.0, 6.0, 1.5)
		if p != null:
			points.enemy.append(p)
	if points.has("boss"):
		points.enemy.insert(0, points.boss)
	if points.has("arena_center"):
		points["arena_spawn"] = []
		for i in 8:
			var a := i * TAU / 8.0
			points.arena_spawn.append(points.hub + Vector2(cos(a), sin(a)) * 14.0)
	# Sleeping spot for owned house
	if region.has("house") and not points.has("bed"):
		points["bed"] = points.house_doors[0] if points.house_doors.size() > 0 else points.hub

func exit_position(dir: String) -> Vector3:
	if points.exits.has(dir):
		var p: Vector2 = points.exits[dir]
		# step a little inward so the player does not retrigger the exit
		var hub: Vector2 = points.hub
		var inward: Vector2 = (hub - p).normalized() * 6.0
		return v3(p + inward, 0.2)
	if points.exits.has("spawn"):
		return v3(points.exits["spawn"], 0.2)
	return v3(points.hub, 0.2)
