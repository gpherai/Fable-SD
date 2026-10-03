## What each siddhi in data/siddhis.json actually does when cast. PlayerCombat.cast_siddhi has
## already checked the level, cooldown and Ojas and paid the cost; `execute` does the effect.
## Numbers (dmg, radius, duration, ...) come from the siddhi's level in the data file.
extends RefCounted

const Effects = preload("res://scripts/combat/Effects.gd")

const SACRED_FAMILIES := ["preta", "rakshasa", "asura"]

## c: the PlayerCombat node, id: siddhi id, sd: its data, p: the current level's parameters.
static func execute(c, id: String, sd: Dictionary, p: Dictionary) -> void:
	var player = c.player
	var w = Game.world
	if w == null:
		return
	var color := Color(str(sd.get("color", "#ffffff")))
	var pos: Vector3 = player.global_position
	var chest := pos + Vector3(0, 1.3, 0)
	match id:
		"agni_astra":
			_fireball(c, chest, p)
		"vajra":
			_chain_lightning(c, chest, p, color)
		"vayu_astra":
			_cone_push(c, pos, chest, p, color)
		"kala_stambhana":
			w.slow_time(float(p["duration"]), float(p["factor"]))
			Effects.ring(w, pos, 9.0, color, 0.8)
			Audio.play("teleport", -6.0)
		"kavacha":
			c.add_shield(float(p["absorb"]), float(p["duration"]))
			Effects.ring(w, pos, 2.2, color, 0.5)
			Audio.play("shield")
		"ugra_rupa":
			Game.add_buff("ugra", float(p["mult"]), float(p["duration"]))
			Effects.ring(w, pos, 3.0, color, 0.6)
			Effects.sparks(w, pos + Vector3(0, 1.0, 0), color, 10)
			Audio.play("roar", -2.0)
		"vrishabha_vega":
			var dir := _flat(c.aim_direction(chest))
			c.begin_dash(dir, float(p["distance"]), float(p["dmg"]))
			Audio.play("roar", -8.0)
		"chhaya_gati":
			_shadow_strike(c, pos, p, color)
		"sanjivani":
			_heal(c, pos, p, color)
		"bhuta_ahvana":
			_summon(c, "bhuta_sevak", p, 2, {"lifetime": float(p["duration"]), "hp_mult": 1.0 + 0.5 * float(int(p["level"]) - 1), "dmg_mult": 1.0 + 0.5 * float(int(p["level"]) - 1)})
			Effects.ring(w, pos, 2.5, color, 0.6)
			Audio.play("summon")
		"mohini_maya":
			_charm(c, pos, p, color)
		"agni_kundala":
			_aoe(c, pos, p, "fire", color, {"burn": 0.1, "burn_for": 3.0})
		"kalagni":
			_aoe(c, pos, p, "fire", color, {"burn": 0.15, "burn_for": float(p["duration"]), "sparks": 16})
		"surya_tejas":
			_aoe(c, pos, p, "sacred", color, {"sacred": float(p["sacred"])})
		"prana_harana":
			_drain(c, chest, p, color)
		"chhaya_khadga":
			_summon(c, "chhaya_khadga_sword", p, 1, {"lifetime": float(p["duration"]), "dmg_mult": float(p["dmg"]) / 15.0})
			Effects.ring(w, pos, 2.0, color, 0.5)
			Audio.play("summon")
		"shara_varsha":
			c.multi_arrows = int(p["arrows"])
			c.multi_until = c.clock + float(p["duration"])
			Effects.ring(w, pos, 2.0, color, 0.5)
			Audio.play("bow")
		"shata_khadga":
			Game.add_buff("attack_speed", float(p["mult"]), float(p["duration"]))
			Effects.ring(w, pos, 2.0, color, 0.5)
			Audio.play("swing_heavy", -4.0)
		"naga_pasha":
			_roots(c, pos, p, color)
		"garuda_drishti":
			_reveal(float(p["duration"]))
			Effects.ring(w, pos, 3.0, color, 0.8)
			Audio.play("bell", -6.0)
		"hanuman_langhana":
			c.begin_leap(_flat(c.aim_direction(chest)), float(p["distance"]), p)
			Audio.play("roar", -8.0)

static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	if v.length() < 0.001:
		return Vector3(0, 0, -1)
	return v.normalized()

# ---------- attacks ----------
static func _fireball(c, chest: Vector3, p: Dictionary) -> void:
	var dir: Vector3 = c.aim_direction(chest)
	c.player.face_now(_flat(dir))
	var radius := float(p["radius"])
	var dmg := float(p["dmg"])
	var dur := float(p["duration"])
	Game.world.spawn_projectile({
		"pos": chest + dir * 0.8, "dir": dir, "speed": 20.0, "range": 45.0, "kind": "fire",
		"radius": 0.5, "from_player": true,
		"on_end": func(at: Vector3) -> void: _explode(c, at, radius, dmg, dur)})
	Audio.play("fire", -4.0)

static func _explode(c, at: Vector3, radius: float, dmg: float, burn_for: float) -> void:
	var w = Game.world
	if w == null or not is_instance_valid(c):
		return
	Effects.ring(w, at, radius, Color("#ff6a00"), 0.4)
	Effects.sparks(w, at + Vector3(0, 0.3, 0), Color("#ff8a2a"), 10)
	Audio.play("fire", -2.0)
	for e in c.enemies_within(at, radius):
		var away := Vector3(e.global_position.x - at.x, 0, e.global_position.z - at.z)
		away = away.normalized() if away.length() > 0.01 else Vector3.ZERO
		var dealt: float = c.deal_spell(e, dmg, "fire", {"knock": away * 3.0, "stun": 0.3})
		if dealt > 0.0 and not e.dead:
			e.burn(dmg * Game.siddhi_mult() * 0.12, burn_for)

static func _chain_lightning(c, chest: Vector3, p: Dictionary, color: Color) -> void:
	var w = Game.world
	var reach := float(p["radius"])
	var first = c.pick_target(reach * 1.8 + 6.0)
	Audio.play("lightning", -2.0)
	if first == null:
		var dir: Vector3 = c.aim_direction(chest)
		Effects.bolt(w, chest, chest + dir * 10.0, color)
		return
	var hit: Array = [first]
	var cur = first
	Effects.bolt(w, chest, first.center(), color)
	c.deal_spell(first, float(p["dmg"]), "lightning", {"stun": 0.4})
	for i in range(1, int(p["targets"])):
		var next = null
		var nd := INF
		for e in c.enemies_within(cur.center(), reach):
			if e in hit:
				continue
			var d: float = e.center().distance_to(cur.center())
			if d < nd:
				nd = d
				next = e
		if next == null:
			break
		Effects.bolt(w, cur.center(), next.center(), color)
		c.deal_spell(next, float(p["dmg"]), "lightning", {"stun": 0.4})
		hit.append(next)
		cur = next

static func _cone_push(c, pos: Vector3, chest: Vector3, p: Dictionary, color: Color) -> void:
	var fwd := _flat(c.aim_direction(chest))
	c.player.face_now(fwd)
	var radius := float(p["radius"])
	Effects.wedge(Game.world, pos, fwd, radius, deg_to_rad(50.0), color, 0.4)
	Audio.play("wind")
	for e in c.enemies_within(pos + Vector3(0, 1.0, 0), radius):
		var to := Vector3(e.global_position.x - pos.x, 0, e.global_position.z - pos.z)
		if to.length() > 0.01 and fwd.dot(to.normalized()) < cos(deg_to_rad(50.0)):
			continue
		var away := to.normalized() if to.length() > 0.01 else fwd
		c.deal_spell(e, float(p["dmg"]), "air", {"knock": away * float(p["knockback"]), "stun": 0.8})

static func _aoe(c, pos: Vector3, p: Dictionary, element: String, color: Color, extra: Dictionary) -> void:
	var w = Game.world
	var radius := float(p["radius"])
	Effects.ring(w, pos, radius, color, 0.5)
	Effects.sparks(w, pos + Vector3(0, 0.5, 0), color, int(extra.get("sparks", 8)))
	Audio.play("fire" if element == "fire" else "cast", -2.0)
	for e in c.enemies_within(pos + Vector3(0, 0.8, 0), radius):
		var dmg := float(p["dmg"])
		if extra.has("sacred") and str(e.data.get("family", "")) in SACRED_FAMILIES:
			dmg *= float(extra["sacred"])
		var opts := {}
		if p.has("knockback"):
			var away := Vector3(e.global_position.x - pos.x, 0, e.global_position.z - pos.z)
			opts["knock"] = (away.normalized() if away.length() > 0.01 else Vector3.ZERO) * float(p["knockback"])
			opts["stun"] = 0.5
		var dealt: float = c.deal_spell(e, dmg, element, opts)
		if extra.has("burn") and dealt > 0.0 and not e.dead:
			e.burn(dmg * Game.siddhi_mult() * float(extra["burn"]), float(extra["burn_for"]))

static func _shadow_strike(c, pos: Vector3, p: Dictionary, color: Color) -> void:
	var w = Game.world
	var e = c.pick_target(float(p["radius"]))
	if e == null:
		Events.notify.emit(Loc.t("UI_NO_TARGET"), "bad")
		return
	var to := _flat(e.global_position - pos)
	var dest: Vector3 = e.global_position + to * (float(e.radius) + 0.9)
	dest.y = w.height_at(dest.x, dest.z) + 0.1
	Effects.ring(w, pos, 1.5, color, 0.35)
	c.player.global_position = dest
	c.player.velocity = Vector3.ZERO
	Effects.ring(w, dest, 1.5, color, 0.35)
	c.player.face_now(-to)
	Audio.play("teleport", -6.0)
	var prof: Dictionary = c.melee_profile()
	var dmg := float(prof["dmg"]) * float(prof["sharp"]) * Game.melee_mult() * float(p["mult"])
	e.take_damage(dmg, c.player, "shadow", {"stun": 0.5, "knock": -to * 3.0})
	c.register_hit()

static func _heal(c, pos: Vector3, p: Dictionary, color: Color) -> void:
	var w = Game.world
	var amount := float(p["heal"])
	var radius := float(p["radius"])
	Game.heal(amount)
	for a in w.allies:
		if is_instance_valid(a) and not a.dead and a.global_position.distance_to(pos) <= radius:
			a.hp = minf(a.hp_max, a.hp + amount)
	Effects.ring(w, pos, radius, color, 0.6)
	Effects.sparks(w, pos + Vector3(0, 1.0, 0), color, 8)
	Audio.play("heal")

static func _summon(c, eid: String, p: Dictionary, max_alive: int, opts: Dictionary) -> void:
	var same: Array = c.summons.filter(func(s) -> bool: return is_instance_valid(s) and not s.dead and s.enemy_id == eid)
	while same.size() >= max_alive:
		same[0].expire()
		same.remove_at(0)
	c.spawn_ally(eid, opts)

static func _charm(c, pos: Vector3, p: Dictionary, color: Color) -> void:
	var w = Game.world
	var radius := float(p["radius"])
	Effects.ring(w, pos, radius, color, 0.6)
	Audio.play("mudra")
	for e in c.enemies_within(pos + Vector3(0, 0.8, 0), radius):
		if e.is_boss:
			Effects.popup(w, e.center() + Vector3(0, e.height * 0.5, 0), "-", Color("#9a9a9a"))
			continue
		e.charm(float(p["duration"]))
		Effects.flash(e.model, Color(1.0, 0.6, 0.9, 0.4), 0.4)

static func _drain(c, chest: Vector3, p: Dictionary, color: Color) -> void:
	var w = Game.world
	var e = c.pick_target(float(p["radius"]))
	if e == null:
		Events.notify.emit(Loc.t("UI_NO_TARGET"), "bad")
		return
	Effects.bolt(w, e.center(), chest, color, 0.4)
	Audio.play("cast", -2.0)
	var dealt: float = c.deal_spell(e, float(p["dmg"]), "shadow", {})
	if dealt > 0.0 and "drain" not in e.data.get("resist", []):
		Game.heal(dealt * float(p["leech"]))

static func _roots(c, pos: Vector3, p: Dictionary, color: Color) -> void:
	var w = Game.world
	var radius := float(p["radius"])
	Effects.ring(w, pos, radius, color, 0.5)
	Audio.play("dig")
	for e in c.enemies_within(pos + Vector3(0, 0.8, 0), radius):
		c.deal_spell(e, float(p["dmg"]), "earth", {})
		if not e.dead:
			e.root(float(p["duration"]) * (0.5 if e.is_boss else 1.0))
			Effects.flash(e.model, Color(0.2, 0.7, 0.3, 0.4), 0.4)

# ---------- Garuda Drishti ----------
static func _reveal(duration: float) -> void:
	var w = Game.world
	for e in w.enemies:
		if is_instance_valid(e) and not e.dead:
			_marker(e, float(e.height) + float(e.hover) + 1.3, Color("#ff4a3a"), duration)
	for it in w.interactables:
		if is_instance_valid(it) and not bool(it.used) and str(it.kind) in ["chest", "key"]:
			_marker(it, 1.4, Color("#ffd24a"), duration)

static func _marker(parent: Node3D, y: float, col: Color, duration: float) -> void:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.16
	s.height = 0.32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	mat.render_priority = 20
	m.mesh = s
	m.material_override = mat
	m.position = Vector3(0, y, 0)
	parent.add_child(m)
	parent.get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(m):
			m.queue_free())
