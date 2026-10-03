## Rebindable controls. tools/gen_project.py writes the default input map into project.godot; this
## script lays the player's own choices (Game.settings["bindings"]) over it and keeps the rest honest:
## which actions may be rebound, which keys are reserved, what happens when two actions want the same
## key (they swap), and the short labels the HUD and the key list show.
##
## An action holds events of two classes: "kbm" (keys and mouse buttons) and "pad" (gamepad buttons and
## trigger axes). A rebind replaces every event of ONE class of ONE action, so a keyboard change never
## touches the gamepad. settings["bindings"] = {action: {"kbm": [event dicts], "pad": [event dicts]}},
## and only what differs from the defaults is stored. An event dict is {"k": physical keycode},
## {"m": mouse button}, {"b": joypad button} or {"a": joypad axis, "v": +1 or -1}.
extends RefCounted

const KBM := "kbm"
const PAD := "pad"

## Actions that can be rebound on the keyboard and mouse, in the order of the key list.
const KBM_ACTIONS := [
	"move_forward", "move_back", "move_left", "move_right", "attack", "block", "roll", "sprint", "ranged_toggle",
	"lock_target", "interact", "meditate", "siddhi_1", "siddhi_2", "siddhi_3", "siddhi_4", "siddhi_5", "siddhi_6",
	"potion_prana", "potion_ojas", "menu_inventory", "menu_siddhis", "menu_sadhana", "menu_quests", "menu_map",
	"menu_mudras", "menu_codex", "quicksave", "quickload", "help",
]
## ... and on a gamepad. The sticks (move, look), LT (the siddhi layer), Start and B-as-back stay where they are.
const PAD_ACTIONS := [
	"attack", "block", "roll", "sprint", "ranged_toggle", "lock_target", "interact", "meditate", "potion_prana", "potion_ojas",
	"cam_zoom_in", "cam_zoom_out", "menu_inventory", "menu_siddhis", "menu_sadhana", "menu_quests", "menu_map",
	"menu_mudras", "menu_codex",
]

const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D↑", JOY_BUTTON_DPAD_DOWN: "D↓", JOY_BUTTON_DPAD_LEFT: "D←", JOY_BUTTON_DPAD_RIGHT: "D→",
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_TOUCHPAD: "Touchpad",
}
const KEY_NAMES := {
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→", KEY_SPACE: "Space", KEY_ENTER: "Enter", KEY_KP_ENTER: "Enter (num)",
}
const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB", MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}
## A trigger counts as pressed past this (the stick axes are not offered at all).
const AXIS_PRESS := 0.6

## action -> its events as project.godot defined them. Filled once, so a reset has something to go back to.
static var _defaults: Dictionary = {}

# =====================================================================
# Setting up
# =====================================================================
## Remembers the defaults (first call only) and applies the player's overrides.
static func setup(settings: Dictionary) -> void:
	if _defaults.is_empty():
		for a in InputMap.get_actions():
			_defaults[String(a)] = InputMap.action_get_events(a).duplicate()
	apply(settings)

## Defaults for every action, then the overrides on top. Safe to call again after any change.
static func apply(settings: Dictionary) -> void:
	for a in _defaults.keys():
		if not InputMap.has_action(a):
			continue
		InputMap.action_erase_events(a)
		for e in _defaults[a]:
			InputMap.action_add_event(a, e)
	var overrides = settings.get("bindings", {})
	if not (overrides is Dictionary):
		return
	for a in overrides.keys():
		if not InputMap.has_action(a) or not (overrides[a] is Dictionary):
			continue
		for cls in [KBM, PAD]:
			if not overrides[a].has(cls) or not (overrides[a][cls] is Array) or not is_rebindable(a, cls):
				continue
			var events: Array = []
			for d in overrides[a][cls]:
				var e := from_dict(d)
				if e != null and class_of(e) == cls and not is_reserved(e):
					events.append(e)
			if not events.is_empty():   # a damaged entry leaves the defaults alone instead of unbinding the action
				_set_events(a, cls, events)

# =====================================================================
# Reading
# =====================================================================
static func is_rebindable(action: String, cls: String) -> bool:
	return (KBM_ACTIONS if cls == KBM else PAD_ACTIONS).has(action)

static func class_of(event: InputEvent) -> String:
	return PAD if (event is InputEventJoypadButton or event is InputEventJoypadMotion) else KBM

## The events of one class that an action has right now.
static func events_of(action: String, cls: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if class_of(e) == cls:
			out.append(e)
	return out

## Short name of the action's first binding on that device ("E", "LMB", "RT"), "-" when it has none.
static func label(action: String, pad: bool) -> String:
	var list := events_of(action, PAD if pad else KBM)
	return event_text(list[0]) if not list.is_empty() else "-"

## All of its bindings on one device, "W / ↑".
static func label_all(action: String, cls: String) -> String:
	var parts: Array = []
	for e in events_of(action, cls):
		parts.append(event_text(e))
	return " / ".join(parts) if not parts.is_empty() else "-"

static func event_text(e: InputEvent) -> String:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if KEY_NAMES.has(code):
			return KEY_NAMES[code]
		var k := InputEventKey.new()
		k.physical_keycode = code as Key
		return k.as_text_physical_keycode()
	if e is InputEventMouseButton:
		return MOUSE_NAMES.get(e.button_index, "Mouse %d" % e.button_index)
	if e is InputEventJoypadButton:
		return PAD_BUTTON_NAMES.get(e.button_index, "Btn %d" % e.button_index)
	if e is InputEventJoypadMotion:
		match e.axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
			_: return "Axis %d%s" % [e.axis, "+" if e.axis_value > 0.0 else "-"]
	return "?"

# =====================================================================
# Events <-> dictionaries (settings.json)
# =====================================================================
static func to_dict(e: InputEvent) -> Dictionary:
	if e is InputEventKey:
		return {"k": int(e.physical_keycode if e.physical_keycode != 0 else e.keycode)}
	if e is InputEventMouseButton:
		return {"m": int(e.button_index)}
	if e is InputEventJoypadButton:
		return {"b": int(e.button_index)}
	if e is InputEventJoypadMotion:
		return {"a": int(e.axis), "v": 1 if e.axis_value > 0.0 else -1}
	return {}

## A clean event from a dictionary, or null when it is not one of ours (an edited or damaged settings file).
static func from_dict(d) -> InputEvent:
	if not (d is Dictionary):
		return null
	if d.has("k") and (d["k"] is float or d["k"] is int) and int(d["k"]) > 0:
		var e := InputEventKey.new()
		e.physical_keycode = int(d["k"]) as Key
		return e
	if d.has("m") and (d["m"] is float or d["m"] is int):
		var b := int(d["m"])
		if not MOUSE_NAMES.has(b):
			return null
		var e := InputEventMouseButton.new()
		e.button_index = b as MouseButton
		return e
	if d.has("b") and (d["b"] is float or d["b"] is int):
		var b := int(d["b"])
		if b < 0 or b >= JOY_BUTTON_SDL_MAX:
			return null
		var e := InputEventJoypadButton.new()
		e.button_index = b as JoyButton
		return e
	if d.has("a") and d.has("v") and (d["a"] is float or d["a"] is int) and (d["v"] is float or d["v"] is int):
		var a := int(d["a"])
		if a < 0 or a >= JOY_AXIS_SDL_MAX:
			return null
		var e := InputEventJoypadMotion.new()
		e.axis = a as JoyAxis
		e.axis_value = 1.0 if float(d["v"]) > 0.0 else -1.0
		return e
	return null

static func same(a: InputEvent, b: InputEvent) -> bool:
	return class_of(a) == class_of(b) and to_dict(a) == to_dict(b)

# =====================================================================
# Capturing a new binding
# =====================================================================
## What the player pressed, as a clean event, or null when it is not something to bind: releases, key
## repeats, the mouse wheel, stick axes, weak trigger pulls. `cls` is the tab the player is on.
static func capture(event: InputEvent, cls: String) -> InputEvent:
	if cls == KBM:
		if event is InputEventKey and event.pressed and not event.is_echo():
			return from_dict({"k": event.physical_keycode if event.physical_keycode != 0 else event.keycode})
		if event is InputEventMouseButton and event.pressed:
			return from_dict({"m": event.button_index})
	else:
		if event is InputEventJoypadButton and event.pressed:
			return from_dict({"b": event.button_index})
		if event is InputEventJoypadMotion and absf(event.axis_value) >= AXIS_PRESS and (event.axis == JOY_AXIS_TRIGGER_LEFT or event.axis == JOY_AXIS_TRIGGER_RIGHT):
			return from_dict({"a": event.axis, "v": event.axis_value})
	return null

## Esc and Backspace always leave a menu; Start is the pause button; LT holds the siddhi layer.
static func is_reserved(e: InputEvent) -> bool:
	if e is InputEventKey:
		var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return code == KEY_ESCAPE or code == KEY_BACKSPACE
	if e is InputEventJoypadButton:
		return e.button_index == JOY_BUTTON_START
	if e is InputEventJoypadMotion:
		return e.axis == JOY_AXIS_TRIGGER_LEFT
	return false

# =====================================================================
# Changing
# =====================================================================
## Gives `action` the event on that device. Another action that held it swaps: it keeps its other
## bindings, or else takes over what `action` gave up. Returns {"ok", "swapped": the other action or ""}.
static func rebind(settings: Dictionary, action: String, cls: String, e: InputEvent) -> Dictionary:
	if e == null or not is_rebindable(action, cls) or is_reserved(e) or class_of(e) != cls:
		return {"ok": false, "swapped": ""}
	var old := events_of(action, cls)
	var owner := ""
	for other in (KBM_ACTIONS if cls == KBM else PAD_ACTIONS):
		if other == action:
			continue
		for oe in events_of(other, cls):
			if same(oe, e):
				owner = other
	_set_events(action, cls, [e])
	_remember(settings, action, cls)
	if owner != "":
		var rest: Array = events_of(owner, cls).filter(func(x): return not same(x, e))
		if rest.is_empty():
			rest = old.filter(func(x): return not same(x, e))
		_set_events(owner, cls, rest)
		_remember(settings, owner, cls)
	return {"ok": true, "swapped": owner}

## Back to the defaults for one device.
static func reset(settings: Dictionary, cls: String) -> void:
	var overrides = settings.get("bindings", {})
	if overrides is Dictionary:
		for a in overrides.keys():
			if overrides[a] is Dictionary:
				overrides[a].erase(cls)
				if overrides[a].is_empty():
					overrides.erase(a)
	apply(settings)

static func is_default(action: String, cls: String) -> bool:
	var now := events_of(action, cls)
	var was: Array = (_defaults.get(action, []) as Array).filter(func(x): return class_of(x) == cls)
	if now.size() != was.size():
		return false
	for i in now.size():
		if not same(now[i], was[i]):
			return false
	return true

static func _set_events(action: String, cls: String, events: Array) -> void:
	for e in events_of(action, cls):
		InputMap.action_erase_event(action, e)
	for e in events:
		InputMap.action_add_event(action, e)

## Writes the action's current events of one class into the settings, or drops the entry when they equal the defaults.
static func _remember(settings: Dictionary, action: String, cls: String) -> void:
	if not (settings.get("bindings") is Dictionary):
		settings["bindings"] = {}
	var all: Dictionary = settings["bindings"]
	if is_default(action, cls):
		if all.has(action) and all[action] is Dictionary:
			all[action].erase(cls)
			if all[action].is_empty():
				all.erase(action)
		return
	if not (all.get(action) is Dictionary):
		all[action] = {}
	all[action][cls] = events_of(action, cls).map(func(x): return to_dict(x))
