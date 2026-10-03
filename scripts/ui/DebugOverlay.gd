## Temporary on-screen readout (region, time, health, gold, interaction hint, controls).
## Replaced by the real HUD in the UI step. It also stands in for the death screen: the hero
## wakes again after a few seconds (World.respawn_player), so a fight can be lost and retried.
extends CanvasLayer

var info: Label
var hint: Label
var notice: Label
var cross: Label
var death: Label
var _notice_t: float = 0.0
var _death_t: float = -1.0

func _ready() -> void:
	layer = 50
	info = _label(Vector2(16, 12), 18)
	hint = _label(Vector2(0, 0), 26)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -130
	hint.offset_bottom = -90
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice = _label(Vector2(0, 0), 24)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	notice.offset_top = 190
	notice.offset_bottom = 230
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross = _label(Vector2(0, 0), 34)
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.text = "+"
	cross.visible = false
	death = _label(Vector2(0, 0), 36)
	death.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death.offset_left = 300
	death.offset_right = -300
	death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	death.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	death.visible = false
	Events.interact_hint.connect(func(t): hint.text = t)
	Events.notify.connect(_on_notify)
	Events.panel_requested.connect(_on_panel)

func _on_panel(panel: String, _payload) -> void:
	if panel == "death":
		death.text = "%s\n%s" % [Loc.t("UI_DEATH_TITLE"), Loc.t("UI_DEATH_TEXT")]
		death.visible = true
		_death_t = 4.0

func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color("#fff3d0"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l

func _on_notify(text: String, _kind: String) -> void:
	notice.text = text
	_notice_t = 3.0

func _process(delta: float) -> void:
	if not Game.in_game or Game.hero.is_empty():
		return
	_notice_t -= delta
	if _notice_t <= 0.0:
		notice.text = ""
	if _death_t > 0.0:
		_death_t -= delta
		if _death_t <= 0.0:
			death.visible = false
			if Game.world != null:
				Game.world.respawn_player()
			if Game.player != null:
				Game.player.capture_mouse()
	var pc: Node = Game.player.combat if Game.player != null else null
	cross.visible = pc != null and pc.ranged_stance() and not Game.player.dead
	var w: Node = Game.world
	var region := Loc.t(Data.region(Game.state.get("region", "")).get("name", {}))
	var stance := "boog/chakra" if (pc != null and pc.ranged_stance()) else "melee"
	var lock_txt := "  doel vergrendeld" if (pc != null and pc.lock_valid()) else ""
	info.text = "%s\nDag %d  %s\nHP %d/%d   Ojas %d/%d   Goud %d\nTapas %d   Multiplier x%d   Vijanden: %d   Stand: %s%s\n[LMB/J] slag (vasthouden: zware slag)  [RMB/K] blok  [F] boog/melee  [Tab] doel  [1-6] siddhi's\n[Esc] muis vrijmaken   [Spatie] rollen   [Shift] rennen   [E] gebruiken   [scrollwiel] zoom" % [
		region, int(Game.state.get("day", 1)), Game.time_string(),
		int(Game.hero.hp), int(Game.hp_max()), int(Game.hero.ojas), int(Game.ojas_max()), int(Game.hero.gold),
		int(Game.hero.tapas_total), (Game.player.combat_mult if Game.player != null else 0), (w.enemies.size() if w != null else 0), stance, lock_txt]
