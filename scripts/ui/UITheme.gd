## Look of every menu and panel: palette, one Theme for the whole UI and small builders so the
## panels stay short. Everything is drawn from code (no image assets): dark temple wood, gold
## trim, saffron accents.
extends RefCounted

const INK := Color("#fff3d0")        # normal text
const DIM := Color("#b9a98a")        # secondary text
const GOLD := Color("#e0b050")       # borders, titles
const SAFFRON := Color("#f28c28")    # highlights, selected
const WOOD := Color("#1c130e")       # panel background
const WOOD2 := Color("#2b1d14")      # raised background (rows, buttons)
const WOOD3 := Color("#3d2a1c")      # hover
const RED := Color("#c0392b")
const GREEN := Color("#58b368")
const BLUE := Color("#3b7dd8")
const BAD := Color("#ff6a5a")
const GOOD := Color("#9fe0a0")

const KIND_COLORS := {
	"good": Color("#9fe0a0"), "bad": Color("#ff7a6a"), "info": Color("#fff3d0"), "item": Color("#ffd98a"),
	"gold": Color("#ffd24a"), "quest": Color("#8ad0ff"), "boss": Color("#ff9a6a"), "region": Color("#ffe9b0"),
	"karma_up": Color("#c8f0ff"), "karma_down": Color("#c09aff"),
}

static var _theme: Theme = null

# ---------------------------------------------------------------------
# Styleboxes
# ---------------------------------------------------------------------
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 6, border_w: int = 0, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s

## The Theme every UI root gets: buttons, panels, bars, scrollbars, sliders, line edits.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color.BLACK)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color("#6f6350"))
	t.set_stylebox("normal", "Button", box(WOOD2, Color("#6b4e2a"), 5, 1, 12))
	t.set_stylebox("hover", "Button", box(WOOD3, GOLD, 5, 2, 12))
	t.set_stylebox("pressed", "Button", box(Color("#5a3a1c"), SAFFRON, 5, 2, 12))
	t.set_stylebox("disabled", "Button", box(Color("#1a120d"), Color("#3a2c1c"), 5, 1, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", box(WOOD, GOLD, 10, 2, 16))
	t.set_stylebox("panel", "Panel", box(WOOD, GOLD, 10, 2, 16))
	t.set_stylebox("background", "ProgressBar", box(Color("#120c08"), Color("#5a4326"), 4, 1, 0))
	t.set_stylebox("fill", "ProgressBar", box(GREEN, Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("normal", "LineEdit", box(Color("#120c08"), Color("#6b4e2a"), 4, 1, 8))
	t.set_stylebox("focus", "LineEdit", box(Color("#120c08"), GOLD, 4, 2, 8))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_stylebox("slider", "HSlider", box(Color("#120c08"), Color("#5a4326"), 4, 1, 7))
	t.set_stylebox("grabber_area", "HSlider", box(SAFFRON, Color(0, 0, 0, 0), 4, 0, 7))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(GOLD, Color(0, 0, 0, 0), 4, 0, 7))
	t.set_stylebox("scroll", "VScrollBar", box(Color("#120c08"), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color("#6b4e2a"), Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD, Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(SAFFRON, Color(0, 0, 0, 0), 4, 0, 0))
	t.set_stylebox("normal", "OptionButton", box(WOOD2, Color("#6b4e2a"), 5, 1, 12))
	t.set_stylebox("hover", "OptionButton", box(WOOD3, GOLD, 5, 2, 12))
	t.set_stylebox("pressed", "OptionButton", box(WOOD3, SAFFRON, 5, 2, 12))
	t.set_stylebox("panel", "PopupMenu", box(WOOD, GOLD, 6, 2, 8))
	t.set_stylebox("hover", "PopupMenu", box(WOOD3, Color(0, 0, 0, 0), 4, 0, 6))
	var line := StyleBoxLine.new()
	line.color = Color("#5a4326")
	t.set_stylebox("separator", "HSeparator", line)
	t.set_stylebox("panel", "ItemList", box(Color("#120c08"), Color("#4a3520"), 5, 1, 6))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_stylebox("selected", "ItemList", box(Color("#5a3a1c"), SAFFRON, 4, 1, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color("#5a3a1c"), SAFFRON, 4, 1, 4))
	t.set_stylebox("hovered", "ItemList", box(WOOD3, Color(0, 0, 0, 0), 4, 0, 4))
	t.set_color("font_color", "ItemList", INK)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_font_size("font_size", "ItemList", 17)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("h_separation", "GridContainer", 8)
	t.set_constant("v_separation", "GridContainer", 8)
	_theme = t
	return t

# ---------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------
static func label(text: String, size: int = 18, color: Color = INK, outline: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A wrapping label for paragraphs.
static func para(text: String, size: int = 17, color: Color = INK) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func title(text: String, size: int = 28) -> Label:
	var l := label(text, size, GOLD, 4)
	return l

static func button(text: String, cb: Callable = Callable(), min_w: float = 0.0, min_h: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE   # Space / Enter are game keys, a focused button would also fire on them
	b.custom_minimum_size = Vector2(min_w, min_h)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b

static func hsep() -> HSeparator:
	return HSeparator.new()

static func spacer(h: float = 0.0, w: float = 0.0, expand: bool = false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func margin(child: Control, m: int = 8) -> MarginContainer:
	var mc := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(child)
	return mc

static func scroll(child: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(child)
	return sc

## A coloured bar (Prana, Ojas, tapas...).
static func bar(color: Color, w: float = 200.0, h: float = 16.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 4, 0, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

## A framed card for list rows and info blocks.
static func card(child: Control, bg: Color = WOOD2, border: Color = Color("#4a3520")) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, 6, 1, 10))
	p.add_child(child)
	return p

## Stat/discipline colours from misc.json, falling back to gold.
static func discipline_color(id: String) -> Color:
	var d: Dictionary = Data.misc.get("disciplines", {}).get(id, {})
	return Color.html(str(d.get("color", "#e0b050")))

static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, INK)

## Gold-bordered button state for "selected" (tabs, categories).
static func set_selected(b: Button, on: bool) -> void:
	if on:
		b.add_theme_stylebox_override("normal", box(Color("#5a3a1c"), SAFFRON, 5, 2, 12))
		b.add_theme_color_override("font_color", Color.WHITE)
	else:
		b.remove_theme_stylebox_override("normal")
		b.remove_theme_color_override("font_color")

## Item colour dot / name colour by item data.
static func item_color(it: Dictionary) -> Color:
	return Color.html(str(it.get("color", "#cccccc")))
