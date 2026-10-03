## Quest log (Q). Left: active, completed and failed commissions (main story first). Right: the
## selected one with its stages, progress, vows and rewards.
extends "res://scripts/ui/UIPanel.gd"

var tab: String = "active"
var selected: String = ""

func init() -> void:
	kind = "quests"
	win_size = Vector2(1200, 700)
	set_title(Loc.t("UI_QUESTS"))

func build() -> void:
	var tabs := T.hbox(8)
	for t in [["active", "UI_ACTIVE"], ["done", "UI_DONE"], ["failed", "UI_FAILED"]]:
		var id: String = t[0]
		var b := T.button("%s (%d)" % [Loc.t(t[1]), _ids(id).size()], func(): _set_tab(id), 0, 36)
		T.set_selected(b, tab == id)
		tabs.add_child(b)
	body.add_child(tabs)
	var ids := _ids(tab)
	if selected == "" or not ids.has(selected):
		selected = ids[0] if not ids.is_empty() else ""
	var cols := T.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := T.vbox(6)
	left.custom_minimum_size = Vector2(380, 0)
	if ids.is_empty():
		left.add_child(T.label(Loc.t("UI_NO_QUESTS"), 17, T.DIM))
	for kind_name in ["main", "side"]:
		var group := ids.filter(func(id): return str(Data.quest(id).get("type", "side")) == kind_name)
		if group.is_empty():
			continue
		left.add_child(T.label(Loc.t("UI_MAIN_QUESTS" if kind_name == "main" else "UI_SIDE_QUESTS"), 16, T.GOLD))
		for id in group:
			var b := T.button(Loc.t(Data.quest(id).get("name", {})), func(): _select(id), 0, 36)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			T.set_selected(b, id == selected)
			left.add_child(b)
	cols.add_child(T.scroll(left))
	left.get_parent().custom_minimum_size = Vector2(390, 0)
	left.get_parent().size_flags_horizontal = Control.SIZE_FILL
	cols.add_child(_details())

func _ids(which: String) -> Array:
	var out: Array = []
	for id in Game.state.quests.keys():
		if Game.state.quests[id]["state"] == which and Data.quests.has(id):
			out.append(id)
	out.sort_custom(func(a, b) -> bool:
		var qa := Data.quest(a)
		var qb := Data.quest(b)
		return int(qa.get("chapter", 0)) < int(qb.get("chapter", 0)))
	return out

func _details() -> Control:
	var v := T.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected == "":
		return v
	var qd := Data.quest(selected)
	var st := str(Game.state.quests[selected]["state"])
	v.add_child(T.label(Loc.t(qd.get("name", {})), 28, T.GOLD, 4))
	var meta := "%s %d" % [Loc.t("UI_CHAPTER"), int(qd.get("chapter", 0))]
	var giver := Data.character(str(qd.get("giver", "")))
	if not giver.is_empty():
		meta += "  ·  %s: %s" % [Loc.t("UI_QUEST_GIVER"), Loc.t(giver.get("name", {}))]
	v.add_child(T.label(meta, 15, T.DIM))
	v.add_child(T.para(Loc.t(qd.get("desc", {})), 17))
	v.add_child(T.hsep())
	var stages: Array = qd.get("stages", [])
	var cur := int(Game.state.quests[selected].get("stage", 0))
	for i in stages.size():
		var done: bool = st == "done" or i < cur
		var active: bool = st == "active" and i == cur
		if not done and not active and st != "failed":
			continue
		var text := Loc.t(stages[i].get("text", {}))
		var prefix := "✓  " if done else ("▸  " if active else "✗  ")
		var line := T.para(prefix + text, 17, T.GOOD if done else (Color("#8ad0ff") if active else T.DIM))
		v.add_child(line)
		if active:
			var prog: String = Game.quests.progress_text(selected)
			if prog != "":
				v.add_child(T.label("      " + prog, 16, T.GOLD))
	var q: Dictionary = Game.state.quests[selected]
	if not q.get("boasts", []).is_empty():
		v.add_child(T.hsep())
		v.add_child(T.label(Loc.t("UI_BOASTS"), 17, T.GOLD))
		for b in q["boasts"]:
			var broken: bool = q.get("broken", []).has(b)
			var bd: Dictionary = Data.misc.get("boasts", {}).get(b, {})
			v.add_child(T.label("%s  —  %s" % [Loc.t(bd.get("name", {})), Loc.t("UI_QUEST_VOWS_BROKEN" if broken else "UI_QUEST_VOWS_KEPT")], 16, T.BAD if broken else T.GOOD))
	v.add_child(T.hsep())
	v.add_child(T.label(Loc.t("UI_REWARDS"), 17, T.GOLD))
	v.add_child(T.para(_reward_text(qd.get("rewards", {})), 16))
	return T.scroll(v)

func _reward_text(rw: Dictionary) -> String:
	var parts: Array = []
	if int(rw.get("gold", 0)) != 0:
		parts.append("%d %s" % [int(rw["gold"]), Loc.t("UI_GOLD")])
	if int(rw.get("yasha", 0)) != 0:
		parts.append("%d %s" % [int(rw["yasha"]), Loc.t("UI_YASHA").get_slice(" (", 0)])
	if int(rw.get("tapas", 0)) != 0:
		parts.append("%d %s" % [int(rw["tapas"]), Loc.t("UI_TAPAS")])
	if int(rw.get("karma", 0)) != 0:
		parts.append("%+d %s" % [int(rw["karma"]), Loc.t("UI_KARMA")])
	for it in rw.get("items", []):
		parts.append(Loc.t(Data.item(it).get("name", {})))
	return ", ".join(parts) if not parts.is_empty() else "—"

func _set_tab(t: String) -> void:
	tab = t
	selected = ""
	rebuild()

func _select(id: String) -> void:
	selected = id
	rebuild()
