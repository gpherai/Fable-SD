## The main menu: game title over a slowly turning mandala, then Continue / New game / Load /
## Settings / Controls / Quit.
extends "res://scripts/ui/UIPanel.gd"

class Mandala extends Control:
	var t: float = 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, -30)
		var r := minf(size.x, size.y) * 0.5
		for ring in 6:
			draw_arc(c, r * (0.30 + 0.13 * ring), 0.0, TAU, 120, Color(0.88, 0.69, 0.31, 0.07 + 0.015 * ring), 2.0, true)
		for layer in 3:
			var n := 8 + layer * 4
			var rad := r * (0.50 + 0.17 * layer)
			var dir := 1.0 if layer % 2 == 0 else -1.0
			for i in n:
				var a := TAU * float(i) / float(n) + t * 0.04 * dir + layer * 0.25
				var tip := c + Vector2(cos(a), sin(a)) * rad
				var b1 := c + Vector2(cos(a - PI / n * 0.8), sin(a - PI / n * 0.8)) * rad * 0.84
				var b2 := c + Vector2(cos(a + PI / n * 0.8), sin(a + PI / n * 0.8)) * rad * 0.84
				draw_polyline(PackedVector2Array([b1, tip, b2]), Color(0.95, 0.55, 0.16, 0.16 + 0.04 * layer), 1.5, true)

func init() -> void:
	kind = "title"
	closable = false
	framed = false
	live = false
	dim_alpha = 1.0
	win_size = Vector2(460, 560)

func _extra_background() -> void:
	var m := Mandala.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)

func build() -> void:
	var title := T.label(Loc.t("GAME_TITLE"), 54, T.GOLD, 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var sub := T.label(Loc.t("UI_TITLE_SUB"), 18, T.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(sub)
	body.add_child(T.spacer(26))
	var latest := Game.latest_save_slot()
	if latest >= 0:
		var meta := Game.save_meta(latest)
		var b := T.button("%s  (%s, %s %d)" % [Loc.t("UI_CONTINUE"), str(meta.get("name", "?")), Loc.t("UI_DAY"), int(meta.get("day", 1))], func(): ui.main.load_slot(latest), 0, 48)
		body.add_child(b)
	body.add_child(T.button(Loc.t("UI_NEW_GAME"), func(): ui.open("newgame"), 0, 48))
	var load_btn := T.button(Loc.t("UI_LOAD"), func(): ui.open("saves", {"mode": "load"}, "title"), 0, 48)
	load_btn.disabled = latest < 0
	body.add_child(load_btn)
	body.add_child(T.button(Loc.t("UI_SETTINGS"), func(): ui.open("settings", null, "title"), 0, 48))
	body.add_child(T.button(Loc.t("UI_CONTROLS"), func(): ui.open("controls", null, "title"), 0, 48))
	body.add_child(T.button(Loc.t("UI_QUIT"), func(): get_tree().quit(), 0, 48))
	body.add_child(T.spacer(10, 0, true))
	var ver := T.label("%s %s" % [Loc.t("UI_VERSION"), Game.SD_VERSION], 14, T.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(ver)
