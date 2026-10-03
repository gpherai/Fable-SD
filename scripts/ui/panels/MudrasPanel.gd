## Mudras (X): the hand gestures the hero knows or could learn, and why the others are locked.
## Performing one tells the game (quests and Yaksha doors listen for it).
extends "res://scripts/ui/UIPanel.gd"

func init() -> void:
	kind = "mudras"
	win_size = Vector2(1000, 700)
	set_title(Loc.t("UI_MUDRAS"))

func build() -> void:
	var ids := Data.mudras.keys()
	ids.sort_custom(func(a, b) -> bool:
		var ka := 0 if Game.hero.mudras.has(a) else 1
		var kb := 0 if Game.hero.mudras.has(b) else 1
		return ka < kb or (ka == kb and str(a) < str(b)))
	var list := T.vbox(8)
	for id in ids:
		list.add_child(_card(str(id)))
	body.add_child(T.scroll(list))

func _card(id: String) -> Control:
	var m: Dictionary = Data.mudras[id]
	var av := Game.mudra_available(id)
	var known: bool = Game.hero.mudras.has(id)
	var row := T.hbox(14)
	var info := T.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(T.label(Loc.t(m.get("name", {})), 19, T.GOLD if known else T.DIM))
	info.add_child(T.para(Loc.t(m.get("desc", {})), 15, T.DIM))
	if not bool(av["ok"]) and str(av.get("why", "")) != "":
		info.add_child(T.label(str(av["why"]), 14, T.BAD))
	row.add_child(info)
	var b := T.button(Loc.t("UI_PERFORM"), func(): _perform(id), 130, 38)
	b.disabled = not bool(av["ok"])
	row.add_child(b)
	return T.card(row)

func _perform(id: String) -> void:
	if Game.perform_mudra(id):
		Events.notify.emit(Loc.t("UI_MUDRA_PERFORMED", {"name": Loc.t(Data.mudras[id].get("name", {}))}), "info")
