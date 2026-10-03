## An enemy built from data/enemies.json. This is the body: model, collision, health and
## death. Behaviour (patrol, aggro, attacks) is added on top in the combat step; the hook for
## that is `_think(delta)`.
extends CharacterBody3D

const Body = preload("res://scripts/entities/Body.gd")

var enemy_id: String = ""
var data: Dictionary = {}
var is_ally: bool = false
var is_boss: bool = false
var drop_item: String = ""
var on_death_flags: Array = []
var spawn_index: int = -1
var respawn: bool = true
var arena: bool = false
var dead: bool = false
var hp: float = 1.0
var hp_max: float = 1.0
var home_pos := Vector3.ZERO
var model: Node3D
var label: Label3D
var name_override: String = ""
var hover: float = 0.0
var flying: bool = false
var stationary: bool = false
var nonlethal: bool = false
var _t: float = 0.0
var _ready_pos: bool = false

func setup(eid: String, opts: Dictionary = {}) -> void:
	enemy_id = eid
	data = Data.enemy(eid)
	is_ally = bool(data.get("ally", false))
	is_boss = bool(opts.get("boss", data.get("boss", false)))
	drop_item = str(opts.get("drop", ""))
	on_death_flags = opts.get("on_death_flags", [])
	spawn_index = int(opts.get("spawn_index", -1))
	respawn = bool(opts.get("respawn", true))
	arena = bool(opts.get("arena", false))
	name_override = str(opts.get("name_override", ""))
	flying = bool(data.get("flying", false))
	hover = float(data.get("hover", 0.0))
	stationary = bool(data.get("stationary", false))
	nonlethal = bool(data.get("nonlethal", false))
	hp_max = float(data.get("hp", 30.0))
	hp = hp_max
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	var size: float = float(data.get("size", 1.0))
	var shape := CapsuleShape3D.new()
	shape.radius = clampf(0.35 * size, 0.25, 1.6)
	shape.height = maxf(1.8 * size, shape.radius * 2.0 + 0.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, shape.height / 2.0 + hover, 0)
	add_child(cs)
	model = Body.enemy(data.get("body", {}))
	model.position.y = hover
	add_child(model)
	if is_boss or name_override != "":
		label = Label3D.new()
		label.text = display_name()
		label.font_size = 40
		label.pixel_size = 0.009
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color("#ff9a6a") if not is_ally else Color("#9affb0")
		label.outline_size = 10
		label.position = Vector3(0, shape.height + hover + 0.5, 0)
		add_child(label)

func display_name() -> String:
	if name_override != "" and Data.characters.has(name_override):
		return Loc.t(Data.character(name_override).get("name", {}))
	return Loc.t(data.get("name", {}))

func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _ready_pos:
		# World sets the spawn position right after add_child; remember it once.
		_ready_pos = true
		home_pos = global_position
	_t += delta
	if flying or hover > 0.0:
		velocity = Vector3.ZERO
		model.position.y = hover + sin(_t * 2.0 + float(get_instance_id() % 7)) * 0.12
	else:
		if not is_on_floor():
			velocity.y -= 12.0 * delta
		else:
			velocity.y = 0.0
	_think(delta)
	if not stationary or not is_on_floor():
		move_and_slide()

## Behaviour hook, filled in by the combat/AI step. Must set velocity.x/z.
func _think(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

# =====================================================================
# Taking damage
# =====================================================================
## Applies damage after defence and element weakness/resistance. Returns the damage dealt.
func take_damage(amount: float, source: Node = null, element: String = "") -> float:
	if dead or bool(data.get("invulnerable", false)):
		return 0.0
	if data.get("sacred_only", false) and element not in ["sacred", "light"]:
		return 0.0
	var dmg := amount * (1.0 - clampf(float(data.get("def", 0.0)), 0.0, 0.9))
	if element != "":
		if element in data.get("weak", []):
			dmg *= 1.5
		elif element in data.get("resist", []):
			dmg *= 0.5
	dmg = maxf(dmg, 0.0)
	hp -= dmg
	Events.damage_dealt.emit(self, dmg, element if source == null else str(source.name))
	if hp <= 0.0:
		die()
	else:
		Audio.play("hit", -4.0)
	return dmg

func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	Audio.play("enemy_die", -3.0)
	var world: Node = Game.world
	if world != null:
		world.on_enemy_died(self)
	if label != null:
		label.visible = false
	# topple over, sink away, then remove
	var tw := create_tween()
	tw.tween_property(model, "rotation:x", -PI / 2.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_interval(1.5)
	tw.tween_property(model, "position:y", model.position.y - 1.2, 1.0)
	tw.tween_callback(queue_free)

## Back to the spawn point with full health (used when the player respawns).
func leash() -> void:
	if dead:
		return
	hp = hp_max
	global_position = home_pos
	velocity = Vector3.ZERO
