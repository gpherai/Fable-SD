## A flying projectile (arrow, fireball, rock, chakra disc...). It moves straight, dies on
## terrain or after its range, and reports contacts through cfg.on_hit so the combat code
## decides what damage means.
##
## cfg: pos: Vector3, dir: Vector3, speed: float (18), range: float (30), kind: String
## ("arrow", "fire", "rock", "chakra", anything else = glowing bolt), color: Color (optional),
## radius: float (0.5, contact radius), pierce: bool, from_player: bool (targets enemies,
## otherwise the player), gravity: float (0), on_hit: Callable(target, projectile).
extends Node3D

var cfg: Dictionary = {}
var world: Node = null
var dir := Vector3.FORWARD
var speed: float = 18.0
var max_range: float = 30.0
var travelled: float = 0.0
var radius: float = 0.5
var pierce: bool = false
var from_player: bool = false
var gravity: float = 0.0
var kind: String = "bolt"
var on_hit: Callable = Callable()
var _hit_ids: Dictionary = {}
var _vy: float = 0.0
var _spin: Node3D = null

const Props = preload("res://scripts/world/Props.gd")

func setup(cfg_: Dictionary, world_: Node) -> void:
	cfg = cfg_
	world = world_
	kind = str(cfg.get("kind", "bolt"))
	dir = (cfg.get("dir", Vector3.FORWARD) as Vector3).normalized()
	speed = float(cfg.get("speed", 18.0))
	max_range = float(cfg.get("range", 30.0))
	radius = float(cfg.get("radius", 0.5))
	pierce = bool(cfg.get("pierce", false))
	from_player = bool(cfg.get("from_player", false))
	gravity = float(cfg.get("gravity", 0.0))
	if cfg.get("on_hit", null) is Callable:
		on_hit = cfg["on_hit"]
	name = "Projectile_" + kind
	_build_visual()
	global_position = cfg.get("pos", Vector3.ZERO)
	if dir.length() > 0.001:
		look_at(global_position + dir, Vector3.UP)

func _build_visual() -> void:
	var c: Color = cfg.get("color", Color.WHITE)
	match kind:
		"arrow":
			add_child(Props.cyl(0.012, 0.012, 0.9, Color("#8a6a3a"), Vector3.ZERO, Vector3(PI / 2.0, 0, 0), 4))
			add_child(Props.cone(0.03, 0.12, Color("#c0c0c8"), Vector3(0, 0, -0.5), Vector3(-PI / 2.0, 0, 0), 4))
		"fire":
			add_child(Props.sphere(0.2, Color("#ff7a1a"), Vector3.ZERO, Vector3.ONE, 0.5, 0.0, Color(1.0, 0.45, 0.1, 1.0)))
			var l := OmniLight3D.new()
			l.light_color = Color("#ff8a3a")
			l.light_energy = 1.5
			l.omni_range = 5.0
			add_child(l)
		"rock":
			add_child(Props.sphere(0.3, Color("#7a766e"), Vector3.ZERO, Vector3(1, 0.85, 1.1), 0.95))
			_spin = get_child(0)
		"chakra":
			_spin = Node3D.new()
			add_child(_spin)
			_spin.add_child(Props.torus(0.03, 0.3, Color("#c8d0e0"), Vector3.ZERO, Vector3(PI / 2.0, 0, 0), 0.3, 0.9))
		_:
			if c == Color.WHITE:
				c = Color("#ffe9b0")
			add_child(Props.sphere(0.14, c, Vector3.ZERO, Vector3.ONE, 0.4, 0.0, Color(c.r, c.g, c.b, 0.9)))

func _physics_process(delta: float) -> void:
	var step := speed * delta
	_vy -= gravity * delta
	global_position += dir * step + Vector3(0, _vy * delta, 0)
	travelled += step
	if _spin != null:
		_spin.rotation.z += delta * 14.0
	if travelled >= max_range or (world != null and global_position.y <= world.height_at(global_position.x, global_position.z)):
		_die()
		return
	_check_contacts()

func _check_contacts() -> void:
	if world == null:
		return
	var targets: Array = []
	if from_player:
		targets = world.enemies_in_radius(global_position, radius + 0.6)
	elif Game.player != null and is_instance_valid(Game.player):
		var p: Node3D = Game.player
		if p.global_position.distance_to(global_position + Vector3(0, -1.0, 0)) <= radius + 0.6:
			targets = [p]
	for t in targets:
		var id: int = t.get_instance_id()
		if _hit_ids.has(id):
			continue
		_hit_ids[id] = true
		if on_hit.is_valid():
			on_hit.call(t, self)
		if not pierce:
			_die()
			return

func _die() -> void:
	set_physics_process(false)
	queue_free()
