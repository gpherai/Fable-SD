## A story card: title and pages of text on black (Events.cutscene_requested). Click / Space /
## Enter for the next page, Esc skips the rest. `on_done` (a Callable) runs when it ends.
extends "res://scripts/ui/UIPanel.gd"

var title: String = ""
var pages: Array = []
var on_done: Callable = Callable()
var page: int = 0
var _text: Label
var _hint: Label
var _tween: Tween = null

func init() -> void:
	kind = "cutscene"
	live = false
	framed = false
	dim_alpha = 1.0
	win_size = Vector2(980, 560)
	var d: Dictionary = payload if payload is Dictionary else {}
	title = str(d.get("title", ""))
	pages = d.get("pages", [])
	on_done = d.get("on_done", Callable())

func build() -> void:
	var t := T.label(title, 40, T.GOLD, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(t)
	body.add_child(T.hsep())
	_text = T.para("", 24)
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.add_child(_text)
	_hint = T.label("%s  (%d/%d)" % [Loc.t("UI_CLICK_CONTINUE"), 1, maxi(1, pages.size())], 15, T.DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_hint)
	_show_page()

func _show_page() -> void:
	if page >= pages.size():
		close()
		return
	_text.text = Loc.t(pages[page])
	_hint.text = "%s  (%d/%d)" % [Loc.t("UI_CLICK_CONTINUE"), page + 1, pages.size()]
	_text.modulate.a = 0.0
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_text, "modulate:a", 1.0, 0.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_next()
		accept_event()

func on_key(event: InputEvent) -> bool:
	if event.is_action_pressed("interact") or (event is InputEventKey and event.physical_keycode == KEY_SPACE):
		_next()
		return true
	return false

func _next() -> void:
	page += 1
	_show_page()

## Esc: skip the rest (UI.close runs on_closed, which fires on_done).
func on_escape() -> bool:
	close()
	return true

func on_closed() -> void:
	if on_done.is_valid():
		on_done.call()
