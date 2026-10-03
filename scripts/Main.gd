extends Node
## Entry point. Without arguments it starts a new game; with test hooks it runs a headless
## check instead (--validate, --check-scripts, --gen-test, --smoke, --shot <region>, --game-shot).

const WorldGen = preload("res://scripts/world/WorldGen.gd")
const WorldScript = preload("res://scripts/world/World.gd")
const DebugOverlay = preload("res://scripts/ui/DebugOverlay.gd")

var world: Node3D

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or "--game-shot" in args:
		_start_game()
		if "--game-shot" in args:
			_game_shot()
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
