## Inventory and equipment (I). Left: what the hero wears and the numbers that follow from it.
## Middle: the bag by category. Right: the selected item with its actions (equip, use, drop,
## set a gem in a weapon).
extends "res://scripts/ui/UIPanel.gd"

const SLOT_KEYS := {"melee": "UI_WEAPON_MELEE", "ranged": "UI_WEAPON_RANGED", "head": "UI_HEAD", "chest": "UI_CHEST", "hands": "UI_HANDS",
	"legs": "UI_LEGS", "feet": "UI_FEET", "hair": "UI_HAIR", "beard": "UI_BEARD", "tattoo": "UI_TATTOO"}
const CATS := [
	["all", "UI_CAT_ALL", []],
	["weapons", "UI_CAT_WEAPONS", ["melee", "ranged"]],
	["armor", "UI_CAT_ARMOR", ["head", "chest", "hands", "legs", "feet"]],
	["consumable", "UI_CAT_CONSUMABLE", ["potion", "food"]],
	["books", "UI_CAT_BOOKS", ["book"]],
	["gems", "UI_CAT_GEMS", ["gem"]],
	["trophies", "UI_CAT_TROPHIES", ["trophy"]],
	["quest", "UI_CAT_QUEST", ["quest", "key"]],
	["cosmetic", "UI_CAT_COSMETIC", ["hair", "beard", "tattoo"]],
	["tools", "UI_CAT_TOOLS", ["tool", "gift"]],
]

var cat: String = "all"
var selected: String = ""

func init() -> void:
	kind = "inventory"
	win_size = Vector2(1360, 760)
	set_title(Loc.t("UI_INVENTORY"))

func build() -> void:
	if selected != "" and not Game.has(selected) and not _worn(selected):
		selected = ""
	var cols := T.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	cols.add_child(_left_column())
	cols.add_child(_middle_column())
	cols.add_child(_right_column())

func _worn(id: String) -> bool:
	return Game.hero.equipment.values().has(id)

# ---------------------------------------------------------------------
# Left: worn items and numbers
# ---------------------------------------------------------------------
func _left_column() -> Control:
	var v := T.vbox(6)
	v.custom_minimum_size = Vector2(380, 0)
	v.add_child(T.label(Loc.t("UI_EQUIP_SLOTS"), 20, T.GOLD))
	for slot in Game.EQUIP_SLOTS:
		var id: String = Game.equipped(slot)
		var it := Data.item(id)
		var text: String = Loc.t(it.get("name", {})) if id != "" else Loc.t("UI_EMPTY")
		var b := T.button("%s:  %s" % [Loc.t(SLOT_KEYS[slot]), text], func(): _select(id), 0, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		b.clip_text = true
		b.disabled = id == ""
		if id != "":
			b.add_theme_color_override("font_color", T.item_color(it).lightened(0.35))
		if id != "" and id == selected:
			T.set_selected(b, true)
		v.add_child(b)
	v.add_child(T.hsep())
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 2)
	v.add_child(g)
	_stat(g, Loc.t("UI_DEF"), "%d" % int(Game.total_def()))
	_stat(g, Loc.t("UI_REDUCTION"), "%d%%" % int(round(Game.dmg_reduction() * 100.0)))
	_stat(g, Loc.t("UI_MELEE_POWER"), "x%.2f" % Game.melee_mult())
	_stat(g, Loc.t("UI_RANGED_POWER"), "x%.2f" % Game.ranged_mult())
	_stat(g, Loc.t("UI_SIDDHI_POWER"), "x%.2f" % Game.siddhi_mult())
	_stat(g, Loc.t("UI_MOVE_SPEED"), "%d%%" % int(round(Game.speed_mult() * 100.0)))
	_stat(g, Loc.t("UI_WEIGHT"), "%.1f" % Game.armor_weight())
	_stat(g, Loc.t("UI_SAUNDARYA"), "%d" % Game.saundarya())
	_stat(g, Loc.t("UI_BHAYA"), "%d" % Game.bhaya())
	v.add_child(T.spacer(0, 0, true))
	v.add_child(T.label("%s: %d" % [Loc.t("UI_GOLD").capitalize(), int(Game.hero.gold)], 20, Color("#ffd24a")))
	return v

func _stat(g: GridContainer, caption: String, value: String) -> void:
	var a := T.label(caption, 15, T.DIM)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(a)
	g.add_child(T.label(value, 15, T.INK))

# ---------------------------------------------------------------------
# Middle: the bag
# ---------------------------------------------------------------------
func _middle_column() -> Control:
	var v := T.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for c in CATS:
		var id: String = c[0]
		var b := T.button(Loc.t(c[1]), func(): _set_cat(id), 0, 32)
		T.set_selected(b, cat == id)
		tabs.add_child(b)
	v.add_child(tabs)
	var list := T.vbox(4)
	var ids := _bag_ids()
	for id in ids:
		list.add_child(_row(id))
	if ids.is_empty():
		list.add_child(T.label(Loc.t("UI_NO_ITEMS"), 17, T.DIM))
	v.add_child(T.scroll(list))
	return v

func _bag_ids() -> Array:
	var allowed: Array = []
	for c in CATS:
		if c[0] == cat:
			allowed = c[2]
	var out: Array = []
	for id in Game.hero.inventory.keys():
		if Game.count(id) <= 0 or not Data.items.has(id):
			continue
		if cat == "all" or allowed.has(Data.item(id).get("cat", "")):
			out.append(id)
	out.sort_custom(func(a, b) -> bool:
		var ia := Data.item(a)
		var ib := Data.item(b)
		var ca := str(ia.get("cat", ""))
		var cb := str(ib.get("cat", ""))
		if ca != cb:
			return ca < cb
		return int(ia.get("value", 0)) > int(ib.get("value", 0)))
	return out

func _row(id: String) -> Control:
	var it := Data.item(id)
	var line := T.hbox(8)
	var dot := ColorRect.new()
	dot.color = T.item_color(it)
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(dot)
	var title := T.label(Loc.t(it.get("name", {})), 18, T.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)
	if _worn(id):
		line.add_child(T.label("● " + Loc.t("UI_EQUIPPED"), 14, T.GREEN))
	if Game.count(id) > 1:
		line.add_child(T.label("x%d" % Game.count(id), 17, T.GOLD))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = false
	b.add_theme_stylebox_override("normal", T.box(Color("#5a3a1c") if id == selected else T.WOOD2, T.SAFFRON if id == selected else Color("#3a2a1a"), 5, 2 if id == selected else 1, 10))
	b.add_theme_stylebox_override("hover", T.box(T.WOOD3, T.GOLD, 5, 2, 10))
	b.custom_minimum_size = Vector2(0, 38)
	b.pressed.connect(func(): _select(id))
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 10
	line.offset_right = -10
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)
	return b

# ---------------------------------------------------------------------
# Right: the selected item
# ---------------------------------------------------------------------
func _right_column() -> Control:
	var v := T.vbox(8)
	v.custom_minimum_size = Vector2(400, 0)
	if selected == "":
		v.add_child(T.label(Loc.t("UI_SELECT_ITEM"), 18, T.DIM))
		return v
	var it := Data.item(selected)
	var title := T.label(Loc.t(it.get("name", {})), 24, T.item_color(it).lightened(0.4), 4)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(title)
	var desc := Loc.t(it.get("desc", {}))
	if desc != "":
		v.add_child(T.para(desc, 16, T.DIM))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 2)
	for row in _item_facts(it):
		_stat(g, row[0], row[1])
	v.add_child(g)
	v.add_child(_gem_block(it))
	v.add_child(T.spacer(0, 0, true))
	v.add_child(_actions(it))
	return v

func _item_facts(it: Dictionary) -> Array:
	var rows: Array = []
	if Data.is_weapon(it):
		rows.append([Loc.t("UI_DMG"), "%d" % int(it.get("dmg", 0))])
		rows.append([Loc.t("UI_SPEED"), "%.2f" % float(it.get("speed", 1.0))])
		if it.get("cat", "") == "melee":
			rows.append([Loc.t("UI_REACH"), "%.1f" % float(it.get("reach", 1.5))])
		else:
			rows.append([Loc.t("UI_RANGE"), "%d" % int(it.get("range", 0))])
		rows.append([Loc.t("UI_SLOTS"), "%d" % int(it.get("slots", 0))])
		if bool(it.get("two_handed", false)):
			rows.append([Loc.t("UI_TWO_HANDED"), "✓"])
	if Data.is_armor(it):
		rows.append([Loc.t("UI_DEF"), "%d" % int(it.get("def", 0))])
		rows.append([Loc.t("UI_WEIGHT"), "%.1f" % float(it.get("weight", 0.0))])
		if int(it.get("ojas", 0)) != 0:
			rows.append([Loc.t("UI_OJAS"), "+%d" % int(it["ojas"])])
	if int(it.get("saundarya", 0)) != 0:
		rows.append([Loc.t("UI_SAUNDARYA"), "%+d" % int(it["saundarya"])])
	if int(it.get("bhaya", 0)) != 0:
		rows.append([Loc.t("UI_BHAYA"), "%+d" % int(it["bhaya"])])
	var u: Dictionary = it.get("use", {})
	if u.has("heal"):
		rows.append([Loc.t("UI_PRANA"), "+%d" % int(u["heal"])])
	if u.has("ojas"):
		rows.append([Loc.t("UI_OJAS"), "+%d" % int(u["ojas"])])
	if u.has("tapas"):
		rows.append([Loc.t("UI_TAPAS"), "+%d" % int(u["tapas"])])
	if u.has("karma"):
		rows.append([Loc.t("UI_KARMA"), "%+d" % int(u["karma"])])
	if int(it.get("yasha", 0)) > 0:
		rows.append([Loc.t("UI_PRESTIGE"), "+%d" % int(it["yasha"])])
	if int(it.get("affection", 0)) > 0:
		rows.append([Loc.t("UI_GIFT_FOR", {"n": int(it["affection"])}), ""])
	if it.has("guna"):
		rows.append(["Guna", Loc.t(Data.misc.get("gunas", {}).get(it["guna"], {}).get("name", {})).get_slice(" (", 0)])
	rows.append([Loc.t("UI_VALUE"), "%d" % int(it.get("value", 0))])
	rows.append([Loc.t("UI_OWNED").capitalize(), "%d" % Game.count(selected)])
	return rows

## Gems set in a weapon, and the gems that could still be set in it.
func _gem_block(it: Dictionary) -> Control:
	var v := T.vbox(4)
	if not Data.is_weapon(it) or int(it.get("slots", 0)) <= 0:
		return v
	var set_gems: Array = Game.hero.augments.get(selected, [])
	var free := int(it["slots"]) - set_gems.size()
	v.add_child(T.hsep())
	v.add_child(T.label("%s  (%s)" % [Loc.t("UI_GEMS"), Loc.t("UI_GEM_FREE", {"n": free})], 16, T.GOLD))
	for gid in set_gems:
		v.add_child(T.label("◆ " + Loc.t(Data.item(gid).get("name", {})), 15, T.item_color(Data.item(gid))))
	if free > 0 and Game.has(selected):
		for gid in Game.hero.inventory.keys():
			if Data.item(gid).get("cat", "") == "gem" and Game.count(gid) > 0:
				v.add_child(T.button("%s: %s" % [Loc.t("UI_SOCKET"), Loc.t(Data.item(gid).get("name", {}))], func(): Game.socket_gem(selected, gid), 0, 32))
	return v

func _actions(it: Dictionary) -> Control:
	var v := T.vbox(6)
	var cat_id: String = str(it.get("cat", ""))
	var slot := Game.slot_for(it)
	if slot != "":
		if Game.equipped(slot) == selected:
			v.add_child(T.button(Loc.t("UI_UNEQUIP"), func(): Game.unequip(slot), 0, 42))
		elif Game.has(selected):
			v.add_child(T.button(Loc.t("UI_EQUIP"), func(): _equip(selected), 0, 42))
	elif not it.get("use", {}).is_empty() and Game.has(selected):
		v.add_child(T.button(Loc.t("UI_READ") if cat_id == "book" else Loc.t("UI_USE"), func(): Game.use_item(selected), 0, 42))
	if Game.has(selected):
		var can_drop := not ["quest", "key"].has(cat_id)
		var d := T.button(Loc.t("UI_DROP"), func(): _drop(selected), 0, 36)
		d.disabled = not can_drop
		v.add_child(d)
	return v

# ---------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------
func _select(id: String) -> void:
	selected = id
	Audio.play("ui", -8.0)
	rebuild()

func _set_cat(c: String) -> void:
	cat = c
	rebuild()

func _equip(id: String) -> void:
	if not Game.equip(id):
		Events.notify.emit(Loc.t("UI_CHILD_NO_WEAPON"), "bad")

func _drop(id: String) -> void:
	Game.drop_item(id)
