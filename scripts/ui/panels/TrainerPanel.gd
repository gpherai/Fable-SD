## A teacher's lesson (payload = trainer id from misc.json "trainers"): the siddhis they teach
## (level by level, paid in Shakti/General tapas) and the Panth they can initiate the hero into.
extends "res://scripts/ui/UIPanel.gd"

var trainer_id: String = ""
var cfg: Dictionary = {}

func init() -> void:
	kind = "trainer"
	trainer_id = str(payload)
	cfg = Data.misc.get("trainers", {}).get(trainer_id, {})
	win_size = Vector2(1000, 700)
	set_title("%s — %s" % [Loc.t("UI_TRAINER"), Loc.t(Data.character(trainer_id).get("name", {}))])

func build() -> void:
	var tp := int(Game.hero.tapas.get("shakti", 0)) + int(Game.hero.tapas.general)
	body.add_child(T.label("%s: %d" % [Loc.t("UI_TAPAS_POOL"), tp], 16, T.GOLD))
	var list := T.vbox(8)
	for id in cfg.get("siddhis", []):
		list.add_child(_siddhi_card(str(id)))
	if cfg.has("panth"):
		list.add_child(T.label(Loc.t("UI_TRAINER_PANTH"), 20, T.GOLD))
		list.add_child(_panth_card(str(cfg["panth"])))
	if cfg.get("siddhis", []).is_empty() and not cfg.has("panth"):
		list.add_child(T.label(Loc.t("UI_TRAINER_NONE"), 17, T.DIM))
	body.add_child(T.scroll(list))

func _siddhi_card(id: String) -> Control:
	var sd := Data.siddhi(id)
	var lvl := Game.siddhi_level(id)
	var row := T.hbox(14)
	var icon := T.label(str(sd.get("icon", "")), 26, Color.html(str(sd.get("color", "#ffffff"))), 6)
	icon.custom_minimum_size = Vector2(54, 0)
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(icon)
	var info := T.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(T.label("%s   %s %d / 4" % [Loc.t(sd.get("name", {})), Loc.t("UI_LEVEL"), lvl], 19, T.GOLD))
	info.add_child(T.para(Loc.t(sd.get("desc", {})), 15, T.DIM))
	row.add_child(info)
	if lvl >= 4:
		row.add_child(T.label(Loc.t("UI_MAX_LEVEL"), 16, T.GREEN))
	else:
		var cost := Game.siddhi_next_cost(id)
		var b := T.button("%s  (%s)" % [Loc.t("UI_LEARN"), Loc.t("UI_SIDDHI_LEARN_COST", {"n": cost})], func(): Game.learn_siddhi(id), 220, 40)
		b.disabled = not Game.can_learn_siddhi(id)
		row.add_child(b)
	return T.card(row)

func _panth_card(pid: String) -> Control:
	var p := Data.panth(pid)
	var col := T.vbox(4)
	col.add_child(T.label(Loc.t(p.get("name", {})), 19, T.INK))
	col.add_child(T.para(Loc.t(p.get("desc", {})), 15, T.DIM))
	var check := Game.can_initiate(pid)
	var row := T.hbox(10)
	var why := T.label(str(check.get("why", "")) if not bool(check["ok"]) else "%s: %d %s" % [Loc.t("UI_COST"), int(p.get("cost", 0)), Loc.t("UI_GOLD")], 15, T.BAD if not bool(check["ok"]) else T.GOLD)
	why.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(why)
	var b := T.button(Loc.t("UI_INITIATE"), func(): Game.initiate(pid), 150, 38)
	b.disabled = not bool(check["ok"])
	row.add_child(b)
	col.add_child(row)
	return T.card(col)
