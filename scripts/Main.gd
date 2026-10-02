extends Node
## Temporary bootstrap with test hooks (--validate, --gen-test, --shot <region>).

const WorldGen = preload("res://scripts/world/WorldGen.gd")

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--validate" in args:
		_validate_and_quit()
	elif "--check-scripts" in args:
		_check_scripts()
	elif "--gen-test" in args:
		_gen_test()
	elif "--shot" in args:
		var i := args.find("--shot")
		_shot(args[i + 1] if i + 1 < args.size() else "vatagram")

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
