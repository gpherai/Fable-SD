## The hero (Vira). Third-person movement relative to the camera, mouse-look camera on a
## spring arm, roll, sprint, and interacting with the world (E). Health and Ojas regenerate
## here. Fighting (attack, block, bow, lock, siddhis) is in scripts/combat/PlayerCombat.gd; this
## script owns the body and `take_damage`, the entry point for enemies and hazards.
extends CharacterBody3D

const Body = preload("res://scripts/entities/Body.gd")
const Props = preload("res://scripts/world/Props.gd")
const Effects = preload("res://scripts/combat/Effects.gd")
const PlayerCombat = preload("res://scripts/combat/PlayerCombat.gd")

const WALK_SPEED := 5.0
const SPRINT_MULT := 1.6
const ACCEL := 45.0
const ROLL_SPEED := 9.5
const ROLL_TIME := 0.45
const ROLL_COOLDOWN := 0.35
const ROLL_PIVOT := Vector3(0, 0.9, 0)   # the somersault turns about the middle of the body
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6
const MOUSE_SENS := 0.0028

var model: Node3D
var combat: Node
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D

var combat_mult: int = 0
var dead: bool = false
var invulnerable: bool = false
var rolling: bool = false
var roll_left: float = 0.0
var roll_cd: float = 0.0
var roll_dir := Vector3.ZERO
var _roll_anim: bool = false
var walk_phase: float = 0.0
var yaw: float = 0.0
var pitch: float = -0.35
var hint: String = ""
var controls_on: bool = false
var forced_dir := Vector3.ZERO
var forced_speed: float = 0.0
var forced_left: float = 0.0
var knock_t: float = 0.0
var _hint_timer: float = 0.0
var _regen_emit: float = 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(55.0)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	_build_camera()
	Events.equipment_changed.connect(rebuild_visual)
	Events.stat_raised.connect(func(_s, _l): rebuild_visual())
	combat = PlayerCombat.new()
	combat.name = "Combat"
	combat.player = self
	add_child(combat)
	Events.player_died.connect(_on_died)
	Events.panel_requested.connect(func(_p, _d): release_mouse())
	capture_mouse()
	rebuild_visual()

func _build_camera() -> void:
	pivot = Node3D.new()
	pivot.name = "CameraPivot"
	pivot.position = Vector3(0, 1.55, 0)
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.name = "SpringArm"
	arm.spring_length = 6.0
	arm.margin = 0.4
	arm.collision_mask = 1
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 70.0
	cam.far = 500.0
	arm.add_child(cam)
	cam.current = true
	_apply_look()

func _apply_look() -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)

# =====================================================================
# Appearance
# =====================================================================
## Rebuilds the model from the hero's equipment (clothes, hair, weapon).
func rebuild_visual() -> void:
	if model != null:
		remove_child(model)
		model.queue_free()
		model = null
	var b := {"skin": Game.hero.get("skin", "#c68a5a"), "cloth": "#e8e0cc", "cloth2": "#8a6d3b", "child": Game.is_child(), "hair": "#1a1a1a"}
	var chest := Game.equipped_item("chest")
	if not chest.is_empty():
		b["cloth"] = chest.get("colors", {}).get("primary", b["cloth"])
		b["cloth2"] = chest.get("colors", {}).get("secondary", b["cloth2"])
		b["armor"] = chest.get("style", "") == "metal"
	var legs := Game.equipped_item("legs")
	if not legs.is_empty():
		b["legs"] = legs.get("colors", {}).get("primary", b["cloth2"])
	var hair := Game.equipped_item("hair")
	if not hair.is_empty():
		b["hair"] = hair.get("color", "#1a1a1a")
		b["hair_style"] = str(hair.get("id", "")).trim_prefix("kesh_")
	var beard := Game.equipped_item("beard")
	if not beard.is_empty():
		b["beard"] = true
		b["hair"] = beard.get("color", b["hair"]) if hair.is_empty() else b["hair"]
	model = Body.humanoid(b)
	add_child(model)
	var head: Node3D = Body.joints(model).get("Head")
	var hat := Game.equipped_item("head")
	if head != null and not hat.is_empty():
		var hc := Color.html(hat.get("colors", {}).get("primary", "#c8b48a"))
		head.add_child(Props.sphere(0.17, hc, Vector3(0, 0.2, 0), Vector3(1, 0.8, 1.05)))
	var hand: Node3D = Body.joints(model).get("WeaponHand")
	var wid := Game.equipped("ranged") if bool(Game.hero.get("ranged_stance", false)) else Game.equipped("melee")
	if hand != null and wid != "":
		var wi := Data.item(wid)
		hand.add_child(Props.sword_mesh(str(wi.get("shape", "straight")), Color.html(str(wi.get("color", "#b0b0b8"))), 1.0))
		hand.rotation.x = -1.0

# =====================================================================
# Input
# =====================================================================
func capture_mouse() -> void:
	controls_on = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

## Frees the mouse for a menu (the UI manager calls this; panel_requested does too, for headless runs).
func release_mouse() -> void:
	controls_on = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controls_on:
		var sens := MOUSE_SENS * float(Game.settings.get("mouse_sens", 1.0))
		var inv := -1.0 if Game.settings.get("invert_y", false) else 1.0
		yaw -= event.screen_relative.x * sens
		pitch = clampf(pitch - event.screen_relative.y * sens * inv, PITCH_MIN, PITCH_MAX)
		_apply_look()
	elif event is InputEventMouseButton and event.pressed:
		if not controls_on and not Game.paused_for_ui:
			capture_mouse()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = clampf(arm.spring_length - 0.5, 2.5, 12.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = clampf(arm.spring_length + 0.5, 2.5, 12.0)
	elif event.is_action_pressed("interact") and _can_act():
		_interact()
	elif event.is_action_pressed("roll") and _can_act():
		_start_roll()
	elif event.is_action_pressed("potion_prana") and _can_act():
		Game.quaff("heal")
	elif event.is_action_pressed("potion_ojas") and _can_act():
		Game.quaff("ojas")

func _can_act() -> bool:
	return not dead and Game.in_game and not Game.paused_for_ui and controls_on

# =====================================================================
# Movement
# =====================================================================
func reset_state() -> void:
	velocity = Vector3.ZERO
	dead = false
	invulnerable = false
	rolling = false
	roll_left = 0.0
	combat_mult = 0
	forced_left = 0.0
	knock_t = 0.0
	combat.reset()
	if model != null:
		model.rotation = Vector3.ZERO
		Body.pose_walk(model, 0.0, 0.0)
	Events.combat_multiplier_changed.emit(0)

func _physics_process(delta: float) -> void:
	if not Game.in_game:
		return
	roll_cd = maxf(0.0, roll_cd - delta)
	combat.tick(delta)
	var wish := Vector3.ZERO
	var sprinting := false
	if _can_move():
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = Vector3(v.x, 0, v.y).rotated(Vector3.UP, yaw)
		sprinting = Input.is_action_pressed("sprint") and wish != Vector3.ZERO and combat.is_idle()
	var target: Vector3 = wish * WALK_SPEED * Game.speed_mult() * (SPRINT_MULT if sprinting else 1.0) * combat.move_mult()
	var accel := ACCEL
	if knock_t > 0.0:
		knock_t -= delta
		accel = 6.0
	if forced_left > 0.0:
		forced_left -= delta
		target = forced_dir * forced_speed
		accel = 200.0
		wish = forced_dir
	if rolling:
		roll_left -= delta
		target = roll_dir * ROLL_SPEED
		accel = 200.0
		if roll_left <= 0.0:
			rolling = false
			invulnerable = false
	velocity.x = move_toward(velocity.x, target.x, accel * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
	else:
		velocity.y -= 12.0 * delta
	move_and_slide()
	_animate(delta, wish, sprinting)
	_regen(delta)
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = 0.1
		_update_hint()

## Used by dashes and leaps (siddhis): overrides the walking input for `seconds`.
func begin_forced_move(dir: Vector3, speed: float, seconds: float) -> void:
	forced_dir = Vector3(dir.x, 0, dir.z).normalized()
	forced_speed = speed
	forced_left = seconds

func end_forced_move() -> void:
	forced_left = 0.0

## Turns the model straight away (attacks, shots and spells aim instantly).
func face_now(dir: Vector3) -> void:
	if model != null and Vector2(dir.x, dir.z).length() > 0.001:
		model.rotation.y = atan2(-dir.x, -dir.z)

## A shove (enemy blows, explosions): the hero slides for a moment.
func knock(impulse: Vector3) -> void:
	velocity.x += impulse.x
	velocity.z += impulse.z
	knock_t = 0.25

func _on_died() -> void:
	dead = true
	combat.on_died()
	if model != null:
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", -PI / 2.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

func _can_move() -> bool:
	return not dead and not Game.paused_for_ui and controls_on

func _start_roll() -> void:
	if rolling or roll_cd > 0.0 or not is_on_floor() or forced_left > 0.0:
		return
	combat.cancel()
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var d := Vector3(v.x, 0, v.y).rotated(Vector3.UP, yaw)
	if d == Vector3.ZERO:
		d = Vector3(0, 0, -1).rotated(Vector3.UP, model.rotation.y)
	roll_dir = d.normalized()
	rolling = true
	invulnerable = true
	roll_left = ROLL_TIME
	roll_cd = ROLL_TIME + ROLL_COOLDOWN
	Audio.play("roll")

func _animate(delta: float, wish: Vector3, sprinting: bool) -> void:
	if model == null or dead:
		return
	var flat := Vector3(velocity.x, 0, velocity.z)
	var ov: Vector3 = combat.facing_override()
	var face := roll_dir if rolling else (ov if ov != Vector3.ZERO else wish)
	if face != Vector3.ZERO:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-face.x, -face.z), clampf(delta * (24.0 if ov != Vector3.ZERO else 14.0), 0.0, 1.0))
	if rolling:
		# a forward somersault: one full turn over the roll, about the middle of the body (so the head and
		# feet never dip through the ground)
		model.rotation.x = -TAU * clampf(1.0 - roll_left / ROLL_TIME, 0.0, 1.0)
		var mid: Vector3 = ROLL_PIVOT * model.scale.y   # the model is scaled (a child is small): so is its middle
		model.position = mid - Basis.from_euler(model.rotation, EULER_ORDER_YXZ) * mid
		Body.pose_walk(model, 0.0, 0.0)
		_roll_anim = true
		return
	if _roll_anim:   # a full turn is the same as none: land upright, do not unwind
		_roll_anim = false
		model.rotation.x = 0.0
		model.position = Vector3.ZERO
	model.rotation.x = lerpf(model.rotation.x, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	if flat.length() > 0.3:
		walk_phase += delta * flat.length() * 2.0
		Body.pose_walk(model, walk_phase, 0.75 if sprinting else 0.55)
	else:
		Body.pose_walk(model, 0.0, 0.0)
	combat.apply_pose()

func _regen(delta: float) -> void:
	if dead:
		return
	var changed := false
	var hmax := Game.hp_max()
	if Game.hero.hp < hmax:
		Game.hero.hp = minf(hmax, Game.hero.hp + Game.hp_regen() * delta)
		changed = true
	var omax := Game.ojas_max()
	if Game.hero.ojas < omax:
		Game.hero.ojas = minf(omax, Game.hero.ojas + Game.ojas_regen() * combat.ojas_regen_mult() * delta)
		changed = true
	if changed:
		_regen_emit += delta
		if _regen_emit >= 0.4:
			_regen_emit = 0.0
			Events.hero_changed.emit()

# =====================================================================
# Interaction
# =====================================================================
## Nearest thing E would act on: {"node": Node, "text": String}, or {} when nothing is in reach.
func _find_target() -> Dictionary:
	var world: Node = Game.world
	if world == null:
		return {}
	var best: Node = null
	var best_d := INF
	for it in world.interactables:
		if not is_instance_valid(it) or not it.can_interact() or it.hint_text() == "":
			continue
		var d: float = it.global_position.distance_to(global_position)
		if d <= it.interact_radius and d < best_d:
			best = it
			best_d = d
	var npc: Node = world.nearest_npc(global_position, 3.5)
	if npc != null:
		var nd: float = npc.global_position.distance_to(global_position)
		if nd < best_d:
			best = npc
	if best == null:
		# nothing to act on: standing at water with a half-empty kamandalu, E fills it
		if Game.has("kamandalu") and int(Game.hero.water) < Game.water_max() and world.water_near(global_position):
			return {"node": null, "text": Loc.t("HINT_WATER", {"n": int(Game.hero.water), "max": Game.water_max()}), "action": Game.refill_water}
		return {}
	return {"node": best, "text": best.hint_text()}

func _update_hint() -> void:
	var t := _find_target()
	var text: String = t.get("text", "") if not dead else ""
	if text != hint:
		hint = text
		Events.interact_hint.emit(hint)

func _interact() -> void:
	var t := _find_target()
	if t.is_empty():
		return
	Audio.play("ui", -6.0)
	if t.has("action"):
		t["action"].call()
		return
	t["node"].interact(Game.world)

# =====================================================================
# Damage
# =====================================================================
## Enemy attacks and hazards enter here. Rolling is invulnerable. `kind` is "melee", "projectile"
## or "magic" (only the first two can be blocked); `attacker` and `from_pos` say where it came
## from (for the guard cone, parries and knockback). Returns the damage that got through.
func take_damage(amount: float, source: String = "", attacker: Node3D = null, kind: String = "melee", from_pos: Vector3 = Vector3.INF) -> float:
	if dead or invulnerable:
		return 0.0
	var world: Node = Game.world
	var res: Dictionary = combat.filter_incoming(amount, attacker, kind, from_pos)
	if bool(res["parried"]):
		combat.on_parry(attacker)
		return 0.0
	if bool(res["blocked"]):
		combat.on_blocked(from_pos)
		if float(res["amount"]) <= 0.0:
			return 0.0
	var dmg: float = float(res["amount"]) * (1.0 - Game.dmg_reduction())
	dmg = combat.absorb(dmg)
	if dmg <= 0.0:
		return 0.0
	Audio.play("player_hit")
	combat_mult = int(combat_mult / 2.0)
	Events.combat_multiplier_changed.emit(combat_mult)
	var src := from_pos
	if src == Vector3.INF and attacker != null and is_instance_valid(attacker):
		src = attacker.global_position
	if src != Vector3.INF and kind != "hazard":
		var away := Vector3(global_position.x - src.x, 0, global_position.z - src.z)
		if away.length() > 0.01:
			knock(away.normalized() * (1.5 if bool(res["blocked"]) else 4.0))
	Effects.damage_number(world, global_position + Vector3(0, 2.1, 0), dmg, Color("#ff5a4a"), dmg >= Game.hp_max() * 0.15)
	combat.on_damaged(dmg)
	Game.damage_hero(dmg, source)
	return dmg
