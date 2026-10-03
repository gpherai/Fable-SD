extends Node
## Entry point. Without arguments it starts a new game; with test hooks it runs a headless
## check instead (--validate, --check-scripts, --gen-test, --smoke, --shot <region>, --game-shot,
## --combat-shot).

const WorldGen = preload("res://scripts/world/WorldGen.gd")
const WorldScript = preload("res://scripts/world/World.gd")
const DebugOverlay = preload("res://scripts/ui/DebugOverlay.gd")

var world: Node3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--game-shot" in args or "--combat-shot" in args:
		_start_game()
		if "--game-shot" in args:
			_game_shot()
		elif "--combat-shot" in args:
			_combat_shot()
	elif "--smoke" in args:
		_smoke()
	elif "--validate" in args:
		_validate_and_quit()
	elif "--check-scripts" in args:
		_check_scripts()
	elif "--gen-test" in args:
		_gen_test()
	elif "--shot" in args:
		var i := args.find("--shot")
		_shot(args[i + 1] if i + 1 < args.size() else "vatagram")

## Temporary: starts a fresh hero straight away until the main menu exists.
func _start_game() -> void:
	Game.new_game("Vira")
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	add_child(DebugOverlay.new())
	world.start_game()

## Windowed only: lets the world settle, saves a screenshot of the real game view, quits.
func _game_shot() -> void:
	for i in 150:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	img.save_png("res://screenshots/game.png")
	print("saved screenshots/game.png")
	get_tree().quit(0)

## Windowed only: stages a small fight (bandit, fire caster, rakshasa), lets it run, swings the
## staff and throws a fireball, and saves screenshots/combat_1.png and combat_2.png.
func _combat_shot() -> void:
	var p = Game.player
	var c = p.combat
	Game.hero.age = 20.0
	for e in world.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	world.enemies.clear()
	Game.learn_siddhi("agni_astra", true)
	Game.learn_siddhi("ugra_rupa", true)
	Game.hero.ojas = Game.ojas_max()
	await _frames(60)
	var o: Vector3 = p.global_position
	var a = world.spawn_enemy("dasyu", o + Vector3(2.5, 0.3, -3.0))
	world.spawn_enemy("pisacha_mantrika", o + Vector3(-5.0, 0.3, -8.0))
	world.spawn_enemy("rakshasa", o + Vector3(6.0, 0.3, -9.0))
	c._set_lock(a)
	await _frames(150)
	Input.action_press("attack")
	await _frames(4)
	Input.action_release("attack")
	await _frames(14)
	await RenderingServer.frame_post_draw
	_save_shot("combat_1")
	c.cast_siddhi("ugra_rupa")
	await _frames(20)
	c.siddhi_ready.clear()
	c.cast_siddhi("agni_astra")
	await _frames(28)
	await RenderingServer.frame_post_draw
	_save_shot("combat_2")
	get_tree().quit(0)

func _save_shot(nm: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	img.save_png("res://screenshots/%s.png" % nm)
	print("saved screenshots/%s.png" % nm)

## Headless end-to-end check: start a game, walk, kill an enemy, collect its orbs, then
## travel through every region. Prints SMOKE lines and exits non-zero on failure.
func _smoke() -> void:
	var fails := 0
	Game.new_game("Vira")
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.start_game()
	for i in 5:
		await get_tree().physics_frame
	var p = Game.player
	if p == null or world.region_id != "vatagram_bachpan":
		print("SMOKE FAIL: no player or wrong start region (", world.region_id, ")")
		get_tree().quit(1)
		return
	print("SMOKE ok: started in ", world.region_id, " npcs=", world.npcs.size(), " enemies=", world.enemies.size(), " interactables=", world.interactables.size())
	# settle onto the ground, then walk forward
	for i in 30:
		await get_tree().physics_frame
	var y0: float = p.global_position.y
	var ground: float = world.height_at(p.global_position.x, p.global_position.z)
	if absf(y0 - ground) > 1.0:
		print("SMOKE FAIL: player not on the ground y=%.2f ground=%.2f" % [y0, ground])
		fails += 1
	else:
		print("SMOKE ok: player stands on the ground (y=%.2f, ground=%.2f)" % [y0, ground])
	var start: Vector3 = p.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var moved := Vector3(p.global_position.x - start.x, 0, p.global_position.z - start.z).length()
	print("SMOKE ", "ok" if moved > 2.0 else "FAIL", ": walked %.1f m in 1 s" % moved)
	if moved <= 2.0:
		fails += 1
	# enemy: spawn, kill, orbs
	var en = world.spawn_enemy("pisacha", p.global_position + Vector3(4, 0.5, 0))
	for i in 10:
		await get_tree().physics_frame
	var kills0 := int(Game.hero.counters.get("kills", 0))
	var tapas0 := int(Game.hero.tapas_total)
	en.take_damage(9999.0)
	for i in 240:
		await get_tree().physics_frame
	var got := int(Game.hero.tapas_total) - tapas0
	var killed := int(Game.hero.counters.get("kills", 0)) - kills0
	print("SMOKE ", "ok" if killed == 1 and got > 0 else "FAIL", ": kills +%d, tapas +%d, gold %d" % [killed, got, Game.hero.gold])
	if killed != 1 or got <= 0:
		fails += 1
	# projectile
	var proj = world.spawn_projectile({"pos": p.global_position + Vector3(0, 1, 0), "dir": Vector3(1, 0, 0), "kind": "fire", "range": 5.0})
	for i in 60:
		await get_tree().physics_frame
	print("SMOKE ", "ok" if not is_instance_valid(proj) else "FAIL", ": projectile expired at its range")
	if is_instance_valid(proj):
		fails += 1
	# combat: strikes, enemy attacks, block and parry, bow, siddhis, every enemy type, death
	fails += await _smoke_combat(p)
	# every region
	var t0 := Time.get_ticks_msec()
	var n := 0
	for rid in Data.regions.keys():
		world.build_region(rid, "")
		n += 1
		for i in 2:
			await get_tree().physics_frame
	print("SMOKE ok: built %d regions with population in %d ms" % [n, Time.get_ticks_msec() - t0])
	print("SMOKE ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _report(ok: bool, text: String) -> int:
	print("SMOKE ", "ok" if ok else "FAIL", ": ", text)
	return 0 if ok else 1

## Headless combat check. Returns the number of failed checks.
func _smoke_combat(p) -> int:
	var fails := 0
	var c = p.combat
	# a clean arena: no region enemies, grown-up hero with a bow
	for e in world.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	world.enemies.clear()
	Game.hero.age = 20.0
	Game.give("dhanush_loha", 1, true)
	Game.equip("dhanush_loha")
	Game.equip("lathi")
	p.global_position = world.ground_pos(p.global_position.x, p.global_position.z, 0.2)
	p.velocity = Vector3.ZERO
	await _frames(10)
	var origin: Vector3 = p.global_position
	# 1. a tap swings the staff and hurts an enemy in reach
	p.face_now(Vector3(0, 0, -1))
	var dummy = world.spawn_enemy("maha_keeta", origin + Vector3(0, 0.3, -1.5))
	dummy.stationary = true
	dummy.ai.cd["attack"] = 999.0
	await _frames(5)
	var mult0: int = p.combat_mult
	Input.action_press("attack")
	await _frames(4)
	Input.action_release("attack")
	await _frames(28)
	fails += _report(dummy.hp < dummy.hp_max and p.combat_mult > mult0, "light strike hurt the enemy (hp %.0f/%.0f, multiplier %d)" % [dummy.hp, dummy.hp_max, p.combat_mult])
	# 2. holding attack charges a heavy blow that does clearly more
	var hp_before: float = dummy.hp
	Input.action_press("attack")
	await _frames(75)
	Input.action_release("attack")
	await _frames(60)
	var heavy: float = hp_before - dummy.hp
	fails += _report(heavy > 0.0 and c.combo_step == 0, "charged heavy blow landed for %.1f" % heavy)
	dummy.take_damage(99999.0)
	await _frames(5)
	# 3. an enemy walks up and hurts the hero
	Game.hero.hp = Game.hp_max()
	var foe = world.spawn_enemy("dasyu", origin + Vector3(4, 0.3, 0))
	await _frames(240)
	fails += _report(Game.hero.hp < Game.hp_max(), "dasyu chased the hero and hit (hp %.0f)" % Game.hero.hp)
	foe.take_damage(99999.0)
	await _frames(5)
	# 4. block, parry
	p.global_position = world.ground_pos(origin.x, origin.z, 0.2)
	await _frames(5)
	var attacker = world.spawn_enemy("dasyu", origin + Vector3(0, 0.3, -2.5))
	attacker.stationary = true
	attacker.ai.cd["attack"] = 999.0
	await _frames(3)
	Game.hero.hp = Game.hp_max()
	Input.action_press("block")
	await _frames(3)
	var parried: float = p.take_damage(20.0, "test", attacker, "melee")
	fails += _report(parried == 0.0 and attacker.is_stunned(), "block just before the hit parries and staggers the attacker")
	await _frames(40)
	var blocked: float = p.take_damage(20.0, "test", attacker, "melee")
	fails += _report(blocked > 0.0 and blocked < 8.0, "a late block still weakens the hit (took %.1f of 20)" % blocked)
	var arrow_taken: float = p.take_damage(20.0, "test", attacker, "projectile", attacker.global_position)
	fails += _report(arrow_taken == 0.0, "a blocked arrow does nothing")
	Input.action_release("block")
	await _frames(3)
	var magic: float = p.take_damage(10.0, "test", attacker, "magic")
	fails += _report(magic > 0.0, "magic is not blocked")
	attacker.take_damage(99999.0)
	await _frames(5)
	Game.hero.hp = Game.hp_max()
	# 5. bow with target lock
	var target = world.spawn_enemy("pisacha", origin + Vector3(0, 0.3, -9))
	target.hp_max = 5000.0
	target.hp = 5000.0
	target.stationary = true
	target.ai.cd["attack"] = 999.0
	await _frames(5)
	c._toggle_stance()
	c._set_lock(target)
	fails += _report(c.ranged_stance() and c.lock_valid(), "ranged stance on and target locked")
	var thp: float = target.hp
	c._fire_shot(c.ranged_profile(), 1.0)
	await _frames(70)
	fails += _report(target.hp < thp, "full-draw arrow hit the locked target (%.0f -> %.0f)" % [thp, target.hp])
	c._toggle_stance()
	c.release_lock()
	# 6. siddhis
	Game.learn_siddhi("agni_astra", true)
	Game.learn_siddhi("sanjivani", true)
	Game.learn_siddhi("bhuta_ahvana", true)
	Game.learn_siddhi("vajra", true)
	Game.hero.ojas = Game.ojas_max()
	c._set_lock(target)
	thp = target.hp
	c.cast_siddhi("agni_astra")
	await _frames(100)
	fails += _report(target.hp < thp, "Agni Astra fireball exploded on the target (%.0f -> %.0f)" % [thp, target.hp])
	Game.hero.hp = 40.0
	Game.hero.ojas = Game.ojas_max()
	c.siddhi_ready.clear()
	c.cast_siddhi("sanjivani")
	fails += _report(Game.hero.hp > 60.0, "Sanjivani healed the hero (hp %.0f)" % Game.hero.hp)
	c.siddhi_ready.clear()
	await _frames(25)
	c.cast_siddhi("bhuta_ahvana")
	fails += _report(world.allies.size() >= 1, "Bhuta Ahvana summoned an ally")
	await _frames(240)
	c.siddhi_ready.erase("vajra")
	thp = target.hp
	Game.hero.ojas = Game.ojas_max()
	c.cast_siddhi("vajra")
	await _frames(30)
	fails += _report(target.dead or target.hp < thp, "Vajra struck the target")
	var ojas_before: float = Game.hero.ojas
	c.cast_siddhi("vajra")
	fails += _report(Game.hero.ojas == ojas_before, "a siddhi on cooldown costs nothing")
	c.release_lock()
	for e in world.allies.duplicate():
		if is_instance_valid(e):
			e.expire()
	for e in world.enemies.duplicate():
		if is_instance_valid(e):
			e.take_damage(99999.0)
	await _frames(10)
	# 7. nonlethal duellists yield instead of dying
	var duel = world.spawn_enemy("marmara_sparring", origin + Vector3(6, 0.3, 0), {"on_death_flags": ["smoke_duel_won"]})
	await _frames(3)
	duel.take_damage(99999.0)
	await _frames(3)
	fails += _report(duel.dead and duel.hp == 1.0 and Game.flag("smoke_duel_won"), "Marmara yields and sets her flag")
	# 8. every enemy type runs its AI for ten seconds against a hero who cannot die
	Game.hero.hp = 1000000.0
	var all: Array = []
	var ids := Data.enemies.keys()
	var i := 0
	for eid in ids:
		if bool(Data.enemies[eid].get("ally", false)):
			continue
		var ang := float(i) / float(ids.size()) * TAU
		var pos: Vector3 = origin + Vector3(cos(ang), 0, sin(ang)) * (9.0 + float(i % 3) * 3.0)
		pos.y = world.height_at(pos.x, pos.z) + 0.4
		var en = world.spawn_enemy(eid, pos)
		if en != null:
			all.append(en)
		i += 1
	var hero_hp0: float = Game.hero.hp
	await _frames(600)
	var attacked: float = hero_hp0 - float(Game.hero.hp)
	fails += _report(attacked > 0.0, "%d enemy types fought the hero for 10 s and dealt %.0f damage" % [all.size(), attacked])
	var summoned := 0
	for e in world.enemies:
		if is_instance_valid(e) and e.no_reward:
			summoned += 1
	fails += _report(summoned > 0, "summoners and bosses called %d minions" % summoned)
	for e in world.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	world.enemies.clear()
	await _frames(5)
	# 9. dying and waking again
	Game.hero.hp = 30.0
	p.invulnerable = false
	p.take_damage(500.0, "test", null, "hazard")
	await _frames(3)
	var died: bool = p.dead
	world.respawn_player()
	await _frames(3)
	fails += _report(died and not p.dead and Game.hero.hp > 50.0, "the hero fell and woke again")
	return fails

func _check_scripts() -> void:
	## Loads every .gd under res://scripts and reports scripts that fail to compile.
	var bad := 0
	var total := 0
	for path in _list_scripts("res://scripts"):
		total += 1
		var sc = load(path)
		if sc == null or not sc.can_instantiate():
			print("BROKEN SCRIPT: ", path)
			bad += 1
	print("Scripts checked: %d, broken: %d" % [total, bad])
	get_tree().quit(1 if bad > 0 else 0)

func _list_scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var nm := dir.get_next()
	while nm != "":
		var full := dir_path.path_join(nm)
		if dir.current_is_dir():
			out.append_array(_list_scripts(full))
		elif nm.ends_with(".gd"):
			out.append(full)
		nm = dir.get_next()
	dir.list_dir_end()
	return out

func _validate_and_quit() -> void:
	print("Data summary: ", Data.summary())
	var errs := Data.validate()
	for e in errs:
		print("ERR: ", e)
	print("Validation errors: ", errs.size())
	get_tree().quit(1 if errs.size() > 0 else 0)

var _log: FileAccess

func dlog(msg: String) -> void:
	if _log == null:
		_log = FileAccess.open("res://screenshots/gen.log", FileAccess.WRITE)
	_log.store_line(msg)
	_log.flush()

func _gen_test() -> void:
	var total := 0
	var t0 := Time.get_ticks_msec()
	dlog("start gen-test")
	for rid in Data.regions.keys():
		var t1 := Time.get_ticks_msec()
		dlog("building " + rid)
		var gen := WorldGen.new()
		gen.logger = Callable(self, "dlog")
		var node: Node3D = gen.build(Data.regions[rid], "high")
		add_child(node)
		var cnt := _count_nodes(node)
		total += cnt
		dlog("done " + rid)
		print("%-26s nodes=%5d  npc=%d enemy=%d chest=%d key=%d pickup=%d fish=%d exits=%s  %dms" % [rid, cnt, gen.points.npc.size(), gen.points.enemy.size(), gen.points.chest.size(), gen.points.key.size(), gen.points.pickup.size(), gen.points.fish.size(), str(gen.points.exits.keys()), Time.get_ticks_msec() - t1])
		node.queue_free()
		await get_tree().process_frame
	print("ALL REGIONS BUILT total_nodes=%d in %dms" % [total, Time.get_ticks_msec() - t0])
	get_tree().quit(0)

func _count_nodes(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count_nodes(ch)
	return c

func _shot(rid: String) -> void:
	var gen := WorldGen.new()
	var node: Node3D = gen.build(Data.regions[rid], "high")
	add_child(node)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = gen.biome.sky_top
	sm.sky_horizon_color = gen.biome.sky_horizon
	sm.ground_bottom_color = gen.biome.sky_ground
	sm.ground_horizon_color = gen.biome.sky_horizon
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = gen.biome.ambient
	e.fog_enabled = true
	e.fog_light_color = gen.biome.fog
	e.fog_density = gen.biome.fog_density * 0.5
	e.fog_sky_affect = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = gen.biome.sun_energy
	sun.light_color = gen.biome.sun_color
	sun.shadow_enabled = true
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	var hub: Vector2 = gen.points.hub
	var p := gen.v3(hub + Vector2(0, 38), 0)
	cam.position = Vector3(p.x, p.y + 16.0, p.z)
	cam.look_at(gen.v3(hub, 3.0))
	cam.fov = 70
	cam.far = 400
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://screenshots")
	img.save_png("res://screenshots/%s.png" % rid)
	print("saved screenshots/%s.png" % rid)
	get_tree().quit(0)
