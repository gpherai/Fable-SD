## Region manager: builds the current region, populates NPCs/enemies/interactables,
## handles travel, followers, day/night, enemy deaths and the arena.
extends Node3D

const WorldGen = preload("res://scripts/world/WorldGen.gd")
const InteractableScript = preload("res://scripts/world/Interactable.gd")
const PlayerScript = preload("res://scripts/entities/Player.gd")
const NPCScript = preload("res://scripts/entities/NPC.gd")
const EnemyScript = preload("res://scripts/entities/Enemy.gd")
const ProjectileScript = preload("res://scripts/entities/Projectile.gd")
const Effects = preload("res://scripts/combat/Effects.gd")
const Props = preload("res://scripts/world/Props.gd")

var gen = null
var region_node: Node3D
var region_id: String = ""
var region_data: Dictionary = {}
var env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var player = null
var npcs: Array = []
var enemies: Array = []
var allies: Array = []
var interactables: Array = []
var projectiles: Array = []
var spawned_ids: Dictionary = {}
var time_factor: float = 1.0
var slow_until: float = -1.0
var traveling: bool = false
var biome: Dictionary = {}
var ambient_level: float = 1.0
# arena
var arena_wave: int = -1
var arena_waves: Array = []
var arena_timer: float = 0.0
var arena_pending: bool = false

func _ready() -> void:
	Game.world = self
	_build_environment()
	Events.player_died.connect(_on_player_died)

func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = true
	e.fog_sky_affect = 0.25
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.18
	e.adjustment_contrast = 1.05
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		e.ssao_enabled = true
		e.ssao_intensity = 1.2
		e.volumetric_fog_enabled = false
		e.sdfgi_enabled = false
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 120.0
	sun.light_energy = 1.0
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color("#8aa0d8")
	moon.light_energy = 0.0
	moon.rotation_degrees = Vector3(-55, -120, 0)
	add_child(moon)

# =====================================================================
# Region lifecycle
# =====================================================================
func start_game() -> void:
	var rid: String = Game.state.get("region", "vatagram_bachpan")
	build_region(rid, Game.state.get("entry", ""))
	if Game.state.has("pos") and Game.state.get("restore_pos", false):
		var p: Array = Game.state.pos
		player.global_position = Vector3(p[0], p[1] + 0.3, p[2])
		Game.state.restore_pos = false

func travel(to_id: String, from_dir: String) -> void:
	if traveling or not Data.regions.has(to_id):
		return
	traveling = true
	Audio.play("teleport", -6.0) if from_dir == "" else Audio.play("step")
	Events.panel_closed.emit()
	await get_tree().process_frame
	var opposite := {"N": "S", "S": "N", "E": "W", "W": "E"}
	var entry: String = opposite.get(from_dir, "")
	build_region(to_id, entry)
	traveling = false

func build_region(rid: String, entry_dir: String) -> void:
	_clear_region()
	region_id = rid
	region_data = Data.region(rid)
	Game.state.region = rid
	Game.state.entry = entry_dir
	gen = WorldGen.new()
	region_node = gen.build(region_data, Game.settings.get("quality", "high"))
	add_child(region_node)
	biome = gen.biome
	_apply_biome_environment()
	spawned_ids.clear()
	_ensure_player()
	player.global_position = gen.exit_position(entry_dir)
	player.reset_state()
	_populate_interactables()
	_populate_npcs()
	_populate_enemies()
	_spawn_followers()
	var rs := Game.region_state(rid)
	var first := not bool(rs.get("visited", false))
	rs.visited = true
	Audio.set_ambient(biome.get("mood", "overworld"))
	Events.region_entered.emit(rid)
	Events.notify.emit(Loc.t(region_data.get("name", {})), "region")
	if first and region_data.has("on_first_enter") and not rs.get("first_enter_done", false):
		rs.first_enter_done = true
		Game.apply_effects(region_data["on_first_enter"])

func _clear_region() -> void:
	for arr in [npcs, enemies, allies, interactables, projectiles]:
		for nd in arr:
			if is_instance_valid(nd):
				nd.queue_free()
		arr.clear()
	if region_node != null and is_instance_valid(region_node):
		region_node.queue_free()
		region_node = null
	arena_wave = -1
	arena_pending = false
	Game.arena_running = false

func _ensure_player() -> void:
	if player == null:
		player = PlayerScript.new()
		player.name = "Player"
		add_child(player)
		Game.player = player
	player.rebuild_visual()

func height_at(x: float, z: float) -> float:
	if gen == null:
		return 0.0
	return gen.height_at(x, z)

func ground_pos(x: float, z: float, lift: float = 0.0) -> Vector3:
	return Vector3(x, height_at(x, z) + lift, z)

func is_interior() -> bool:
	return bool(biome.get("interior", false))

## True when `pos` is at the water's edge or at a well/fountain: the kamandalu can be filled here.
func water_near(pos: Vector3, reach: float = 2.6) -> bool:
	if gen == null:
		return false
	for w in gen.points.get("wells", []):
		if Vector2(pos.x, pos.z).distance_to(w) < reach + 2.2:
			return true
	if not gen.has_water:
		return false
	if gen.is_water_at(pos.x, pos.z):
		return true
	for k in 8:
		var a := k * TAU / 8.0
		if gen.is_water_at(pos.x + cos(a) * reach, pos.z + sin(a) * reach):
			return true
	return false

# =====================================================================
# Population
# =====================================================================
func _populate_interactables() -> void:
	var rs := Game.region_state(region_id)
	var pts: Dictionary = gen.points
	# Exits
	for d in pts.exits.keys():
		if d == "spawn":
			continue
		for ex in region_data.get("exits", []):
			if ex["dir"] == d:
				var inter := _add_interactable("exit", {"to": ex["to"], "dir": d, "locked": ex.get("locked", null)}, gen.v3(pts.exits[d]))
				inter.look_at(gen.v3(pts.hub), Vector3.UP)
	# Chests
	var chests: Array = region_data.get("chests", [])
	for i in chests.size():
		var ch: Dictionary = chests[i]
		if ch.has("when") and not Game.check(ch["when"]):
			continue
		if i >= pts.chest.size():
			continue
		var node := _add_interactable("chest", ch, gen.v3(pts.chest[i]))
		node.index = i
		node.rotation.y = randf() * TAU
		if rs.chests.has(i):
			node.used = true
			var lid: Node3D = node.visual.get_node_or_null("Lid")
			if lid:
				lid.rotation.x = -1.2
				lid.position.z = -0.35
	# Silver keys
	for i in pts.key.size():
		if rs.keys.has(i):
			continue
		var node := _add_interactable("key", {}, gen.v3(pts.key[i]))
		node.index = i
	# Pickups
	var k := 0
	for pk in region_data.get("pickups", []):
		for j in int(pk.get("count", 1)):
			if k < pts.pickup.size():
				if pk.get("night_only", false) and not Game.is_night():
					k += 1
					continue
				if not rs.picked.has(k):
					var node := _add_interactable("pickup", {"item": pk["item"]}, gen.v3(pts.pickup[k]))
					node.index = k
			k += 1
	# Tirtha
	if pts.has("tirtha"):
		var t := _add_interactable("tirtha", {}, gen.v3(pts.tirtha))
		Game.unlock_tirtha(region_id)
	# Yaksha door
	if pts.has("yaksha") and region_data.has("yaksha"):
		var y := _add_interactable("yaksha", {"door": region_data["yaksha"]}, gen.v3(pts.yaksha))
		y.rotation.y = pts.yaksha_yaw
		if rs.get("yaksha", false):
			var mouth: Node3D = y.visual.get_node_or_null("Mouth")
			if mouth:
				mouth.visible = false
	# Shrine
	if region_data.has("shrine") and pts.has("shrine"):
		_add_interactable("shrine", {"shrine": region_data["shrine"]}, gen.v3(pts.shrine))
	# Dig spots
	var digs: Array = region_data.get("dig_spots", [])
	for i in mini(digs.size(), pts.dig.size()):
		if rs.dug.has(i):
			continue
		var node := _add_interactable("dig", digs[i], gen.v3(pts.dig[i]))
		node.index = i
	# Fishing
	for i in pts.fish.size():
		var node := _add_interactable("fish", {}, gen.v3(pts.fish[i]))
		node.index = i
	# Bed
	if pts.has("bed") and (region_data.has("house") or region_id == "vira_akhara"):
		_add_interactable("bed", {}, gen.v3(pts.bed))
	# Boat
	if region_data.has("boat") and pts.has("boat"):
		_add_interactable("boat", region_data["boat"], gen.v3(pts.boat))
	# Signpost
	if pts.has("sign"):
		_add_interactable("sign", {}, gen.v3(pts.sign))

func _add_interactable(kind: String, data: Dictionary, pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.set_script(InteractableScript)
	add_child(node)
	node.setup(kind, data, region_id, interactables.size())
	node.global_position = pos
	interactables.append(node)
	return node

func _npc_entries() -> Array:
	var out := []
	for e in region_data.get("npcs", []):
		if e is String:
			out.append({"id": e, "when": null})
		else:
			out.append({"id": e.get("id", ""), "when": e.get("when", null)})
	return out

func _populate_npcs() -> void:
	var pts: Dictionary = gen.points
	var entries := _npc_entries()
	var i := 0
	for e in entries:
		var nid: String = e["id"]
		if e["when"] != null and not Game.check(e["when"]):
			i += 1
			continue
		if Game.is_following(nid):
			i += 1
			continue
		var p: Vector2 = pts.npc[i % pts.npc.size()] if pts.npc.size() > 0 else pts.hub
		if nid == "devi_himashikhara" and pts.has("oracle"):
			p = pts.oracle
		if nid in ["khadgasura_npc", "khadgasura_vritra_npc", "dvikhadga_npc", "tara_mandapa"] and pts.has("center"):
			p = pts.center + Vector2(0, 6.0)
		if nid == "chhotu_bachcha" and pts.has("cage"):
			p = pts.cage
		if nid == "raktambari_bandi":
			p = pts.hub + Vector2(-20.0, 18.0)
		_spawn_npc(nid, gen.v3(p, 0.2))
		i += 1

func _spawn_npc(nid: String, pos: Vector3) -> Node:
	var npc = NPCScript.new()
	npc.name = "NPC_" + nid
	add_child(npc)
	npc.setup(nid)
	npc.global_position = pos
	npc.home_pos = pos
	npcs.append(npc)
	return npc

func find_npc(nid: String) -> Node:
	for nd in npcs:
		if is_instance_valid(nd) and nd.npc_id == nid:
			return nd
	return null

func remove_npc(nid: String) -> void:
	var nd := find_npc(nid)
	if nd != null:
		npcs.erase(nd)
		nd.queue_free()

func make_hostile(nid: String) -> void:
	var nd := find_npc(nid)
	if nd == null:
		return
	var cd := Data.character(nid)
	var eid: String = cd.get("as_enemy", "dasyu")
	var pos: Vector3 = nd.global_position
	remove_npc(nid)
	spawn_enemy(eid, pos, {"boss": true, "name_override": nid})

func _populate_enemies() -> void:
	var pts: Dictionary = gen.points
	var rs := Game.region_state(region_id)
	var spawns: Array = region_data.get("spawns", [])
	var pi := 0
	for si in spawns.size():
		var sp: Dictionary = spawns[si]
		if sp.has("when") and not Game.check(sp["when"]):
			continue
		if sp.get("night_only", false) and not Game.is_night():
			continue
		if not sp.get("respawn", true) and rs.killed_once.has(si):
			continue
		spawned_ids[si] = true
		var count := int(sp.get("count", 1))
		for c in count:
			var p: Vector2 = pts.enemy[pi % pts.enemy.size()] if pts.enemy.size() > 0 else pts.hub
			pi += 1
			if sp.get("boss", false) and pts.has("boss"):
				p = pts.boss
			elif sp.get("boss", false) and pts.has("center"):
				p = pts.center + Vector2(randf_range(-4, 4), 6.0)
			var pos: Vector3 = gen.v3(p, 0.2)
			if count > 1:
				pos += Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5))
			spawn_enemy(sp["enemy"], pos, {"spawn_index": si, "boss": sp.get("boss", false), "on_death_flags": sp.get("on_death_flags", []), "drop": sp.get("drop", ""), "name_override": sp.get("name_override", ""), "respawn": sp.get("respawn", true)})

func spawn_enemy(eid: String, pos: Vector3, opts: Dictionary = {}) -> Node:
	if not Data.enemies.has(eid):
		push_warning("unknown enemy " + eid)
		return null
	var en = EnemyScript.new()
	en.name = "Enemy_" + eid
	add_child(en)
	en.setup(eid, opts)
	en.global_position = pos
	if en.is_ally:
		allies.append(en)
	else:
		enemies.append(en)
	Events.enemy_spawned.emit(en)
	return en

func spawn_group(v) -> void:
	if not v is Dictionary:
		return
	var pts: Dictionary = gen.points
	var base: Vector2 = pts.get("center", pts.hub)
	for c in int(v.get("count", 1)):
		var p := base + Vector2(randf_range(-5, 5), 5.0 + randf_range(0, 4))
		spawn_enemy(v.get("enemy", "dasyu"), gen.v3(p, 0.2), {"boss": v.get("boss", false), "on_death_flags": v.get("on_death_flags", []), "drop": v.get("drop", "")})

## Re-evaluates conditional NPC entries and spawns after a flag/quest change.
func refresh_conditionals() -> void:
	if region_node == null or gen == null:
		return
	var pts: Dictionary = gen.points
	var i := 0
	for e in _npc_entries():
		var nid: String = e["id"]
		var ok: bool = e["when"] == null or Game.check(e["when"])
		var present := find_npc(nid) != null
		if ok and not present and not Game.is_following(nid):
			var p: Vector2 = pts.npc[i % pts.npc.size()] if pts.npc.size() > 0 else pts.hub
			if nid in ["khadgasura_npc", "khadgasura_vritra_npc", "dvikhadga_npc", "tara_mandapa"] and pts.has("center"):
				p = pts.center + Vector2(0, 6.0)
			_spawn_npc(nid, gen.v3(p, 0.2))
		elif not ok and present:
			remove_npc(nid)
		i += 1
	var rs := Game.region_state(region_id)
	var spawns: Array = region_data.get("spawns", [])
	for si in spawns.size():
		if spawned_ids.has(si):
			continue
		var sp: Dictionary = spawns[si]
		if sp.has("when") and not Game.check(sp["when"]):
			continue
		if not sp.get("respawn", true) and rs.killed_once.has(si):
			continue
		spawned_ids[si] = true
		for c in int(sp.get("count", 1)):
			var p: Vector2 = pts.get("center", pts.hub) + Vector2(randf_range(-5, 5), 8.0 + c * 2.0)
			if sp.get("boss", false) and pts.has("boss"):
				p = pts.boss
			spawn_enemy(sp["enemy"], gen.v3(p, 0.2), {"spawn_index": si, "boss": sp.get("boss", false), "on_death_flags": sp.get("on_death_flags", []), "drop": sp.get("drop", ""), "name_override": sp.get("name_override", ""), "respawn": sp.get("respawn", true)})
			if sp.get("boss", false):
				Events.notify.emit(Loc.t(Data.enemy(sp["enemy"]).get("name", {})), "boss")

func _spawn_followers() -> void:
	for nid in Game.state.followers:
		if find_npc(nid) == null and Data.characters.has(nid):
			var off := Vector3(randf_range(-2, 2), 0, 2.0)
			var npc = _spawn_npc(nid, player.global_position + off)
			npc.following = true

func set_follower(nid: String, on: bool) -> void:
	var nd := find_npc(nid)
	if nd != null:
		nd.following = on
		if on:
			nd.home_pos = nd.global_position

# =====================================================================
# Enemy death, drops, orbs
# =====================================================================
func on_enemy_died(en: Node) -> void:
	var eid: String = en.enemy_id
	var ed := Data.enemy(eid)
	var pos: Vector3 = en.global_position
	enemies.erase(en)
	allies.erase(en)
	if en.is_ally or en.no_reward:
		return
	# tapas orbs scaled by combat multiplier
	var mult := 1.0 + 0.1 * float(player.combat_mult)
	var bala_mult := mult * (Game.FIST_BALA_MULT if en.last_hit_fist else 1.0)
	var t: Dictionary = ed.get("tapas", {})
	Effects.tapas_orbs(self, pos, {
		"general": int(round(float(t.get("general", 0)) * mult)),
		"bala": int(round(float(t.get("bala", 0)) * bala_mult)),
		"kaushala": int(round(float(t.get("kaushala", 0)) * mult)),
		"shakti": int(round(float(t.get("shakti", 0)) * mult))})
	var g: Array = ed.get("gold", [0, 0])
	var gold := randi_range(int(g[0]), int(g[1]))
	if gold > 0:
		spawn_gold(pos + Vector3(randf_range(-1, 1), 0.3, randf_range(-1, 1)), gold)
	for d in ed.get("drops", []):
		if randf() < float(d.get("chance", 0.0)):
			spawn_item_drop(pos + Vector3(randf_range(-1.5, 1.5), 0.3, randf_range(-1.5, 1.5)), d["item"])
	if en.drop_item != "":
		spawn_item_drop(pos + Vector3(0, 0.3, 1.0), en.drop_item)
	Game.hero.counters.kills = int(Game.hero.counters.get("kills", 0)) + 1
	Game.hero.counters["kill_" + eid] = int(Game.hero.counters.get("kill_" + eid, 0)) + 1
	if Game.panth_flag("drain_on_kill") or Game.panth_bonus("drain_on_kill") > 0.0:
		Game.heal(Game.panth_bonus("drain_on_kill"))
	if ed.get("family", "") == "human" and not ed.get("boss", false) and eid in ["gram_rakshak"]:
		Game.add_karma(-15)
	var rs := Game.region_state(region_id)
	if en.spawn_index >= 0 and not en.respawn:
		if not rs.killed_once.has(en.spawn_index):
			rs.killed_once.append(en.spawn_index)
	var is_boss: bool = ed.get("boss", false) or en.is_boss
	Events.enemy_killed.emit(eid, region_id, is_boss)
	for f in en.on_death_flags:
		Game.set_flag(f, true)
	if is_boss:
		Audio.play("levelup")
		Events.notify.emit(Loc.t(ed.get("name", {})) + " ✝", "boss")
		Game.add_yasha(int(ed.get("level", 1)) * 5)

func spawn_item_drop(pos: Vector3, item_id: String) -> void:
	var node := _add_interactable("pickup", {"item": item_id}, pos)
	node.index = -1
	node.position.y = height_at(pos.x, pos.z) + 0.1

func spawn_gold(pos: Vector3, amount: int) -> void:
	Effects.gold_orb(self, pos, amount)

# =====================================================================
# Queries
# =====================================================================
func enemies_in_radius(pos: Vector3, radius: float, include_allies: bool = false) -> Array:
	var out := []
	for e in enemies:
		if is_instance_valid(e) and not e.dead and e.global_position.distance_to(pos) <= radius:
			out.append(e)
	if include_allies:
		for e in allies:
			if is_instance_valid(e) and not e.dead and e.global_position.distance_to(pos) <= radius:
				out.append(e)
	return out

func nearest_enemy(pos: Vector3, max_dist: float = 30.0, forward: Vector3 = Vector3.ZERO) -> Node:
	var best = null
	var bd := max_dist
	for e in enemies:
		if not is_instance_valid(e) or e.dead:
			continue
		var d: float = e.global_position.distance_to(pos)
		if forward != Vector3.ZERO:
			var to: Vector3 = (e.global_position - pos).normalized()
			if to.dot(forward) < -0.2:
				d += 10.0
		if d < bd:
			bd = d
			best = e
	return best

func nearest_npc(pos: Vector3, max_dist: float = 4.0) -> Node:
	var best = null
	var bd := max_dist
	for n in npcs:
		if not is_instance_valid(n):
			continue
		var d: float = n.global_position.distance_to(pos)
		if d < bd:
			bd = d
			best = n
	return best

func spawn_projectile(cfg: Dictionary) -> Node:
	var p = ProjectileScript.new()
	add_child(p)
	p.setup(cfg, self)
	projectiles.append(p)
	return p

func slow_time(duration: float, factor: float) -> void:
	time_factor = factor
	slow_until = Game.state.play_time + duration
	env.environment.adjustment_saturation = 0.6

# =====================================================================
# Arena
# =====================================================================
func start_arena() -> void:
	if Game.arena_running or not gen.points.has("arena_center"):
		return
	var cfg: Dictionary = Data.misc.get("arena", {})
	arena_waves = cfg.get("waves", []).duplicate()
	if Game.flag("rangabhumi_done"):
		arena_waves = arena_waves.slice(0, int(cfg.get("rematch_waves", 5)))
	arena_wave = -1
	Game.arena_running = true
	arena_pending = true
	arena_timer = 2.0
	Audio.set_ambient("arena")
	Events.notify.emit(Loc.t("UI_ARENA_WAVE", {"n": 1}), "boss")

func _arena_process(delta: float) -> void:
	if not Game.arena_running:
		return
	if arena_pending:
		arena_timer -= delta
		if arena_timer <= 0.0:
			arena_pending = false
			arena_wave += 1
			if arena_wave >= arena_waves.size():
				_arena_finish()
				return
			Events.notify.emit(Loc.t("UI_ARENA_WAVE", {"n": arena_wave + 1}), "boss")
			var sp: Array = gen.points.arena_spawn
			var k := 0
			for grp in arena_waves[arena_wave]:
				for c in int(grp.get("count", 1)):
					var p: Vector2 = sp[k % sp.size()]
					k += 1
					spawn_enemy(grp["enemy"], gen.v3(p, 0.2), {"arena": true})
		return
	# wave running: check all arena enemies dead
	var alive := 0
	for e in enemies:
		if is_instance_valid(e) and not e.dead and e.arena:
			alive += 1
	if alive == 0:
		Game.add_gold(int(Data.misc.get("arena", {}).get("gold_per_wave", 100)))
		arena_pending = true
		arena_timer = 3.0

func _arena_finish() -> void:
	Game.arena_running = false
	Audio.set_ambient(biome.get("mood", "arena"))
	if not Game.flag("arena_won"):
		Game.set_flag("arena_won", true)
		Game.set_flag("rangabhumi_done_pending", true)
		var cs: Dictionary = Data.misc.get("cutscenes", {}).get("arena_mask", {})
		Events.cutscene_requested.emit(Loc.t(cs.get("title", {})), cs.get("pages", []), Callable(self, "_arena_marmara_choice"))
	else:
		Events.notify.emit(Loc.t("UI_ARENA_WON"), "boss")

func _arena_marmara_choice() -> void:
	Events.panel_requested.emit("marmara_choice", null)

# =====================================================================
# Day / night & environment
# =====================================================================
func _apply_biome_environment() -> void:
	var e := env.environment
	e.fog_light_color = biome.fog
	e.fog_density = float(biome.fog_density) * (0.6 if not is_interior() else 1.0)
	sky_mat.sky_top_color = biome.sky_top
	sky_mat.sky_horizon_color = biome.sky_horizon
	sky_mat.ground_horizon_color = biome.sky_horizon
	sky_mat.ground_bottom_color = biome.sky_ground
	sun.light_color = biome.sun_color
	ambient_level = float(biome.ambient)
	if is_interior():
		e.background_mode = Environment.BG_COLOR
		e.background_color = biome.fog
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = biome.ceiling.lightened(0.3)
		e.ambient_light_energy = ambient_level
		sun.light_energy = 0.0
		sun.shadow_enabled = false
		moon.light_energy = 0.0
	else:
		e.background_mode = Environment.BG_SKY
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		sun.shadow_enabled = Game.settings.get("quality", "high") != "low"
	_update_daylight()

func _update_daylight() -> void:
	if is_interior():
		return
	var t: float = Game.state.get("time", 12.0)
	var daylight := clampf(sin((t - 6.0) / 12.0 * PI), -1.0, 1.0)
	var dl := clampf(daylight, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(daylight) * 3.0, 0.0, 1.0)
	var elev := daylight * 70.0
	sun.rotation_degrees = Vector3(-maxf(elev, 8.0) if daylight > 0.0 else -8.0, 40.0 + (t - 12.0) * 10.0, 0)
	sun.light_energy = float(biome.sun_energy) * (0.15 + 0.85 * dl)
	var warm := Color("#ffb070")
	sun.light_color = biome.sun_color.lerp(warm, dusk * 0.8)
	moon.light_energy = 0.35 * (1.0 - dl)
	var night_top := Color("#07091c")
	var night_hor := Color("#1a2040")
	sky_mat.sky_top_color = biome.sky_top.lerp(night_top, 1.0 - dl).lerp(Color("#5a3a6a"), dusk * 0.5)
	sky_mat.sky_horizon_color = biome.sky_horizon.lerp(night_hor, 1.0 - dl).lerp(Color("#ff9a5a"), dusk * 0.7)
	sky_mat.ground_horizon_color = sky_mat.sky_horizon_color
	var e := env.environment
	e.fog_light_color = biome.fog.lerp(night_hor, 1.0 - dl)
	e.ambient_light_energy = ambient_level * (0.25 + 0.75 * dl)

func _process(delta: float) -> void:
	if not Game.in_game:
		return
	Game.tick(delta)
	if slow_until > 0.0 and Game.state.play_time > slow_until:
		time_factor = 1.0
		slow_until = -1.0
		env.environment.adjustment_saturation = 1.18
	if Engine.get_process_frames() % 20 == 0:
		_update_daylight()
	_arena_process(delta)
	projectiles = projectiles.filter(func(p): return is_instance_valid(p))

func _on_player_died() -> void:
	Events.panel_requested.emit("death", null)

func respawn_player() -> void:
	Game.respawn_penalty()
	Events.notify.emit(Loc.t("UI_RESPAWN"), "bad")
	player.global_position = gen.exit_position(Game.state.get("entry", ""))
	player.reset_state()
	for e in enemies:
		if is_instance_valid(e):
			e.leash()
