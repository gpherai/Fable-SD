## The UI manager. Owns the HUD and at most one modal panel at a time (menu, dialogue, shop...).
## An open panel pauses the world (SceneTree.paused), frees the mouse and tells the game
## (`Game.paused_for_ui`); closing it hands everything back. It also turns the events the game
## fires (dialogue_started, cutscene_requested, panel_requested, panel_closed) into panels and
## listens for the menu keys (I, O, P, Q, M, X, C, Esc, F5, F9).
extends Node

const T = preload("res://scripts/ui/UITheme.gd")

## panel kind -> script. Loaded on first use.
const PANELS := {
	"title": "res://scripts/ui/panels/TitlePanel.gd",
	"pause": "res://scripts/ui/panels/PausePanel.gd",
	"settings": "res://scripts/ui/panels/SettingsPanel.gd",
	"saves": "res://scripts/ui/panels/SavesPanel.gd",
	"controls": "res://scripts/ui/panels/ControlsPanel.gd",
	"newgame": "res://scripts/ui/panels/NewGamePanel.gd",
	"death": "res://scripts/ui/panels/DeathPanel.gd",
	"dialogue": "res://scripts/ui/panels/DialoguePanel.gd",
	"cutscene": "res://scripts/ui/panels/CutscenePanel.gd",
	"boasts": "res://scripts/ui/panels/BoastsPanel.gd",
	"yaksha": "res://scripts/ui/panels/YakshaPanel.gd",
	"marmara_choice": "res://scripts/ui/panels/MarmaraChoicePanel.gd",
	"inventory": "res://scripts/ui/panels/InventoryPanel.gd",
	"quests": "res://scripts/ui/panels/QuestsPanel.gd",
	"sadhana": "res://scripts/ui/panels/SadhanaPanel.gd",
	"siddhis": "res://scripts/ui/panels/SiddhisPanel.gd",
	"mudras": "res://scripts/ui/panels/MudrasPanel.gd",
	"map": "res://scripts/ui/panels/MapPanel.gd",
	"trainer": "res://scripts/ui/panels/TrainerPanel.gd",
	"shop": "res://scripts/ui/panels/ShopPanel.gd",
	"gift": "res://scripts/ui/panels/GiftPanel.gd",
	"shrine": "res://scripts/ui/panels/ShrinePanel.gd",
	"codex": "res://scripts/ui/panels/CodexPanel.gd",
}

## input action -> panel it toggles (only while playing).
const MENU_KEYS := {
	"menu_inventory": "inventory", "menu_quests": "quests", "menu_sadhana": "sadhana",
	"menu_siddhis": "siddhis", "menu_mudras": "mudras", "menu_map": "map", "menu_codex": "codex",
	"help": "controls",
}

## panels that cover the whole screen, so the HUD is hidden behind them.
const HIDE_HUD := ["title", "cutscene", "newgame", "dialogue"]
## W A S D (and the arrow keys) -> the menu-navigation action they stand for while a panel is open.
const NAV_ACTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const WASD_TO_NAV := {"move_forward": "ui_up", "move_back": "ui_down", "move_left": "ui_left", "move_right": "ui_right"}
## panels that only the game itself closes (no Esc).
const NO_ESCAPE := ["title", "death", "newgame"]

var main                       # Main.gd: start / load / back to title
var hud                        # HUD.gd
var current: Control = null
var _layer: CanvasLayer
var _death_pending: bool = false
var _opened_msec: int = 0   # when the current panel appeared (see _unhandled_input)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 60
	_layer.name = "Modal"
	add_child(_layer)
	var hud_script: GDScript = load("res://scripts/ui/HUD.gd")
	hud = hud_script.new()
	hud.name = "HUD"
	add_child(hud)
	Events.dialogue_started.connect(func(npc_id: String): open("dialogue", npc_id))
	Events.cutscene_requested.connect(func(title: String, pages: Array, on_done: Callable): open("cutscene", {"title": title, "pages": pages, "on_done": on_done}))
	Events.panel_requested.connect(_on_panel_requested)
	Events.panel_closed.connect(_on_panel_closed)

# =====================================================================
# Opening and closing
# =====================================================================
## `back`: the panel to return to when this one closes.
func open(kind: String, payload = null, back: String = "") -> Control:
	if not PANELS.has(kind):
		push_warning("UI: unknown panel " + kind)
		return null
	var guard := 0
	while current != null and guard < 4:   # a panel's on_closed may open another one: drop that too
		_remove_current()
		guard += 1
	var script: GDScript = load(PANELS[kind])
	if script == null:
		push_warning("UI: cannot load " + PANELS[kind])
		return null
	var p: Control = script.new()
	p.theme = T.theme()
	p.name = kind.capitalize().replace(" ", "")
	p.back_kind = back
	p.setup(self, kind, payload)
	current = p
	_opened_msec = Time.get_ticks_msec()
	_layer.add_child(p)
	_enter_modal(kind)
	return p

func _remove_current() -> Control:
	var p := current
	current = null
	p.on_closed()   # may open the next panel (a cutscene's end)
	p.queue_free()
	return p

func close(panel: Control = null, go_back: bool = true) -> void:
	if current == null or (panel != null and panel != current):
		return
	var p := _remove_current()
	if current == null and go_back and p.back_kind != "":
		open(p.back_kind)
	if current == null:
		_leave_modal()

func close_all() -> void:
	if current != null:
		close(current, false)

func is_open(kind: String = "") -> bool:
	return current != null and (kind == "" or current.kind == kind)

func _enter_modal(kind: String) -> void:
	Game.paused_for_ui = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Game.player != null and is_instance_valid(Game.player):
		Game.player.release_mouse()
	hud.visible = not HIDE_HUD.has(kind) and Game.in_game
	hud.set_modal(true)

func _leave_modal() -> void:
	Game.paused_for_ui = false
	get_tree().paused = false
	hud.visible = Game.in_game
	hud.set_modal(false)
	var pl = Game.player
	if Game.in_game and pl != null and is_instance_valid(pl) and not pl.dead:
		pl.capture_mouse()
		pl.combat.ignore_held_buttons()

# =====================================================================
# Events from the game
# =====================================================================
func _on_panel_requested(panel: String, payload) -> void:
	if panel == "death":
		_open_death_later()
	elif PANELS.has(panel):
		open(panel, payload)

func _on_panel_closed() -> void:
	if current != null and not NO_ESCAPE.has(current.kind):
		close(current, false)

## The hero falls over first (half a second), then the screen comes.
func _open_death_later() -> void:
	if _death_pending:
		return
	_death_pending = true
	await get_tree().create_timer(1.2, true).timeout
	_death_pending = false
	if Game.in_game and Game.player != null and Game.player.dead:
		open("death")

# =====================================================================
# Keys
# =====================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.pressed or event.is_echo():
		return
	if current != null:
		# the key press that opened the panel (E on an NPC) reaches this node too: it must not also act inside it
		if Time.get_ticks_msec() - _opened_msec < 150:
			return
		if current.on_key(event):
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_back"):   # Esc, Backspace, or B on a gamepad
			if not current.on_escape() and current.closable and not NO_ESCAPE.has(current.kind):
				close(current)
			get_viewport().set_input_as_handled()
			return
		for action in MENU_KEYS.keys():
			if event.is_action_pressed(action) and current.kind == MENU_KEYS[action] and current.closable:
				close(current)
				get_viewport().set_input_as_handled()
				return
		if _menu_navigation(event):
			get_viewport().set_input_as_handled()
		return
	if not _can_open_menu():
		return
	if event.is_action_pressed("pause"):
		open("pause")
		get_viewport().set_input_as_handled()
		return
	for action in MENU_KEYS.keys():
		if event.is_action_pressed(action):
			open(MENU_KEYS[action])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("quicksave"):
		Game.save_game(0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quickload"):
		if Game.has_save(0) and main != null:
			main.load_slot(0)
		else:
			Events.notify.emit(Loc.t("UI_SLOT_EMPTY"), "bad")
		get_viewport().set_input_as_handled()

## Menu navigation that the focused control did not take itself. Arrow keys and the d-pad move the
## focus by themselves (Godot's ui_* actions); this catches the first press when nothing has the focus
## yet, and turns W A S D into the same arrows. Returns true when the event is used up.
func _menu_navigation(event: InputEvent) -> bool:
	var action := ""
	for a in NAV_ACTIONS:
		if event.is_action_pressed(a):
			action = a
	var wasd := ""
	if action == "":
		for w in WASD_TO_NAV.keys():
			if event.is_action_pressed(w):
				action = WASD_TO_NAV[w]
				wasd = w
	if action == "" and (event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")):
		action = "ui_down"
	if action == "":
		return false
	current.nav_visible = true
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not current.is_ancestor_of(f):
		current.focus_first()
		return true
	if wasd != "":
		var arrow := InputEventAction.new()   # the focused control reads it like the arrow key (slider, list, map...)
		arrow.action = action
		arrow.pressed = true
		Input.parse_input_event(arrow)
		return true
	return false

func _can_open_menu() -> bool:
	var pl = Game.player
	return Game.in_game and pl != null and is_instance_valid(pl) and not pl.dead and not (Game.world != null and Game.world.traveling)
