## Global signal bus. Every system talks through here so modules stay decoupled.
extends Node

# World / exploration
signal region_entered(region_id: String)
signal region_built(region_id: String)
signal time_changed(hour: float)

# Combat
signal enemy_killed(enemy_id: String, region_id: String, is_boss: bool)
signal enemy_spawned(enemy)
signal damage_dealt(target, amount: float, source: String)
signal player_damaged(amount: float)
signal player_died
signal siddhi_cast(siddhi_id: String, level: int)
signal combat_multiplier_changed(value: int)

# Progression / hero
signal hero_changed
signal karma_changed(delta: int, total: int)
signal gold_changed(total: int)
signal tapas_gained(kind: String, amount: int)
signal stat_raised(stat_id: String, level: int)
signal item_picked(item_id: String, count: int)
signal item_used(item_id: String)
signal ate(item_id: String)
signal equipment_changed
signal yasha_changed(total: int)
signal mudra_performed(mudra_id: String)
signal panth_initiated(panth_id: String)

# Quests / story
signal npc_talked(npc_id: String)
signal npc_killed(npc_id: String)
signal flag_set(flag: String, value)
signal quest_started(quest_id: String)
signal quest_advanced(quest_id: String, stage_index: int)
signal quest_completed(quest_id: String)
signal quest_failed(quest_id: String)
signal boast_broken(quest_id: String, boast_id: String)
signal chest_opened(region_id: String, index: int)
signal yaksha_opened(door_id: String)

# UI
signal notify(text: String, kind: String)
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal cutscene_requested(title: String, pages: Array, on_done: Callable)
signal panel_requested(panel: String, payload)
signal panel_closed
signal language_changed(lang: String)
signal interact_hint(text: String)
signal bindings_changed   # the player rebound a key or reset them: hints and labels must be read again
signal input_device_changed(pad: bool)   # the player went from keyboard/mouse to gamepad or back
signal game_loaded
signal game_saved
