## A trader's stall (payload = shop id from misc.json "shops"). Left: what is for sale, at the
## price the hero's Chaturya earns them. Right: what the hero can sell, at the trader's offer.
extends "res://scripts/ui/UIPanel.gd"

var shop_id: String = ""
var shop: Dictionary = {}

func init() -> void:
	kind = "shop"
	shop_id = str(payload)
	shop = Data.shop(shop_id)
	win_size = Vector2(1240, 720)
	set_title(Loc.t(shop.get("name", {})))

func build() -> void:
	body.add_child(T.label("%s: %d" % [Loc.t("UI_GOLD").capitalize(), int(Game.hero.gold)], 20, Color("#ffd24a")))
	var cols := T.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	cols.add_child(_buy_list())
	cols.add_child(_sell_list())

func _buy_list() -> Control:
	var wrap := T.vbox(6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(T.label(Loc.t("UI_SHOP_BUY_TAB"), 20, T.GOLD))
	var list := T.vbox(6)
	for id in shop.get("items", []):
		list.add_child(_buy_row(str(id)))
	wrap.add_child(T.scroll(list))
	return wrap

func _sell_list() -> Control:
	var wrap := T.vbox(6)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(T.label(Loc.t("UI_SHOP_SELL_TAB"), 20, T.GOLD))
	var list := T.vbox(6)
	var ids: Array = []
	for id in Game.hero.inventory.keys():
		if Game.count(id) > 0 and Data.items.has(id) and not ["quest", "key"].has(str(Data.item(id).get("cat", ""))):
			ids.append(id)
	ids.sort_custom(func(a, b) -> bool: return Game.item_sell_price(a) > Game.item_sell_price(b))
	for id in ids:
		list.add_child(_sell_row(str(id)))
	if ids.is_empty():
		list.add_child(T.label(Loc.t("UI_SHOP_NOTHING_TO_SELL"), 16, T.DIM))
	wrap.add_child(T.scroll(list))
	return wrap

func _item_info(id: String, count_text: String) -> Control:
	var it := Data.item(id)
	var info := T.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(T.label(Loc.t(it.get("name", {})) + count_text, 18, T.item_color(it).lightened(0.4)))
	info.add_child(T.label(Loc.t(it.get("desc", {})), 13, T.DIM))
	(info.get_child(1) as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return info

func _buy_row(id: String) -> Control:
	var price := Game.item_buy_price(id, float(shop.get("buy_mult", 1.0)))
	var row := T.hbox(10)
	row.add_child(_item_info(id, "   (%s %d)" % [Loc.t("UI_OWNED"), Game.count(id)] if Game.count(id) > 0 else ""))
	var b := T.button("%s  %d" % [Loc.t("UI_BUY"), price], func(): _buy(id, price), 130, 38)
	b.disabled = Game.hero.gold < price
	row.add_child(b)
	return T.card(row)

func _sell_row(id: String) -> Control:
	var price := Game.item_sell_price(id)
	var row := T.hbox(10)
	row.add_child(_item_info(id, "  x%d" % Game.count(id)))
	row.add_child(T.button("%s  %d" % [Loc.t("UI_SELL"), price], func(): _sell(id, price), 130, 38))
	return T.card(row)

func _buy(id: String, price: int) -> void:
	if Game.spend_gold(price):
		Game.give(id, 1, true)
		Audio.play("pickup")
		Events.notify.emit(Loc.t("UI_BOUGHT", {"name": Loc.t(Data.item(id).get("name", {}))}), "item")

func _sell(id: String, price: int) -> void:
	if Game.take(id, 1):
		Game.add_gold(price)
		Audio.play("pickup")
		Events.notify.emit(Loc.t("UI_SOLD", {"name": Loc.t(Data.item(id).get("name", {})), "n": price}), "gold")
