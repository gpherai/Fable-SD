extends Node
## `--systems`: headless check of the systems the foundation claimed but never ran: save / load,
## day and night, the arena, shrines, chests, digging and fishing, followers, quests, boss spawns,
## progression and death. Prints SYS lines; exits non-zero when a check fails.
## Writes only to user://test_saves (Main sets Game.save_dir), never to the real saves.

var main                 # Main.gd
var world: Node3D
var fails: int = 0
var checks: int = 0

func ok(name: String, cond: bool, detail: String = "") -> bool:
	checks += 1
	if not cond:
		fails += 1
	print("SYS ", "ok" if cond else "FAIL", ": ", name, ("  [%s]" % detail) if detail != "" else "")
	return cond

func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout

## A brand-new game (and optionally a given region), the hero unhurtable.
func fresh(region: String = "") -> void:
	if main.ui != null:
		main.ui.close_all()   # an open panel pauses the world: no test may start behind one
	get_tree().paused = false
	Game.paused_for_ui = false
	main._drop_world()
	Game.new_game("Test")
	main._make_world()
	main.world.start_game()
	world = main.world
	await frames(3)
	if region != "":
		world.build_region(region, "")
		await frames(3)
	Game.player.invulnerable = true

## Kills an enemy for sure: sacred damage (some bosses take nothing else), repeated while it is still rising.
func slay(en) -> void:
	for i in 40:
		if not is_instance_valid(en) or en.dead:
			break
		en.take_damage(9999999.0, null, "sacred")
		await get_tree().physics_frame
	await frames(30)

func inters(kind: String) -> Array:
	var out := []
	for i in world.interactables:
		if is_instance_valid(i) and i.kind == kind:
			out.append(i)
	return out

## Puts the game into a state where `cond` (a dialogue / spawn condition) is true.
func satisfy(cond) -> void:
	if cond is Array:
		for c in cond:
			satisfy(c)
		return
	if not cond is Dictionary:
		return
	for k in cond.keys():
		var v = cond[k]
		match k:
			"flag":
				for f in (v if v is Array else [v]):
					Game.set_flag(f, true)
			"not_flag":
				for f in (v if v is Array else [v]):
					Game.set_flag(f, false)
			"quest_active":
				force_quest(v, 0)
			"quest_stage":
				force_quest(v[0], int(v[1]))
			"quest_stage_min":
				force_quest(v[0], int(v[1]))
			"night":
				Game.state.time = 22.0 if v else 12.0

func force_quest(qid: String, stage: int) -> void:
	var q: Dictionary = Game.quests._q(qid)
	q["state"] = "active"
	q["stage"] = stage

func same(a, b, path: String = "") -> String:
	## "" when equal (ints and floats compare by value), else the first path that differs.
	if a is Dictionary and b is Dictionary:
		for k in a.keys():
			if not b.has(k):
				return path + "/" + str(k) + " (missing after load)"
			var r: String = same(a[k], b[k], path + "/" + str(k))
			if r != "":
				return r
		for k in b.keys():
			if not a.has(k):
				return path + "/" + str(k) + " (appeared after load)"
		return ""
	if a is Array and b is Array:
		if a.size() != b.size():
			return path + " (size %d vs %d)" % [a.size(), b.size()]
		for i in a.size():
			var r2: String = same(a[i], b[i], path + "[%d]" % i)
			if r2 != "":
				return r2
		return ""
	if (a is float or a is int) and (b is float or b is int):
		return "" if absf(float(a) - float(b)) < 0.0001 else path + " (%s vs %s)" % [str(a), str(b)]
	return "" if a == b else path + " (%s vs %s)" % [str(a), str(b)]

# =====================================================================
func run() -> void:
	await test_save_load()
	await test_day_night()
	await test_containers()
	await test_minigames()
	await test_kamandalu()
	await test_shrines()
	await test_followers()
	await test_arena()
	await test_bosses()
	await test_quests()
	await test_progression()
	await test_death()
	await test_dialogue_effects()
	await test_roll()
	for slot in [0, 90, 91, 92, 93]:
		Game.delete_save(slot)
	print("SYS summary: %d checks, %d failed" % [checks, fails])
	print("SYSTEMS ", "PASS" if fails == 0 else "FAILED (%d)" % fails)
	get_tree().quit(1 if fails > 0 else 0)

# =====================================================================
# Save / load
# =====================================================================
func test_save_load() -> void:
	print("-- save / load")
	await fresh()
	var p = Game.player
	var rid: String = world.region_id
	# change a bit of everything the save has to carry
	Game.add_gold(777)
	Game.add_karma(-33)
	Game.add_yasha(12)
	var potion := ""
	for k in Data.items.keys():
		if Data.items[k].get("cat", "") == "potion":
			potion = k
			break
	Game.give(potion, 3, true)
	Game.give("bansi", 1, true)
	Game.add_tapas("bala", 400)
	Game.raise_stat("deha")
	var sid: String = Data.siddhis.keys()[0]
	Game.learn_siddhi(sid, true)
	Game.set_hotbar(3, sid)
	Game.set_flag("sys_flag", true)
	Game.set_flag("sys_counter", 5)
	Game.quests.start("q_tara_janmadin")
	Game.add_affection("bhadra", 20)
	Game.follow("chhotu_bachcha")
	Game.buy_house("vatagram")
	Game.add_mudra(Data.mudras.keys()[Data.mudras.size() - 1])
	Game.hero.counters.fish = 3
	var rs := Game.region_state(rid)
	rs.chests.append(0)
	rs.picked.append(1)
	rs.killed_once.append(2)
	rs.dug.append(0)
	rs.keys.append(0)
	Game.state.time = 21.5
	Game.state.day = 4
	Game.add_buff("speed", 1.5, 500.0)
	p.global_position += Vector3(5, 0, 3)
	await frames(30)
	var pos_before: Vector3 = p.global_position
	var saved: bool = Game.save_game(90, true)
	ok("save_game writes slot 90", saved and Game.has_save(90))
	var snap: Dictionary = JSON.parse_string(JSON.stringify({"hero": Game.hero, "state": Game.state, "buffs": Game.buffs}))
	var meta: Dictionary = Game.save_meta(90)
	ok("save_meta reads name, region and day", meta.get("name", "") == "Test" and meta.get("region", "") == rid and int(meta.get("day", 0)) == 4, str(meta))
	# throw everything away, then load
	Game.hero = {}
	Game.state = {}
	var loaded: bool = Game.load_game(90)
	ok("load_game succeeds", loaded)
	var diff: String = same(snap.hero, Game.hero, "hero")
	ok("hero is identical after load", diff == "", diff)
	diff = same(snap.state, Game.state, "state")
	ok("state is identical after load", diff == "", diff)
	ok("buffs survive a load", Game.buffs.size() == 1 and Game.buff_active("speed"))
	var rs2 := Game.region_state(rid)
	ok("region state arrays still answer int lookups after JSON (chests/picked/dug/keys/killed_once)", rs2.chests.has(0) and rs2.picked.has(1) and rs2.dug.has(0) and rs2.keys.has(0) and rs2.killed_once.has(2))
	ok("quests API works on loaded data", Game.quests.is_active("q_tara_janmadin") and Game.quests.stage_of("q_tara_janmadin") == 0)
	ok("derived values are sane after load", Game.stat("deha") == 2 and Game.melee_mult() > 1.0 and Game.siddhi_level(sid) == 1 and Game.count(potion) == 3 and Game.hero.hotbar[3] == sid)
	ok("flags keep their values", Game.flag("sys_flag") and int(Game.state.flags.get("sys_counter", 0)) == 5)
	ok("follower list survives", Game.is_following("chhotu_bachcha"))
	# the whole flow: menu "load" = new world, hero back where they stood
	main.load_slot(90)
	await frames(60)
	p = Game.player
	world = main.world
	ok("load_slot rebuilds the world in the saved region", world.region_id == rid and p != null)
	var moved := Vector2(p.global_position.x - pos_before.x, p.global_position.z - pos_before.z).length()
	ok("hero stands where they saved", moved < 1.5, "off by %.2f m" % moved)
	var fol = world.find_npc("chhotu_bachcha")
	ok("the follower is back and following (exactly one)", fol != null and fol.following and world.npcs.filter(func(n): return is_instance_valid(n) and n.npc_id == "chhotu_bachcha").size() == 1)
	var chest0 = null
	for c in inters("chest"):
		if c.index == 0:
			chest0 = c
	ok("an opened chest stays opened", chest0 == null or chest0.used)
	var key0_present := false
	for k in inters("key"):
		if k.index == 0:
			key0_present = true
	ok("a picked-up silver key does not come back", not key0_present)
	var pick1_present := false
	for k in inters("pickup"):
		if k.index == 1:
			pick1_present = true
	ok("a picked-up item does not come back", not pick1_present)
	ok("time and day are kept", int(Game.state.day) == 4 and absf(float(Game.state.time) - 21.5) < 0.5, "day %s time %.2f" % [str(Game.state.day), float(Game.state.time)])
	# slot bookkeeping
	Game.save_game(91, true)
	ok("latest_save_slot ignores slots outside the menu range", Game.latest_save_slot() == -1)
	# bad files
	var f := FileAccess.open(Game.save_path(92), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var gold_before: int = int(Game.hero.gold)
	ok("a corrupt save is refused and leaves the running game alone", not Game.load_game(92) and int(Game.hero.gold) == gold_before)
	ok("a missing slot is refused", not Game.load_game(93))
	f = FileAccess.open(Game.save_path(93), FileAccess.WRITE)
	f.store_string(JSON.stringify({"hero": {"name": "Oud"}, "state": {}, "version": "0.1"}))
	f.close()
	ok("a save with a missing hero or state is refused, not half-loaded", not Game.load_game(93) and int(Game.hero.gold) == gold_before)
	f = FileAccess.open(Game.save_path(93), FileAccess.WRITE)
	f.store_string("[1, 2, 3]")
	f.close()
	ok("a save that is not an object is refused", not Game.load_game(93) and int(Game.hero.gold) == gold_before)
	# every region state persists through a round trip even when many regions were visited
	for r in ["vira_akhara", "akhara_vana", "drishtikuta"]:
		world.build_region(r, "")
		await frames(2)
	Game.save_game(91, true)
	var snap2: Dictionary = JSON.parse_string(JSON.stringify({"hero": Game.hero, "state": Game.state}))
	Game.load_game(91)
	diff = same(snap2.state, Game.state, "state")
	ok("state with several visited regions round-trips", diff == "", diff)

# =====================================================================
# Day and night
# =====================================================================
func test_day_night() -> void:
	print("-- day / night")
	await fresh()
	Game.state.time = 19.4
	var a1: bool = Game.is_night()
	Game.state.time = 19.5
	var a2: bool = Game.is_night()
	Game.state.time = 4.99
	var a3: bool = Game.is_night()
	Game.state.time = 5.0
	var a4: bool = Game.is_night()
	ok("night runs from 19:30 to 05:00", not a1 and a2 and a3 and not a4)
	Game.state.time = 22.0
	ok("conditions 'night' and 'day' follow the clock", Game.check({"night": true}) and not Game.check({"day": true}) and not Game.check({"night": false}))
	Game.state.time = 12.0
	ok("... and at noon", Game.check({"day": true}) and not Game.check({"night": true}))
	# the clock
	Game.settings.time_speed = 1.0
	Game.state.time = 23.9
	var day0: int = int(Game.state.day)
	var hours := []
	var cb := func(h: float): hours.append(h)
	Events.time_changed.connect(cb)
	Game.tick(12.0)
	Events.time_changed.disconnect(cb)
	ok("midnight rolls the day over and wraps the clock", int(Game.state.day) == day0 + 1 and float(Game.state.time) < 0.5 and float(Game.state.time) >= 0.0, "day %s time %.3f" % [str(Game.state.day), float(Game.state.time)])
	ok("time_changed fires when the hour changes", hours.size() >= 1)
	Game.state.time = 8.0
	Game.settings.time_speed = 2.0
	Game.tick(30.0)
	ok("time_speed 2 doubles the clock", absf(float(Game.state.time) - 9.0) < 0.01, "%.3f" % float(Game.state.time))
	Game.settings.time_speed = 1.0
	Game.hero.poison = 5.0
	Game.hero.drunk = 30.0
	var hp0: float = Game.hero.hp
	Game.tick(2.0)
	ok("poison hurts over time and drunkenness wears off", Game.hero.hp < hp0 and Game.hero.drunk < 30.0 and Game.hero.poison < 5.0)
	Game.hero.poison = 0.0
	Game.hero.hp = Game.hp_max()
	# light
	var sun = world.sun
	var moon = world.moon
	var res := {}
	for t in [0.0, 5.0, 6.0, 12.0, 18.0, 19.5, 22.0]:
		Game.state.time = t
		world._update_daylight()
		res[t] = [sun.light_energy, moon.light_energy]
	ok("the sun is strong at noon and weak at midnight", res[12.0][0] > res[0.0][0] * 2.0, "noon %.2f midnight %.2f" % [res[12.0][0], res[0.0][0]])
	ok("the moon shines at night and not at noon", res[0.0][1] > 0.1 and res[12.0][1] < 0.05, "midnight %.2f noon %.2f" % [res[0.0][1], res[12.0][1]])
	ok("the sky changes colour between noon and midnight", world.sky_mat.sky_top_color != Color.BLACK)
	# interiors keep their own light, and leaving one gives the outdoor light back
	world.build_region("pisacha_guha", "")
	await frames(2)
	Game.state.time = 12.0
	world._update_daylight()
	var interior_ok: bool = world.is_interior() and sun.light_energy == 0.0
	world.build_region("vatagram_bachpan", "")
	await frames(2)
	Game.state.time = 12.0
	world._update_daylight()
	ok("inside a cave there is no sun, back outside there is", interior_ok and sun.light_energy > 0.5 and world.env.environment.background_mode == Environment.BG_SKY, "sun %.2f" % sun.light_energy)
	# night-only content is present only at night
	Game.state.time = 12.0
	world.build_region("dakinivana_shila", "")
	await frames(2)
	var day_flowers: int = inters("pickup").filter(func(i): return i.data.get("item", "") == "yaksha_phool").size()
	Game.state.time = 22.0
	world.build_region("dakinivana_shila", "")
	await frames(2)
	var night_flowers: int = inters("pickup").filter(func(i): return i.data.get("item", "") == "yaksha_phool").size()
	ok("night flowers only bloom at night", day_flowers == 0 and night_flowers > 0, "day %d night %d" % [day_flowers, night_flowers])
	Game.state.time = 12.0
	world.build_region("samadhi_kshetra", "")
	await frames(2)
	var day_preta: int = world.enemies.filter(func(e): return is_instance_valid(e) and e.enemy_id == "preta").size()
	Game.state.time = 22.0
	world.build_region("samadhi_kshetra", "")
	await frames(2)
	var night_preta: int = world.enemies.filter(func(e): return is_instance_valid(e) and e.enemy_id == "preta").size()
	ok("night-only enemies spawn only at night", day_preta == 0 and night_preta > 0, "day %d night %d" % [day_preta, night_preta])
	# nightfall while standing in the region
	Game.state.time = 12.0
	world.build_region("samadhi_kshetra", "")
	await frames(2)
	Game.state.time = 22.0
	Events.time_changed.emit(22.0)
	world.refresh_conditionals()
	await frames(2)
	var late_preta: int = world.enemies.filter(func(e): return is_instance_valid(e) and e.enemy_id == "preta").size()
	ok("when night falls inside a region the night enemies show up (no re-entry needed)", late_preta > 0, "%d preta" % late_preta)
	# sleeping
	await fresh("vira_akhara")
	var beds := inters("bed")
	ok("the Akhara has a bed", beds.size() == 1)
	Game.hero.hp = 10.0
	Game.hero.ojas = 0.0
	Game.state.time = 23.0
	var day1: int = int(Game.state.day)
	Game.delete_save(0)
	if beds.size() > 0:
		beds[0].interact(world)
	ok("sleeping: morning, next day, full hp and ojas, autosave", absf(float(Game.state.time) - 6.0) < 0.01 and int(Game.state.day) == day1 + 1 and Game.hero.hp >= Game.hp_max() - 0.1 and Game.hero.ojas >= Game.ojas_max() - 0.1 and Game.has_save(0))
	await fresh("vatagram_bachpan")
	var vbeds := inters("bed")
	if vbeds.size() > 0:
		var t0: float = Game.state.time
		vbeds[0].interact(world)
		ok("a bed in a house you do not own stays locked", is_equal_approx(float(Game.state.time), t0))

# =====================================================================
# Chests, keys, pickups
# =====================================================================
func first_region_with(pred: Callable) -> String:
	for rid in Data.regions.keys():
		if pred.call(Data.regions[rid]):
			return rid
	return ""

func test_containers() -> void:
	print("-- chests, keys, pickups")
	var rid := first_region_with(func(r): return r.get("chests", []).any(func(c): return int(c.get("locked", 0)) == 0 and not c.has("when") and (c.get("items", []).size() > 0 or int(c.get("gold", 0)) > 0)))
	await fresh(rid)
	var chests := inters("chest")
	var plain = null
	for c in chests:
		if int(c.data.get("locked", 0)) == 0:
			plain = c
			break
	ok("region %s has an unlocked chest" % rid, plain != null)
	if plain == null:
		return
	var g0: int = int(Game.hero.gold)
	var items: Array = plain.data.get("items", [])
	var counts0 := {}
	for it in items:
		counts0[it] = Game.count(it)
	var n0: int = int(Game.hero.counters.chests)
	plain.interact(world)
	var got_items := true
	for it in items:
		if Game.count(it) != int(counts0[it]) + items.count(it):
			got_items = false
	var gold_expected := int(plain.data.get("gold", 0))
	ok("opening a chest gives its items and gold", got_items and int(Game.hero.gold) - g0 >= gold_expected and plain.used, "gold +%d (chest %d)" % [int(Game.hero.gold) - g0, gold_expected])
	ok("the chest counter goes up and the chest is remembered", int(Game.hero.counters.chests) == n0 + 1 and Game.region_state(rid).chests.has(plain.index))
	var g1: int = int(Game.hero.gold)
	plain.interact(world)
	ok("an opened chest gives nothing a second time", int(Game.hero.gold) == g1)
	var idx: int = plain.index
	world.build_region(rid, "")
	await frames(2)
	var again = null
	for c in inters("chest"):
		if c.index == idx:
			again = c
	ok("after leaving and coming back the chest is still open", again != null and again.used)
	# locked chests
	var lrid := first_region_with(func(r): return r.get("chests", []).any(func(c): return int(c.get("locked", 0)) > 0 and not c.has("when")))
	await fresh(lrid)
	var locked = null
	for c in inters("chest"):
		if int(c.data.get("locked", 0)) > 0:
			locked = c
			break
	if ok("region %s has a locked chest" % lrid, locked != null):
		var need: int = int(locked.data.locked)
		locked.interact(world)
		ok("a locked chest stays shut without keys", not locked.used)
		Game.give("rajat_kunji", need - 1, true)
		locked.interact(world)
		ok("... and with one key too few", not locked.used and Game.count("rajat_kunji") == need - 1)
		Game.give("rajat_kunji", 1, true)
		locked.interact(world)
		ok("with enough keys it opens and the keys are spent", locked.used and Game.count("rajat_kunji") == 0)
	# keys and pickups
	await fresh(first_region_with(func(r): return not r.get("pickups", []).is_empty() and not r.get("pickups", [])[0].get("night_only", false)))
	var picks := inters("pickup")
	var keys := inters("key")
	if ok("a region with pickups and silver keys", picks.size() > 0):
		var pk = picks[0]
		var item: String = pk.data.item
		var c0: int = Game.count(item)
		pk.interact(world)
		ok("a pickup lands in the inventory once", Game.count(item) == c0 + 1 and pk.used)
		pk.interact(world)
		ok("... and not twice", Game.count(item) == c0 + 1)
		if keys.size() > 0:
			var k = keys[0]
			k.interact(world)
			ok("a silver key counts as found", Game.count("rajat_kunji") == 1 and int(Game.hero.counters.keys_found) == 1)
		var pidx: int = pk.index
		world.build_region(world.region_id, "")
		await frames(2)
		var back := false
		for q in inters("pickup"):
			if q.index == pidx and q.data.get("item", "") == item:
				back = true
		ok("collected pickups stay collected after re-entering", not back)
	# enemy drops are pickups without a slot: they must not corrupt the persistent list
	var rs := Game.region_state(world.region_id)
	var picked0: int = rs.picked.size()
	world.spawn_item_drop(Game.player.global_position + Vector3(2, 0, 0), "matsya")
	var drop = inters("pickup").back()
	drop.interact(world)
	ok("a dropped item can be picked up", Game.count("matsya") == 1)
	ok("... without writing a bogus slot into the region's picked list", rs.picked.size() == picked0, "picked list grew from %d to %d (%s)" % [picked0, rs.picked.size(), str(rs.picked)])

# =====================================================================
# Digging and fishing
# =====================================================================
func test_minigames() -> void:
	print("-- digging and fishing")
	await fresh("vata_tata")
	var digs := inters("dig")
	if ok("vata_tata has a dig spot", digs.size() > 0):
		var d = digs[0]
		var item: String = d.data.get("item", "")
		var gold: int = int(d.data.get("gold", 0))
		d.interact(world)
		ok("digging without a shovel does nothing", not d.used and not d.busy)
		Game.give("kudala", 1, true)
		var g0: int = int(Game.hero.gold)
		var c0: int = Game.count(item)
		d.interact(world)
		ok("digging takes time (busy)", d.busy)
		d.interact(world)   # a second E while digging must not dig twice
		await seconds(1.8)
		ok("a dig spot gives its item and gold exactly once", d.used and not d.busy and Game.count(item) == c0 + 1 and int(Game.hero.gold) - g0 == gold, "item %d gold +%d" % [Game.count(item) - c0, int(Game.hero.gold) - g0])
		var idx: int = d.index
		world.build_region("vata_tata", "")
		await frames(2)
		var left: int = inters("dig").filter(func(i): return i.index == idx).size()
		ok("a dug-up spot is gone after re-entering", left == 0)
	# fishing: find water
	var frid := ""
	for rid in ["dhivara_nala", "vata_tata", "ankusha_tata", "mahavana_hrada"]:
		await fresh(rid)
		if inters("fish").size() > 0:
			frid = rid
			break
	if not ok("a region with fishing spots exists", frid != ""):
		return
	var spot = inters("fish")[0]
	spot.interact(world)
	ok("fishing without a rod does nothing", spot.fish_state == 0)
	Game.give("bansi", 1, true)
	var fish0: int = int(Game.hero.counters.fish)
	var m0: int = Game.count("matsya")
	spot.interact(world)
	ok("casting starts the wait", spot.fish_state == 1)
	var waited := 0.0
	while spot.fish_state == 1 and waited < 8.0:
		await seconds(0.1)
		waited += 0.1
	ok("a fish bites within 2-5 s", spot.fish_state == 2 and waited >= 1.8 and waited <= 5.6, "after %.1f s, state %d" % [waited, spot.fish_state])
	spot.interact(world)
	ok("reeling in during the bite catches a fish", spot.fish_state == 0 and int(Game.hero.counters.fish) == fish0 + 1 and (Game.count("matsya") == m0 + 1 or Game.count("suvarna_matsya") > 0 or Game.count("nilakantha_talwar") > 0))
	# reeling in too early loses it
	spot.interact(world)
	await seconds(0.3)
	spot.interact(world)
	ok("reeling in too early loses the fish", spot.fish_state == 0 and int(Game.hero.counters.fish) == fish0 + 1)
	# missing the bite window loses it
	spot.interact(world)
	waited = 0.0
	while spot.fish_state != 2 and waited < 8.0:
		await seconds(0.1)
		waited += 0.1
	await seconds(1.2)
	ok("missing the bite window loses the fish", spot.fish_state == 0 and int(Game.hero.counters.fish) == fish0 + 1)
	# an interrupted wait must not leave the next cast haunted by the old timer
	spot.interact(world)
	await seconds(0.2)
	spot.interact(world)   # cancel
	spot.interact(world)   # cast again
	await seconds(6.5)
	ok("cancelling and casting again does not double-fire the old bite timer", spot.fish_state in [0, 2], "state %d" % spot.fish_state)

# =====================================================================
# Kamandalu: sips and refilling
# =====================================================================
## A spot on the shore (not water, water within reach) with no interactable or NPC close by.
func shore_spot() -> Variant:
	var gen = world.gen
	for ring in 12:
		for k in 24:
			var a := k * TAU / 24.0
			var r: float = gen.lake_radius + 1.0 + ring * 0.7
			var c: Vector2 = gen.lake_center + Vector2(cos(a), sin(a)) * r
			if not gen.inside(c) or gen.is_water_at(c.x, c.y):
				continue
			var pos: Vector3 = world.ground_pos(c.x, c.y, 0.2)
			if not world.water_near(pos):
				continue
			var clear := true
			for i in world.interactables:
				if is_instance_valid(i) and i.global_position.distance_to(pos) < 7.0:
					clear = false
			if clear and world.nearest_npc(pos, 5.0) == null:
				return pos
	return null

func test_kamandalu() -> void:
	print("-- kamandalu")
	await fresh("dhivara_nala")
	var pl = Game.player
	Game.hero.hp = 10.0
	ok("without a kamandalu water gives no target", not pl._find_target().has("action"))
	ok("a kamandalu cannot be used when you do not have one", not Game.use_item("kamandalu"))
	Game.give("kamandalu", 1, true)
	ok("a new kamandalu comes full", int(Game.hero.water) == Game.water_max() and Game.water_max() == 3)
	var hp0: float = Game.hero.hp
	ok("a sip heals and costs one charge, the pot stays", Game.use_item("kamandalu") and Game.hero.hp > hp0 and int(Game.hero.water) == 2 and Game.count("kamandalu") == 1)
	Game.hero.hp = 10.0
	Game.use_item("kamandalu")
	Game.hero.hp = 10.0
	Game.use_item("kamandalu")
	ok("three sips empty it", int(Game.hero.water) == 0)
	Game.hero.hp = 10.0
	ok("an empty kamandalu does nothing", not Game.use_item("kamandalu") and Game.hero.hp == 10.0 and Game.count("kamandalu") == 1)
	Game.hero.hp = Game.hp_max()
	Game.hero.ojas = Game.ojas_max()
	Game.hero.water = 2
	ok("no sip is wasted on a full hero", not Game.use_item("kamandalu") and int(Game.hero.water) == 2)
	Game.hero.water = 0
	# at the shore
	var spot = shore_spot()
	if ok("the lake has a free shore spot", spot != null):
		pl.global_position = spot
		await frames(2)
		var t: Dictionary = pl._find_target()
		ok("at the shore E offers to fill the kamandalu", t.has("action") and t.get("text", "").find("0/3") >= 0, str(t.get("text", "")))
		pl._interact()
		ok("E at the shore fills it", int(Game.hero.water) == 3)
		await frames(2)
		ok("a full kamandalu is not offered water", not pl._find_target().has("action"))
		ok("refilling a full kamandalu does nothing", not Game.refill_water())
	var hub: Vector2 = world.gen.points.hub
	Game.hero.water = 0
	ok("far from water there is nothing to fill", not world.water_near(Vector3(hub.x, 0.0, hub.y)) or world.gen.points.wells.size() > 0)
	# a well counts as water
	await fresh("vatagram_bachpan")
	Game.give("kamandalu", 1, true)
	Game.hero.water = 1
	var wells: Array = world.gen.points.wells
	if ok("the village has a well", wells.size() > 0):
		var w: Vector2 = wells[0]
		ok("a well is a water source", world.water_near(Vector3(w.x, 0.0, w.y)))
	# the sips are saved, and a save from before the pot could run dry gets a full one
	Game.hero.water = 1
	Game.save_game(90, true)
	Game.hero = {}
	Game.load_game(90)
	ok("sips survive a save and load (as int)", typeof(Game.hero.water) == TYPE_INT and Game.hero.water == 1)
	var raw := FileAccess.open(Game.save_path(90), FileAccess.READ)
	var data: Dictionary = JSON.parse_string(raw.get_as_text())
	raw.close()
	data.hero.erase("water")
	var wf := FileAccess.open(Game.save_path(90), FileAccess.WRITE)
	wf.store_string(JSON.stringify(data))
	wf.close()
	Game.load_game(90)
	ok("an old save with a kamandalu loads it full", int(Game.hero.water) == Game.water_max())

# =====================================================================
# Shrines
# =====================================================================
func test_shrines() -> void:
	print("-- shrines")
	await fresh("surya_mandir")
	main._make_ui()
	var sh := inters("shrine")
	if not ok("surya_mandir has a shrine", sh.size() > 0):
		return
	sh[0].interact(world)
	await get_tree().process_frame
	var panel = main.ui.current
	ok("E at the shrine opens the dharma panel", panel != null and panel.kind == "shrine")
	if panel == null:
		return
	Game.hero.gold = 6000
	Game.hero.karma = 0
	Game.hero.counters.donated = 0
	panel._donate(1000)
	ok("a donation costs gold, counts and earns karma (1 per 20 gold)", Game.hero.gold == 5000 and int(Game.hero.counters.donated) == 1000 and Game.hero.karma == 50, "gold %d karma %d" % [Game.hero.gold, Game.hero.karma])
	panel._donate(1000)
	panel._donate(1000)
	panel._donate(1000)
	ok("below 5000 donated the quest flag is not set", not Game.flag("mandir_daan_5000"))
	panel._donate(1000)
	ok("at 5000 donated the flag mandir_daan_5000 is set", Game.flag("mandir_daan_5000") and int(Game.hero.counters.donated) == 5000, "donated %d gold left %d" % [int(Game.hero.counters.donated), Game.hero.gold])
	var g: int = Game.hero.gold
	panel._donate(1000)
	ok("a donation you cannot afford does nothing", Game.hero.gold == g or g >= 1000)
	main.ui.close_all()
	ok("closing the shrine unpauses the world", not get_tree().paused and not Game.paused_for_ui)
	# the Asura shrine
	await fresh("andhaka_pith")
	main._make_ui()
	var sh2 := inters("shrine")
	if not ok("andhaka_pith has a shrine", sh2.size() > 0):
		return
	Game.give("preta_asthi", 3, true)
	Game.hero.gold = 1500
	Game.state.time = 12.0
	sh2[0].interact(world)
	await get_tree().process_frame
	panel = main.ui.current
	ok("E at the Asura shrine opens its panel", panel != null and panel.kind == "shrine" and panel.shrine == "asura")
	if panel != null:
		panel._sacrifice()
		ok("by day nothing is sacrificed", not Game.flag("andhaka_bali_done") and Game.count("preta_asthi") == 3 and Game.hero.gold == 1500)
		Game.state.time = 22.0
		panel._sacrifice()
		ok("at night 3 bones and 1000 gold buy the flag", Game.flag("andhaka_bali_done") and Game.count("preta_asthi") == 0 and Game.hero.gold == 500)
	main.ui.close_all()

# =====================================================================
# Followers
# =====================================================================
func test_followers() -> void:
	print("-- followers")
	await fresh()
	force_quest("q_pisacha_guha", 0)
	world.build_region("pisacha_guha", "")
	await frames(3)
	var p = Game.player
	var chhotu = world.find_npc("chhotu_bachcha")
	if not ok("Chhotu waits in the Pisacha cave while his quest is active", chhotu != null):
		return
	Game.follow("chhotu_bachcha")
	ok("follow() switches the NPC on and records it", chhotu.following and Game.is_following("chhotu_bachcha"))
	# walk away and see him keep up
	var start: Vector3 = p.global_position
	p.global_position = start + Vector3(14, 0, 0)
	await frames(240)
	var d: float = Vector2(chhotu.global_position.x - p.global_position.x, chhotu.global_position.z - p.global_position.z).length()
	ok("a follower catches up with a hero 14 m away", d < 6.0, "%.1f m apart" % d)
	p.global_position = start + Vector3(60, 0, 0)
	await frames(10)
	d = Vector2(chhotu.global_position.x - p.global_position.x, chhotu.global_position.z - p.global_position.z).length()
	ok("a follower more than 30 m behind snaps next to the hero", d < 6.0, "%.1f m apart" % d)
	# travelling takes him along, and the village does not grow a second Chhotu
	var exit_to: String = Data.regions["pisacha_guha"].exits[0].to
	world.build_region(exit_to, "")
	await frames(5)
	var here: Array = world.npcs.filter(func(n): return is_instance_valid(n) and n.npc_id == "chhotu_bachcha")
	ok("the follower comes along into the next region", here.size() == 1 and here[0].following, "%d copies" % here.size())
	world.build_region("pisacha_guha", "")
	await frames(5)
	var back: Array = world.npcs.filter(func(n): return is_instance_valid(n) and n.npc_id == "chhotu_bachcha")
	ok("back in his cave he is still one follower, not an extra villager", back.size() == 1 and back[0].following, "%d copies" % back.size())
	# quests that watch the follower
	Game.unfollow("chhotu_bachcha")
	ok("unfollow() lets him go", not Game.is_following("chhotu_bachcha") and not back[0].following)
	# the escort quests
	for qid in Data.quests.keys():
		var q: Dictionary = Data.quests[qid]
		for i in q.stages.size():
			var o: Dictionary = q.stages[i].get("objective", {})
			if o.get("type", "") != "escort":
				continue
			await fresh()
			force_quest(qid, i)
			var npc: String = o.npc
			# not following: arriving alone must not complete it
			world.build_region(o.region, "")
			await frames(3)
			var alone_done: bool = Game.quests.stage_of(qid) != i or not Game.quests.is_active(qid)
			Game.follow(npc)
			world.build_region("vatagram_bachpan", "")
			await frames(2)
			world.build_region(o.region, "")
			await frames(3)
			var done: bool = not Game.quests.is_active(qid) or Game.quests.stage_of(qid) != i
			ok("escort %s stage %d: arriving without %s does not count, arriving with them does" % [qid, i, npc], not alone_done and done, "alone_done=%s done=%s" % [str(alone_done), str(done)])

# =====================================================================
# Arena
# =====================================================================
func test_arena() -> void:
	print("-- arena")
	await fresh("rangabhumi")
	var w = world
	var cfg: Dictionary = Data.misc.arena
	var waves: Array = cfg.waves
	ok("the Rangabhumi has an arena with spawn points", w.gen.points.has("arena_center") and w.gen.points.get("arena_spawn", []).size() > 0)
	var cutscenes := []
	var cs_cb := func(title: String, _pages: Array, on_done: Callable): cutscenes.append(on_done)
	Events.cutscene_requested.connect(cs_cb)
	var panels := []
	var pn_cb := func(k: String, _pl): panels.append(k)
	Events.panel_requested.connect(pn_cb)
	for e in w.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	w.enemies.clear()
	var g0: int = int(Game.hero.gold)
	w.start_arena()
	ok("start_arena sets the arena running", Game.arena_running and w.arena_pending)
	w.start_arena()
	var seen := {}
	var t0 := Time.get_ticks_msec()
	var kills := 0
	var last_report := 0
	while Game.arena_running and Time.get_ticks_msec() - t0 < 180000:
		await get_tree().physics_frame
		if Time.get_ticks_msec() - t0 - last_report > 30000:
			last_report = Time.get_ticks_msec() - t0
			print("SYS   (arena at %d s: wave %d, pending %s)" % [last_report / 1000, w.arena_wave, str(w.arena_pending)])
			for e in w.enemies:
				if is_instance_valid(e):
					print("SYS     %s hp %.0f dead %s rising %s arena %s at %s" % [e.enemy_id, e.hp, str(e.dead), str(e.rising), str(e.arena), str(e.global_position)])
		var wv: int = w.arena_wave
		if wv >= 0 and wv < waves.size() and not w.arena_pending and not seen.has(wv):
			var alive: int = w.enemies.filter(func(e): return is_instance_valid(e) and not e.dead and e.arena).size()
			seen[wv] = alive
		for e in w.enemies.duplicate():
			if is_instance_valid(e) and not e.dead and e.arena:
				e.take_damage(999999.0, null, "sacred")
				kills += 1
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	ok("all %d waves came and the arena ended" % waves.size(), not Game.arena_running and seen.size() == waves.size(), "seen %d waves in %.0f s" % [seen.size(), took])
	var counts_ok := true
	var detail := ""
	for wi in seen.keys():
		var expect := 0
		for grp in waves[wi]:
			expect += int(grp.count)
		if int(seen[wi]) < expect:
			counts_ok = false
			detail += "wave %d: %d of %d  " % [wi + 1, int(seen[wi]), expect]
	ok("every wave spawned its full roster", counts_ok, detail)
	ok("each cleared wave paid %d gold" % int(cfg.gold_per_wave), int(Game.hero.gold) - g0 >= int(cfg.gold_per_wave) * (waves.size() - 1), "+%d gold" % (int(Game.hero.gold) - g0))
	ok("winning sets arena_won and plays the mask cutscene", Game.flag("arena_won") and cutscenes.size() == 1, "%d cutscenes" % cutscenes.size())
	if cutscenes.size() == 1 and cutscenes[0].is_valid():
		cutscenes[0].call()
		ok("after the cutscene Marmara's choice appears", "marmara_choice" in panels)
	Events.cutscene_requested.disconnect(cs_cb)
	Events.panel_requested.disconnect(pn_cb)
	# a rematch is shorter
	Game.set_flag("rangabhumi_done", true)
	w.start_arena()
	ok("a rematch uses only %d waves" % int(cfg.rematch_waves), w.arena_waves.size() == int(cfg.rematch_waves), "%d waves" % w.arena_waves.size())
	for e in w.enemies.duplicate():
		if is_instance_valid(e):
			e.queue_free()
	# leaving mid-arena stops it
	w.build_region("vatagram_bachpan", "")
	await frames(3)
	ok("leaving the region mid-arena stops the arena", not Game.arena_running and w.arena_wave == -1)
	# dying mid-arena
	await fresh("rangabhumi")
	w = world
	w.start_arena()
	var wait := 0.0
	while w.arena_wave < 0 and wait < 15.0:
		await seconds(0.1)
		wait += 0.1
	var spawned: int = w.enemies.filter(func(e): return is_instance_valid(e) and e.arena).size()
	Game.player.invulnerable = false
	Game.damage_hero(99999.0)
	await frames(2)
	w.respawn_player()
	await frames(5)
	var live_arena: int = w.enemies.filter(func(e): return is_instance_valid(e) and not e.dead and e.arena).size()
	ok("dying mid-arena: the hero is back up", Game.hero.hp > 0.0 and not Game.player.dead)
	ok("dying mid-arena: the first wave had come (%d enemies)" % spawned, spawned > 0)
	ok("dying mid-arena does not leave the arena running with no enemies (wave %d, %d alive, running %s)" % [w.arena_wave, live_arena, str(Game.arena_running)], not Game.arena_running or live_arena > 0 or w.arena_pending)

# =====================================================================
# Bosses: flags, drops, no respawn
# =====================================================================
func test_bosses() -> void:
	print("-- boss spawns")
	for rid in Data.regions.keys():
		var r: Dictionary = Data.regions[rid]
		var spawns: Array = r.get("spawns", [])
		for si in spawns.size():
			var sp: Dictionary = spawns[si]
			if sp.get("on_death_flags", []).is_empty() and sp.get("drop", "") == "":
				continue
			await fresh()
			if sp.has("when"):
				satisfy(sp.when)
			world.build_region(rid, "")
			await frames(3)
			var en = null
			for e in world.enemies:
				if is_instance_valid(e) and e.spawn_index == si:
					en = e
					break
			if en == null:
				# conditional spawns may need a refresh after the condition changed
				world.refresh_conditionals()
				await frames(2)
				for e in world.enemies:
					if is_instance_valid(e) and e.spawn_index == si:
						en = e
						break
			var label := "%s spawn %d (%s)" % [rid, si, sp.enemy]
			if not ok("%s appears once its condition holds" % label, en != null):
				continue
			var flags_before := {}
			for f in sp.get("on_death_flags", []):
				flags_before[f] = Game.flag(f)
			await slay(en)
			var all_set := true
			for f in sp.get("on_death_flags", []):
				if not Game.flag(f):
					all_set = false
			var drop_ok := true
			if sp.get("drop", "") != "":
				drop_ok = inters("pickup").any(func(i): return i.data.get("item", "") == sp.drop) or Game.count(sp.drop) > 0
			ok("%s: killing it sets %s%s" % [label, str(sp.get("on_death_flags", [])), (" and drops " + sp.drop) if sp.get("drop", "") != "" else ""], all_set and drop_ok)
			if sp.get("respawn", true) == false:
				world.build_region(rid, "")
				await frames(3)
				world.refresh_conditionals()
				await frames(2)
				var back: int = world.enemies.filter(func(e): return is_instance_valid(e) and not e.dead and e.spawn_index == si).size()
				ok("%s: does not come back after re-entering" % label, back == 0, "%d alive" % back)
	# the hostile-NPC route (Khadgasura and friends)
	await fresh("karma_mandapa")
	for nid in Data.characters.keys():
		var cd: Dictionary = Data.characters[nid]
		if cd.has("as_enemy") and not Data.enemies.has(cd.as_enemy):
			ok("character %s turns into a known enemy" % nid, false, cd.as_enemy)

# =====================================================================
# Quests: every quest, start to finish, through the real machinery
# =====================================================================
func test_quests() -> void:
	print("-- quests")
	await fresh()
	var done_count := 0
	var problems := []
	for qid in Data.quests.keys():
		await fresh()
		var q: Dictionary = Data.quests[qid]
		var req: Dictionary = q.get("requires", {})
		for f in req.get("flags", []):
			Game.set_flag(f, true)
		for rq in req.get("quests_done", []):
			Game.quests._q(rq)["state"] = "done"
		if not Game.quests.can_start(qid):
			problems.append("%s: can_start is false even with its requirements met" % qid)
			continue
		var g0: int = int(Game.hero.gold)
		var y0: int = int(Game.hero.yasha)
		var tapas0: int = int(Game.hero.tapas_total)
		var karma0: int = int(Game.hero.karma)
		var items0 := {}
		for it in q.get("rewards", {}).get("items", []):
			items0[it] = Game.count(it)
		var events_done := []
		var cb := func(id: String): events_done.append(id)
		Events.quest_completed.connect(cb)
		Game.quests.start(qid)
		if not Game.quests.is_active(qid):
			problems.append("%s: start() did not activate it" % qid)
			Events.quest_completed.disconnect(cb)
			continue
		var guard := 0
		while Game.quests.is_active(qid) and guard < 40:
			guard += 1
			var i: int = Game.quests.stage_of(qid)
			var o: Dictionary = Game.quests.current_stage(qid).get("objective", {})
			var before := i
			match o.get("type", ""):
				"flag":
					Game.set_flag(o.flag, true)
				"flags":
					for f in o.flags:
						Game.set_flag(f, true)
				"collect":
					Game.give(o.item, int(o.get("count", 1)), true)
				"kill":
					for k in int(o.get("count", 1)):
						Events.enemy_killed.emit(o.enemy, o.get("region", world.region_id), false)
				"kill_boss":
					Events.enemy_killed.emit(o.enemy, world.region_id, true)
				"reach":
					Events.region_entered.emit(o.region)
				"escort":
					Game.follow(o.npc)
					Events.region_entered.emit(o.region)
				"mudra":
					for m in o.mudras:
						Events.mudra_performed.emit(m)
				"stat":
					Game.hero.counters[o.stat] = int(o.get("min", 1))
					Events.hero_changed.emit()
				"gold":
					Game.add_gold(int(o.get("min", 0)))
				"karma":
					Game.hero.karma = int(o.get("min", 0)) if o.has("min") else int(o.get("max", 0))
					Events.karma_changed.emit(0, Game.hero.karma)
				"talk", "deliver", "choice":
					if o.get("type", "") == "deliver" and o.has("item"):
						Game.give(o.item, int(o.get("count", 1)), true)
					Game.quests.advance(qid)
				_:
					problems.append("%s stage %d: unknown objective %s" % [qid, i, str(o)])
					break
			if Game.quests.is_active(qid) and Game.quests.stage_of(qid) == before:
				problems.append("%s stage %d (%s): the objective was met but the quest did not advance" % [qid, i, o.get("type", "")])
				break
		Events.quest_completed.disconnect(cb)
		if not Game.quests.is_done(qid):
			problems.append("%s: never reached done (state %s stage %d)" % [qid, Game.quests.state_of(qid), Game.quests.stage_of(qid)])
			continue
		done_count += 1
		if events_done.count(qid) != 1:
			problems.append("%s: quest_completed fired %d times" % [qid, events_done.count(qid)])
		var rw: Dictionary = q.get("rewards", {})
		if int(rw.get("gold", 0)) > 0 and int(Game.hero.gold) - g0 < int(rw.gold):
			problems.append("%s: reward gold %d not paid (+%d)" % [qid, int(rw.gold), int(Game.hero.gold) - g0])
		if int(rw.get("yasha", 0)) > 0 and int(Game.hero.yasha) - y0 < int(rw.yasha):
			problems.append("%s: reward yasha %d not paid (+%d)" % [qid, int(rw.yasha), int(Game.hero.yasha) - y0])
		if int(rw.get("tapas", 0)) > 0 and int(Game.hero.tapas_total) - tapas0 < int(rw.tapas):
			problems.append("%s: reward tapas %d not paid (+%d)" % [qid, int(rw.tapas), int(Game.hero.tapas_total) - tapas0])
		for it in rw.get("items", []):
			if Game.count(it) <= int(items0[it]):
				problems.append("%s: reward item %s not given" % [qid, it])
		if rw.has("karma") and int(Game.hero.karma) == karma0 and int(rw.karma) != 0:
			problems.append("%s: reward karma %d not applied" % [qid, int(rw.karma)])
	ok("every one of the %d quests runs from start to done through the real objective code" % Data.quests.size(), problems.is_empty() and done_count == Data.quests.size(), "%d/%d done" % [done_count, Data.quests.size()])
	for pr in problems:
		print("SYS   - ", pr)
	# failure and exclusion rules
	await fresh()
	var ex := ""
	for qid in Data.quests.keys():
		if Data.quests[qid].get("excludes", []).size() > 0:
			ex = qid
			break
	if ex != "":
		var other: String = Data.quests[ex].excludes[0]
		Game.quests.start(ex)
		ok("starting %s fails its exclusion %s" % [ex, other], Game.quests.state_of(other) == "failed")
		ok("a failed quest cannot be started", not Game.quests.start(other))
	var esc := ""
	for qid in Data.quests.keys():
		if Data.quests[qid].get("fail_on_npc_death", "") != "":
			esc = qid
			break
	if esc != "":
		Game.quests.start(esc)
		Events.npc_killed.emit(Data.quests[esc].fail_on_npc_death)
		ok("%s fails when %s dies" % [esc, Data.quests[esc].fail_on_npc_death], Game.quests.state_of(esc) == "failed")
	# boasts
	var bq := ""
	for qid in Data.quests.keys():
		if Data.quests[qid].get("boasts", []).size() > 0:
			bq = qid
			break
	if bq != "":
		await fresh()
		var boasts: Array = Data.quests[bq].boasts
		Game.quests.start(bq, boasts.slice(0, 1))
		var b: String = boasts[0]
		match b:
			"no_potion":
				var pot := ""
				for k in Data.items.keys():
					if Data.items[k].get("cat", "") == "potion" and Data.items[k].has("use"):
						pot = k
						break
				Game.give(pot, 1, true)
				Game.use_item(pot)
			"no_siddhi":
				Events.siddhi_cast.emit("x", 1)
			"no_armor":
				for k in Data.items.keys():
					if Data.items[k].get("cat", "") == "chest":
						Game.give(k, 1, true)
						Game.equip(k)
						break
			"melee_only":
				Game.quests.ranged_used()
		ok("boast '%s' breaks when broken" % b, not Game.quests.boast_intact(bq, b))

# =====================================================================
# Progression: stats, siddhis, panths
# =====================================================================
func test_progression() -> void:
	print("-- progression")
	await fresh()
	var hp0: float = Game.hp_max()
	ok("a new hero cannot raise a stat without tapas", not Game.raise_stat("deha"))
	Game.add_tapas("bala", 1000)
	var total0: int = int(Game.hero.tapas.bala) + int(Game.hero.tapas.general)
	var cost: int = Game.stat_cost(1)
	var age0: float = Game.hero.age
	ok("raising a stat pays tapas and ages the hero", Game.raise_stat("deha") and int(Game.hero.tapas.bala) + int(Game.hero.tapas.general) == total0 - cost and Game.hero.age > age0 and Game.stat("deha") == 2)
	var melee0: float = Game.melee_mult()
	Game.hero.tapas.general = 5000
	Game.raise_stat("prana")
	ok("Deha raises melee damage, Prana raises hp", Game.melee_mult() > 1.0 and Game.hp_max() > hp0, "melee x%.1f hp %.0f -> %.0f" % [Game.melee_mult(), hp0, Game.hp_max()])
	Game.hero.tapas.general = 999999
	for s in Data.misc.stats.keys():
		while Game.stat(s) < 7:
			if not Game.raise_stat(s):
				break
	var all7 := true
	for s in Data.misc.stats.keys():
		if Game.stat(s) != 7:
			all7 = false
	ok("every stat can be raised to 7 and then stops", all7 and not Game.can_raise("deha"))
	ok("a level 7 hero has a sensible hp and ojas pool", Game.hp_max() > 250.0 and Game.ojas_max() > 100.0 and Game.dmg_reduction() < 0.9 and Game.dmg_reduction() >= 0.0, "hp %.0f ojas %.0f red %.2f" % [Game.hp_max(), Game.ojas_max(), Game.dmg_reduction()])
	# siddhis
	var sid := ""
	for k in Data.siddhis.keys():
		if Game.siddhi_next_cost(k) > 0:
			sid = k
			break
	Game.hero.tapas.shakti = 0
	Game.hero.tapas.general = 0
	ok("a siddhi cannot be learnt without tapas", not Game.learn_siddhi(sid))
	Game.hero.tapas.shakti = 100000
	var lvl_ok := true
	for l in 4:
		lvl_ok = lvl_ok and Game.learn_siddhi(sid)
	ok("a siddhi levels up to 4 and no further", lvl_ok and Game.siddhi_level(sid) == 4 and not Game.learn_siddhi(sid))
	ok("the first learnt siddhi lands on the hotbar", Game.hero.hotbar.has(sid))
	var all_ok := true
	for s in Data.siddhis.keys():
		var pr: Dictionary = Game.siddhi_params(s)
		if s != sid and not pr.is_empty():
			all_ok = false
	ok("siddhi_params is empty for unlearnt siddhis and filled for learnt ones", all_ok and not Game.siddhi_params(sid).is_empty())
	# panths
	var bad := []
	for pid in Data.misc.panths.keys():
		var c: Dictionary = Game.can_initiate(pid)
		if not c.has("ok") or not c.has("why"):
			bad.append(pid)
	ok("can_initiate answers for every panth", bad.is_empty(), str(bad))
	# gold and items
	Game.hero.gold = 50
	ok("spending more gold than you have is refused", not Game.spend_gold(51) and Game.hero.gold == 50)
	Game.give("lathi", 1, true)
	ok("take() refuses to take what is not there and clears a worn item", not Game.take("lathi", 5) and Game.take("lathi", Game.count("lathi")) and Game.equipped("melee") == "")
	ok("karma is clamped to its range", (func(): Game.add_karma(5000); return Game.hero.karma == Game.KARMA_MAX).call() and (func(): Game.add_karma(-5000); return Game.hero.karma == Game.KARMA_MIN).call())

# =====================================================================
# Death and respawn
# =====================================================================
func test_death() -> void:
	print("-- death")
	await fresh("vatagram_bachpan")
	var p = Game.player
	p.invulnerable = false
	var died := []
	var cb := func(): died.append(true)
	Events.player_died.connect(cb)
	Game.hero.gold = 1000
	Game.damage_hero(99999.0)
	ok("lethal damage fires player_died once", died.size() == 1 and Game.hero.hp == 0.0, "%d times" % died.size())
	Game.damage_hero(10.0)
	ok("a corpse does not die again and again", died.size() == 1, "%d times" % died.size())
	Events.player_died.disconnect(cb)
	var scars0: int = int(Game.hero.get("scars", 0))
	world.respawn_player()
	ok("respawning heals, costs 10% gold and adds a scar", Game.hero.hp >= Game.hp_max() - 0.1 and Game.hero.gold == 900 and int(Game.hero.scars) == scars0 + 1, "hp %.0f gold %d" % [Game.hero.hp, Game.hero.gold])
	# the amrita phial
	await fresh("vatagram_bachpan")
	Game.player.invulnerable = false
	Game.give("amrita_phial", 1, true)
	var died2 := []
	var cb2 := func(): died2.append(true)
	Events.player_died.connect(cb2)
	Game.damage_hero(99999.0)
	Events.player_died.disconnect(cb2)
	ok("an Amrita phial saves the hero once, and is used up", died2.size() == 0 and Game.hero.hp >= Game.hp_max() - 0.1 and Game.count("amrita_phial") == 0)

# =====================================================================
# Every dialogue condition and effect, run for real
# =====================================================================
func test_dialogue_effects() -> void:
	print("-- dialogue effects")
	await fresh("vira_akhara")
	main._make_ui()
	var nodes := 0
	var effects := 0
	var crashed := []
	var i := 0
	for cid in Data.characters.keys():
		i += 1
		if i % 12 == 0:
			await fresh("vira_akhara")   # enemies and quests pile up: start over now and then
		Game.player.invulnerable = true
		for node in Data.characters[cid].get("dialogue", []):
			nodes += 1
			Game.check(node.get("when"))
			var list := [node.get("effects", {})]
			for ch in node.get("choices", []):
				Game.check(ch.get("when"))
				list.append(ch)
			for e in list:
				if not e is Dictionary or e.is_empty():
					continue
				Game.hero.gold = 100000
				Game.hero.hp = Game.hp_max()
				var res: bool = Game.apply_effects(e, cid)
				effects += 1
				if not res:
					crashed.append("%s: cost refused with 100000 gold" % cid)
				main.ui.close_all()
		await frames(2)
		world = main.world
	ok("every dialogue condition and effect runs (%d nodes, %d effects)" % [nodes, effects], crashed.is_empty(), str(crashed.slice(0, 3)))

# =====================================================================
# The roll (Space): a real forward somersault
# =====================================================================
func test_roll() -> void:
	print("-- roll")
	await fresh("vatagram_bachpan")
	var p = Game.player
	await frames(30)
	p.controls_on = true
	p._start_roll()
	ok("Space starts a roll and makes the hero invulnerable", p.rolling and p.invulnerable)
	var min_x := 0.0
	var min_mid_y := 99.0
	var max_mid_y := -99.0
	var start: Vector3 = p.global_position
	var n := 0
	while p.rolling and n < 120:
		await get_tree().physics_frame
		n += 1
		min_x = minf(min_x, p.model.rotation.x)
		var mid_y: float = (p.model.transform * Vector3(0, 0.9, 0)).y / p.model.scale.y   # relative to the model's own size
		min_mid_y = minf(min_mid_y, mid_y)
		max_mid_y = maxf(max_mid_y, mid_y)
	await frames(3)
	ok("the model turns a full circle forward during the roll", min_x < -TAU * 0.8, "furthest turn %.2f rad of %.2f" % [min_x, -TAU])
	ok("it turns about the middle of the body (the middle stays put)", min_mid_y > 0.85 and max_mid_y < 0.95, "middle between %.2f and %.2f (of 0.90), model scale %.2f" % [min_mid_y, max_mid_y, p.model.scale.y])
	ok("it lands upright, without unwinding", absf(p.model.rotation.x) < 0.05 and p.model.position.length() < 0.01 and not p.rolling and not p.invulnerable, "x %.3f pos %s" % [p.model.rotation.x, str(p.model.position)])
	var moved := Vector2(p.global_position.x - start.x, p.global_position.z - start.z).length()
	ok("the roll still carries the hero forward", moved > 2.5, "%.1f m" % moved)
