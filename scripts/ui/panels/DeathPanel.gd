## "Yama calls": shown after the hero falls. Rising again wakes the hero at the region's edge with
## the death penalty (World.respawn_player); a save can be loaded instead.
extends "res://scripts/ui/UIPanel.gd"

func init() -> void:
	kind = "death"
	closable = false
	live = false
	framed = false
	dim_alpha = 0.78
	win_size = Vector2(620, 380)

func build() -> void:
	var t := T.label(Loc.t("UI_DEATH_TITLE"), 52, Color("#d9503c"), 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(t)
	var txt := T.para(Loc.t("UI_DEATH_TEXT"), 20, T.INK)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(txt)
	body.add_child(T.spacer(18))
	body.add_child(T.button(Loc.t("UI_DEATH_BUTTON"), _rise, 0, 50))
	var latest := Game.latest_save_slot()
	if latest >= 0:
		body.add_child(T.button(Loc.t("UI_DEATH_LOAD"), func(): ui.main.load_slot(latest), 0, 44))
	body.add_child(T.button(Loc.t("UI_TO_TITLE"), func(): ui.main.to_title(), 0, 44))

func _rise() -> void:
	if Game.world != null:
		Game.world.respawn_player()
	ui.close(self)
