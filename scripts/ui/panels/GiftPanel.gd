## Give a gift to someone (payload = npc id): flowers and trinkets with an `affection` value raise
## how much they like the hero.
extends "res://scripts/ui/UIPanel.gd"

var npc_id: String = ""

func init() -> void:
	kind = "gift"
	npc_id = str(payload)
	win_size = Vector2(700, 560)
	set_title(Loc.t("UI_GIFT_GIVE"))

func build() -> void:
	var who := Loc.t(Data.character(npc_id).get("name", {}))
	body.add_child(T.para(Loc.t("UI_GIFT_PICK", {"name": who}), 18, T.GOLD))
	var list := T.vbox(6)
	var any := false
	for id in Game.hero.inventory.keys():
		var it := Data.item(id)
		if Game.count(id) <= 0 or int(it.get("affection", 0)) <= 0:
			continue
		any = true
		var row := T.hbox(10)
		var info := T.vbox(1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(T.label("%s  x%d" % [Loc.t(it.get("name", {})), Game.count(id)], 18, T.item_color(it).lightened(0.4)))
		info.add_child(T.label("%s +%d" % [Loc.t("UI_AFFECTION"), int(it["affection"])], 14, T.DIM))
		row.add_child(info)
		row.add_child(T.button(Loc.t("UI_GIFT_GIVE"), func(): _give(id, who), 150, 38))
		list.add_child(T.card(row))
	if not any:
		list.add_child(T.label(Loc.t("UI_NOTHING_TO_GIVE"), 17, T.DIM))
	body.add_child(T.scroll(list))

func _give(id: String, who: String) -> void:
	var it := Data.item(id)
	if Game.take(id, 1):
		Game.add_affection(npc_id, int(it.get("affection", 0)))
		Audio.play("pickup")
		Events.notify.emit(Loc.t("UI_GIFT_GIVEN", {"name": who, "item": Loc.t(it.get("name", {}))}), "good")
