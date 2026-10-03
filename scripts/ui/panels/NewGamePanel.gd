## Name entry for a new game.
extends "res://scripts/ui/UIPanel.gd"

var edit: LineEdit

func init() -> void:
	kind = "newgame"
	closable = false
	live = false
	win_size = Vector2(520, 330)
	set_title(Loc.t("UI_NEW_GAME"))

func build() -> void:
	body.add_child(T.para(Loc.t("UI_HERO_NAME"), 20, T.GOLD))
	edit = LineEdit.new()
	edit.text = "Vira"
	edit.max_length = 20
	edit.custom_minimum_size = Vector2(0, 44)
	edit.add_theme_font_size_override("font_size", 22)
	edit.text_submitted.connect(func(_t: String): _begin())
	body.add_child(edit)
	body.add_child(T.para(Loc.t("UI_NEW_GAME_WARN"), 15, T.DIM))
	body.add_child(T.spacer(0, 0, true))
	var row := T.hbox(10)
	row.add_child(T.button(Loc.t("UI_BACK"), func(): ui.open("title"), 140, 46))
	row.add_child(T.spacer(0, 0, true))
	row.add_child(T.button(Loc.t("UI_START"), _begin, 180, 46))
	body.add_child(row)
	edit.call_deferred("grab_focus")
	edit.call_deferred("select_all")

func _begin() -> void:
	ui.main.start_new(edit.text.strip_edges())

func on_escape() -> bool:
	ui.open("title")
	return true
