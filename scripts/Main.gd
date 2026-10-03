extends Node
## Entry point. Without arguments it starts a new game; with test hooks it runs a headless
## check instead (--validate, --check-scripts, --gen-test, --smoke, --balance, --shot <region>, --game-shot,
## --combat-shot).

const WorldGen = preload("res://scripts/world/WorldGen.gd")
const WorldScript = preload("res://scripts/world/World.gd")
const DebugOverlay = preload("res://scripts/ui/DebugOverlay.gd")

var world: Node3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--game-shot" in args or "--combat-shot" in args:
		_start_game()
		if not args.is_empty():
			_isolate_window()
		if "--game-shot" in args:
			_game_shot()
		elif "--combat-shot" in args:
			_combat_shot()
	elif "--smoke" in args:
		_smoke()
	elif "--balance" in args:
		_balance()
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

## Screenshot runs open a real window on the desktop. This keeps real keys and mouse out of it
## (they would mix with the scripted input) and leaves the pointer free.
func _isolate_window() -> void:
	var w := get_window()
	w.unfocusable = true
	w.mouse_passthrough_polygon = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.player.set_process_unhandled_input(false)
	Game.player.controls_on = true   # scripted Input.action_press still has to drive the hero

## Windowed only: a close-up fight. combat_1 = staff strike on a locked dasyu (hit number, hp bar,
## lock marker, follow-through), combat_2 = Ugra Rupa and Agni Astra, combat_3 = a second dasyu's
## orange wind-up flash, combat_4 = Dhyana (seated). The hero cannot be hurt: these shots are about
## how it looks.
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
	p.invulnerable = true
	await _frames(60)
	p.arm.spring_length = 4.2
	var o: Vector3 = p.global_position
	var a = world.spawn_enemy("dasyu", o + Vector3(0.0, 0.3, -1.7))
	a.stationary = true
	a.ai.cd["attack"] = 999.0
	world.spawn_enemy("rakshasa", o + Vector3(5.0, 0.3, -8.0)).stationary = true
	c._set_lock(a)
	await _frames(60)
	Input.action_press("attack")
	await _frames(3)
	Input.action_release("attack")
	await _frames(15)   # the strike lands at 45% of the swing
	await RenderingServer.frame_post_draw
	_save_shot("combat_1")
	await _frames(40)
	c.cast_siddhi("ugra_rupa")
	await _frames(20)
	c.siddhi_ready.clear()
	c.cast_siddhi("agni_astra")
	await _frames(22)
	await RenderingServer.frame_post_draw
	_save_shot("combat_2")
	# wind-up flash: a free dasyu walks up and starts its attack; shoot the moment it does
	a.take_damage(99999.0)
	var b = world.spawn_enemy("dasyu", o + Vector3(3.0, 0.3, -3.0))
	c._set_lock(b)
	for i in 600:
		await get_tree().physics_frame
		if not b.ai.action.is_empty():
			break
	await _frames(4)
	await RenderingServer.frame_post_draw
	_save_shot("combat_3")
	# Dhyana: the hero sits down in lotus pose
	b.take_damage(99999.0)
	c.release_lock()
	await _frames(60)
	Input.action_press("meditate")
	await _frames(45)
	await RenderingServer.frame_post_draw
	_save_shot("combat_4")
	Input.action_release("meditate")
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

## Balance report (headless): for every enemy, a hero build that fits its level fights it with
## light strikes only, every blow landing, no armour, no dodging. Prints how long the hero needs to
## kill it and how long it needs to kill the hero. Ratio < 1 = the hero is faster. A fair fight is
## roughly 0.6-1.0 for ordinary foes (dodging and blocking make up the difference) and 1.5-3 for bosses.
const BALANCE_BUILDS := [
	{"upto": 4, "stat": 1, "weapon": "lathi"},
	{"upto": 8, "stat": 2, "weapon": "talwar_loha"},
	{"upto": 15, "stat": 4, "weapon": "khanda_ispat"},
	{"upto": 24, "stat": 6, "weapon": "talwar_krishnashila"},
	{"upto": 99, "stat": 7, "weapon": "khanda_krishnashila"},
]

func _balance() -> void:
	Game.new_game("Vira")
	Game.hero.age = 20.0
	var rows: Array = []
	for eid in Data.enemies.keys():
		var ed: Dictionary = Data.enemies[eid]
		if bool(ed.get("ally", false)) or float(ed.get("hp", 0)) >= 9000.0 and not bool(ed.get("boss", false)):
			continue
		var lvl := int(ed.get("level", 1))
		var build: Dictionary = BALANCE_BUILDS[BALANCE_BUILDS.size() - 1]
		for b in BALANCE_BUILDS:
			if lvl <= int(b["upto"]):
				build = b
				break
		for s in Game.hero.stats.keys():
			Game.hero.stats[s] = int(build["stat"])
		if not Game.has(str(build["weapon"])):
			Game.give(str(build["weapon"]), 1, true)
		Game.equip(str(build["weapon"]))
		Game.hero.hp = Game.hp_max()
		var w: Dictionary = Data.item(str(build["weapon"]))
		var spd := float(w.get("speed", 1.0))
		var period := clampf(0.5 / spd, 0.2, 1.0)
		var hit: float = float(w.get("dmg", 4)) * Game.melee_mult() * (1.0 - clampf(float(ed.get("def", 0.0)), 0.0, 0.9)) * 1.25   # 1.25 = average of the three combo strikes
		var hero_ttk := ceilf(float(ed.get("hp", 1)) / hit) * period
		var foe_hit: float = float(ed.get("dmg", 1)) * (1.0 - Game.dmg_reduction())
		var foe_ttk := ceilf(Game.hp_max() / foe_hit) * float(ed.get("attack_cd", 1.2))
		rows.append([lvl, eid, bool(ed.get("boss", false)), build["weapon"], int(build["stat"]), float(ed.get("hp", 0)), float(ed.get("dmg", 0)), hero_ttk, foe_ttk, hero_ttk / foe_ttk, Game.hp_max()])
	rows.sort_custom(func(a, b) -> bool: return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
	print("%3s %-22s %-4s %-22s %4s %6s %5s %9s %9s %6s" % ["lvl", "enemy", "boss", "hero weapon", "stat", "hp", "dmg", "hero kills", "foe kills", "ratio"])
	for r in rows:
		print("%3d %-22s %-4s %-22s %4d %6.0f %5.0f %8.1fs %8.1fs %6.2f" % [r[0], r[1], "boss" if r[2] else "", r[3], r[4], r[5], r[6], r[7], r[8], r[9]])
	get_tree().quit(0)

## Taps an action the way a keyboard does: as an InputEvent, so Player._unhandled_input hears it.
func _tap(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)

## A spot on the ground about 1.5 m from `pos`, as level with it as possible (`pref` = the
## direction to try first), so a scripted hero stands where a strike can reach.
func _ground_beside(pos: Vector3, pref: Vector3) -> Vector3:
	var best := pos
	var best_gap := INF
	var base := atan2(pref.z, pref.x)
	for k in 8:
		var a := base + float(k) * TAU / 8.0
		var q: Vector3 = world.ground_pos(pos.x + cos(a) * 1.5, pos.z + sin(a) * 1.5, 0.2)
		var gap := absf(q.y - pos.y)
		if gap < best_gap - 0.05:
			best_gap = gap
			best = q
	return best

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
	# 8. potions: R and T drink the fitting elixir and never waste one
	var notes: Array = []
	Events.notify.connect(func(t, _k) -> void: notes.append(t))
	for id in ["prana_rasa_laghu", "prana_rasa_laghu", "prana_rasa", "ojas_rasa", "vishahara"]:
		Game.give(id, 1, true)
	p.invulnerable = false
	Game.hero.hp = 90.0
	await _tap("potion_prana")
	fails += _report(Game.count("prana_rasa_laghu") == 1 and Game.count("prana_rasa") == 1 and Game.hero.hp >= 99.9, "R with 10 Prana missing drinks the small elixir (hp %.0f)" % Game.hero.hp)
	Game.hero.hp = 20.0
	await _tap("potion_prana")
	fails += _report(Game.count("prana_rasa") == 0 and Game.count("prana_rasa_laghu") == 1 and Game.hero.hp >= 99.9, "R with 80 missing takes the bigger elixir (hp %.0f)" % Game.hero.hp)
	Game.hero.hp = Game.hp_max()
	notes.clear()
	await _tap("potion_prana")
	fails += _report(Game.count("prana_rasa_laghu") == 1 and notes.has(Loc.t("UI_PRANA_FULL")), "R on full Prana wastes nothing and says so")
	Game.hero.hp = 10.0
	await _tap("potion_prana")
	fails += _report(Game.count("prana_rasa_laghu") == 0 and Game.hero.hp > 49.0 and Game.hero.hp < 53.0, "R drinks the last small elixir (hp %.0f)" % Game.hero.hp)
	notes.clear()
	await _tap("potion_prana")
	fails += _report(notes.has(Loc.t("UI_NO_PRANA_RASA")) and Game.count("vishahara") == 1, "R with no elixir says so and leaves the antidote alone")
	Game.hero.ojas = 10.0
	await _tap("potion_ojas")
	fails += _report(Game.count("ojas_rasa") == 0 and Game.hero.ojas >= Game.ojas_max() - 0.1, "T drinks the Ojas elixir (ojas %.0f)" % Game.hero.ojas)
	notes.clear()
	Game.hero.ojas = 10.0
	await _tap("potion_ojas")
	fails += _report(notes.has(Loc.t("UI_NO_OJAS_RASA")), "T with no Ojas elixir says so")
	Game.take("vishahara", 1)
	Game.hero.hp = Game.hp_max()
	Game.hero.ojas = Game.ojas_max()
	# 9. Dhyana: hold H to sit, Ojas flows back four times faster, a seated hero neither walks nor
	# fights, and a blow (or a roll) ends it
	p.global_position = world.ground_pos(origin.x, origin.z, 0.2)
	p.velocity = Vector3.ZERO
	await _frames(10)
	Game.hero.ojas = 0.0
	Input.action_press("meditate")
	await _frames(6)
	fails += _report(c.is_meditating(), "holding H sits the hero down (Dhyana)")
	var ojas0: float = Game.hero.ojas
	var seat: Vector3 = p.global_position
	Input.action_press("move_forward")
	Input.action_press("attack")
	await _frames(60)
	Input.action_release("move_forward")
	Input.action_release("attack")
	var gain: float = Game.hero.ojas - ojas0
	fails += _report(gain > Game.ojas_regen() * 3.0, "Ojas flows back %.1f in 1 s (normal %.1f)" % [gain, Game.ojas_regen()])
	fails += _report(c.is_meditating() and c.combo_step == 0 and p.global_position.distance_to(seat) < 0.2 and p.model.position.y < -0.3, "seated: no walking, no swinging, body is low (y %.2f)" % p.model.position.y)
	p.take_damage(5.0, "test", null, "hazard")
	await _frames(10)
	fails += _report(not c.is_meditating(), "a blow ends Dhyana, even with H still held")
	Input.action_release("meditate")
	await _frames(3)
	Input.action_press("meditate")
	await _frames(6)
	fails += _report(c.is_meditating(), "pressing H again sits down again")
	p._start_roll()
	await _frames(3)
	fails += _report(not c.is_meditating() and p.rolling, "a roll gets the hero up")
	Input.action_release("meditate")
	await _frames(60)
	fails += _report(not c.is_meditating() and p.model.position.y > -0.05, "hero stands again (y %.2f)" % p.model.position.y)
	Game.hero.hp = Game.hp_max()
	# 10. Mushti Yuddha: bare fists are quick, and a kill with them gives more Bala tapas
	Game.unequip("melee")
	var fist: Dictionary = c.melee_profile()
	fails += _report(float(fist["dmg"]) == 3.0 and float(fist["speed"]) > 1.5, "without a weapon the hero fights with fists (dmg %.0f, speed %.1f)" % [float(fist["dmg"]), float(fist["speed"])])
	var bala_gain: Array = []
	for use_fist in [false, true]:
		var bala0 := int(Game.hero.tapas.get("bala", 0))
		p.combat_mult = 0
		var spar = world.spawn_enemy("marmara_sparring", origin + Vector3(3, 0.3, 0))
		await _frames(3)
		spar.take_damage(99999.0, p, "", {"fist": true} if use_fist else {})
		await _frames(300)
		bala_gain.append(int(Game.hero.tapas.get("bala", 0)) - bala0)
	fails += _report(float(bala_gain[1]) > float(bala_gain[0]) * 1.35 and float(bala_gain[1]) < float(bala_gain[0]) * 1.65, "a fist kill gave %d Bala tapas against %d for any other kill" % [bala_gain[1], bala_gain[0]])
	p.global_position = world.ground_pos(origin.x, origin.z, 0.2)
	p.velocity = Vector3.ZERO
	p.face_now(Vector3(0, 0, -1))
	await _frames(5)
	var keeta = world.spawn_enemy("keeta", origin + Vector3(0, 0.3, -1.2))
	keeta.stationary = true
	keeta.ai.cd["attack"] = 999.0
	await _frames(3)
	for i in 30:
		if keeta.dead:
			break
		Input.action_press("attack")
		await _frames(3)
		Input.action_release("attack")
		await _frames(20)
	fails += _report(keeta.dead and keeta.last_hit_fist, "the hero killed a beetle with real fist blows")
	await _frames(120)
	Game.equip("lathi")
	# 11. every enemy type runs its AI for ten seconds against a hero who cannot die
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
	# 12. dying and waking again
	Game.hero.hp = 30.0
	p.invulnerable = false
	p.take_damage(500.0, "test", null, "hazard")
	await _frames(3)
	var died: bool = p.dead
	world.respawn_player()
	await _frames(3)
	fails += _report(died and not p.dead and Game.hero.hp > 50.0, "the hero fell and woke again")
	fails += await _smoke_marmara(p)
	return fails

## Marmara's graduation duel in her real region, fought with real staff strikes (the hero is
## unhurtable here: this checks the flow, not the odds, which --balance covers).
func _smoke_marmara(p) -> int:
	var fails := 0
	var c = p.combat
	Game.hero.age = 20.0
	Game.equip("lathi")
	# the death panel of the previous check let go of the mouse; the overlay normally takes it back
	p.capture_mouse()
	Game.set_flag("marmara_duel_started", true)
	world.build_region("vira_akhara", "")
	await _frames(30)
	var duel = null
	for e in world.enemies:
		if is_instance_valid(e) and e.enemy_id == "marmara_sparring":
			duel = e
	fails += _report(duel != null and duel.nonlethal and duel.is_boss, "Marmara waits on the training field once the duel has begun")
	if duel == null:
		return fails
	Game.hero.hp = Game.hp_max()
	p.invulnerable = true
	var tapas0 := int(Game.hero.tapas_total)
	var swings := 0
	for i in 4000:
		await get_tree().physics_frame
		if duel.dead:
			break
		var to: Vector3 = duel.global_position - p.global_position
		to.y = 0.0
		if to.length() > 2.2 or absf(duel.global_position.y - p.global_position.y) > 1.0:
			p.global_position = _ground_beside(duel.global_position, -to)
			p.velocity = Vector3.ZERO
			to = duel.global_position - p.global_position
			to.y = 0.0
		p.face_now(to)
		if i % 40 == 0:
			Input.action_press("attack")
			swings += 1
		elif i % 40 == 3:
			Input.action_release("attack")
	Input.action_release("attack")
	fails += _report(duel.dead and duel.hp == 1.0, "Marmara yields at 1 hp after %d real strikes instead of dying" % swings)
	fails += _report(Game.flag("marmara_duel_won"), "her yielding sets marmara_duel_won (the quest condition)")
	p.invulnerable = false
	var hp_after: float = Game.hero.hp
	await _frames(300)
	fails += _report(not p.dead and Game.hero.hp >= hp_after - 0.01, "she does not hit the hero after yielding")
	fails += _report(int(Game.hero.tapas_total) > tapas0, "the duel paid out tapas (+%d)" % (int(Game.hero.tapas_total) - tapas0))
	world.build_region("vira_akhara", "")
	await _frames(30)
	var again := false
	for e in world.enemies:
		if is_instance_valid(e) and e.enemy_id == "marmara_sparring":
			again = true
	fails += _report(not again, "she does not come back when the region is rebuilt")
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
