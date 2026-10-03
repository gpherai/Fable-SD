## Pratijna: vows the hero may take on when a commission starts (payload = quest id). Keeping a vow
## pays extra gold and renown when the quest is done; Quests.gd breaks them on the first slip.
extends "res://scripts/ui/UIPanel.gd"

var quest_id: String = ""
var chosen: Array = []

func init() -> void:
	kind = "boasts"
	live = false
	quest_id = str(payload)
	win_size = Vector2(760, 560)
	set_title(Loc.t("UI_BOASTS"))

func build() -> void:
	var qd: Dictionary = Data.quest(quest_id)
	body.add_child(T.label(Loc.t(qd.get("name", {})), 22, Color("#8ad0ff")))
	body.add_child(T.para(Loc.t("UI_CHOOSE_BOASTS"), 17, T.DIM))
	var list := T.vbox(8)
	for b in qd.get("boasts", []):
		var bd: Dictionary = Data.misc.get("boasts", {}).get(b, {})
		if bd.is_empty():
			continue
		var blocked: bool = b == "no_armor" and Game.wearing_armor()
		var cb := CheckBox.new()
		cb.text = Loc.t(bd.get("name", {}))
		cb.add_theme_font_size_override("font_size", 20)
		cb.disabled = blocked
		cb.button_pressed = chosen.has(b)
		cb.toggled.connect(func(on: bool):
			if on and not chosen.has(b):
				chosen.append(b)
			elif not on:
				chosen.erase(b))
		var col := T.vbox(2)
		col.add_child(cb)
		col.add_child(T.para(Loc.t(bd.get("desc", {})), 15, T.DIM))
		col.add_child(T.label(Loc.t("UI_BOAST_REWARD", {"gold": int(bd.get("gold", 0)), "yasha": int(bd.get("yasha", 0))}) + ("   " + Loc.t("UI_BOAST_ARMOR_ON") if blocked else ""), 14, T.GOLD))
		list.add_child(T.card(col))
	body.add_child(T.scroll(list))
	var row := T.hbox(8)
	row.add_child(T.spacer(0, 0, true))
	row.add_child(T.button(Loc.t("UI_BOAST_ACCEPT"), _accept, 240, 46))
	body.add_child(row)

func _accept() -> void:
	if Game.state.quests.has(quest_id):
		Game.state.quests[quest_id]["boasts"] = chosen.duplicate()
	close()
