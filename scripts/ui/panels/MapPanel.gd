## Map (M, or a Tirtha gate: payload "tirtha"). A drawn map of Jambudvipa: every region the hero has
## seen is a dot on the grid from `regions.json` ("map": [x, y]), joined by the paths between them.
## Regions next to a visited one show up as unexplored "?" dots, so a locked path hints at what
## lies behind it. Click a dot (or move the selection with the arrow keys) to read about the region;
## standing at a Tirtha gate, a gate you unlocked can be travelled to. Travel only works at a gate.
extends "res://scripts/ui/UIPanel.gd"

const DIRS := ["N", "S", "E", "W"]

## The drawing and the picking. The panel gives it nodes and edges and listens to `picked` (select)
## and `activated` (double click / Enter: travel).
class MapView extends Control:
	signal picked(id: String)
	signal activated(id: String)

	const T = preload("res://scripts/ui/UITheme.gd")
	const MAX_CELL := Vector2(150.0, 74.0)
	const PAD := Vector2(56.0, 36.0)
	const LEGEND_H := 26.0   # strip kept free at the bottom for the legend
	const LABEL_SIZE := 12

	var nodes: Dictionary = {}    # id -> {"pos": Vector2 (grid), "state": "here"|"visited"|"unknown", "tirtha": bool, "danger": int, "name": String}
	var edges: Array = []         # {"a": id, "b": id, "kind": "path"|"locked"|"boat"|"boat_closed", "known": bool}
	var selected: String = ""
	var hovered: String = ""
	var legend: Array = []        # [[shape, color, text]] drawn bottom left
	var _t: float = 0.0
	var _origin := Vector2.ZERO
	var _cell := Vector2(60.0, 40.0)
	var _min := Vector2.ZERO
	var _fit_cache: Dictionary = {}
	var _bg: StyleBoxFlat = T.box(Color("#0f0a07"), Color("#4a3520"), 8, 2, 0)
	var _plate: StyleBoxFlat = T.box(Color("#2b1d14"), T.GOLD, 5, 1, 0)

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		mouse_exited.connect(func():
			hovered = ""
			queue_redraw())

	func set_data(n: Dictionary, e: Array) -> void:
		nodes = n
		edges = e
		_fit_cache.clear()
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_fit_cache.clear()
		elif what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
			queue_redraw()

	## Scale and offset that fit every shown dot in the control, with a different scale for x and y
	## (the map is tall and narrow, the window is wide).
	func _compute_view() -> void:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for id in nodes.keys():
			var p: Vector2 = nodes[id]["pos"]
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		if lo.x == INF:
			lo = Vector2.ZERO
			hi = Vector2.ZERO
		var span := hi - lo
		var avail := size - PAD * 2.0 - Vector2(0.0, LEGEND_H)
		_cell = Vector2(
			minf(MAX_CELL.x, avail.x / maxf(span.x, 1.0)) if span.x > 0.0 else MAX_CELL.x,
			minf(MAX_CELL.y, avail.y / maxf(span.y, 1.0)) if span.y > 0.0 else MAX_CELL.y)
		_min = lo
		_origin = Vector2(size.x * 0.5 - span.x * _cell.x * 0.5, PAD.y + (size.y - PAD.y * 2.0 - LEGEND_H - span.y * _cell.y) * 0.5)

	func to_screen(grid: Vector2) -> Vector2:
		return _origin + (grid - _min) * _cell

	func node_at(p: Vector2, reach: float = 20.0) -> String:
		_compute_view()
		var best := ""
		var best_d := reach
		for id in nodes.keys():
			var d := to_screen(nodes[id]["pos"]).distance_to(p)
			if d < best_d:
				best_d = d
				best = id
		return best

	# -----------------------------------------------------------------
	# Input
	# -----------------------------------------------------------------
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var h := node_at(event.position)
			if h != hovered:
				hovered = h
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := node_at(event.position)
			if id != "":
				picked.emit(id)
				if event.double_click:
					activated.emit(id)
			accept_event()
		elif event.is_action_pressed("ui_accept") and selected != "":
			activated.emit(selected)
			accept_event()
		else:
			for pair in [["ui_left", Vector2.LEFT], ["ui_right", Vector2.RIGHT], ["ui_up", Vector2.UP], ["ui_down", Vector2.DOWN]]:
				if event.is_action_pressed(pair[0], true):
					_step(pair[1])
					accept_event()
					return

	## Moves the selection to the nearest dot in a direction (a cone around it, so a column of dots is walkable).
	func _step(dir: Vector2) -> void:
		if selected == "" or not nodes.has(selected):
			return
		var from: Vector2 = nodes[selected]["pos"]
		var best := ""
		var best_score := INF
		for id in nodes.keys():
			if id == selected:
				continue
			var d: Vector2 = nodes[id]["pos"] - from
			var along := d.dot(dir)
			if along < 0.4:
				continue
			var across := absf(d.dot(Vector2(-dir.y, dir.x)))
			var score := along + across * 1.8
			if score < best_score:
				best_score = score
				best = id
		if best != "":
			picked.emit(best)

	# -----------------------------------------------------------------
	# Drawing
	# -----------------------------------------------------------------
	func _draw() -> void:
		_compute_view()
		draw_style_box(_bg, Rect2(Vector2.ZERO, size))
		var font := get_theme_default_font()
		for e in edges:
			_draw_edge(e)
		for id in nodes.keys():
			if id != selected:
				_draw_node(id, font)
		if nodes.has(selected):
			_draw_node(selected, font)
		if hovered != "" and nodes.has(hovered):
			_draw_hover_label(hovered, font)
		_draw_compass(font)
		_draw_legend(font)

	func _draw_edge(e: Dictionary) -> void:
		var a: Vector2 = to_screen(nodes[e["a"]]["pos"])
		var b: Vector2 = to_screen(nodes[e["b"]]["pos"])
		var known: bool = e["known"]
		match e["kind"]:
			"locked":
				draw_dashed_line(a, b, Color("#c0392b") if known else Color("#6a2a22"), 2.0, 7.0, true, true)
			"boat":
				draw_dashed_line(a, b, Color("#3b7dd8") if known else Color("#2a4a78"), 2.0, 9.0, true, true)
			"boat_closed":
				draw_dashed_line(a, b, Color("#2f4a70"), 1.5, 5.0, true, true)
			_:
				draw_line(a, b, Color("#a8865a") if known else Color("#5a4326"), 2.5 if known else 1.5, true)

	func _draw_node(id: String, font: Font) -> void:
		var n: Dictionary = nodes[id]
		var c := to_screen(n["pos"])
		var state: String = n["state"]
		var r := 9.0
		var sel := id == selected
		if state == "unknown":
			draw_circle(c, r, Color("#1a120d"))
			draw_arc(c, r, 0.0, TAU, 28, Color("#6f6350"), 1.5, true)
			draw_string(font, c + Vector2(-5.0, 6.0), "?", HORIZONTAL_ALIGNMENT_CENTER, 10.0, 15, Color("#8a7a5a"))
		else:
			var col := Color.from_hsv(lerpf(0.34, 0.0, clampf(float(n["danger"]) / 5.0, 0.0, 1.0)), 0.62, 0.92)
			if n["tirtha"]:
				var s := r * 1.45
				var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
				draw_colored_polygon(pts, col.darkened(0.15))
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), T.GOLD, 2.5, true)
			else:
				draw_circle(c, r, col)
				draw_arc(c, r, 0.0, TAU, 28, Color("#1a120d"), 2.0, true)
			if state == "here":
				var pulse := 0.5 + 0.5 * sin(_t * 3.2)
				draw_arc(c, r + 5.0 + pulse * 3.0, 0.0, TAU, 36, Color(T.SAFFRON, 0.9 - pulse * 0.4), 2.5, true)
			_draw_label(c, str(n["name"]), font, T.INK if state != "visited" or sel else Color("#d9c9a4"))
		if sel:
			draw_arc(c, r + 8.0, 0.0, TAU, 36, Color.WHITE, 2.0, true)

	func _draw_label(c: Vector2, text: String, font: Font, col: Color) -> void:
		var maxw := maxf(_cell.x - 8.0, 52.0)
		var key := text + "|" + str(int(maxw)) + "|" + str(_cell.y >= 44.0)
		if not _fit_cache.has(key):
			_fit_cache[key] = _fit(text, maxw, font, 2 if _cell.y >= 44.0 else 1)
		var y := 25.0
		for line in _fit_cache[key]:
			var pos := c + Vector2(-maxw * 0.5, y)
			draw_string_outline(font, pos, line, HORIZONTAL_ALIGNMENT_CENTER, maxw, LABEL_SIZE, 5, Color(0.06, 0.04, 0.03, 0.95))
			draw_string(font, pos, line, HORIZONTAL_ALIGNMENT_CENTER, maxw, LABEL_SIZE, col)
			y += LABEL_SIZE + 2.0

	func _width(text: String, font: Font) -> float:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE).x

	## The name cut to `maxw` pixels: on one line, or (room permitting) split at a space into two,
	## and shortened with "…" only when even that does not fit.
	func _fit(text: String, maxw: float, font: Font, max_lines: int) -> Array:
		if _width(text, font) <= maxw:
			return [text]
		if max_lines >= 2 and text.contains(" "):
			var words := text.split(" ")
			var best: Array = []
			var best_w := INF
			for i in range(1, words.size()):
				var a := " ".join(words.slice(0, i))
				var b := " ".join(words.slice(i))
				var w := maxf(_width(a, font), _width(b, font))
				if w < best_w:
					best_w = w
					best = [a, b]
			if best_w <= maxw:
				return best
			return [best[0], _cut(best[1], maxw, font)]
		return [_cut(text, maxw, font)]

	func _cut(text: String, maxw: float, font: Font) -> String:
		var t := text
		while t.length() > 3 and _width(t + "…", font) > maxw:
			t = t.substr(0, t.length() - 1)
		return t.strip_edges() + "…" if t != text else t

	## The hovered dot's full name in a plate (the labels under the dots are cut to fit).
	func _draw_hover_label(id: String, font: Font) -> void:
		var n: Dictionary = nodes[id]
		var text: String = str(n["name"]) if n["state"] != "unknown" else "?"
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 16.0
		var c := to_screen(n["pos"])
		var rect := Rect2(c + Vector2(-w * 0.5, -40.0), Vector2(w, 24.0))
		rect.position.x = clampf(rect.position.x, 4.0, size.x - w - 4.0)
		rect.position.y = maxf(rect.position.y, 4.0)
		draw_style_box(_plate, rect)
		draw_string(font, rect.position + Vector2(8.0, 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, T.INK)

	func _draw_compass(font: Font) -> void:
		var c := Vector2(size.x - 36.0, 62.0)
		draw_line(c + Vector2(0, 20), c + Vector2(0, -16), Color("#8a7a5a"), 2.0, true)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -22), c + Vector2(-5, -12), c + Vector2(5, -12)]), T.GOLD)
		draw_string(font, c + Vector2(-5.0, -28.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 10.0, 14, T.GOLD)

	func _draw_legend(font: Font) -> void:
		var y := size.y - 14.0
		var x := 16.0
		for entry in legend:
			var shape: String = entry[0]
			var col: Color = entry[1]
			var text: String = entry[2]
			var c := Vector2(x + 8.0, y - 5.0)
			match shape:
				"dot":
					draw_circle(c, 6.0, col)
				"diamond":
					var s := 8.0
					draw_polyline(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)]), col, 2.0, true)
				"ring":
					draw_arc(c, 6.0, 0.0, TAU, 20, col, 1.5, true)
				"dash":
					draw_dashed_line(c + Vector2(-9, 0), c + Vector2(9, 0), col, 2.0, 5.0, true, true)
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(x + 24.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, T.DIM)
			x += 24.0 + w + 22.0

var at_gate: bool = false
var selected: String = ""
var view: MapView
var _info: VBoxContainer

func init() -> void:
	kind = "map"
	live = false
	at_gate = str(payload) == "tirtha"
	win_size = Vector2(1360, 760)
	set_title(Loc.t("UI_MAP"))

# ---------------------------------------------------------------------
# What the map knows
# ---------------------------------------------------------------------
func _here() -> String:
	return str(Game.state.get("region", ""))

func _visited(id: String) -> bool:
	# read the state without region_state(): that would create an entry for every region we look at
	return id == _here() or bool(Game.state.regions.get(id, {}).get("visited", false)) or Game.state.get("tirthas", []).has(id)

## True when the path through `ex` cannot be walked right now (a door that wants a flag or prestige).
static func exit_locked(ex: Dictionary) -> bool:
	var lock = ex.get("locked", null)
	if lock != null and not Game.check(lock):
		return true
	var rlock = Data.region(str(ex.get("to", ""))).get("locked", null)
	if rlock != null:
		if rlock.has("yasha") and Game.hero.yasha < int(rlock["yasha"]):
			return true
		if rlock.has("flag") and not Game.flag(rlock["flag"]):
			return true
	return false

## Every neighbour of a region: [other id, kind] with kind "path", "locked", "boat" or "boat_closed".
func _links(id: String) -> Array:
	var out: Array = []
	var rd := Data.region(id)
	for ex in rd.get("exits", []):
		out.append([str(ex.get("to", "")), "locked" if exit_locked(ex) else "path"])
	var boat = rd.get("boat", null)
	if boat is Dictionary:
		var open: bool = not boat.has("when") or Game.check(boat["when"])
		out.append([str(boat.get("to", "")), "boat" if open else "boat_closed"])
	return out

func _graph() -> Array:
	var nodes := {}
	var edges: Array = []
	var seen_edges := {}
	for id in Data.regions.keys():
		if not _visited(id) or (Data.region(id).get("childhood", false) and id != _here()):
			continue   # the childhood village is gone from the map once you have left it
		_add_node(nodes, id, "here" if id == _here() else "visited")
		for l in _links(id):
			var to: String = l[0]
			if not Data.regions.has(to):
				continue
			if not nodes.has(to):
				_add_node(nodes, to, "visited" if _visited(to) else "unknown")
			var key: String = (id + ":" + to) if id < to else (to + ":" + id)
			if seen_edges.has(key):
				continue
			seen_edges[key] = true
			edges.append({"a": id, "b": to, "kind": l[1], "known": _visited(to)})
	return [nodes, edges]

func _add_node(nodes: Dictionary, id: String, state: String) -> void:
	var rd := Data.region(id)
	var mp: Array = rd.get("map", [0, 0])
	nodes[id] = {"pos": Vector2(float(mp[0]), float(mp[1])), "state": state, "tirtha": bool(rd.get("tirtha", false)),
		"danger": int(rd.get("danger", 0)), "name": Loc.t(rd.get("name", {}))}

# ---------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------
func build() -> void:
	if selected == "" or not Data.regions.has(selected):
		selected = _here()
	body.add_child(T.para(Loc.t("UI_MAP_AT_GATE") if at_gate else Loc.t("UI_TIRTHA_FAR"), 17, T.GOOD if at_gate else T.DIM))
	var cols := T.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	view = MapView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(900, 560)
	var g := _graph()
	view.legend = [
		["dot", T.SAFFRON, Loc.t("UI_MAP_LEGEND_HERE")],
		["diamond", T.GOLD, Loc.t("UI_MAP_LEGEND_TIRTHA")],
		["ring", Color("#8a7a5a"), Loc.t("UI_MAP_LEGEND_UNKNOWN")],
		["dash", Color("#c0392b"), Loc.t("UI_MAP_LEGEND_LOCKED")],
		["dash", Color("#3b7dd8"), Loc.t("UI_MAP_LEGEND_BOAT")],
	]
	view.set_data(g[0], g[1])
	view.selected = selected
	view.picked.connect(_select)
	view.activated.connect(_activate)
	cols.add_child(view)
	_info = T.vbox(8)
	_info.custom_minimum_size = Vector2(380, 0)
	cols.add_child(_info)
	_fill_info()
	view.grab_focus(true)   # arrow keys move the selection from the start

func _select(id: String) -> void:
	if not view.nodes.has(id):
		return
	selected = id
	view.selected = id
	Audio.play("ui", -10.0)
	_fill_info()

func _activate(id: String) -> void:
	if _can_travel(id):
		_travel(id)

func _can_travel(id: String) -> bool:
	return at_gate and id != _here() and Game.state.get("tirthas", []).has(id)

func _fill_info() -> void:
	for c in _info.get_children():
		_info.remove_child(c)
		c.queue_free()
	var id := selected
	var rd := Data.region(id)
	var state: String = str(view.nodes.get(id, {}).get("state", "unknown"))
	if state == "unknown":
		_info.add_child(T.label("?", 26, T.DIM))
		_info.add_child(T.para(Loc.t("UI_MAP_UNKNOWN"), 16, T.DIM))
		return
	var title := T.label(Loc.t(rd.get("name", {})), 25, T.GOLD, 4)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(title)
	var tags := PackedStringArray()
	if id == _here():
		tags.append(Loc.t("UI_CURRENT"))
	if rd.get("tirtha", false):
		tags.append(Loc.t("UI_MAP_LEGEND_TIRTHA"))
	if not tags.is_empty():
		_info.add_child(T.label("  ·  ".join(tags), 16, T.SAFFRON))
	_info.add_child(T.para(Loc.t(rd.get("desc", {})), 16, T.DIM))
	var danger := int(rd.get("danger", 0))
	var drow := T.hbox(10)
	drow.add_child(T.label(Loc.t("UI_DANGER"), 16, T.INK))
	var bar := T.bar(Color.from_hsv(lerpf(0.34, 0.0, clampf(float(danger) / 5.0, 0.0, 1.0)), 0.62, 0.92), 150.0, 14.0)
	bar.max_value = 5.0
	bar.value = float(danger)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drow.add_child(bar)
	_info.add_child(drow)
	_info.add_child(T.hsep())
	_info.add_child(T.label(Loc.t("UI_MAP_EXITS"), 18, T.GOLD))
	var shown := 0
	for ex in rd.get("exits", []):
		var to := str(ex.get("to", ""))
		var known: bool = view.nodes.has(to) and view.nodes[to]["state"] != "unknown"
		var line := "%s  →  %s" % [Loc.t("UI_MAP_DIR_" + str(ex.get("dir", "N"))), Loc.t(Data.region(to).get("name", {})) if known else "?"]
		if exit_locked(ex):
			line += "   (%s)" % Loc.t("UI_LOCKED").to_lower()
		_info.add_child(T.label(line, 15, T.BAD if exit_locked(ex) else T.INK))
		shown += 1
	if rd.get("boat", null) is Dictionary:
		var bt: Dictionary = rd["boat"]
		var open: bool = not bt.has("when") or Game.check(bt["when"])
		var bname: String = Loc.t(Data.region(str(bt.get("to", ""))).get("name", {})) if _visited(str(bt.get("to", ""))) else "?"
		_info.add_child(T.label("%s  →  %s%s" % [Loc.t("UI_MAP_LEGEND_BOAT"), bname, "" if open else "   (%s)" % Loc.t("UI_LOCKED").to_lower()], 15, T.INK if open else T.BAD))
		shown += 1
	if shown == 0:
		_info.add_child(T.label("—", 15, T.DIM))
	_info.add_child(T.spacer(0, 0, true))
	if Game.state.get("tirthas", []).has(id) and id != _here():
		var b := T.button(Loc.t("UI_TRAVEL") + "  →  " + Loc.t(rd.get("name", {})), func(): _travel(id), 0, 46)
		b.disabled = not at_gate
		_info.add_child(b)

func _travel(rid: String) -> void:
	if Game.world == null:
		return
	ui.close(self)
	Game.world.travel(rid, "")
