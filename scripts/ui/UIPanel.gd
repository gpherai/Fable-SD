## Base of every modal panel: a dimmed screen, a framed window with a title and a close button,
## and a body that subclasses fill in `build()`. `rebuild()` redraws the body (keeping scroll
## positions) and runs by itself when the hero changes, so a panel always shows the truth.
extends Control

const T = preload("res://scripts/ui/UITheme.gd")
const Bindings = preload("res://scripts/systems/Bindings.gd")

## The ring that shows where the keyboard / gamepad focus is. One for the whole panel, drawn above
## everything, so buttons, sliders, checkboxes, lists and the map all look alike.
class FocusRing extends Control:
	const T = preload("res://scripts/ui/UITheme.gd")
	var _target: Control = null
	var _rect := Rect2()
	var _t: float = 0.0
	var _box: StyleBoxFlat = T.box(Color(0, 0, 0, 0), Color("#fff3d0"), 7, 2, 0)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(delta: float) -> void:
		var panel = get_parent()
		var f := get_viewport().gui_get_focus_owner()
		var want: Control = f if (f != null and panel.nav_visible and panel.is_ancestor_of(f) and f.is_visible_in_tree()) else null
		var r := Rect2() if want == null else want.get_global_rect()
		if want != null:
			_t += delta
			queue_redraw()
		elif _target != null:
			queue_redraw()
		_target = want
		_rect = r

	func _draw() -> void:
		if _target == null:
			return
		_box.border_color = Color("#fff3d0", 0.65 + 0.35 * sin(_t * 6.0))
		draw_style_box(_box, Rect2(_rect.position - get_global_rect().position - Vector2(3, 3), _rect.size + Vector2(6, 6)))

var ui                       # the UI manager (UI.gd)
var kind: String = ""
var payload = null
var title_text: String = ""
var closable: bool = true
var win_size := Vector2(1000, 640)
var dim_alpha: float = 0.62
var live: bool = true        # redraw on Events.hero_changed
var framed: bool = true      # false: no window frame or header (the title screen)
var show_header: bool = true     # false: no title row (the dialogue draws its own)
var align_bottom: bool = false   # dock the window at the bottom of the screen (dialogue)
var back_kind: String = ""   # panel to return to when this one closes (settings from the pause menu)
var autofocus: bool = true   # the first control takes the keyboard focus when the panel opens
var nav_visible: bool = false   # the player uses keys / gamepad: show the focus ring and keep the focus through redraws

var window: PanelContainer
var body: VBoxContainer
var _title_label: Label
var _close_btn: Button
var _rebuild_queued: bool = false

## Called by UI.open() before the panel enters the tree. Subclasses set title/win_size in `init()`.
func setup(ui_, kind_: String, payload_) -> void:
	ui = ui_
	kind = kind_
	payload = payload_
	process_mode = Node.PROCESS_MODE_ALWAYS
	init()

func init() -> void:
	pass

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.0, dim_alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_extra_background()
	window = PanelContainer.new()
	window.custom_minimum_size = win_size
	if not framed:
		window.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if align_bottom:
		var dock := VBoxContainer.new()
		dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dock.alignment = BoxContainer.ALIGNMENT_END
		dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dock.add_theme_constant_override("separation", 0)
		add_child(dock)
		window.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		dock.add_child(window)
		dock.add_child(T.spacer(28))
	else:
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		center.add_child(window)
	var outer := T.vbox(10)
	window.add_child(outer)
	var head := T.hbox(10)
	_title_label = T.title(title_text, 30)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title_label)
	_close_btn = T.button("✕  " + Loc.t("UI_CLOSE"), Callable(self, "close"), 110)
	_close_btn.visible = closable
	head.add_child(_close_btn)
	head.visible = framed and show_header
	outer.add_child(head)
	var sep := T.hsep()
	sep.visible = framed and show_header
	outer.add_child(sep)
	body = T.vbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)
	build()
	add_child(FocusRing.new())
	_sync_focus_modes()
	if autofocus:
		focus_first()
	if live:
		Events.hero_changed.connect(_queue_rebuild)
	Events.language_changed.connect(func(_l): _queue_rebuild())

## Subclasses may draw something behind the window (the title screen's mandala).
func _extra_background() -> void:
	pass

func set_title(text: String) -> void:
	title_text = text
	if _title_label != null:
		_title_label.text = text

## Fill `body` here.
func build() -> void:
	pass

func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("rebuild")

func rebuild() -> void:
	_rebuild_queued = false
	if body == null or not is_instance_valid(body):
		return
	var saved: Array = []
	_collect_scroll(body, saved)
	var focus_i := _focus_index()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	build()
	if nav_visible and focus_i >= 0:
		var now_focusable := _focusables()
		if not now_focusable.is_empty():
			now_focusable[clampi(focus_i, 0, now_focusable.size() - 1)].grab_focus(true)
	if not saved.is_empty():
		await get_tree().process_frame
		var now: Array = []
		_collect_nodes(body, now)
		for i in mini(now.size(), saved.size()):
			if is_instance_valid(now[i]):
				now[i].scroll_vertical = int(saved[i])

func _collect_scroll(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c.scroll_vertical)
		_collect_scroll(c, out)

func _collect_nodes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is ScrollContainer:
			out.append(c)
		_collect_nodes(c, out)

# ---------------------------------------------------------------------
# Keyboard and gamepad focus
# ---------------------------------------------------------------------
## Every control in the body the keys can land on, in tree order.
func _focusables() -> Array:
	var out: Array = []
	_collect_focusables(body, out)
	return out

func _collect_focusables(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control:
			if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and not (c is BaseButton and c.disabled):
				out.append(c)
			_collect_focusables(c, out)

## A disabled button must not take the focus. Godot would still land on it, so the focus mode follows
## the `disabled` flag, refreshed whenever the panel is drawn and before every navigation key.
func _sync_focus_modes() -> void:
	_sync_modes_in(self)

func _sync_modes_in(n: Node) -> void:
	for c in n.get_children():
		if c is BaseButton:
			c.focus_mode = Control.FOCUS_NONE if c.disabled else Control.FOCUS_ALL
		_sync_modes_in(c)

func _focus_index() -> int:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	return _focusables().find(f) if f != null else -1

## Puts the focus on the first control of the panel (the close button if the body has none),
## unless something in the panel already has it.
func focus_first() -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f != null and is_ancestor_of(f):
		return
	var list := _focusables()
	if not list.is_empty():
		list[0].grab_focus(true)
	elif _close_btn != null and _close_btn.is_visible_in_tree():
		_close_btn.grab_focus(true)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			nav_visible = false
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# a clicked button must not stay focused, or Space / Enter would press it again
			call_deferred("_drop_button_focus")
	elif (event is InputEventKey or event is InputEventJoypadButton) and event.pressed:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
			if event.is_action_pressed(a):
				nav_visible = true
				_sync_focus_modes()   # before Godot picks the next control: a disabled button is skipped

func _drop_button_focus() -> void:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f is BaseButton and is_ancestor_of(f):
		f.release_focus()

## Esc / the menu key of this panel / the close button.
func close() -> void:
	if ui != null:
		ui.close(self)

## Esc pressed while this panel is on top. Return true if handled here (a sub-view went back).
func on_escape() -> bool:
	return false

## Extra keys a panel wants (Enter / Space for dialogue). Called from UI._unhandled_input.
func on_key(_event: InputEvent) -> bool:
	return false

## Called once when the panel is removed (cleanup, on_done callbacks).
func on_closed() -> void:
	pass
