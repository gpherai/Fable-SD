## Temporary on-screen readout (region, time, health, gold, interaction hint, controls).
## Replaced by the real HUD in the UI step.
extends CanvasLayer

var info: Label
var hint: Label
var notice: Label
var _notice_t: float = 0.0

func _ready() -> void:
	layer = 50
	info = _label(Vector2(16, 12), 18)
	hint = _label(Vector2(0, 0), 26)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -130
	hint.offset_bottom = -90
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice = _label(Vector2(0, 0), 24)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice.offset_top = 190
	notice.offset_bottom = 230
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Events.interact_hint.connect(func(t): hint.text = t)
	Events.notify.connect(_on_notify)

func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("#fff3d0"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _on_notify(text: String, _kind: String) -> void:
	notice.text = text
	_notice_t = 3.0

func _process(delta: float) -> void:
	if not Game.in_game or Game.hero.is_empty():
		return
	_notice_t -= delta
	if _notice_t <= 0.0:
		notice.text = ""
	var w: Node = Game.world
	var region := Loc.t(Data.region(Game.state.get("region", "")).get("name", {}))
	info.text = "%s\nDag %d  %s\nHP %d/%d   Ojas %d/%d   Goud %d\nTapas %d   Vijanden: %d\n[Esc] muis vrijmaken   [Spatie] rollen   [Shift] rennen   [E] gebruiken   [scrollwiel] zoom" % [
		region, int(Game.state.get("day", 1)), Game.time_string(),
		int(Game.hero.hp), int(Game.hp_max()), int(Game.hero.ojas), int(Game.ojas_max()), int(Game.hero.gold),
		int(Game.hero.tapas_total), (w.enemies.size() if w != null else 0)]
