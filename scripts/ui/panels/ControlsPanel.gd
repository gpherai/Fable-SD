## The key list from misc.json ("controls").
extends "res://scripts/ui/UIPanel.gd"

func init() -> void:
	kind = "controls"
	live = false
	win_size = Vector2(760, 640)
	set_title(Loc.t("UI_HELP_TITLE"))

func build() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	for c in Data.misc.get("controls", []):
		var k := T.label(str(c.get("keys", "")), 18, T.GOLD)
		k.custom_minimum_size = Vector2(150, 0)
		grid.add_child(k)
		grid.add_child(T.label(Loc.t(c.get("action", {})), 18))
	body.add_child(T.scroll(grid))
