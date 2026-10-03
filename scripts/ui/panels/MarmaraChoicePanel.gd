## After the last Rangabhumi round: spare Marmara or give the crowd its blood. The data holds no
## story for either yet, so the choice only moves karma and renown and sets the flags
## `marmara_spared` / `marmara_killed` for later chapters to read.
extends "res://scripts/ui/UIPanel.gd"

func init() -> void:
	kind = "marmara_choice"
	closable = false
	live = false
	win_size = Vector2(700, 420)
	set_title(Loc.t("UI_MARMARA_TITLE"))

func build() -> void:
	body.add_child(T.para(Loc.t("UI_MARMARA_TEXT"), 21))
	body.add_child(T.spacer(0, 0, true))
	body.add_child(T.button(Loc.t("UI_MARMARA_SPARE"), _spare, 0, 52))
	body.add_child(T.button(Loc.t("UI_MARMARA_KILL"), _kill, 0, 52))

func _spare() -> void:
	Game.set_flag("marmara_spared", true)
	Game.add_karma(40)
	Game.add_yasha(30)
	Events.notify.emit(Loc.t("UI_MARMARA_SPARED"), "good")
	ui.close(self)

func _kill() -> void:
	Game.set_flag("marmara_killed", true)
	Game.add_karma(-60)
	Events.notify.emit(Loc.t("UI_MARMARA_KILLED"), "bad")
	ui.close(self)
