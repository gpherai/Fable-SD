## The hero's fighting: Prahara strikes, the Sankhala chain combo, Mahaprahara (hold to charge),
## Rakshana (block) and Pratiprahara (parry), bow and chakra, target lock, siddhi hotkeys and the
## Kavacha shield. A child node of the Player; Player.gd calls `tick()` every physics frame and
## routes incoming damage through `filter_incoming()` / `absorb()`.
##
## Input is polled (Input.is_action_*), never taken from events, so it works the same with a
## mouse, keys or the scripted input of the headless smoke test.
extends Node

const Body = preload("res://scripts/entities/Body.gd")
const Effects = preload("res://scripts/combat/Effects.gd")
const Props = preload("res://scripts/world/Props.gd")
const Siddhis = preload("res://scripts/combat/Siddhis.gd")

enum S { IDLE, SWING, CHARGE, BLOCK, CAST, MEDITATE }

const HOLD_TIME := 0.18          # holding attack longer than this starts a charge
const COMBO_WINDOW := 0.6
const PARRY_WINDOW := 0.25       # Pratiprahara: block pressed this shortly before the hit
const COMBAT_MULT_MAX := 10
const MEDITATE_OJAS_MULT := 4.0  # Dhyana: Ojas comes back this many times faster
const MEDITATE_SIT_TIME := 0.4
const COMBO_MULT := [1.0, 1.15, 1.6]
const LOCK_RANGE := 28.0
const UNARMED := {"dmg": 3.0, "speed": 1.6, "reach": 1.1, "arc": 100.0, "stun": 0.0, "element": "blunt",
	"sharp": 1.0, "bonus_flat": 0.0, "bonus_element": "", "drain": 0.0, "fear": 0.0, "pierce_def": 0.0}
const PHYSICAL := {"gada": "blunt", "lathi": "blunt", "trishula": "pierce", "katar": "pierce", "dhanush": "pierce", "mahadhanush": "pierce"}

var player  # Player.gd (untyped: Player.gd preloads this script)
var state: int = S.IDLE
var st_t: float = 0.0
var clock: float = 0.0
var swing: Dictionary = {}
var combo_step: int = 0
var combo_timer: float = 0.0
var buffered: float = 0.0
var atk_hold_active: bool = false
var atk_hold: float = 0.0
var shot_cd: float = 0.0
var aim_face := Vector3.ZERO
var blocking: bool = false
var block_t0: float = -10.0
var counter_until: float = 0.0
var lock: Node3D = null
var lock_marker: Node3D = null
var siddhi_ready: Dictionary = {}
var multi_arrows: int = 0
var multi_until: float = 0.0
var shield_hp: float = 0.0
var shield_until: float = 0.0
var shield_node: Node3D = null
var dash_left: float = 0.0
var dash_dir := Vector3.ZERO
var dash_dmg: float = 0.0
var dash_hit: Dictionary = {}
var leaping: bool = false
var leap_t: float = 0.0
var leap_p: Dictionary = {}
var summons: Array = []
var cast_dur: float = 0.35
var _posed: bool = false
var _full_cue: bool = false
var _atk_down: bool = false
var _atk_just: bool = false
var _atk_rel: bool = false
var _atk_prev: bool = false
var _blk_down: bool = false
var _ignore_atk: bool = false
var _ignore_blk: bool = false
var _was_active: bool = false
var sit_k: float = 0.0           # 0 standing .. 1 seated (Dhyana pose blend)
var _sitting: bool = false
var _med_prev: bool = false

# =====================================================================
# Frame
# =====================================================================
func tick(delta: float) -> void:
	clock += delta
	var active: bool = player._can_act()
	if not active:
		if _was_active:
			cancel()
		_was_active = false
		# a click that only re-captured the mouse must not become an attack
		_ignore_atk = Input.is_action_pressed("attack")
		_ignore_blk = Input.is_action_pressed("block")
		_end_modifiers(delta)
		return
	_was_active = true
	_read_inputs()
	combo_timer = maxf(0.0, combo_timer - delta)
	buffered = maxf(0.0, buffered - delta)
	shot_cd = maxf(0.0, shot_cd - delta)
	_update_lock(delta)
	var med := Input.is_action_pressed("meditate")
	if med and not _med_prev:
		_try_meditate()
	_med_prev = med
	if state == S.MEDITATE:
		# seated and defenceless: no attack, block or siddhi, only letting go of H (or rolling) ends it
		if not med:
			cancel()
		else:
			_tick_state(delta)
			_end_modifiers(delta)
			return
	if Input.is_action_just_pressed("lock_target"):
		_lock_pressed()
	if Input.is_action_just_pressed("ranged_toggle"):
		_toggle_stance()
	for i in 6:
		if Input.is_action_just_pressed("siddhi_%d" % (i + 1)):
			cast_siddhi(str(Game.hero.hotbar[i]))
	_block_input()
	_attack_input(delta)
	_tick_state(delta)
	_end_modifiers(delta)

func _read_inputs() -> void:
	_atk_down = Input.is_action_pressed("attack")
	_atk_just = Input.is_action_just_pressed("attack")
	_atk_rel = Input.is_action_just_released("attack")
	_blk_down = Input.is_action_pressed("block")
	# also derive the edges ourselves, in case the engine's just-pressed flag lands on another frame
	_atk_just = _atk_just or (_atk_down and not _atk_prev)
	_atk_rel = _atk_rel or (not _atk_down and _atk_prev)
	_atk_prev = _atk_down
	if _ignore_atk:
		if _atk_down:
			_atk_down = false
			_atk_just = false
			_atk_rel = false
		else:
			_ignore_atk = false
	if _ignore_blk:
		if _blk_down:
			_blk_down = false
		else:
			_ignore_blk = false

## Things that run whether or not the hero can act: shield timer, dash, leap, buffs.
func _end_modifiers(delta: float) -> void:
	if shield_hp > 0.0 and clock >= shield_until:
		_drop_shield()
	if shield_node != null:
		shield_node.rotation.y += delta * 1.5
	if multi_arrows > 0 and clock >= multi_until:
		multi_arrows = 0
	_tick_dash(delta)
	_tick_leap(delta)
	_tick_scale(delta)
	sit_k = move_toward(sit_k, 1.0 if state == S.MEDITATE else 0.0, delta / MEDITATE_SIT_TIME)
	summons = summons.filter(func(s) -> bool: return is_instance_valid(s) and not s.dead)

func is_idle() -> bool:
	return state == S.IDLE

func cancel() -> void:
	state = S.IDLE
	st_t = 0.0
	swing = {}
	blocking = false
	atk_hold_active = false
	buffered = 0.0
	_full_cue = false

func reset() -> void:
	cancel()
	combo_step = 0
	combo_timer = 0.0
	counter_until = 0.0
	release_lock()
	_drop_shield()
	dash_left = 0.0
	leaping = false
	multi_arrows = 0

func on_died() -> void:
	reset()

# =====================================================================
# Weapons
# =====================================================================
func ranged_stance() -> bool:
	return bool(Game.hero.get("ranged_stance", false)) and Game.equipped("ranged") != ""

func melee_profile() -> Dictionary:
	var wid: String = Game.equipped("melee")
	if wid == "":
		return UNARMED.duplicate()
	var it: Dictionary = Data.item(wid)
	var wtype := str(it.get("wtype", ""))
	var wt: Dictionary = Data.weapon_types.get(wtype, {})
	var p: Dictionary = UNARMED.duplicate()
	p["dmg"] = float(it.get("dmg", 5))
	p["speed"] = float(it.get("speed", 1.0))
	p["reach"] = float(it.get("reach", wt.get("reach", 1.6)))
	p["arc"] = float(it.get("arc", wt.get("arc", 100)))
	p["stun"] = float(it.get("stun", wt.get("stun", 0.0)))
	p["element"] = PHYSICAL.get(wtype, "")
	_apply_augs(p, wid)
	return p

func ranged_profile() -> Dictionary:
	var wid: String = Game.equipped("ranged")
	var it: Dictionary = Data.item(wid)
	var wtype := str(it.get("wtype", ""))
	var wt: Dictionary = Data.weapon_types.get(wtype, {})
	var p: Dictionary = UNARMED.duplicate()
	var proj := str(it.get("projectile", wt.get("projectile", "arrow")))
	p["dmg"] = float(it.get("dmg", 8))
	p["speed"] = float(it.get("speed", 1.0))
	p["range"] = float(it.get("range", wt.get("range", 28)))
	p["projectile"] = "chakra" if proj == "disc" else proj
	p["pierce"] = bool(it.get("pierce", wt.get("pierce", false))) or proj == "disc"
	p["element"] = PHYSICAL.get(wtype, "")
	p["wtype"] = wtype
	_apply_augs(p, wid)
	return p

func _apply_augs(p: Dictionary, wid: String) -> void:
	for a in Game.weapon_augs(wid):
		var power := float(a.get("power", 0.0))
		match str(a.get("type", "")):
			"sacred":
				p["element"] = "sacred"
				p["sharp"] = float(p["sharp"]) * (1.0 + power)
			"sharp":
				p["sharp"] = float(p["sharp"]) * (1.0 + power)
			"fire", "lightning":
				p["bonus_flat"] = float(p["bonus_flat"]) + power
				p["bonus_element"] = str(a["type"])
			"drain":
				p["drain"] = float(p["drain"]) + power
			"fear":
				p["fear"] = float(p["fear"]) + power
			"pierce":
				p["pierce_def"] = float(p["pierce_def"]) + power

# =====================================================================
# Block
# =====================================================================
func _block_input() -> void:
	if _blk_down and not blocking and state != S.CAST and not player.rolling:
		cancel()
		state = S.BLOCK
		blocking = true
		block_t0 = clock
	elif not _blk_down and blocking:
		blocking = false
		if state == S.BLOCK:
			state = S.IDLE

## Applies Rakshana / Pratiprahara to an incoming hit. Returns {"amount", "blocked", "parried"}.
## Only melee and projectile hits from in front can be blocked; magic cannot.
func filter_incoming(amount: float, attacker, kind: String, from_pos: Vector3) -> Dictionary:
	var res := {"amount": amount, "blocked": false, "parried": false}
	if state != S.BLOCK or kind not in ["melee", "projectile"]:
		return res
	var src := from_pos
	if src == Vector3.INF and attacker != null and is_instance_valid(attacker):
		src = attacker.global_position
	if src == Vector3.INF:
		return res
	var to := Vector3(src.x - player.global_position.x, 0, src.z - player.global_position.z)
	if to.length() > 0.05 and facing().dot(to.normalized()) < cos(deg_to_rad(65.0)):
		return res
	res["blocked"] = true
	if kind == "projectile":
		res["amount"] = 0.0
	elif clock - block_t0 <= PARRY_WINDOW:
		res["parried"] = true
		res["amount"] = 0.0
	else:
		res["amount"] = amount * 0.2
	return res

func on_parry(attacker) -> void:
	Audio.play("block", 2.0)
	Audio.play("bell", -10.0)
	var pos: Vector3 = player.global_position + Vector3(0, 1.2, 0) + facing() * 0.8
	Effects.sparks(Game.world, pos, Color("#fff0b0"), 12)
	Effects.ring(Game.world, player.global_position, 2.4, Color("#fff0b0"), 0.3)
	var nm: String = str(Loc.t(Data.moves.get("pratiprahara", {}).get("name", {}))).split(" (")[0]
	Effects.popup(Game.world, player.global_position + Vector3(0, 2.3, 0), nm + "!", Color("#ffe27a"))
	counter_until = clock + 4.0
	if attacker != null and is_instance_valid(attacker) and attacker.has_method("stagger"):
		attacker.stagger(0.9 if bool(attacker.is_boss) else 1.6)

func on_blocked(pos_hint: Vector3) -> void:
	Audio.play("block")
	Effects.sparks(Game.world, player.global_position + Vector3(0, 1.2, 0) + facing() * 0.7, Color("#d8e0ff"), 6)

# =====================================================================
# Kavacha shield
# =====================================================================
func add_shield(absorb: float, duration: float) -> void:
	shield_hp = absorb
	shield_until = clock + duration
	if shield_node == null:
		shield_node = Node3D.new()
		shield_node.add_child(Props.sphere(1.0, Color("#ffe27a"), Vector3(0, 1.0, 0), Vector3.ONE, 0.4, 0.0, Color(1.0, 0.85, 0.3, 0.7), 0.25))
		player.add_child(shield_node)
	shield_node.visible = true

## Soaks damage into the shield first; returns what is left over.
func absorb(amount: float) -> float:
	if shield_hp <= 0.0:
		return amount
	var soaked := minf(shield_hp, amount)
	shield_hp -= soaked
	Audio.play("shield", -8.0)
	if shield_hp <= 0.0:
		_drop_shield()
		Effects.sparks(Game.world, player.global_position + Vector3(0, 1.0, 0), Color("#ffe27a"), 10)
	return amount - soaked

func _drop_shield() -> void:
	shield_hp = 0.0
	if shield_node != null:
		shield_node.visible = false

func on_damaged(amount: float) -> void:
	if state == S.MEDITATE:
		cancel()   # a blow breaks Dhyana
	# a hit breaks a charge or a bow draw, but not a light swing
	if state == S.CHARGE:
		cancel()
	Effects.flash(player.model, Color(1.0, 0.2, 0.2, 0.4), 0.12)

# =====================================================================
# Attack input and state machine
# =====================================================================
func _attack_input(delta: float) -> void:
	if state == S.BLOCK or state == S.CAST:
		return
	var ranged := ranged_stance()
	if ranged:
		_ranged_input()
		return
	match state:
		S.IDLE:
			if _atk_just:
				atk_hold_active = true
				atk_hold = 0.0
			if atk_hold_active:
				if _atk_rel or not _atk_down:
					atk_hold_active = false
					_start_melee(false, 0.0)
				else:
					atk_hold += delta
					if atk_hold >= HOLD_TIME:
						atk_hold_active = false
						state = S.CHARGE
						st_t = 0.0
						_full_cue = false
						aim_face = _pick_aim_face(melee_profile())
		S.SWING:
			if _atk_just:
				buffered = 0.35
		S.CHARGE:
			if _atk_rel or not _atk_down:
				var frac := clampf(st_t / 1.0, 0.0, 1.0)
				if st_t < 0.3:
					_start_melee(false, 0.0)
				else:
					_start_melee(true, frac)

func _tick_state(delta: float) -> void:
	match state:
		S.SWING:
			st_t += delta
			if str(swing.get("kind", "melee")) == "melee":
				if not bool(swing["done"]) and st_t >= float(swing["hit_t"]):
					swing["done"] = true
					_melee_strike()
				var dur: float = swing["dur"]
				if bool(swing["done"]) and buffered > 0.0 and st_t >= dur * 0.7 and not bool(swing["heavy"]):
					buffered = 0.0
					_start_melee(false, 0.0)
					return
				if st_t >= dur:
					state = S.IDLE
					combo_timer = COMBO_WINDOW
					if int(swing.get("step", 0)) >= 3:
						combo_step = 0
					swing = {}
			else:
				if st_t >= float(swing["dur"]):
					state = S.IDLE
					swing = {}
		S.CHARGE:
			st_t += delta
			if not ranged_stance() and st_t >= 1.0 and not _full_cue:
				_full_cue = true
				Audio.play("ui_open", -6.0)
				Effects.flash(player.model, Color(1.0, 0.85, 0.3, 0.35), 0.15)
		S.CAST:
			st_t += delta
			if st_t >= cast_dur:
				state = S.IDLE
		S.BLOCK:
			st_t += delta
		S.MEDITATE:
			var rings := int(st_t / 1.6)
			st_t += delta
			if int(st_t / 1.6) != rings:
				Effects.ring(Game.world, player.global_position + Vector3(0, 0.05, 0), 1.6, Color("#7ec8ff"), 0.9)

# =====================================================================
# Dhyana (hold H): sit in lotus pose, Ojas returns four times as fast, but you are defenceless
# =====================================================================
func _try_meditate() -> void:
	if state != S.IDLE or player.rolling or player.forced_left > 0.0 or leaping or dash_left > 0.0 or not player.is_on_floor():
		return
	cancel()
	state = S.MEDITATE
	st_t = 0.0
	Events.notify.emit(Loc.t("UI_MEDITATING"), "info")
	Audio.play("ui_open", -6.0)
	Effects.ring(Game.world, player.global_position + Vector3(0, 0.05, 0), 1.6, Color("#7ec8ff"), 0.9)

func is_meditating() -> bool:
	return state == S.MEDITATE

func ojas_regen_mult() -> float:
	return MEDITATE_OJAS_MULT if state == S.MEDITATE else 1.0

func move_mult() -> float:
	match state:
		S.SWING:
			return 0.45
		S.CHARGE:
			return 0.5
		S.BLOCK:
			return 0.45
		S.CAST:
			return 0.55
		S.MEDITATE:
			return 0.0
	return 1.0

# =====================================================================
# Melee
# =====================================================================
func _start_melee(heavy: bool, charge: float) -> void:
	var prof := melee_profile()
	var spd := float(prof["speed"]) * Game.buff_mult("attack_speed")
	if combo_timer <= 0.0:
		combo_step = 0
	var step := 0
	if not heavy:
		combo_step = (combo_step % 3) + 1
		step = combo_step
	else:
		combo_step = 0
	var dur := clampf(0.5 / spd, 0.2, 1.0) * (1.4 if heavy else 1.0)
	var mult := 1.0 + 1.5 * charge if heavy else float(COMBO_MULT[maxi(step, 1) - 1])
	swing = {"kind": "melee", "dur": dur, "hit_t": dur * 0.45, "mult": mult, "heavy": heavy, "step": step, "done": false, "prof": prof}
	state = S.SWING
	st_t = 0.0
	atk_hold_active = false
	aim_face = _pick_aim_face(prof)
	player.face_now(aim_face)
	Audio.play("swing_heavy" if (heavy or step == 3) else "swing", -4.0, 1.0 + 0.08 * float(step))

func _melee_strike() -> void:
	var prof: Dictionary = swing["prof"]
	var heavy: bool = swing["heavy"]
	var step: int = swing["step"]
	var targets := melee_targets(prof)
	if targets.is_empty():
		return
	var counter := clock < counter_until
	var base: float = float(prof["dmg"]) * float(prof["sharp"]) * Game.melee_mult() * float(swing["mult"]) * (2.0 if counter else 1.0)
	var pos: Vector3 = player.global_position
	var n := 0
	for e in targets:
		if n >= 4:
			break
		n += 1
		var away := Vector3(e.global_position.x - pos.x, 0, e.global_position.z - pos.z).normalized()
		var knock := away * 3.0
		var stun := 0.0
		if step == 3:
			knock = away * 8.0
			stun = 1.4 if e.size <= 1.2 else 0.3
		if heavy:
			knock = away * 7.0
			stun = 0.9
		if randf() < float(prof["stun"]):
			stun = maxf(stun, 0.8)
		var opts := {"knock": knock, "stun": stun, "break_guard": heavy, "pierce_def": float(prof["pierce_def"]), "fist": Game.equipped("melee") == ""}
		var dealt: float = e.take_damage(base, player, str(prof["element"]), opts)
		if float(prof["bonus_flat"]) > 0.0 and not e.dead:
			e.take_damage(float(prof["bonus_flat"]) * Game.melee_mult(), player, str(prof["bonus_element"]), {"dot": true})
		_on_weapon_effects(e, dealt, prof)
		if n == 1:
			Effects.sparks(Game.world, e.center(), Color("#fff0c0") if not heavy else Color("#ffd24a"), 6 if not heavy else 12)
	if heavy:
		Audio.play("hit_heavy", -2.0)
		Effects.ring(Game.world, player.global_position + facing() * 1.2, 1.8, Color("#ffd24a"), 0.3)
	if counter:
		counter_until = 0.0
	register_hit()

## Drain and fear from the weapon's augments.
func _on_weapon_effects(e, dealt: float, prof: Dictionary) -> void:
	if dealt <= 0.0:
		return
	var dr := float(prof["drain"])
	if dr > 0.0 and "drain" not in e.data.get("resist", []):
		Game.heal(dealt * dr)
	var fr := float(prof["fear"])
	if fr > 0.0 and randf() < fr:
		e.frighten(2.5)

## Enemies the swing reaches: within weapon reach (body surface) and the weapon's arc.
func melee_targets(prof: Dictionary) -> Array:
	var out: Array = []
	var w = Game.world
	if w == null:
		return out
	var pos: Vector3 = player.global_position
	var reach := float(prof["reach"]) + 0.35
	var arc := float(prof["arc"])
	var fwd := facing()
	var cos_half := cos(deg_to_rad(arc) / 2.0) if arc < 359.0 else -2.0
	for e in w.enemies_in_radius(pos, reach + 4.0):
		if e.rising:
			continue
		var gap: float = e.flat_reach(pos, pos.y - 0.4, pos.y + 2.4)
		if gap > reach:
			continue
		var to := Vector3(e.global_position.x - pos.x, 0, e.global_position.z - pos.z)
		if gap > 0.3 and to.length() > 0.01 and fwd.dot(to.normalized()) < cos_half:
			continue
		out.append(e)
	out.sort_custom(func(a, b) -> bool: return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	return out

## Which way a swing points: the lock target, else a nearby enemy roughly in front, else the
## way the hero is already facing (or moving).
func _pick_aim_face(prof: Dictionary) -> Vector3:
	var pos: Vector3 = player.global_position
	if lock_valid():
		return _flat_dir(lock.global_position - pos)
	var base := facing()
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if v != Vector2.ZERO:
		base = Vector3(v.x, 0, v.y).rotated(Vector3.UP, player.yaw).normalized()
	var w = Game.world
	if w == null:
		return base
	var best = null
	var bd := float(prof["reach"]) + 2.5
	for e in w.enemies_in_radius(pos, bd + 3.0):
		if e.rising:
			continue
		var gap: float = e.flat_reach(pos, pos.y - 0.4, pos.y + 2.4)
		var to := _flat_dir(e.global_position - pos)
		if gap < bd and base.dot(to) > cos(deg_to_rad(80.0)):
			bd = gap
			best = e
	if best != null:
		return _flat_dir(best.global_position - pos)
	return base

func register_hit() -> void:
	if player.combat_mult < COMBAT_MULT_MAX:
		player.combat_mult += 1
		Events.combat_multiplier_changed.emit(player.combat_mult)

# =====================================================================
# Bow and chakra
# =====================================================================
func _toggle_stance() -> void:
	if Game.equipped("ranged") == "":
		Events.notify.emit(Loc.t("UI_NO_RANGED"), "bad")
		return
	cancel()
	Game.hero["ranged_stance"] = not bool(Game.hero.get("ranged_stance", false))
	player.rebuild_visual()
	Audio.play("equip")
	Events.hero_changed.emit()

func _ranged_input() -> void:
	var prof := ranged_profile()
	var is_chakra: bool = str(prof["projectile"]) == "chakra"
	if state == S.SWING:
		return
	if is_chakra:
		if _atk_down and shot_cd <= 0.0 and state == S.IDLE:
			_fire_shot(prof, 0.0)
		return
	match state:
		S.IDLE:
			if _atk_just and shot_cd <= 0.0:
				state = S.CHARGE
				st_t = 0.0
		S.CHARGE:
			if _atk_rel or not _atk_down:
				var frac := clampf(st_t / draw_time(prof), 0.0, 1.0)
				state = S.IDLE
				_fire_shot(prof, frac)

func draw_time(prof: Dictionary) -> float:
	return clampf(0.9 / (float(prof["speed"]) * Game.buff_mult("attack_speed")), 0.35, 1.6)

## Fire the equipped bow or chakra. frac is the bow draw (0..1); a full draw does double
## damage and pierces (Purna Akarshana). A chakra always pierces and needs no draw.
func _fire_shot(prof: Dictionary, frac: float) -> void:
	var w = Game.world
	if w == null:
		return
	var is_chakra: bool = str(prof["projectile"]) == "chakra"
	var origin: Vector3 = player.global_position + Vector3(0, 1.3, 0) + facing() * 0.5
	var dir := aim_direction(origin)
	player.face_now(_flat_dir(dir))
	var mult := 1.0 if is_chakra else lerpf(0.6, 2.0, frac)
	var full := frac >= 0.95
	var pierce: bool = bool(prof["pierce"]) or full
	var dmg: float = float(prof["dmg"]) * float(prof["sharp"]) * Game.ranged_mult() * mult * (2.0 if clock < counter_until else 1.0)
	var arrows := 1
	if multi_arrows > 0 and not is_chakra:
		arrows = multi_arrows
	var spread := deg_to_rad(7.0)
	for i in arrows:
		var off := (float(i) - float(arrows - 1) / 2.0) * spread
		var d := dir.rotated(Vector3.UP, off)
		w.spawn_projectile({
			"pos": origin, "dir": d, "speed": 22.0 if is_chakra else 34.0,
			"range": float(prof["range"]), "kind": str(prof["projectile"]),
			"radius": 0.6 if is_chakra else 0.45, "pierce": pierce, "from_player": true,
			"on_hit": func(e, proj) -> void: _ranged_hit(e, dmg, prof, proj, frac)})
	Audio.play("swing" if is_chakra else "bow", -2.0)
	shot_cd = clampf(0.45 / (float(prof["speed"]) * Game.buff_mult("attack_speed")), 0.2, 1.0)
	swing = {"kind": "shot", "dur": 0.2}
	state = S.SWING
	st_t = 0.0
	if clock < counter_until:
		counter_until = 0.0
	Game.quests.ranged_used()

func _ranged_hit(e, dmg: float, prof: Dictionary, proj, frac: float) -> void:
	if not is_instance_valid(e) or e.dead:
		return
	var knock: Vector3 = proj.dir * 2.0
	var stun := 0.0
	if str(prof.get("wtype", "")) == "mahadhanush" and frac >= 0.9:
		stun = 0.6
	var dealt: float = e.take_damage(dmg, player, str(prof["element"]), {"knock": knock, "stun": stun, "pierce_def": float(prof["pierce_def"])})
	if float(prof["bonus_flat"]) > 0.0 and not e.dead:
		e.take_damage(float(prof["bonus_flat"]) * Game.ranged_mult(), player, str(prof["bonus_element"]), {"dot": true})
	_on_weapon_effects(e, dealt, prof)
	Audio.play("arrow_hit", -4.0)
	register_hit()

## Where a shot or spell goes: at the lock target, else along the camera's centre ray (with a
## little pull towards an enemy close to that ray), as seen from `origin`.
func aim_direction(origin: Vector3) -> Vector3:
	if lock_valid():
		return (lock.center() - origin).normalized()
	var cam: Camera3D = player.cam
	var fwd := -cam.global_transform.basis.z
	var cpos := cam.global_position
	var point := cpos + fwd * 45.0
	var w = Game.world
	if w != null:
		var q := PhysicsRayQueryParameters3D.create(cpos, cpos + fwd * 60.0, 1)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			point = hit["position"]
		var best = null
		var best_ang := deg_to_rad(7.0)
		for e in w.enemies:
			if not is_instance_valid(e) or e.dead or e.rising:
				continue
			var to: Vector3 = e.center() - cpos
			if to.length() > 45.0 or to.length() < 1.0:
				continue
			var ang := fwd.angle_to(to.normalized())
			if ang < best_ang:
				best_ang = ang
				best = e
		if best != null:
			point = best.center()
	var d := (point - origin).normalized()
	if d.length() < 0.5:
		d = fwd
	return d

# =====================================================================
# Target lock (Lakshya Bandhana)
# =====================================================================
func lock_valid() -> bool:
	return lock != null and is_instance_valid(lock) and not lock.dead

func release_lock() -> void:
	lock = null
	if lock_marker != null and is_instance_valid(lock_marker):
		lock_marker.queue_free()
	lock_marker = null

func _lock_pressed() -> void:
	var w = Game.world
	if w == null:
		return
	var cam: Camera3D = player.cam
	var fwd := -cam.global_transform.basis.z
	var pos: Vector3 = player.global_position
	var cands: Array = []
	for e in w.enemies:
		if not is_instance_valid(e) or e.dead or e.rising:
			continue
		var d: float = e.global_position.distance_to(pos)
		if d > LOCK_RANGE:
			continue
		var ang := fwd.angle_to((e.center() - cam.global_position).normalized())
		cands.append({"e": e, "score": d + ang * 8.0})
	if cands.is_empty():
		release_lock()
		return
	cands.sort_custom(func(a, b) -> bool: return float(a["score"]) < float(b["score"]))
	var pick = cands[0]["e"]
	if lock_valid():
		var idx := -1
		for i in cands.size():
			if cands[i]["e"] == lock:
				idx = i
		if cands.size() == 1:
			release_lock()
			return
		pick = cands[(idx + 1) % cands.size()]["e"]
	_set_lock(pick)

func _set_lock(e: Node3D) -> void:
	release_lock()
	lock = e
	lock_marker = Node3D.new()
	lock_marker.add_child(Props.cone(0.16, 0.34, Color("#ff3b3b"), Vector3.ZERO, Vector3(PI, 0, 0), 4, 0.4))
	lock_marker.position = Vector3(0, float(e.height) + float(e.hover) + 0.95, 0)
	e.add_child(lock_marker)
	Audio.play("ui", -4.0)

func _update_lock(delta: float) -> void:
	if lock == null:
		return
	if not lock_valid() or lock.global_position.distance_to(player.global_position) > LOCK_RANGE + 8.0:
		release_lock()
		return
	if lock_marker != null:
		lock_marker.rotation.y += delta * 3.0
		lock_marker.position.y = float(lock.height) + float(lock.hover) + 0.95 + sin(clock * 5.0) * 0.06
	# the camera swings round so the hero and the target stay in view
	var to: Vector3 = lock.global_position - player.global_position
	var want := atan2(-to.x, -to.z)
	var k := 1.0 - exp(-6.0 * delta)
	player.yaw = lerp_angle(player.yaw, want, k)
	player.pitch = lerpf(player.pitch, -0.3, k)
	player._apply_look()

# =====================================================================
# Siddhis
# =====================================================================
func cooldown_left(id: String) -> float:
	return maxf(0.0, float(siddhi_ready.get(id, 0.0)) - clock)

func cast_siddhi(id: String) -> void:
	if id == "" or state == S.CAST:
		return
	var sd: Dictionary = Data.siddhi(id)
	if sd.is_empty() or Game.siddhi_level(id) <= 0:
		return
	if cooldown_left(id) > 0.0:
		return
	var p: Dictionary = Game.siddhi_params(id)
	var cost := float(p.get("cost", 0)) * Game.siddhi_cost_mult()
	if float(Game.hero.ojas) < cost:
		Events.notify.emit(Loc.t("UI_NO_OJAS"), "bad")
		Audio.play("block", -8.0)
		return
	cancel()
	Game.hero.ojas = float(Game.hero.ojas) - cost
	Events.hero_changed.emit()
	siddhi_ready[id] = clock + float(sd.get("cooldown", 1.0))
	Events.siddhi_cast.emit(id, int(p["level"]))
	state = S.CAST
	st_t = 0.0
	cast_dur = 0.35
	Audio.play("cast", -4.0)
	Siddhis.execute(self, id, sd, p)

# ---------- helpers for Siddhis.gd ----------
func facing() -> Vector3:
	return Vector3(0, 0, -1).rotated(Vector3.UP, player.model.rotation.y)

func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	if v.length() < 0.001:
		return facing() if player.model != null else Vector3(0, 0, -1)
	return v.normalized()

## Enemies whose body is within r of the point (3D, to the body surface).
func enemies_within(pos: Vector3, r: float) -> Array:
	var out: Array = []
	var w = Game.world
	if w == null:
		return out
	for e in w.enemies:
		if is_instance_valid(e) and not e.dead and not e.rising and e.hit_distance(pos) <= r:
			out.append(e)
	return out

## The enemy a targeted siddhi picks: the lock target, else the one nearest the camera's centre
## ray within `max_dist`.
func pick_target(max_dist: float):
	if lock_valid() and lock.global_position.distance_to(player.global_position) <= max_dist + 4.0:
		return lock
	var w = Game.world
	if w == null:
		return null
	var cam: Camera3D = player.cam
	var fwd := -cam.global_transform.basis.z
	var best = null
	var best_score := INF
	for e in w.enemies:
		if not is_instance_valid(e) or e.dead or e.rising:
			continue
		var d: float = e.global_position.distance_to(player.global_position)
		if d > max_dist:
			continue
		var ang := fwd.angle_to((e.center() - cam.global_position).normalized())
		if ang > deg_to_rad(60.0):
			continue
		var score := d + ang * 10.0
		if score < best_score:
			best_score = score
			best = e
	return best

## Damage from a siddhi: scaled by Siddhibala, registers a hit for the combat multiplier.
func deal_spell(e, amount: float, element: String, opts: Dictionary = {}) -> float:
	if e == null or not is_instance_valid(e) or e.dead:
		return 0.0
	var dealt: float = e.take_damage(amount * Game.siddhi_mult(), player, element, opts)
	if dealt > 0.0:
		register_hit()
	return dealt

func spawn_ally(eid: String, opts: Dictionary) -> Node:
	var w = Game.world
	if w == null:
		return null
	var ang := randf() * TAU
	var pos: Vector3 = player.global_position + Vector3(cos(ang), 0, sin(ang)) * 2.2
	pos.y = w.height_at(pos.x, pos.z) + 0.3
	var a = w.spawn_enemy(eid, pos, opts)
	if a != null:
		summons.append(a)
	return a

# ---------- dash (Vrishabha Vega) and leap (Hanuman Langhana) ----------
func begin_dash(dir: Vector3, distance: float, dmg: float) -> void:
	var speed := 20.0
	dash_dir = dir.normalized()
	dash_left = distance / speed
	dash_dmg = dmg
	dash_hit = {}
	player.begin_forced_move(dash_dir, speed, dash_left)
	player.face_now(dash_dir)

func _tick_dash(delta: float) -> void:
	if dash_left <= 0.0:
		return
	dash_left -= delta
	var pos: Vector3 = player.global_position
	for e in enemies_within(pos + Vector3(0, 1.0, 0), 0.9):
		var id: int = e.get_instance_id()
		if dash_hit.has(id):
			continue
		dash_hit[id] = true
		var side := dash_dir.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
		deal_spell(e, dash_dmg, "earth", {"knock": dash_dir * 3.0 + side * 4.0, "stun": 0.6})
		Effects.sparks(Game.world, e.center(), Color("#d9a066"), 8)
		Audio.play("hit_heavy", -4.0)

func begin_leap(dir: Vector3, distance: float, p: Dictionary) -> void:
	var v0 := 6.0
	var air := 2.0 * v0 / 12.0
	leap_p = p
	leap_t = 0.0
	leaping = true
	player.velocity.y = v0
	player.begin_forced_move(dir.normalized(), distance / air, air + 0.6)
	player.face_now(dir)

func _tick_leap(delta: float) -> void:
	if not leaping:
		return
	leap_t += delta
	if (leap_t > 0.2 and player.is_on_floor()) or leap_t > 2.5:
		leaping = false
		player.end_forced_move()
		var r := float(leap_p.get("radius", 3.0))
		var pos: Vector3 = player.global_position
		Effects.ring(Game.world, pos, r, Color("#ffb347"), 0.45)
		Effects.sparks(Game.world, pos + Vector3(0, 0.3, 0), Color("#ffb347"), 10)
		Audio.play("hit_heavy", -2.0)
		for e in enemies_within(pos + Vector3(0, 0.5, 0), r):
			var away := Vector3(e.global_position.x - pos.x, 0, e.global_position.z - pos.z).normalized()
			deal_spell(e, float(leap_p.get("dmg", 20)), "air", {"knock": away * 6.0, "stun": 0.7})

# ---------- growing during Ugra Rupa ----------
func _tick_scale(delta: float) -> void:
	var m: Node3D = player.model
	if m == null:
		return
	if not m.has_meta("base_scale"):
		m.set_meta("base_scale", m.scale)
	var base: Vector3 = m.get_meta("base_scale")
	var want := base * (1.25 if Game.buff_active("ugra") else 1.0)
	m.scale = m.scale.lerp(want, clampf(delta * 6.0, 0.0, 1.0))

# =====================================================================
# Posing (called by Player._animate after the walk cycle)
# =====================================================================
func apply_pose() -> void:
	var m: Node3D = player.model
	if m == null:
		return
	match state:
		S.SWING:
			if str(swing.get("kind", "melee")) == "melee":
				var dur: float = swing["dur"]
				Body.pose_attack(m, clampf(st_t / dur, 0.0, 1.0), bool(swing["heavy"]))
			else:
				Body.pose_draw(m, 0.0)
			_posed = true
		S.CHARGE:
			if ranged_stance():
				Body.pose_draw(m, clampf(st_t / draw_time(ranged_profile()), 0.0, 1.0))
			else:
				Body.pose_attack(m, 0.39, true)
			_posed = true
		S.BLOCK:
			Body.pose_block(m)
			_posed = true
		S.CAST:
			Body.pose_cast(m, st_t)
			_posed = true
		S.MEDITATE:
			Body.pose_sit(m, sit_k)
			_sitting = true
			_posed = true
		_:
			if _sitting:
				# standing up again: blend out, then drop back to the plain pose
				Body.pose_sit(m, sit_k)
				if sit_k <= 0.0:
					_sitting = false
					Body.pose_reset(m)
					_posed = false
			elif ranged_stance():
				Body.pose_draw(m, 0.0)
				_posed = true
			elif _posed:
				Body.pose_reset(m)
				_posed = false

## Direction the hero should face right now, or ZERO to follow the movement keys.
func facing_override() -> Vector3:
	var cam_fwd := Vector3(0, 0, -1).rotated(Vector3.UP, player.yaw)
	if (state == S.SWING and str(swing.get("kind", "melee")) == "melee") or (state == S.CHARGE and not ranged_stance()):
		if aim_face != Vector3.ZERO:
			return aim_face
	if lock_valid():
		return _flat_dir(lock.global_position - player.global_position)
	if ranged_stance() or state == S.BLOCK or state == S.CAST:
		return cam_fwd
	return Vector3.ZERO
