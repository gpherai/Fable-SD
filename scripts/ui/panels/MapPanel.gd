## Map (M, or a Tirtha gate: payload "tirtha"). Jambudvipa has no drawn map yet: this lists the
## paths out of the current region and the Tirtha gates the hero has unlocked. Travel between
## gates only works while standing at a gate.
extends "res://scripts/ui/UIPanel.gd"

var at_gate: bool = false

func init() -> void:
	kind = "map"
	live = false
	at_gate = str(payload) == "tirtha"
	win_size = Vector2(1000, 700)
	set_title(Loc.t("UI_MAP"))

func build() -> void:
	var here: String = str(Game.state.get("region", ""))
	var rd := Data.region(here)
	body.add_child(T.label("%s: %s" % [Loc.t("UI_CURRENT"), Loc.t(rd.get("name", {}))], 24, T.GOLD))
	body.add_child(T.para(Loc.t(rd.get("desc", {})), 16, T.DIM))
	body.add_child(T.para(Loc.t("UI_MAP_AT_GATE") if at_gate else Loc.t("UI_TIRTHA_FAR"), 17, T.GOOD if at_gate else T.DIM))
	body.add_child(T.hsep())
	var cols := T.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var exits := T.vbox(6)
	exits.custom_minimum_size = Vector2(340, 0)
	exits.add_child(T.label(Loc.t("UI_MAP_EXITS"), 19, T.GOLD))
	if rd.get("exits", []).is_empty():
		exits.add_child(T.label("—", 16, T.DIM))
	for ex in rd.get("exits", []):
		var to := Data.region(str(ex.get("to", "")))
		exits.add_child(T.card(T.label("%s  →  %s" % [Loc.t("UI_MAP_DIR_" + str(ex.get("dir", "N"))), Loc.t(to.get("name", {}))], 16)))
	cols.add_child(T.scroll(exits))
	var gates := T.vbox(6)
	gates.add_child(T.label(Loc.t("UI_MAP_TIRTHAS"), 19, T.GOLD))
	var tirthas: Array = Game.state.get("tirthas", [])
	if tirthas.is_empty():
		gates.add_child(T.label(Loc.t("UI_MAP_NO_TIRTHAS"), 16, T.DIM))
	for rid in tirthas:
		gates.add_child(_gate_row(str(rid), here))
	cols.add_child(T.scroll(gates))

func _gate_row(rid: String, here: String) -> Control:
	var r := Data.region(rid)
	var row := T.hbox(10)
	var info := T.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(T.label(Loc.t(r.get("name", {})), 19, T.INK))
	info.add_child(T.label("%s %d" % [Loc.t("UI_DANGER"), int(r.get("danger", 0))], 14, T.DIM))
	row.add_child(info)
	if rid == here:
		row.add_child(T.label(Loc.t("UI_CURRENT"), 16, T.GREEN))
	else:
		var b := T.button(Loc.t("UI_TRAVEL"), func(): _travel(rid), 120, 38)
		b.disabled = not at_gate
		row.add_child(b)
	return T.card(row)

func _travel(rid: String) -> void:
	if Game.world == null:
		return
	ui.close(self)
	Game.world.travel(rid, "")
