## Combat visual helpers. Orbs (tapas and gold) burst out of a fallen enemy, settle on the
## ground and then fly to the player, who collects them on contact.
extends RefCounted

const Props = preload("res://scripts/world/Props.gd")

const ORB_COLORS := {
	"general": "#ffe9b0",
	"bala": "#ff6a3d",
	"kaushala": "#5be37d",
	"shakti": "#7a8cff",
	"gold": "#ffd24a",
}

## An experience or gold orb. Collecting it awards the amount through Game.
class Orb extends Node3D:
	var kind: String = "general"
	var amount: int = 0
	var world: Node = null
	var vel := Vector3.ZERO
	var age: float = 0.0
	var settled: bool = false

	func setup(kind_: String, amount_: int, world_: Node, pos: Vector3) -> void:
		kind = kind_
		amount = amount_
		world = world_
		var c := Color.html(ORB_COLORS.get(kind, "#ffffff"))
		add_child(Props.sphere(0.11, c, Vector3.ZERO, Vector3.ONE, 0.3, 0.0, Color(c.r, c.g, c.b, 0.9)))
		world.add_child(self)
		global_position = pos + Vector3(0, 0.9, 0)
		vel = Vector3(randf_range(-2.2, 2.2), randf_range(3.0, 5.0), randf_range(-2.2, 2.2))

	func _physics_process(delta: float) -> void:
		age += delta
		var player = Game.player
		if player == null or not is_instance_valid(player):
			return
		var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
		var dist := global_position.distance_to(target)
		if age > 0.7 and (dist < 16.0 or age > 45.0):
			# home in, accelerating the longer the orb has been flying
			var speed := 6.0 + (age - 0.7) * 10.0
			global_position = global_position.move_toward(target, speed * delta)
			if global_position.distance_to(target) < 0.5:
				_collect()
			return
		if not settled:
			vel.y -= 14.0 * delta
			global_position += vel * delta
			var floor_y: float = world.height_at(global_position.x, global_position.z) + 0.35
			if global_position.y <= floor_y:
				global_position.y = floor_y
				vel = Vector3.ZERO
				settled = true
		else:
			position.y += sin(age * 4.0) * 0.003

	func _collect() -> void:
		if kind == "gold":
			Game.add_gold(amount)
			Audio.play("gold", -4.0)
		else:
			Game.add_tapas(kind, amount)
			Audio.play("tapas", -6.0)
		queue_free()

static var _flash_mats: Dictionary = {}

# =====================================================================
# Combat feedback: damage numbers, rings, lightning, hit flash, sparks
# =====================================================================
static func _glow_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## A number that floats up from `pos` and fades.
static func damage_number(world: Node, pos: Vector3, amount: float, color: Color = Color("#fff3d0"), big: bool = false) -> void:
	popup(world, pos, str(maxi(1, int(round(amount)))) if amount >= 0.5 else "0", color, 64 if big else 44)

## Floating text (damage numbers, move names) that drifts up and fades.
static func popup(world: Node, pos: Vector3, text: String, color: Color = Color("#fff3d0"), font_size: int = 44) -> void:
	if world == null or not world.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = 0.01
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.9)
	world.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y + 1.3, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

## A flat ring that expands from nothing to `radius` and fades (area spells, landings, shockwaves).
static func ring(world: Node, pos: Vector3, radius: float, color: Color, duration: float = 0.45) -> void:
	if world == null or not world.is_inside_tree():
		return
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.75))
	var m := TorusMesh.new()
	m.inner_radius = 0.9
	m.outer_radius = 1.0
	m.rings = 32
	m.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.scale = Vector3(0.2, 1.0, 0.2)
	world.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.15, 0)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(mi.queue_free)

## A wedge on the ground in front of `pos` (cone spells and breath attacks).
static func wedge(world: Node, pos: Vector3, dir: Vector3, length: float, half_angle: float, color: Color, duration: float = 0.35) -> void:
	if world == null or not world.is_inside_tree():
		return
	var holder := Node3D.new()
	world.add_child(holder)
	holder.global_position = pos + Vector3(0, 0.5, 0)
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() > 0.001:
		holder.look_at(holder.global_position + flat.normalized(), Vector3.UP)
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.5))
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = length * tan(half_angle)
	cm.height = length
	cm.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.rotation = Vector3(PI / 2.0, 0, 0)
	mi.position = Vector3(0, 0, -length / 2.0)
	mi.scale = Vector3(1, 1, 0.12)
	holder.add_child(mi)
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1, 1, 1), duration * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(holder.queue_free)

## A jagged bolt between two points that fades quickly (lightning, drain beams).
static func bolt(world: Node, from: Vector3, to: Vector3, color: Color, duration: float = 0.25) -> void:
	if world == null or not world.is_inside_tree():
		return
	var mat := _glow_mat(Color(color.r, color.g, color.b, 0.95))
	var root := Node3D.new()
	world.add_child(root)
	root.global_position = Vector3.ZERO
	var segs := 5
	var prev := from
	var axis := (to - from)
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	for i in range(1, segs + 1):
		var p := from.lerp(to, float(i) / float(segs))
		if i < segs:
			p += side * randf_range(-0.35, 0.35) + Vector3.UP * randf_range(-0.35, 0.35)
		var seg_len := prev.distance_to(p)
		if seg_len > 0.01:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.07, 0.07, seg_len)
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = mat
			root.add_child(mi)
			mi.global_position = (prev + p) / 2.0
			var up := Vector3.UP if absf((p - prev).normalized().y) < 0.99 else Vector3.RIGHT
			mi.look_at(p, up)
		prev = p
	var tw := root.create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.tween_callback(root.queue_free)

## Briefly tints every mesh of a model (hit flash, attack telegraph). Cleared again after `duration`.
static func flash(model: Node, color: Color, duration: float = 0.1) -> void:
	if model == null or not model.is_inside_tree():
		return
	var key := color.to_html()
	if not _flash_mats.has(key):
		_flash_mats[key] = _glow_mat(color)
	var ov: Material = _flash_mats[key]
	var meshes: Array = []
	_collect_meshes(model, meshes)
	for mi in meshes:
		mi.material_overlay = ov
	model.get_tree().create_timer(duration).timeout.connect(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and mi.material_overlay == ov:
				mi.material_overlay = null)

static func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)

## A few sparks that fly out and drop (weapon hits, parries, impacts).
static func sparks(world: Node, pos: Vector3, color: Color, count: int = 6) -> void:
	if world == null or not world.is_inside_tree():
		return
	for i in count:
		var s := Props.sphere(0.045, color, Vector3.ZERO, Vector3.ONE, 0.4, 0.0, Color(color.r, color.g, color.b, 1.0))
		world.add_child(s)
		s.global_position = pos
		var end := pos + Vector3(randf_range(-0.9, 0.9), randf_range(0.1, 0.9), randf_range(-0.9, 0.9))
		var tw := s.create_tween()
		tw.set_parallel(true)
		tw.tween_property(s, "global_position", end, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "scale", Vector3.ZERO, 0.3).set_delay(0.1)
		tw.chain().tween_callback(s.queue_free)

## Spawns tapas orbs. amounts: {general, bala, kaushala, shakti}.
static func tapas_orbs(world: Node, pos: Vector3, amounts: Dictionary) -> void:
	for kind in ["general", "bala", "kaushala", "shakti"]:
		var total := int(amounts.get(kind, 0))
		if total > 0:
			_spawn_split(world, pos, kind, total, 10)

static func gold_orb(world: Node, pos: Vector3, amount: int) -> void:
	if amount > 0:
		_spawn_split(world, pos, "gold", amount, 25)

## Splits a total over a few orbs (about one per `chunk`, between 1 and 6) so big rewards look big.
static func _spawn_split(world: Node, pos: Vector3, kind: String, total: int, chunk: int) -> void:
	var n := clampi(int(ceil(float(total) / float(chunk))), 1, 6)
	var left := total
	for i in n:
		var part := int(ceil(float(left) / float(n - i)))
		left -= part
		var orb := Orb.new()
		orb.name = "Orb_" + kind
		orb.setup(kind, part, world, pos)
