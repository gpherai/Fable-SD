## Esc during play: resume, save, load, settings, controls, back to the title screen.
extends "res://scripts/ui/UIPanel.gd"

var _confirm_title: bool = false
var _confirm_quit: bool = false

func init() -> void:
	kind = "pause"
	live = false
	win_size = Vector2(500, 680)
	set_title(Loc.t("UI_PAUSED"))

func build() -> void:
	body.add_child(T.button(Loc.t("UI_RESUME"), close, 0, 46))
	# the screens that have a key on the keyboard (I, Q, M, P, O, X) are also reachable from here, for a gamepad
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for entry in [["UI_INVENTORY", "inventory"], ["UI_QUESTS", "quests"], ["UI_MAP", "map"], ["UI_SADHANA", "sadhana"], ["UI_SIDDHIS", "siddhis"], ["UI_MUDRAS", "mudras"]]:
		var b := T.button(Loc.t(entry[0]), func(): ui.open(entry[1], null, "pause"), 0, 42)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	body.add_child(grid)
	body.add_child(T.hsep())
	body.add_child(T.button(Loc.t("UI_SAVE"), func(): ui.open("saves", {"mode": "save"}, "pause"), 0, 46))
	var load_btn := T.button(Loc.t("UI_LOAD"), func(): ui.open("saves", {"mode": "load"}, "pause"), 0, 46)
	load_btn.disabled = Game.latest_save_slot() < 0
	body.add_child(load_btn)
	body.add_child(T.button(Loc.t("UI_SETTINGS"), func(): ui.open("settings", null, "pause"), 0, 46))
	body.add_child(T.button(Loc.t("UI_CONTROLS"), func(): ui.open("controls", null, "pause"), 0, 46))
	body.add_child(T.button(Loc.t("UI_CODEX"), func(): ui.open("codex", null, "pause"), 0, 46))
	body.add_child(T.hsep())
	var to_title := T.button(Loc.t("UI_SURE") if _confirm_title else Loc.t("UI_TO_TITLE"), _on_title, 0, 46)
	body.add_child(to_title)
	var quit := T.button(Loc.t("UI_SURE") if _confirm_quit else Loc.t("UI_QUIT"), _on_quit, 0, 46)
	body.add_child(quit)
	if _confirm_title or _confirm_quit:
		body.add_child(T.para(Loc.t("UI_CONFIRM_TITLE"), 14, T.BAD))
	body.add_child(T.spacer(0, 0, true))
	var played := int(Game.state.get("play_time", 0.0))
	body.add_child(T.label("%s: %d:%02d:%02d" % [Loc.t("UI_PLAY_TIME"), played / 3600, (played / 60) % 60, played % 60], 14, T.DIM))

func _on_title() -> void:
	if not _confirm_title:
		_confirm_title = true
		_confirm_quit = false
		rebuild()
		return
	ui.main.to_title()

func _on_quit() -> void:
	if not _confirm_quit:
		_confirm_quit = true
		_confirm_title = false
		rebuild()
		return
	get_tree().quit()
