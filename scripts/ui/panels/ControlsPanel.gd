## The controls: one list per device (keyboard and mouse, gamepad). Every row is an action with the key
## it has now; click it, press the new key or button, and the binding changes at once (Bindings.gd).
## The fixed rows below the list (mouse look, sticks, the menu keys) come from misc.json. Opens on the
## device the player used last: a gamepad has no way to scroll a long list.
extends "res://scripts/ui/UIPanel.gd"

var _pad_tab: bool = false
var _capturing: String = ""      # the action waiting for a key or button, "" when none
var _status: String = ""         # what the last change did

func init() -> void:
	kind = "controls"
	live = false
	win_size = Vector2(820, 700)
	_pad_tab = Game.pad_active
	set_title(Loc.t("UI_HELP_TITLE"))

func _cls() -> String:
	return Bindings.PAD if _pad_tab else Bindings.KBM

func build() -> void:
	var tabs := T.hbox(8)
	for entry in [[false, "UI_CONTROLS_KEYBOARD"], [true, "UI_CONTROLS_PAD"]]:
		var pad: bool = entry[0]
		var b := T.button(Loc.t(entry[1]), func():
			_capturing = ""
			_status = ""
			_pad_tab = pad
			rebuild(), 0, 40)
		T.set_selected(b, _pad_tab == pad)
		tabs.add_child(b)
	tabs.add_child(T.spacer(0, 0, true))
	var reset := T.button(Loc.t("UI_BIND_RESET"), _reset, 0, 40)
	tabs.add_child(reset)
	body.add_child(tabs)
	body.add_child(T.para(_message(), 15, T.GOLD if _capturing != "" else T.DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 5)
	var cls := _cls()
	for a in (Bindings.PAD_ACTIONS if _pad_tab else Bindings.KBM_ACTIONS):
		var name_lbl := T.label(Loc.t("ACT_" + String(a).to_upper()), 18)
		name_lbl.custom_minimum_size = Vector2(430, 0)
		grid.add_child(name_lbl)
		var waiting: bool = _capturing == a
		var btn := T.button("…" if waiting else Bindings.label_all(a, cls), func(): _start_capture(a), 230, 34)
		T.set_selected(btn, waiting or not Bindings.is_default(a, cls))
		grid.add_child(btn)
	for c in Data.misc.get("controls_pad" if _pad_tab else "controls", []):
		var k := T.label(str(c.get("keys", "")), 17, T.DIM)
		grid.add_child(k)
		grid.add_child(T.label("%s: %s" % [Loc.t("UI_BIND_FIXED"), Loc.t(c.get("action", {}))], 15, T.DIM))
	body.add_child(T.scroll(grid))

func _message() -> String:
	if _capturing != "":
		return Loc.t("UI_BIND_PRESS_PAD" if _pad_tab else "UI_BIND_PRESS_KEY", {"action": Loc.t("ACT_" + _capturing.to_upper())})
	return _status if _status != "" else Loc.t("UI_BIND_HINT")

func _start_capture(action: String) -> void:
	_capturing = action
	_status = ""
	rebuild()

func _reset() -> void:
	_capturing = ""
	Bindings.reset(Game.settings, _cls())
	_status = Loc.t("UI_BIND_RESET_DONE")
	Events.bindings_changed.emit()
	rebuild()

## While a binding waits for its key, every press belongs to it: no menu key, no click, no Esc-to-close.
func _input(event: InputEvent) -> void:
	if _capturing == "":
		super._input(event)
		return
	var cancel: bool = (event is InputEventKey and event.pressed and not event.is_echo() and event.physical_keycode == KEY_ESCAPE) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START)
	if cancel:
		_capturing = ""
		rebuild()
		get_viewport().set_input_as_handled()
		return
	var e := Bindings.capture(event, _cls())
	if e == null:
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	var res := Bindings.rebind(Game.settings, action, _cls(), e)
	_capturing = ""
	if not bool(res["ok"]):
		_status = Loc.t("UI_BIND_RESERVED", {"key": Bindings.event_text(e)})
	elif String(res["swapped"]) != "":
		_status = Loc.t("UI_BIND_SWAPPED", {"action": Loc.t("ACT_" + action.to_upper()), "key": Bindings.event_text(e), "other": Loc.t("ACT_" + String(res["swapped"]).to_upper())})
	else:
		_status = Loc.t("UI_BIND_DONE", {"action": Loc.t("ACT_" + action.to_upper()), "key": Bindings.event_text(e)})
	Events.bindings_changed.emit()
	rebuild()

func on_key(_event: InputEvent) -> bool:
	return _capturing != ""

func on_escape() -> bool:
	if _capturing != "":
		_capturing = ""
		rebuild()
		return true
	return false

func on_closed() -> void:
	Game.save_settings()
