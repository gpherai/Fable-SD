## Sadhana (P): the hero's practice. Tapas earned in fights is spent here on the eight attributes
## (each level costs tapas of its discipline, with General tapas filling a shortfall), and the hero's
## age, karma, renown and Panth are shown.
extends "res://scripts/ui/UIPanel.gd"

const STAT_ORDER := ["deha", "prana", "kavacha", "vega", "lakshya", "chaturya", "siddhibala", "ojas"]

func init() -> void:
	kind = "sadhana"
	win_size = Vector2(1240, 720)
	set_title(Loc.t("UI_SADHANA"))

func build() -> void:
	var cols := T.hbox(18)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	cols.add_child(_left())
	cols.add_child(T.scroll(_stats()))

# ---------------------------------------------------------------------
func _left() -> Control:
	var v := T.vbox(8)
	v.custom_minimum_size = Vector2(430, 0)
	v.add_child(T.label(str(Game.hero.get("name", "")), 30, T.GOLD, 5))
	var ash := Game.ashrama()
	v.add_child(T.label("%s  ·  %s" % [Loc.t("UI_YEARS_OLD", {"n": int(Game.hero.age)}), Loc.t(ash.get("name", {}))], 17, T.INK))
	v.add_child(T.para(Loc.t(ash.get("desc", {})), 15, T.DIM))
	v.add_child(T.hsep())
	# karma and renown
	v.add_child(_gauge(Loc.t("UI_KARMA_TITLE") + ": " + Game.karma_title(), float(Game.hero.karma), -1000.0, 1000.0, Color("#9f7bd8")))
	v.add_child(T.label("%s: %s  (%d)" % [Loc.t("UI_YASHA").get_slice(" (", 0), Game.yasha_title(), int(Game.hero.yasha)], 17, T.INK))
	v.add_child(T.label("%s %d   ·   %s %d" % [Loc.t("UI_SAUNDARYA").get_slice(" (", 0), Game.saundarya(), Loc.t("UI_BHAYA").get_slice(" (", 0), Game.bhaya()], 16, T.DIM))
	v.add_child(T.hsep())
	# tapas
	v.add_child(T.label("%s  —  %s: %d" % [Loc.t("UI_TAPAS"), Loc.t("UI_TOTAL_TAPAS"), int(Game.hero.tapas_total)], 18, T.GOLD))
	for k in ["general", "bala", "kaushala", "shakti"]:
		var row := T.hbox(8)
		var lbl := T.label(Loc.t("UI_TAPAS_" + k.to_upper()), 17, T.discipline_color(k) if k != "general" else T.INK)
		lbl.custom_minimum_size = Vector2(110, 0)
		row.add_child(lbl)
		row.add_child(T.label("%d" % int(Game.hero.tapas.get(k, 0)), 17, T.INK))
		v.add_child(row)
	v.add_child(T.hsep())
	# panth and life
	if Game.hero.panth != "":
		var p := Data.panth(Game.hero.panth)
		v.add_child(T.label("%s: %s" % [Loc.t("UI_PANTH"), Loc.t(p.get("name", {}))], 18, T.GOLD))
		v.add_child(T.para(Loc.t(p.get("desc", {})), 15, T.DIM))
	else:
		v.add_child(T.label(Loc.t("UI_PANTH_NONE"), 16, T.DIM))
	var life := "%s: %d   ·   %s: %d   ·   Yaksha: %d" % [Loc.t("UI_KILLS"), int(Game.hero.counters.get("kills", 0)), Loc.t("UI_FOUND_KEYS"), int(Game.hero.counters.get("keys_found", 0)), int(Game.hero.counters.get("yaksha", 0))]
	v.add_child(T.para(life, 15, T.DIM))
	if Game.hero.spouse != "":
		v.add_child(T.label("%s: %s" % [Loc.t("UI_SPOUSE"), Loc.t(Data.character(Game.hero.spouse).get("name", {}))], 16, T.INK))
	if not Game.hero.houses.is_empty():
		var names: Array = []
		for h in Game.hero.houses:
			names.append(Loc.t(Data.region(h).get("name", {})))
		v.add_child(T.para("%s: %s" % [Loc.t("UI_HOUSES"), ", ".join(names)], 15, T.DIM))
	return v

func _gauge(caption: String, value: float, lo: float, hi: float, color: Color) -> Control:
	var v := T.vbox(2)
	v.add_child(T.label(caption, 17, T.INK))
	var b := T.bar(color, 400, 12)
	b.min_value = lo
	b.max_value = hi
	b.value = value
	v.add_child(b)
	return v

# ---------------------------------------------------------------------
func _stats() -> Control:
	var v := T.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id in STAT_ORDER:
		v.add_child(_stat_card(id))
	return v

func _stat_card(id: String) -> Control:
	var sd: Dictionary = Data.misc.stats.get(id, {})
	var disc := str(sd.get("discipline", "bala"))
	var lvl := Game.stat(id)
	var col := T.vbox(4)
	var head := T.hbox(10)
	var caption := T.label(Loc.t(sd.get("name", {})), 20, T.discipline_color(disc).lightened(0.25))
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(caption)
	head.add_child(T.label(_pips(lvl), 20, T.GOLD))
	col.add_child(head)
	col.add_child(T.para(Loc.t(sd.get("desc", {})), 15, T.DIM))
	var foot := T.hbox(10)
	foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if lvl >= 7:
		foot.add_child(T.label(Loc.t("UI_STAT_MAXED"), 16, T.GREEN))
	else:
		var cost := Game.stat_cost(lvl)
		var have := int(Game.hero.tapas.get(disc, 0)) + int(Game.hero.tapas.general)
		var info := T.label("%s: %d  (%s %s: %d)" % [Loc.t("UI_COST"), cost, Loc.t("UI_TAPAS_POOL"), Loc.t("UI_TAPAS_" + disc.to_upper()), have], 15, T.INK if have >= cost else T.BAD)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(info)
		var b := T.button(Loc.t("UI_RAISE"), func(): Game.raise_stat(id), 120, 36)
		b.disabled = not Game.can_raise(id)
		foot.add_child(b)
	col.add_child(foot)
	return T.card(col)

func _pips(lvl: int) -> String:
	var s := ""
	for i in 7:
		s += "◆" if i < lvl else "◇"
	return s
