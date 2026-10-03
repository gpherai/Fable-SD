## Conversation with an NPC (payload = npc id). Dialogue data (data/characters/*.json): a list of
## nodes; the first node whose `when` holds is the one that speaks (a node without `when` is the
## fallback). A node has `lines` (shown one by one), optional `effects` (applied when it starts) and
## optional `choices`. A choice has a `text`, an optional `when`, optional effect keys (Game.apply_effects),
## optional reply `lines`, and `end: true` when the conversation stops there. A choice that does
## something (quest, item, gold...) also ends the talk after its reply; a choice that only answers
## a question returns to the list.
extends "res://scripts/ui/UIPanel.gd"

const CHARS_PER_SEC := 70.0
const ACTION_FREE_KEYS := ["text", "when", "lines", "end"]

var npc_id: String = ""
var cdata: Dictionary = {}
var node: Dictionary = {}
var lines: Array = []
var line_i: int = 0
var phase: String = "lines"       # "lines" or "choices"
var after_lines: String = "choices"   # what follows the current lines: "choices" or "end"
var _reveal: float = 0.0
var _text_lbl: Label
var _choice_list: Array = []
var _more_lbl: Label

func init() -> void:
	kind = "dialogue"
	autofocus = false   # Enter right after the last line must not pick the first answer
	live = false
	framed = true
	align_bottom = true
	show_header = false
	dim_alpha = 0.18
	win_size = Vector2(1100, 250)
	npc_id = str(payload)
	cdata = Data.character(npc_id)

func _ready() -> void:
	super._ready()
	_face_npc()
	_start()

func _face_npc() -> void:
	var pl = Game.player
	var npc = Game.world.find_npc(npc_id) if Game.world != null else null
	if pl != null and is_instance_valid(pl) and npc != null:
		pl.face_now(npc.global_position - pl.global_position)

func _start() -> void:
	Events.npc_talked.emit(npc_id)
	node = _pick_node()
	var ok := true
	if not node.is_empty() and node.has("effects"):
		ok = Game.apply_effects(node["effects"], npc_id)
		if ui.current != self:
			return   # the effects opened another panel (shop, cutscene...)
	lines = node.get("lines", []) if ok else []
	if lines.is_empty():
		lines = [{"nl": "...", "en": "..."}]
	line_i = 0
	phase = "lines"
	after_lines = "choices" if not node.get("choices", []).is_empty() else "end"
	_render()

func _pick_node() -> Dictionary:
	for n in cdata.get("dialogue", []):
		if not n is Dictionary:
			continue
		if not n.has("when") or Game.check(n["when"]):
			return n
	return {}

# ---------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------
func build() -> void:
	pass   # drawn by _render() (the panel redraws itself on its own events)

func _render() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_choice_list.clear()
	var head := T.hbox(12)
	head.add_child(T.label(Loc.t(cdata.get("name", {})), 26, T.GOLD, 5))
	head.add_child(T.label(Loc.t(cdata.get("role", {})), 15, T.DIM))
	body.add_child(head)
	if phase == "lines":
		_text_lbl = T.para(Loc.t(lines[line_i]), 22)
		_text_lbl.custom_minimum_size = Vector2(0, 100)
		_text_lbl.visible_ratio = 0.0
		_reveal = 0.0
		body.add_child(_text_lbl)
		var foot := T.hbox(8)
		foot.add_child(T.spacer(0, 0, true))
		_more_lbl = T.label("%s  ▸" % Loc.t("UI_CONTINUE_DIALOGUE"), 16, T.DIM)
		foot.add_child(_more_lbl)
		body.add_child(foot)
	else:
		var shown: int = 0
		for ch in node.get("choices", []):
			if ch.has("when") and not Game.check(ch["when"]):
				continue
			shown += 1
			var idx := shown
			var b := T.button("%d.  %s" % [idx, Loc.t(ch.get("text", {}))], func(): _choose(ch), 0, 40)
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if ch.has("cost"):
				b.text += "   (%d %s)" % [int(ch["cost"]), Loc.t("UI_GOLD")]
				b.disabled = Game.hero.gold < int(ch["cost"])
			body.add_child(b)
			_choice_list.append(ch)
		if _choice_list.is_empty():
			close()
		elif nav_visible:
			focus_first()   # a keyboard player stays on the keys between answers

func _process(delta: float) -> void:
	if phase == "lines" and _text_lbl != null and is_instance_valid(_text_lbl) and _text_lbl.visible_ratio < 1.0:
		_reveal += delta * CHARS_PER_SEC
		var total := maxi(1, _text_lbl.text.length())
		_text_lbl.visible_ratio = clampf(_reveal / float(total), 0.0, 1.0)
		if _more_lbl != null:
			_more_lbl.modulate.a = 0.35

func _revealing() -> bool:
	return phase == "lines" and _text_lbl != null and _text_lbl.visible_ratio < 1.0

# ---------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and phase == "lines":
		_advance()
		accept_event()

func on_key(event: InputEvent) -> bool:
	if phase == "lines":
		if event.is_action_pressed("interact") or (event is InputEventKey and event.physical_keycode == KEY_SPACE):
			_advance()
			return true
	else:
		if event is InputEventKey:
			var n: int = event.physical_keycode - KEY_1
			if n >= 0 and n < _choice_list.size():
				_choose(_choice_list[n])
				return true
	return false

func _advance() -> void:
	if _revealing():
		_text_lbl.visible_ratio = 1.0
		_more_lbl.modulate.a = 1.0
		return
	line_i += 1
	if line_i < lines.size():
		_render()
		return
	if after_lines == "choices":
		phase = "choices"
		_render()
	else:
		close()

func _choose(ch: Dictionary) -> void:
	var ok := Game.apply_effects(ch, npc_id)
	if ui.current != self:
		return   # a shop, trainer or cutscene took over
	if not ok:
		return   # could not pay: the talk goes on
	var acts := false
	for k in ch.keys():
		if not ACTION_FREE_KEYS.has(k):
			acts = true
	var ends: bool = bool(ch.get("end", false)) or acts
	if ch.has("lines") and not ch["lines"].is_empty():
		lines = ch["lines"]
		line_i = 0
		phase = "lines"
		after_lines = "end" if ends else "choices"
		_render()
	elif ends:
		close()
	else:
		_render()

func on_closed() -> void:
	Events.dialogue_ended.emit(npc_id)
