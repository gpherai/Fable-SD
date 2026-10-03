## Enemy behaviour, driven by the numbers in data/enemies.json.
##
## Every attack is a timed "action": a telegraphed wind-up (the body flashes orange and the arm
## goes up), the hit at the end of the wind-up, then a recovery. The player can roll through
## the hit, block it, or parry it. Between actions the enemy idles around its home, notices the
## player (aggro), chases, keeps its distance (ranged/caster), summons, leaps, teleports or uses
## a boss ability. Allies (summons) use the same brain but pick enemies as targets and follow
## the player when there is nothing to fight. All timers run on the enemy's own clock, which the
## world's time factor slows (Kala Stambhana).
extends RefCounted

const Effects = preload("res://scripts/combat/Effects.gd")
const Body = preload("res://scripts/entities/Body.gd")

## Projectile looks and speeds per kind (the kinds come from enemies.json "projectile").
const PROJ := {
	"arrow": {"speed": 22.0, "color": "#c8b48a"},
	"fire": {"speed": 14.0, "color": "#ff7a1a"},
	"rock": {"speed": 12.0, "color": "#7a766e"},
	"ice": {"speed": 13.0, "color": "#bfe8ff"},
	"shadow": {"speed": 12.0, "color": "#8e2d8e"},
	"scream": {"speed": 11.0, "color": "#e8e8ff"},
	"blade": {"speed": 15.0, "color": "#dfe6f2"},
}

## Boss abilities: cooldown in seconds.
const ABILITY_CD := {
	"whirlwind": 9.0, "double_strike": 7.0, "vajra": 8.0, "kavacha": 22.0, "teleport": 10.0,
	"blade_fan": 9.0, "kalagni": 14.0, "fire_breath": 9.0, "tail_sweep": 8.0, "fly_phase": 16.0,
}

var en  # the Enemy node (untyped: Enemy.gd preloads this script)
var d: Dictionary = {}
var kind: String = "melee"
var spd: float = 4.0
var aggro_r: float = 20.0
var leash_r: float = 45.0
var atk_range: float = 1.8
var atk_cd: float = 1.2
var ranged: bool = false
var proj_kind: String = ""
var keep_dist: float = 0.0
var throw_range: float = 0.0
var abilities: Array = []
var target: Node3D = null
var engaged: bool = false
var returning: bool = false
var leaping: bool = false
var action: Dictionary = {}
var minions: Array = []
var cd: Dictionary = {}
var walk_phase: float = 0.0
var flank: float = 0.0
var strafe_dir: float = 1.0
var strafe_t: float = 0.0
var wander_t: float = 0.0
var wander_dir := Vector3.ZERO
var retarget_t: float = 0.0
var stuck_t: float = 0.0
var last_pos := Vector3.ZERO
var side_t: float = 0.0
var side_dir := Vector3.ZERO
var leap_t: float = 0.0
var leap_dir := Vector3.ZERO
var leap_speed: float = 0.0
var leap_slam: bool = false
var _fire_pos := Vector3.ZERO

func setup(enemy) -> void:
	en = enemy
	d = enemy.data
	kind = str(d.get("kind", "melee"))
	spd = float(d.get("speed", 4.0))
	aggro_r = minf(float(d.get("aggro", 20.0)), 45.0 if enemy.is_boss else 30.0)
	leash_r = maxf(aggro_r * 2.2, 40.0)
	atk_range = float(d.get("attack_range", 1.8))
	atk_cd = float(d.get("attack_cd", 1.2))
	proj_kind = str(d.get("projectile", ""))
	ranged = atk_range > 5.0 and proj_kind != ""
	keep_dist = float(d.get("keep_distance", 0.0))
	throw_range = float(d.get("throw_range", 0.0))
	abilities = d.get("abilities", [])
	flank = randf_range(-0.6, 0.6) if bool(d.get("pack", false)) else 0.0
	cd = {"attack": randf_range(0.3, 1.2), "summon": 3.0, "leap": randf_range(1.0, 3.0), "ability": 3.0, "tele": 4.0}
	last_pos = enemy.position

func reset() -> void:
	target = null
	engaged = false
	returning = false
	leaping = false
	action = {}
	if en != null and is_instance_valid(en):
		Body.pose_reset(en.model)

func on_death() -> void:
	action = {}
	leaping = false

# =====================================================================
# Main loop
# =====================================================================
func think(dt: float) -> void:
	if en.rising:
		_rise(dt)
		return
	_tick_cd(dt)
	var p: Node3D = _player()
	if target == null and not en.is_ally and (p == null or _flat_len(p) > 90.0):
		_halt()
		return  # far from the player and unaware: nothing to simulate
	if en.is_stunned():
		_halt()
		if not action.is_empty():
			interrupt()
		return
	if leaping:
		_tick_leap(dt)
		return
	if not action.is_empty():
		_tick_action(dt)
		return
	if returning:
		_return_home(dt)
		return
	_retarget(dt)
	if target == null:
		_idle(dt)
	else:
		_combat(dt)

func _tick_cd(dt: float) -> void:
	for k in cd.keys():
		cd[k] = maxf(0.0, float(cd[k]) - dt)

## Called when something hurts this enemy: it notices the attacker even from far away.
func provoke(src) -> void:
	if returning or en.rising or en.dead or not _valid(src) or src == en:
		return
	if not _is_foe(src):
		return
	if target == null or not _valid(target):
		target = src
		engaged = true
		_on_engage()

## A stagger or knock-down cancels whatever the enemy was doing.
func interrupt() -> void:
	if action.is_empty():
		return
	action = {}
	Body.pose_reset(en.model)
	en.model.position.x = 0.0
	en.model.position.z = 0.0
	cd["attack"] = maxf(float(cd.get("attack", 0.0)), 0.5)

# =====================================================================
# Targeting
# =====================================================================
func _player() -> Node3D:
	var p = Game.player
	if p != null and is_instance_valid(p):
		return p
	return null

func _valid(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	if t.is_in_group("player"):
		return not t.dead and Game.in_game
	return not t.dead and not t.rising

## Is `t` somebody this enemy fights (player and allies for enemies, enemies for allies)?
func _is_foe(t) -> bool:
	if en.is_ally:
		return not t.is_in_group("player") and not bool(t.is_ally)
	if en.is_charmed():
		return t != en
	if t.is_in_group("player"):
		return true
	return bool(t.is_ally) and not bool(t.data.get("invulnerable", false))

func _candidates() -> Array:
	var out: Array = []
	var w = Game.world
	if w == null:
		return out
	if en.is_ally:
		for e in w.enemies:
			if _valid(e):
				out.append(e)
	elif en.is_charmed():
		for e in w.enemies:
			if e != en and _valid(e):
				out.append(e)
		for a in w.allies:
			if _valid(a) and not bool(a.data.get("invulnerable", false)):
				out.append(a)
	else:
		var p := _player()
		if p != null and _valid(p):
			out.append(p)
		for a in w.allies:
			if _valid(a) and not bool(a.data.get("invulnerable", false)):
				out.append(a)
	return out

func _retarget(dt: float) -> void:
	retarget_t -= dt
	if retarget_t > 0.0 and _valid(target):
		return
	retarget_t = 0.35
	var reach := aggro_r * (1.6 if engaged else 1.0)
	var best: Node3D = null
	var bd := INF
	for c in _candidates():
		var dist: float = _flat_len(c)
		if dist < reach and dist < bd:
			best = c
			bd = dist
	if best == null:
		target = null
		engaged = false
		return
	target = best
	if not engaged:
		engaged = true
		_on_engage()

func _on_engage() -> void:
	if en.is_boss:
		Audio.play("roar", -8.0)
	if bool(d.get("pack", false)) and Game.world != null:
		for e in Game.world.enemies:
			if e != en and is_instance_valid(e) and e.enemy_id == en.enemy_id and not e.dead:
				if e.global_position.distance_to(en.global_position) < 22.0:
					e.ai.provoke(target)

func _begin_return() -> void:
	returning = true
	target = null
	engaged = false
	action = {}
	Body.pose_reset(en.model)

func _return_home(dt: float) -> void:
	var to := Vector3(en.home_pos.x - en.global_position.x, 0, en.home_pos.z - en.global_position.z)
	en.hp = minf(en.hp_max, en.hp + en.hp_max * 0.15 * dt)
	if to.length() < 1.5:
		returning = false
		en.hp = en.hp_max
		_halt()
		return
	_face(to, dt, 8.0)
	_move(to, spd * 1.3, dt)

# =====================================================================
# Idle
# =====================================================================
func _idle(dt: float) -> void:
	if en.is_ally:
		_follow_player(dt)
		return
	if en.stationary:
		_halt()
		return
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = randf_range(2.0, 5.0)
		var home_gap := Vector3(en.home_pos.x - en.global_position.x, 0, en.home_pos.z - en.global_position.z)
		if home_gap.length() > 6.0:
			wander_dir = home_gap.normalized()
		elif randf() < 0.55:
			var ang := randf() * TAU
			var pt: Vector3 = en.home_pos + Vector3(cos(ang), 0, sin(ang)) * randf_range(1.0, 5.0)
			var to := Vector3(pt.x - en.global_position.x, 0, pt.z - en.global_position.z)
			wander_dir = to.normalized() if to.length() > 0.5 else Vector3.ZERO
		else:
			wander_dir = Vector3.ZERO
	if wander_dir != Vector3.ZERO:
		_face(wander_dir, dt, 5.0)
		_move(wander_dir, spd * 0.35, dt)
	else:
		_halt()

func _follow_player(dt: float) -> void:
	var p := _player()
	if p == null:
		_halt()
		return
	var to := _flat_to(p)
	var dist := to.length()
	if dist > 28.0:
		en.global_position = p.global_position + Vector3(2.0, 0.5, 2.0)
		return
	if dist > 4.0:
		_face(to, dt, 8.0)
		_move(to, spd * (1.3 if dist > 10.0 else 1.0), dt)
	else:
		_face(to, dt, 3.0)
		_halt()

# =====================================================================
# Combat
# =====================================================================
func _combat(dt: float) -> void:
	var t: Node3D = target
	var to := _flat_to(t)
	var dist: float = to.length() - _rad(t) - float(en.radius)
	var dir := to.normalized() if to.length() > 0.01 else Vector3(0, 0, -1)
	if _home_gap() > leash_r:
		_begin_return()
		return
	if en.is_afraid():
		_face(-dir, dt, 8.0)
		_move(-dir, spd * 1.1, dt)
		return
	_face(dir, dt, 10.0)
	if _try_special(t, dist, dir):
		return
	if ranged:
		_ranged(t, dist, dir, dt)
		return
	if dist <= atk_range:
		_halt()
		if float(cd["attack"]) <= 0.0:
			_begin_melee()
	elif en.stationary:
		_halt()
		if throw_range > 0.0 and dist <= throw_range and float(cd["attack"]) <= 0.0:
			_begin_throw()
	else:
		var go := dir
		if flank != 0.0 and dist > 5.0:
			go = dir.rotated(Vector3.UP, flank * clampf((dist - 5.0) / 8.0, 0.0, 1.0))
		_move(go, spd, dt)

func _ranged(t: Node3D, dist: float, dir: Vector3, dt: float) -> void:
	var want := keep_dist if keep_dist > 0.0 else atk_range * 0.6
	if dist < want - 2.0 and not en.stationary:
		_move(-dir, spd * 0.9, dt)
	elif dist > atk_range:
		_move(dir, spd, dt)
	else:
		strafe_t -= dt
		if strafe_t <= 0.0:
			strafe_t = randf_range(1.5, 3.5)
			strafe_dir = 1.0 if randf() < 0.5 else -1.0
		_move(dir.rotated(Vector3.UP, PI / 2.0) * strafe_dir, spd * 0.4, dt)
	if dist <= atk_range + 1.0 and float(cd["attack"]) <= 0.0:
		_begin_shot()

# ---------- attacks as timed actions ----------
## hits: seconds (from the start) at which `fire` is called with the hit index.
func _begin(name: String, hits: Array, recover: float, fire: Callable, anim: String = "attack", heavy: bool = false, flash: bool = true) -> void:
	action = {"name": name, "t": 0.0, "hits": hits, "recover": recover, "fired": 0, "fire": fire, "anim": anim, "heavy": heavy}
	if flash:
		Effects.flash(en.model, Color(1.0, 0.5, 0.1, 0.38), float(hits[0]))

func _tick_action(dt: float) -> void:
	en.velocity.x = 0.0
	en.velocity.z = 0.0
	action["t"] = float(action["t"]) + dt
	var t: float = action["t"]
	var hits: Array = action["hits"]
	var fired: int = action["fired"]
	# keep aiming during the first wind-up, then the strike goes where it was pointed
	if fired == 0 and _valid(target):
		_face(_flat_to(target), dt, 8.0)
	while fired < hits.size() and t >= float(hits[fired]):
		var idx := fired
		fired += 1
		action["fired"] = fired
		var cb: Callable = action["fire"]
		cb.call(idx)
		if action.is_empty():
			return  # the callback replaced or cancelled the action
	_pose_action(t, dt)
	if t >= float(hits[hits.size() - 1]) + float(action["recover"]):
		_end_action()

func _end_action() -> void:
	action = {}
	Body.pose_reset(en.model)
	en.model.position.x = 0.0
	en.model.position.z = 0.0

func _pose_action(t: float, dt: float) -> void:
	var anim: String = action["anim"]
	var hits: Array = action["hits"]
	if anim == "cast":
		Body.pose_cast(en.model, t)
		return
	if anim == "draw":
		var first := float(hits[0])
		if t < first:
			Body.pose_draw(en.model, clampf(t / first, 0.0, 1.0))
		else:
			Body.pose_reset(en.model)
		return
	if anim == "spin" and t >= float(hits[0]):
		en.model.rotation.y += 22.0 * dt
		return
	# generic overhead swing: raise the arm in the 0.45 s before each hit, follow through after
	var k := 0
	while k < hits.size() and t >= float(hits[k]):
		k += 1
	var tp := 0.0
	var lunge := 0.0
	if k < hits.size():
		var start := 0.0 if k == 0 else float(hits[k - 1]) + 0.2
		var span := minf(float(hits[k]) - start, 0.45)
		var raise := clampf((t - (float(hits[k]) - span)) / maxf(span, 0.01), 0.0, 1.0)
		tp = 0.4 * raise
		lunge = -0.25 * raise
	else:
		var since := t - float(hits[hits.size() - 1])
		tp = 0.4 + 0.6 * clampf(since / 0.4, 0.0, 1.0)
		lunge = sin(clampf(since / 0.3, 0.0, 1.0) * PI) * 0.6
	if not Body.pose_attack(en.model, tp, bool(action["heavy"])):
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, en.model.rotation.y)
		en.model.position.x = fwd.x * lunge * en.size
		en.model.position.z = fwd.z * lunge * en.size

func _begin_melee() -> void:
	var w := clampf(atk_cd * 0.38, 0.28, 0.65)
	if en.is_boss:
		w = maxf(w, 0.4)
	cd["attack"] = atk_cd + randf_range(0.0, 0.3)
	_begin("melee", [w], maxf(atk_cd - w, 0.25), func(_i: int) -> void: _fire_melee(1.0), "attack", en.size >= 1.5)

func _fire_melee(mult: float) -> void:
	var t: Node3D = target
	if not _valid(t):
		return
	Audio.play("swing", -8.0)
	var to := _flat_to(t)
	var gap: float = to.length() - _rad(t) - float(en.radius)
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, en.model.rotation.y)
	if gap <= atk_range + 0.5 and fwd.dot(to.normalized()) > 0.25:
		_hurt(t, en.dmg * mult, "melee")

func _begin_throw() -> void:
	cd["attack"] = atk_cd + randf_range(1.0, 2.0)
	_begin("throw", [0.8], 0.6, func(_i: int) -> void: _fire_projectile("", 0.8, 1.0), "attack", true)

func _begin_shot() -> void:
	var caster := kind in ["caster", "summoner", "boss"]
	var w := 0.6 if caster else 0.5
	cd["attack"] = atk_cd + randf_range(0.0, 0.4)
	_begin("shot", [w], maxf(atk_cd - w, 0.3), func(_i: int) -> void: _fire_projectile(), "cast" if caster else "draw")

# ---------- hurting things ----------
func _hurt(t: Node3D, amount: float, hit_kind: String = "melee", from_pos: Vector3 = Vector3.INF) -> float:
	if not _valid(t):
		return 0.0
	var dealt := 0.0
	if t.is_in_group("player"):
		dealt = float(t.take_damage(amount, en.display_name(), en, hit_kind, from_pos))
		if dealt > 0.0:
			_after_player_hit(dealt)
	else:
		dealt = float(t.take_damage(amount, en, ""))
	if dealt > 0.0 and float(d.get("drain", 0.0)) > 0.0:
		en.hp = minf(en.hp_max, en.hp + dealt * float(d["drain"]))
	return dealt

func _after_player_hit(_dealt: float) -> void:
	var poison := float(d.get("poison", 0.0))
	if poison > 0.0:
		Game.hero.poison = minf(15.0, float(Game.hero.poison) + poison)

func _fire_projectile(kind_override: String = "", dmg_mult: float = 1.0, speed_mult: float = 1.0) -> void:
	var t: Node3D = target
	if not _valid(t) or Game.world == null:
		return
	var pk := proj_kind if kind_override == "" else kind_override
	var info: Dictionary = PROJ.get(pk, {"speed": 13.0, "color": "#ffe9b0"})
	var speed: float = float(info["speed"]) * speed_mult
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, en.model.rotation.y)
	var origin: Vector3 = en.center() + Vector3(0, 0.3, 0) + fwd * (en.radius + 0.3)
	var aim := _aim_point(t, speed, origin)
	var dir := (aim - origin).normalized()
	_spawn_projectile(origin, dir, pk, info, en.dmg * dmg_mult, speed)

func _spawn_projectile(origin: Vector3, dir: Vector3, pk: String, info: Dictionary, amount: float, speed: float) -> void:
	var me = en
	var nm: String = en.display_name()
	var hostile_to_enemies: bool = en.is_ally or en.is_charmed()
	var rng := (throw_range if throw_range > 0.0 else atk_range) + 10.0
	Game.world.spawn_projectile({
		"pos": origin, "dir": dir, "speed": speed, "range": rng, "kind": pk,
		"color": Color(str(info.get("color", "#ffe9b0"))), "radius": 0.9 if pk == "rock" else 0.5,
		"from_player": hostile_to_enemies, "from_enemy": true,
		"on_hit": func(tgt, proj) -> void: _proj_hit(tgt, amount, pk, nm, me, proj.global_position)})

func _proj_hit(tgt, amount: float, pk: String, nm: String, me, hit_pos: Vector3) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	var attacker = me if (me != null and is_instance_valid(me)) else null
	if tgt.is_in_group("player"):
		var dealt := float(tgt.take_damage(amount, nm, attacker, "projectile", hit_pos))
		if dealt > 0.0:
			if attacker != null:
				_after_player_hit(dealt)
			if pk == "scream":
				Game.add_buff("speed", 0.6, 2.5)
	else:
		tgt.take_damage(amount, attacker, "")

## Where to shoot: the target's chest, with half a lead for movers (so walking players can be hit
## but a sudden sidestep or roll still dodges it).
func _aim_point(t: Node3D, speed: float, origin: Vector3) -> Vector3:
	var pos: Vector3
	var vel := Vector3.ZERO
	if t.is_in_group("player"):
		pos = t.global_position + Vector3(0, 1.1, 0)
		vel = Vector3(t.velocity.x, 0, t.velocity.z)
	else:
		pos = t.center()
	return pos + vel * (origin.distance_to(pos) / maxf(speed, 1.0)) * 0.5

# =====================================================================
# Specials: leap, teleport, summon, boss abilities
# =====================================================================
func _try_special(t: Node3D, dist: float, dir: Vector3) -> bool:
	if bool(d.get("leap", false)) and float(cd["leap"]) <= 0.0 and dist > 4.5 and dist < 13.0 and en.is_on_floor() and not en.flying:
		_begin_leap(t, false)
		return true
	if bool(d.get("teleport", false)) and abilities.is_empty() and float(cd["tele"]) <= 0.0 and dist > 7.0:
		_do_teleport(t)
		return false
	if not d.get("summons", []).is_empty() and _try_summon():
		return true
	if not abilities.is_empty():
		return _try_ability(t, dist)
	return false

func _try_summon() -> bool:
	if float(cd["summon"]) > 0.0:
		return false
	minions = minions.filter(func(m) -> bool: return is_instance_valid(m) and not m.dead)
	if minions.size() >= int(d.get("summon_max", 2)):
		return false
	cd["summon"] = float(d.get("summon_cd", 10.0))
	_begin("summon", [0.9], 0.5, func(_i: int) -> void: _do_summon(), "cast")
	return true

func _do_summon() -> void:
	var w = Game.world
	var list: Array = d.get("summons", [])
	if w == null or list.is_empty():
		return
	var eid: String = list.pick_random()
	var ang := randf() * TAU
	var pos: Vector3 = en.global_position + Vector3(cos(ang), 0, sin(ang)) * (en.radius + 1.8)
	pos.y = w.height_at(pos.x, pos.z) + 0.3
	var m = w.spawn_enemy(eid, pos, {"respawn": false, "no_reward": true, "arena": en.arena})
	if m != null:
		minions.append(m)
		if _valid(target):
			m.ai.provoke(target)
	Effects.ring(w, en.global_position, 3.0, Color("#9ef0e0"), 0.6)
	Audio.play("summon", -4.0)

func _do_teleport(t: Node3D) -> void:
	var w = Game.world
	if w == null:
		return
	cd["tele"] = randf_range(5.0, 8.0)
	var away := Vector3(en.global_position.x - t.global_position.x, 0, en.global_position.z - t.global_position.z)
	if away.length() < 0.1:
		away = Vector3(0, 0, 1)
	var pos: Vector3 = t.global_position + away.normalized().rotated(Vector3.UP, PI + randf_range(-0.6, 0.6)) * 2.6
	pos.y = w.height_at(pos.x, pos.z) + 0.3
	Effects.ring(w, en.global_position, 1.6, Color("#c9b3ff"), 0.4)
	en.global_position = pos
	en.velocity = Vector3.ZERO
	Effects.ring(w, pos, 1.6, Color("#c9b3ff"), 0.4)
	Audio.play("teleport", -8.0)
	cd["attack"] = minf(float(cd["attack"]), 0.3)

func _begin_leap(t: Node3D, slam: bool) -> void:
	var to := _flat_to(t)
	var dist := to.length()
	var v0 := 7.0 if slam else 4.2
	var air := 2.0 * v0 / 12.0
	leap_dir = to.normalized()
	leap_speed = clampf(dist - (0.0 if slam else 1.0), 1.0, 16.0) / air
	leap_t = 0.0
	leap_slam = slam
	leaping = true
	cd["leap"] = randf_range(5.0, 8.0)
	en.velocity.y = v0
	Effects.flash(en.model, Color(1.0, 0.5, 0.1, 0.38), 0.3)

func _tick_leap(dt: float) -> void:
	leap_t += dt
	en.velocity.x = leap_dir.x * leap_speed * en.tf
	en.velocity.z = leap_dir.z * leap_speed * en.tf
	Body.pose_cast(en.model, leap_t)
	if (leap_t > 0.15 and en.is_on_floor()) or leap_t > 2.5:
		leaping = false
		Body.pose_reset(en.model)
		var r := 6.0 if leap_slam else 2.4
		var w = Game.world
		Effects.ring(w, en.global_position, r, Color("#d9a066"), 0.45)
		Audio.play("hit_heavy", -4.0)
		for c in _candidates():
			if _flat_len(c) - _rad(c) - en.radius <= r:
				_hurt(c, en.dmg * (1.2 if leap_slam else 0.9), "melee")
		cd["attack"] = maxf(float(cd["attack"]), 0.6)

func _ability_ok(a: String, dist: float) -> bool:
	match a:
		"whirlwind":
			return dist <= 4.0
		"double_strike":
			return dist <= atk_range + 0.5
		"vajra":
			return dist >= 3.0 and dist <= 30.0
		"kavacha":
			return not en.is_shielded() and en.hp < en.hp_max * 0.75
		"teleport":
			return dist > 8.0
		"blade_fan":
			return dist >= 4.0 and dist <= 24.0
		"kalagni":
			return dist <= 9.0
		"fire_breath":
			return dist <= 10.0
		"tail_sweep":
			return dist <= 5.0
		"fly_phase":
			return dist >= 6.0 and dist <= 22.0 and en.is_on_floor()
	return false

func _try_ability(t: Node3D, dist: float) -> bool:
	if float(cd["ability"]) > 0.0:
		return false
	var opts: Array = []
	for a in abilities:
		if float(cd.get("ab_" + str(a), 0.0)) <= 0.0 and _ability_ok(str(a), dist):
			opts.append(str(a))
	if opts.is_empty():
		return false
	var pick: String = opts.pick_random()
	cd["ability"] = randf_range(2.5, 4.0)
	cd["ab_" + pick] = float(ABILITY_CD.get(pick, 10.0))
	return _run_ability(pick, t)

func _run_ability(a: String, t: Node3D) -> bool:
	var w = Game.world
	var pos: Vector3 = en.global_position
	var orange := Color("#ff7a1a")
	match a:
		"whirlwind":
			Effects.ring(w, pos, 3.8, orange, 0.7)
			_begin("whirlwind", [0.7], 0.55, func(_i: int) -> void: _area_hit(3.8, 0.9, "melee"), "spin", true)
		"double_strike":
			cd["attack"] = atk_cd + 0.6
			_begin("double", [0.4, 0.85], 0.4, func(_i: int) -> void: _fire_melee(0.85), "attack", false)
		"vajra":
			var spot: Vector3 = t.global_position
			Effects.ring(w, spot, 2.2, Color("#7fdbff"), 0.9)
			_begin("vajra", [0.9], 0.5, func(_i: int) -> void: _lightning_at(spot), "cast")
		"kavacha":
			_begin("kavacha", [0.5], 0.4, func(_i: int) -> void: en.raise_shield(5.0, 0.75), "cast", false, false)
		"teleport":
			_do_teleport(t)
			return false
		"blade_fan":
			_begin("fan", [0.7], 0.5, func(_i: int) -> void: _blade_fan(), "cast")
		"kalagni":
			Effects.ring(w, pos, 7.0, Color("#b30000"), 1.2)
			_begin("kalagni", [1.2], 0.6, func(_i: int) -> void: _kalagni(), "cast", true)
		"fire_breath":
			Effects.wedge(w, pos, Vector3(0, 0, -1).rotated(Vector3.UP, en.model.rotation.y), 9.0, 0.5, orange, 0.9)
			_begin("breath", [0.9, 1.25, 1.6], 0.5, func(_i: int) -> void: _fire_breath(), "attack", true)
		"tail_sweep":
			Effects.ring(w, pos, 5.0, orange, 0.6)
			_begin("tail", [0.6], 0.5, func(_i: int) -> void: _area_hit(5.0, 0.8, "melee", 9.0), "spin", true)
		"fly_phase":
			_begin_leap(t, true)
	return true

## Damage everything of the other side within `radius` of the enemy (surface to surface).
func _area_hit(radius: float, mult: float, hit_kind: String, knock: float = 0.0) -> void:
	var w = Game.world
	Effects.ring(w, en.global_position, radius, Color("#ff7a1a"), 0.35)
	Audio.play("hit_heavy", -4.0)
	for c in _candidates():
		if _flat_len(c) - _rad(c) - en.radius <= radius:
			_hurt(c, en.dmg * mult, hit_kind)
			if knock > 0.0 and _valid(c) and c.is_in_group("player"):
				c.knock(_flat_to(c).normalized() * knock)

func _lightning_at(spot: Vector3) -> void:
	var w = Game.world
	Effects.bolt(w, spot + Vector3(0, 14, 0), spot, Color("#7fdbff"), 0.35)
	Effects.ring(w, spot, 2.2, Color("#7fdbff"), 0.3)
	Audio.play("lightning", -2.0)
	for c in _candidates():
		var cp: Vector3 = c.global_position
		if Vector2(cp.x - spot.x, cp.z - spot.z).length() - _rad(c) <= 2.2:
			_hurt(c, en.dmg * 1.1, "magic")

func _blade_fan() -> void:
	var t: Node3D = target
	if not _valid(t):
		return
	var info: Dictionary = PROJ["blade"]
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, en.model.rotation.y)
	var origin: Vector3 = en.center() + Vector3(0, 0.2, 0) + fwd * (en.radius + 0.3)
	for i in 7:
		var ang := deg_to_rad(-45.0 + 15.0 * float(i))
		_spawn_projectile(origin, fwd.rotated(Vector3.UP, ang), "blade", info, en.dmg * 0.55, 15.0)
	Audio.play("cast", -4.0)

func _kalagni() -> void:
	var w = Game.world
	Effects.ring(w, en.global_position, 7.0, Color("#b30000"), 0.5)
	Effects.sparks(w, en.global_position + Vector3(0, 1, 0), Color("#ff3b1a"), 12)
	Audio.play("fire", -2.0)
	for c in _candidates():
		if _flat_len(c) - _rad(c) - en.radius <= 7.0:
			_hurt(c, en.dmg * 1.3, "magic")

func _fire_breath() -> void:
	var w = Game.world
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, en.model.rotation.y)
	Effects.wedge(w, en.global_position, fwd, 9.0, 0.5, Color("#ff7a1a"), 0.3)
	Audio.play("fire", -6.0)
	for c in _candidates():
		var to := _flat_to(c)
		if to.length() - _rad(c) <= 9.0 + en.radius and fwd.dot(to.normalized()) > cos(0.5):
			_hurt(c, en.dmg * 0.5, "magic")

# =====================================================================
# Rising from the ground (preta)
# =====================================================================
func _rise(dt: float) -> void:
	_halt()
	var p := _player()
	if en.rise_t <= 0.0:
		if p != null and not p.dead and _flat_len(p) < 7.0:
			en.rise_t = 0.001
			Audio.play("roar", -14.0)
		return
	en.rise_t += dt
	var k := clampf(en.rise_t / 1.2, 0.0, 1.0)
	en.model.position.y = lerpf(en.hover - en.height - 0.2, en.hover, k)
	if k >= 1.0:
		en.rising = false
		en.collision_layer = 4
		if p != null:
			provoke(p)

# =====================================================================
# Movement helpers
# =====================================================================
func _halt() -> void:
	en.velocity.x = 0.0
	en.velocity.z = 0.0
	if walk_phase != 0.0:
		walk_phase = 0.0
		Body.pose_walk(en.model, 0.0, 0.0)

func _move(dir: Vector3, speed: float, dt: float) -> void:
	if en.is_rooted():
		_halt()
		return
	var v := Vector3(dir.x, 0, dir.z)
	if v.length() < 0.01:
		_halt()
		return
	v = v.normalized()
	if side_t > 0.0:
		side_t -= dt
		v = (v + side_dir).normalized()
	en.velocity.x = v.x * speed * en.tf
	en.velocity.z = v.z * speed * en.tf
	walk_phase += dt * speed * 1.6
	Body.pose_walk(en.model, walk_phase, 0.55)
	# walking into a wall or prop: slide off sideways for a moment
	stuck_t += dt
	if stuck_t >= 0.7:
		stuck_t = 0.0
		var moved: float = en.global_position.distance_to(last_pos)
		last_pos = en.global_position
		if moved < speed * 0.14 and not en.stationary and en.is_on_floor():
			side_t = 0.8
			side_dir = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized() * 1.2

## Turn the model towards a direction (models look down -Z).
func _face(dir: Vector3, dt: float, rate: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z)
	en.model.rotation.y = lerp_angle(en.model.rotation.y, want, clampf(dt * rate, 0.0, 1.0))

func _flat_to(t: Node3D) -> Vector3:
	return Vector3(t.global_position.x - en.global_position.x, 0, t.global_position.z - en.global_position.z)

func _flat_len(t: Node3D) -> float:
	return _flat_to(t).length()

func _home_gap() -> float:
	return Vector2(en.global_position.x - en.home_pos.x, en.global_position.z - en.home_pos.z).length()

func _rad(t: Node3D) -> float:
	if t.is_in_group("player"):
		return 0.4
	return float(t.radius)
