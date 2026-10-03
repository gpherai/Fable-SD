## Codex (C): everything in the game's data, by tab: people, creatures, items, siddhis, moves,
## mudras, regions, Yaksha doors, Panths, lore, quests and attributes.
extends "res://scripts/ui/UIPanel.gd"

const TABS := [
	["characters", "UI_CODEX_CHARACTERS"], ["enemies", "UI_CODEX_ENEMIES"], ["items", "UI_CODEX_ITEMS"],
	["siddhis", "UI_CODEX_SIDDHIS"], ["moves", "UI_CODEX_MOVES"], ["mudras", "UI_CODEX_MUDRAS"],
	["regions", "UI_CODEX_REGIONS"], ["yaksha", "UI_CODEX_YAKSHA"], ["panths", "UI_CODEX_PANTHS"],
	["lore", "UI_CODEX_LORE"], ["quests", "UI_CODEX_QUESTS"], ["stats", "UI_CODEX_STATS"],
]

var tab: String = "characters"
var entries: Array = []
var selected: int = 0

func init() -> void:
	kind = "codex"
	live = false
	win_size = Vector2(1300, 740)
	set_title(Loc.t("UI_CODEX"))

func build() -> void:
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	for t in TABS:
		var id: String = t[0]
		var b := T.button(Loc.t(t[1]), func(): _set_tab(id), 0, 32)
		T.set_selected(b, tab == id)
		tabs.add_child(b)
	body.add_child(tabs)
	entries = _entries(tab)
	selected = clampi(selected, 0, maxi(0, entries.size() - 1))
	var cols := T.hbox(14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(380, 0)
	list.focus_mode = Control.FOCUS_NONE
	for e in entries:
		list.add_item(str(e["title"]))
	if not entries.is_empty():
		list.select(selected)
	list.item_selected.connect(_on_selected)
	cols.add_child(list)
	var text := T.vbox(8)
	if entries.is_empty():
		text.add_child(T.label(Loc.t("UI_CODEX_EMPTY"), 17, T.DIM))
	else:
		var e: Dictionary = entries[selected]
		text.add_child(T.label(str(e["title"]), 26, T.GOLD, 4))
		if str(e.get("sub", "")) != "":
			text.add_child(T.label(str(e["sub"]), 16, T.DIM))
		text.add_child(T.para(str(e.get("text", "")), 17))
	cols.add_child(T.scroll(text))

func _set_tab(t: String) -> void:
	tab = t
	selected = 0
	rebuild()

func _on_selected(i: int) -> void:
	selected = i
	rebuild()

func _names(ids: Array, dict_name: String) -> String:
	var out: Array = []
	for id in ids:
		match dict_name:
			"items":
				out.append(Loc.t(Data.item(str(id)).get("name", {})))
			"enemies":
				out.append(Loc.t(Data.enemy(str(id)).get("name", {})))
			_:
				out.append(str(id))
	return ", ".join(out)

func _sorted(dict: Dictionary) -> Array:
	var ids: Array = dict.keys()
	ids.sort_custom(func(a, b) -> bool: return Loc.t(dict[a].get("name", {})) < Loc.t(dict[b].get("name", {})))
	return ids

func _entries(which: String) -> Array:
	var out: Array = []
	match which:
		"characters":
			for id in _sorted(Data.characters):
				var c: Dictionary = Data.characters[id]
				out.append({"title": Loc.t(c.get("name", {})), "sub": Loc.t(c.get("role", {})), "text": Loc.t(c.get("desc", {}))})
		"enemies":
			for id in _sorted(Data.enemies):
				var e: Dictionary = Data.enemies[id]
				var facts := "%s %d   ·   %s %d   ·   %s %d" % [Loc.t("UI_LEVEL"), int(e.get("level", 1)), Loc.t("UI_HP"), int(e.get("hp", 0)), Loc.t("UI_DMG"), int(e.get("dmg", 0))]
				var txt := Loc.t(e.get("desc", {}))
				if not e.get("weak", []).is_empty():
					txt += "\n\n%s: %s" % [Loc.t("UI_WEAK"), ", ".join(e["weak"])]
				if not e.get("resist", []).is_empty():
					txt += "\n%s: %s" % [Loc.t("UI_RESIST"), ", ".join(e["resist"])]
				var drops: Array = []
				for d in e.get("drops", []):
					drops.append(str(d.get("item", "")))
				if not drops.is_empty():
					txt += "\n%s: %s" % [Loc.t("UI_DROPS"), _names(drops, "items")]
				out.append({"title": Loc.t(e.get("name", {})), "sub": facts, "text": txt})
		"items":
			for id in _sorted(Data.items):
				var it: Dictionary = Data.items[id]
				out.append({"title": Loc.t(it.get("name", {})), "sub": "%s   ·   %s %d" % [str(it.get("cat", "")), Loc.t("UI_VALUE"), int(it.get("value", 0))], "text": Loc.t(it.get("desc", {}))})
		"siddhis":
			for id in _sorted(Data.siddhis):
				var s: Dictionary = Data.siddhis[id]
				var teacher := Loc.t(Data.character(str(s.get("teacher", ""))).get("name", {}))
				out.append({"title": Loc.t(s.get("name", {})), "sub": "%s: %s   ·   %s: %s" % [Loc.t("UI_SCHOOL"), str(s.get("school", "")), Loc.t("UI_TEACHER"), teacher], "text": Loc.t(s.get("desc", {}))})
		"moves":
			for id in _sorted(Data.moves):
				var m: Dictionary = Data.moves[id]
				out.append({"title": Loc.t(m.get("name", {})), "sub": "%s: %s" % [Loc.t("UI_INPUT"), str(m.get("input", ""))], "text": Loc.t(m.get("desc", {}))})
		"mudras":
			for id in _sorted(Data.mudras):
				var m: Dictionary = Data.mudras[id]
				out.append({"title": Loc.t(m.get("name", {})), "sub": "%s: %s" % [Loc.t("UI_UNLOCK"), str(m.get("unlock", "start"))], "text": Loc.t(m.get("desc", {}))})
		"regions":
			for id in _sorted(Data.regions):
				var r: Dictionary = Data.regions[id]
				var exits: Array = []
				for ex in r.get("exits", []):
					exits.append(Loc.t(Data.region(str(ex.get("to", ""))).get("name", {})))
				out.append({"title": Loc.t(r.get("name", {})), "sub": "%s %d" % [Loc.t("UI_DANGER"), int(r.get("danger", 0))], "text": Loc.t(r.get("desc", {})) + "\n\n%s: %s" % [Loc.t("UI_EXITS"), ", ".join(exits)]})
		"yaksha":
			for id in _sorted(Data.yaksha):
				var y: Dictionary = Data.yaksha[id]
				out.append({"title": Loc.t(y.get("name", {})), "sub": "", "text": Loc.t(y.get("greeting", {}))})
		"panths":
			var panths: Dictionary = Data.misc.get("panths", {})
			for id in _sorted(panths):
				out.append({"title": Loc.t(panths[id].get("name", {})), "sub": "%s: %d" % [Loc.t("UI_COST"), int(panths[id].get("cost", 0))], "text": Loc.t(panths[id].get("desc", {}))})
			var arch: Dictionary = Data.misc.get("archetypes", {})
			for id in _sorted(arch):
				out.append({"title": Loc.t(arch[id].get("name", {})), "sub": Loc.t("UI_ARCHETYPE"), "text": Loc.t(arch[id].get("desc", {}))})
		"lore":
			for l in Data.misc.get("lore", []):
				out.append({"title": Loc.t(l.get("title", {})), "sub": "", "text": Loc.t(l.get("text", {}))})
		"quests":
			for id in _sorted(Data.quests):
				var q: Dictionary = Data.quests[id]
				out.append({"title": Loc.t(q.get("name", {})), "sub": "%s %d   ·   %s" % [Loc.t("UI_CHAPTER"), int(q.get("chapter", 0)), str(q.get("type", ""))], "text": Loc.t(q.get("desc", {}))})
		"stats":
			var stats: Dictionary = Data.misc.get("stats", {})
			for id in stats.keys():
				out.append({"title": Loc.t(stats[id].get("name", {})), "sub": "%s: %s" % [Loc.t("UI_DISCIPLINE"), str(stats[id].get("discipline", ""))], "text": Loc.t(stats[id].get("desc", {}))})
	return out
