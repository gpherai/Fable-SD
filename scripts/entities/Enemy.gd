## An enemy (or summoned ally) built from data/enemies.json. This script is the body: model,
## collision, health, damage rules, status effects (stun, root, burn, charm, fear, shield) and
## death. What it does with them (patrol, aggro, attacks, boss abilities) lives in
## scripts/combat/EnemyAI.gd; `_think` hands over to it.
extends CharacterBody3D

const Body = preload("res://scripts/entities/Body.gd")
const Effects = preload("res://scripts/combat/Effects.gd")
const EnemyAI = preload("res://scripts/combat/EnemyAI.gd")
const Props = preload("res://scripts/world/Props.gd")

static var _bar_mats: Dictionary = {}

var enemy_id: String = ""
var data: Dictionary = {}
var is_ally: bool = false
var is_boss: bool = false
var drop_item: String = ""
var on_death_flags: Array = []
var spawn_index: int = -1
var respawn: bool = true
var arena: bool = false
var no_reward: bool = false
var dead: bool = false
var hp: float = 1.0
var hp_max: float = 1.0
var dmg: float = 5.0
var home_pos := Vector3.ZERO
var model: Node3D
var label: Label3D
var name_override: String = ""
var hover: float = 0.0
var flying: bool = false
var stationary: bool = false
var nonlethal: bool = false
var last_hit_fist: bool = false   # the last real blow came from bare fists (Mushti Yuddha)
var size: float = 1.0
var radius: float = 0.35
var height: float = 1.8
var ai: EnemyAI = null
## Enemy-local clock; runs slower under Kala Stambhana (see `tf`), so all timers below slow too.
var tf: float = 1.0
var stun_until: float = 0.0
var root_until: float = 0.0
var burn_until: float = 0.0
var burn_dps: float = 0.0
var charm_until: float = 0.0
var fear_until: float = 0.0
var shield_until: float = 0.0
var shield_reduction: float = 0.0
var expires_at: float = 0.0
var knock_vel := Vector3.ZERO
var rising: bool = false
var rise_t: float = 0.0
var _t: float = 0.0
var _ready_pos: bool = false
var _burn_acc: float = 0.0
var _bar: Node3D = null
var _bar_fg: MeshInstance3D = null
var _bar_w: float = 1.0
var _bar_until: float = 0.0
var _shield_node: Node3D = null

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
	no_reward = bool(opts.get("no_reward", false))
	name_override = str(opts.get("name_override", ""))
	flying = bool(data.get("flying", false))
	hover = float(data.get("hover", 0.0))
	stationary = bool(data.get("stationary", false))
	nonlethal = bool(data.get("nonlethal", false))
	hp_max = float(data.get("hp", 30.0)) * float(opts.get("hp_mult", 1.0))
	hp = hp_max
	dmg = float(data.get("dmg", 5.0)) * float(opts.get("dmg_mult", 1.0))
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(55.0)
	size = float(data.get("size", 1.0))
	var shape := CapsuleShape3D.new()
	shape.radius = clampf(0.35 * size, 0.25, 1.6)
	shape.height = maxf(1.8 * size, shape.radius * 2.0 + 0.1)
	radius = shape.radius
	height = shape.height
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
	if float(opts.get("lifetime", 0.0)) > 0.0:
		expires_at = float(opts["lifetime"])
	if bool(data.get("rise", false)) and not arena:
		# buried until the player comes close (see EnemyAI); arena fighters are already up and waiting
		rising = true
		collision_layer = 0
		model.position.y = hover - height - 0.2
	ai = EnemyAI.new()
	ai.setup(self)

func display_name() -> String:
	if name_override != "" and Data.characters.has(name_override):
		return Loc.t(Data.character(name_override).get("name", {}))
	return Loc.t(data.get("name", {}))

# =====================================================================
# Geometry (the origin is at the feet, so hit tests use the capsule instead)
# =====================================================================
## Middle of the body in world space.
func center() -> Vector3:
	return global_position + Vector3(0, hover + height * 0.5, 0)

## Distance from a point to the surface of the body capsule (negative when inside).
func hit_distance(p: Vector3) -> float:
	var y0 := global_position.y + hover + radius
	var y1 := global_position.y + hover + maxf(height - radius, radius)
	var cy := clampf(p.y, y0, y1)
	return Vector3(global_position.x, cy, global_position.z).distance_to(p) - radius

## Horizontal distance from a point to the body surface, if the body overlaps the vertical band
## [y_from, y_to] (so melee can reach flying enemies above and low ones below). INF otherwise.
func flat_reach(p: Vector3, y_from: float, y_to: float) -> float:
	var bottom := global_position.y + hover
	var top := bottom + height
	if top < y_from or bottom > y_to:
		return INF
	return Vector2(global_position.x - p.x, global_position.z - p.z).length() - radius

# =====================================================================
# Frame loop
# =====================================================================
func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _ready_pos:
		# World sets the spawn position right after add_child; remember it once.
		_ready_pos = true
		home_pos = global_position
		if expires_at > 0.0:
			expires_at += _t
	var world: Node = Game.world
	tf = 1.0 if (is_ally or world == null) else float(world.time_factor)
	var dt := delta * tf
	_t += dt
	_tick_status(dt)
	if flying or hover > 0.0:
		var gy: float = world.height_at(global_position.x, global_position.z) if world != null else global_position.y
		velocity.y = clampf((gy - global_position.y) * 6.0, -8.0, 8.0)
		model.position.y = hover + sin(_t * 2.0 + float(get_instance_id() % 7)) * 0.12
	else:
		if not is_on_floor():
			velocity.y -= 12.0 * delta
		else:
			velocity.y = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_think(dt)
	if knock_vel.length_squared() > 0.001:
		velocity.x += knock_vel.x
		velocity.z += knock_vel.z
		knock_vel = knock_vel.move_toward(Vector3.ZERO, 9.0 * delta)
	if not stationary or not is_on_floor():
		move_and_slide()
	if _bar != null:
		_bar.visible = _t < _bar_until and not dead

## Behaviour lives in EnemyAI; `delta` is already scaled by the world's time factor.
func _think(delta: float) -> void:
	if ai != null:
		ai.think(delta)

# =====================================================================
# Status effects
# =====================================================================
func is_stunned() -> bool:
	return _t < stun_until

func is_rooted() -> bool:
	return _t < root_until

func is_charmed() -> bool:
	return _t < charm_until

func is_afraid() -> bool:
	return _t < fear_until

func is_shielded() -> bool:
	return _t < shield_until

func stagger(seconds: float) -> void:
	stun_until = maxf(stun_until, _t + seconds)
	if seconds > 0.15 and ai != null:
		ai.interrupt()

func burn(dps: float, seconds: float) -> void:
	burn_dps = maxf(burn_dps, dps)
	burn_until = maxf(burn_until, _t + seconds)

func root(seconds: float) -> void:
	root_until = maxf(root_until, _t + seconds)

func charm(seconds: float) -> void:
	charm_until = maxf(charm_until, _t + seconds)
	if ai != null:
		ai.target = null

func frighten(seconds: float) -> void:
	if "fear" in data.get("resist", []):
		return
	fear_until = maxf(fear_until, _t + seconds)

func raise_shield(seconds: float, reduction: float) -> void:
	shield_until = _t + seconds
	shield_reduction = reduction
	if _shield_node == null:
		_shield_node = Node3D.new()
		_shield_node.add_child(Props.sphere(radius * 1.5 + 0.3, Color("#ffe27a"), Vector3.ZERO, Vector3.ONE, 0.4, 0.0, Color(1.0, 0.85, 0.3, 0.6), 0.28))
		_shield_node.position = Vector3(0, hover + height * 0.5, 0)
		add_child(_shield_node)
	_shield_node.visible = true
	Audio.play("shield", -4.0)

func _drop_shield() -> void:
	shield_until = 0.0
	if _shield_node != null:
		_shield_node.visible = false

func _tick_status(dt: float) -> void:
	if burn_until > _t:
		_burn_acc += dt
		if _burn_acc >= 0.5:
			_burn_acc -= 0.5
			take_damage(burn_dps * 0.5, null, "fire", {"dot": true})
			if not dead:
				Effects.flash(model, Color(1.0, 0.45, 0.1, 0.35), 0.15)
	if shield_until > 0.0 and _t >= shield_until:
		_drop_shield()
	if expires_at > 0.0 and _t >= expires_at:
		expire()

# =====================================================================
# Taking damage
# =====================================================================
## Applies damage after defence and element weakness/resistance. Returns the damage dealt.
## opts: knock (Vector3 impulse), stun (seconds), pierce_def (0..1 of defence ignored),
## break_guard (bool, drops a boss shield), dot (bool, damage over time: no flinch or flash).
func take_damage(amount: float, source: Node = null, element: String = "", opts: Dictionary = {}) -> float:
	if dead or rising or bool(data.get("invulnerable", false)):
		return 0.0
	var is_dot: bool = bool(opts.get("dot", false))
	if not is_dot:
		last_hit_fist = bool(opts.get("fist", false))
	if data.get("sacred_only", false) and element not in ["sacred", "light"]:
		if not is_dot:
			Effects.damage_number(Game.world, center() + Vector3(0, height * 0.5, 0), 0.0, Color("#9a9a9a"))
		return 0.0
	var def: float = clampf(float(data.get("def", 0.0)) * (1.0 - float(opts.get("pierce_def", 0.0))), 0.0, 0.9)
	var dealt: float = amount * (1.0 - def)
	var tint := Color("#fff3d0")
	if element != "":
		if element in data.get("weak", []):
			dealt *= 1.5
			tint = Color("#ffd24a")
		elif element in data.get("resist", []):
			dealt *= 0.5
			tint = Color("#9aa4b8")
	if is_shielded():
		if bool(opts.get("break_guard", false)):
			_drop_shield()
			Audio.play("block")
			Effects.sparks(Game.world, center(), Color("#ffe27a"), 8)
		else:
			dealt *= 1.0 - shield_reduction
			tint = Color("#9aa4b8")
	dealt = maxf(dealt, 0.0)
	hp -= dealt
	_bar_until = _t + 4.0
	_update_bar()
	var src_name := element
	if source != null:
		src_name = str(source.name)
	Events.damage_dealt.emit(self, dealt, src_name)
	if is_dot:
		Effects.damage_number(Game.world, center() + Vector3(0, height * 0.5, 0), dealt, Color("#ff9a3a"))
	else:
		Effects.damage_number(Game.world, center() + Vector3(0, height * 0.5, 0), dealt, tint, dealt >= hp_max * 0.15)
	if hp <= 0.0:
		if nonlethal:
			die(true)
		else:
			die()
		return dealt
	if not is_dot:
		Effects.flash(model, Color(1, 1, 1, 0.5), 0.08)
		Audio.play("hit", -4.0)
		var kn: Vector3 = opts.get("knock", Vector3.ZERO)
		if kn != Vector3.ZERO:
			var resist_k := 1.0 / (size * size)
			if is_boss:
				resist_k *= 0.3
			knock_vel += Vector3(kn.x, 0, kn.z) * resist_k
		var stun_s: float = float(opts.get("stun", 0.0))
		if stun_s > 0.0:
			var res := 1.0
			if is_boss:
				res *= 0.4
			if size >= 2.5:
				res *= 0.3
			if stun_s * res > 0.1:
				stagger(stun_s * res)
		if ai != null and source != null:
			ai.provoke(source)
	return dealt

func die(spare: bool = false) -> void:
	if dead:
		return
	dead = true
	hp = 0.0 if not spare else 1.0
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	if _bar != null:
		_bar.visible = false
	if _shield_node != null:
		_shield_node.visible = false
	var world: Node = Game.world
	if spare:
		# a sparring partner or duelist yields instead of dying
		Audio.play("bell", -6.0)
		Events.notify.emit(Loc.t("UI_YIELDS", {"name": display_name()}), "info")
	else:
		Audio.play("enemy_die", -3.0)
	if world != null:
		world.on_enemy_died(self)
	if label != null:
		label.visible = false
	if ai != null:
		ai.on_death()
	# topple over (or kneel), sink away, then remove
	var tw := create_tween()
	if spare:
		tw.tween_property(model, "rotation:x", -0.7, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(3.0)
	else:
		tw.tween_property(model, "rotation:x", -PI / 2.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(1.5)
	tw.tween_property(model, "position:y", model.position.y - 1.2, 1.0)
	tw.tween_callback(queue_free)

## A summoned ally whose time is up: fades away without any reward logic.
func expire() -> void:
	if dead:
		return
	dead = true
	collision_layer = 0
	collision_mask = 0
	var world: Node = Game.world
	if world != null:
		world.allies.erase(self)
		world.enemies.erase(self)
	Effects.sparks(world, center(), Color("#9ef0e0"), 8)
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ZERO, 0.5)
	tw.tween_callback(queue_free)

## Back to the spawn point with full health (used when the player respawns).
func leash() -> void:
	if dead:
		return
	hp = hp_max
	global_position = home_pos
	velocity = Vector3.ZERO
	knock_vel = Vector3.ZERO
	stun_until = 0.0
	if ai != null:
		ai.reset()

# =====================================================================
# Health bar (shows for a few seconds after the enemy was hurt)
# =====================================================================
func _update_bar() -> void:
	if _bar == null:
		_build_bar()
	var frac := clampf(hp / hp_max, 0.0, 1.0)
	var m := _bar_fg.mesh as QuadMesh
	m.size = Vector2(maxf(_bar_w * frac, 0.001), 0.09)
	m.center_offset = Vector3(-(_bar_w - _bar_w * frac) / 2.0, 0, 0)

func _build_bar() -> void:
	_bar = Node3D.new()
	_bar.position = Vector3(0, height + hover + 0.3, 0)
	_bar.visible = false
	add_child(_bar)
	_bar_w = clampf(0.9 * size, 0.7, 2.6)
	var bg := MeshInstance3D.new()
	var bgm := QuadMesh.new()
	bgm.size = Vector2(_bar_w + 0.06, 0.13)
	bg.mesh = bgm
	bg.material_override = _bar_mat("#101010", 0)
	_bar.add_child(bg)
	_bar_fg = MeshInstance3D.new()
	_bar_fg.mesh = QuadMesh.new()
	_bar_fg.material_override = _bar_mat("#5be37d" if is_ally else "#d63a2a", 1)
	_bar.add_child(_bar_fg)

static func _bar_mat(col: String, prio: int) -> StandardMaterial3D:
	var key := "%s%d" % [col, prio]
	if _bar_mats.has(key):
		return _bar_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.albedo_color = Color(col)
	m.render_priority = 10 + prio
	_bar_mats[key] = m
	return m
