## Settings: language, mouse, sound, day length, graphics. Every change is applied at once and
## written to user://saves/settings.json when the panel closes.
extends "res://scripts/ui/UIPanel.gd"

func init() -> void:
	kind = "settings"
	live = false
	win_size = Vector2(720, 640)
	set_title(Loc.t("UI_SETTINGS"))

func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 14)
	body.add_child(grid)
	# language
	grid.add_child(T.label(Loc.t("UI_LANGUAGE"), 19))
	var lang_row := T.hbox(8)
	for l in Loc.LANGS:
		var b := T.button(l.to_upper(), func(): _set_lang(l), 80, 38)
		T.set_selected(b, Loc.lang == l)
		lang_row.add_child(b)
	grid.add_child(lang_row)
	# sliders
	_slider(grid, "UI_MOUSE_SENS", "mouse_sens", 0.3, 3.0, 0.05, "x%.2f")
	_slider(grid, "UI_PAD_SENS", "pad_sens", 0.3, 3.0, 0.05, "x%.2f")
	_slider(grid, "UI_MUSIC", "music", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(grid, "UI_SFX", "sfx", 0.0, 1.0, 0.05, "%d%%", 100.0)
	_slider(grid, "UI_TIME_SPEED", "time_speed", 0.25, 3.0, 0.25, "x%.2f")
	# quality
	grid.add_child(T.label(Loc.t("UI_QUALITY"), 19))
	var q_row := T.hbox(8)
	for q in ["low", "high"]:
		var b := T.button(Loc.t("UI_LOW") if q == "low" else Loc.t("UI_HIGH"), func(): _set_quality(q), 110, 38)
		T.set_selected(b, str(Game.settings.get("quality", "high")) == q)
		q_row.add_child(b)
	grid.add_child(q_row)
	# toggles
	grid.add_child(T.label(Loc.t("UI_INVERT_Y"), 19))
	grid.add_child(_toggle("invert_y"))
	grid.add_child(T.label(Loc.t("UI_SHOW_FPS"), 19))
	grid.add_child(_toggle("show_fps"))
	body.add_child(T.para(Loc.t("UI_RESTART_REGION"), 14, T.DIM))
	body.add_child(T.spacer(0, 0, true))
	var row := T.hbox(8)
	row.add_child(T.spacer(0, 0, true))
	row.add_child(T.button(Loc.t("UI_BACK"), close, 160, 44))
	body.add_child(row)

func _slider(grid: GridContainer, key: String, setting: String, lo: float, hi: float, step: float, fmt: String, shown_mult: float = 1.0) -> void:
	grid.add_child(T.label(Loc.t(key), 19))
	var row := T.hbox(10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Game.settings.get(setting, 1.0))
	s.custom_minimum_size = Vector2(300, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := T.label(fmt % (s.value * shown_mult), 17, T.GOLD)
	val.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v: float):
		Game.settings[setting] = v
		val.text = fmt % (v * shown_mult)
		if setting in ["music", "sfx"]:
			Audio.refresh_volumes())
	row.add_child(s)
	row.add_child(val)
	grid.add_child(row)

func _toggle(setting: String) -> Control:
	var cb := CheckButton.new()
	cb.button_pressed = bool(Game.settings.get(setting, false))
	cb.toggled.connect(func(on: bool): Game.settings[setting] = on)
	var holder := HBoxContainer.new()
	holder.add_child(cb)
	return holder

func _set_lang(l: String) -> void:
	Loc.set_lang(l)
	Game.settings["lang"] = l
	set_title(Loc.t("UI_SETTINGS"))
	rebuild()

func _set_quality(q: String) -> void:
	Game.settings["quality"] = q
	if Game.world != null and is_instance_valid(Game.world) and Game.world.sun != null and not Game.world.is_interior():
		Game.world.sun.shadow_enabled = q != "low"
	rebuild()

func on_closed() -> void:
	Game.save_settings()
