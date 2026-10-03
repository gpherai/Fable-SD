## Siddhis (O): the powers the hero knows, their level, cost and cooldown, and which of the keys
## 1-6 casts them. Learning happens at a teacher (TrainerPanel).
extends "res://scripts/ui/UIPanel.gd"

func init() -> void:
	kind = "siddhis"
	win_size = Vector2(1100, 700)
	set_title(Loc.t("UI_SIDDHIS"))

func build() -> void:
	body.add_child(T.para(Loc.t("UI_HOTBAR_HINT"), 15, T.DIM))
	var known: Array = []
	for id in Data.siddhis.keys():
		if Game.siddhi_level(id) > 0:
			known.append(id)
	known.sort_custom(func(a, b) -> bool: return str(Data.siddhi(a).get("school", "")) + a < str(Data.siddhi(b).get("school", "")) + b)
	if known.is_empty():
		body.add_child(T.label(Loc.t("UI_NO_SIDDHIS"), 18, T.DIM))
		return
	var list := T.vbox(8)
	for id in known:
		list.add_child(_card(id))
	body.add_child(T.scroll(list))

func _card(id: String) -> Control:
	var sd := Data.siddhi(id)
	var lvl := Game.siddhi_level(id)
	var p := Game.siddhi_params(id)
	var row := T.hbox(14)
	var icon := T.label(str(sd.get("icon", "")), 28, Color.html(str(sd.get("color", "#ffffff"))), 6)
	icon.custom_minimum_size = Vector2(56, 0)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(icon)
	var info := T.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(T.label("%s   %s %d / 4" % [Loc.t(sd.get("name", {})), Loc.t("UI_LEVEL"), lvl], 20, T.GOLD))
	info.add_child(T.para(Loc.t(sd.get("desc", {})), 15, T.DIM))
	info.add_child(T.label("%s: %d   ·   %s: %.1f s" % [Loc.t("UI_OJAS"), int(round(float(p.get("cost", 0)) * Game.siddhi_cost_mult())), Loc.t("UI_SIDDHI_COOLDOWN"), float(sd.get("cooldown", 1.0))], 15, T.INK))
	row.add_child(info)
	var keys := T.hbox(4)
	for i in 6:
		var slot := i
		var b := T.button(str(i + 1), func(): _assign(slot, id), 40, 40)
		T.set_selected(b, str(Game.hero.hotbar[i]) == id)
		keys.add_child(b)
	row.add_child(keys)
	return T.card(row)

func _assign(slot: int, id: String) -> void:
	if str(Game.hero.hotbar[slot]) == id:
		Game.set_hotbar(slot, "")
		return
	for i in 6:
		if str(Game.hero.hotbar[i]) == id:
			Game.hero.hotbar[i] = ""
	Game.set_hotbar(slot, id)
