## Base of every modal panel: a dimmed screen, a framed window with a title and a close button,
## and a body that subclasses fill in `build()`. `rebuild()` redraws the body (keeping scroll
## positions) and runs by itself when the hero changes, so a panel always shows the truth.
extends Control

const T = preload("res://scripts/ui/UITheme.gd")

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
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	build()
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
