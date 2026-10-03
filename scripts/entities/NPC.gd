## A villager, sage or companion. Stands near its home spot, turns to face the player when
## close, and follows the player when recruited (World/Game set `following`).
## Pressing E next to it announces the conversation through Events.dialogue_started; the
## dialogue UI listens for that.
extends CharacterBody3D

const Body = preload("res://scripts/entities/Body.gd")

var npc_id: String = ""
var data: Dictionary = {}
var home_pos := Vector3.ZERO
var following: bool = false
var model: Node3D
var label: Label3D
var walk_phase: float = 0.0
var sitting: bool = false
var _was_moving: bool = false

const FOLLOW_DISTANCE := 3.2
const FOLLOW_SPEED := 4.2
const FACE_PLAYER_RANGE := 7.0

func setup(nid: String) -> void:
	npc_id = nid
	data = Data.character(nid)
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)
	var body: Dictionary = data.get("body", {})
	sitting = bool(body.get("sitting", false))
	model = Body.humanoid(body)
	add_child(model)
	label = Label3D.new()
	label.text = display_name()
	label.font_size = 36
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color("#ffe9b0")
	label.outline_size = 8
	label.position = Vector3(0, 2.25 * float(body.get("scale", 1.0)) * (0.68 if body.get("child", false) else 1.0), 0)
	label.visibility_range_end = 14.0
	add_child(label)
	Events.language_changed.connect(_on_language_changed)

func display_name() -> String:
	return Loc.t(data.get("name", {}))

func _on_language_changed(_l: String) -> void:
	if label != null:
		label.text = display_name()

func hint_text() -> String:
	return Loc.t("HINT_TALK", {"name": display_name()})

## Called by the player when E is pressed next to this NPC.
func interact(_world: Node) -> void:
	_face(Game.player.global_position if Game.player != null else global_position, 1.0)
	Events.dialogue_started.emit(npc_id)

func _face(target: Vector3, t: float) -> void:
	var d := target - global_position
	d.y = 0.0
	if d.length() < 0.05:
		return
	model.rotation.y = lerp_angle(model.rotation.y, atan2(-d.x, -d.z), clampf(t, 0.0, 1.0))

func _physics_process(delta: float) -> void:
	var player: Node3D = Game.player
	var moving := false
	if not is_on_floor():
		velocity.y -= 12.0 * delta
	else:
		velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	if player != null and is_instance_valid(player):
		var to_player := player.global_position - global_position
		var flat := Vector2(to_player.x, to_player.z)
		if following and not sitting:
			if flat.length() > 30.0:
				global_position = player.global_position + Vector3(2, 0.5, 2)
			elif flat.length() > FOLLOW_DISTANCE:
				var dir := flat.normalized()
				velocity.x = dir.x * FOLLOW_SPEED
				velocity.z = dir.y * FOLLOW_SPEED
				moving = true
				_face(player.global_position, delta * 8.0)
			else:
				_face(player.global_position, delta * 4.0)
		elif flat.length() < FACE_PLAYER_RANGE and not sitting:
			_face(player.global_position, delta * 3.0)
	move_and_slide()
	if moving:
		walk_phase += delta * 9.0
		Body.pose_walk(model, walk_phase, 0.6)
	elif _was_moving and not sitting:
		Body.pose_walk(model, 0.0, 0.0)
	_was_moving = moving
