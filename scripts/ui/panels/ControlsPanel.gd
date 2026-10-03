## The key list from misc.json: "controls" for keyboard and mouse, "controls_pad" for a gamepad. Two tabs;
## it opens on the device the player used last (a gamepad has no way to scroll a long list).
extends "res://scripts/ui/UIPanel.gd"

var _pad_tab: bool = false

func init() -> void:
	kind = "controls"
	live = false
	win_size = Vector2(800, 680)
	_pad_tab = Game.pad_active
	set_title(Loc.t("UI_HELP_TITLE"))

func build() -> void:
	var tabs := T.hbox(8)
	for entry in [[false, "UI_CONTROLS_KEYBOARD"], [true, "UI_CONTROLS_PAD"]]:
		var pad: bool = entry[0]
		var b := T.button(Loc.t(entry[1]), func():
			_pad_tab = pad
			rebuild(), 0, 40)
		T.set_selected(b, _pad_tab == pad)
		tabs.add_child(b)
	body.add_child(tabs)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	for c in Data.misc.get("controls_pad" if _pad_tab else "controls", []):
		var k := T.label(str(c.get("keys", "")), 18, T.GOLD)
		k.custom_minimum_size = Vector2(230, 0)
		grid.add_child(k)
		grid.add_child(T.label(Loc.t(c.get("action", {})), 18))
	body.add_child(T.scroll(grid))
