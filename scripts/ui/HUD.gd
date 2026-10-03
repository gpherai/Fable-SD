## The heads-up display while playing: Prana and Ojas bars, gold and combat multiplier, the six
## siddhi slots with cooldowns, elixir counts, region / day / time, the tracked quest, the locked
## target, buffs, floating messages, the "[E] ..." hint, the bow crosshair and a red flash when
## the hero is hurt. It only reads the game; it never changes it.
extends CanvasLayer

const T = preload("res://scripts/ui/UITheme.gd")
const Bindings = preload("res://scripts/systems/Bindings.gd")

const BUFF_NAMES := {"damage": "HUD_BUFF_DAMAGE", "speed": "HUD_BUFF_SPEED", "ojas_regen": "HUD_BUFF_OJAS", "ugra": "HUD_BUFF_UGRA"}
const MAX_TOASTS := 6

var root: Control
var name_lbl: Label
var hp_bar: ProgressBar
var hp_txt: Label
var oj_bar: ProgressBar
var oj_txt: Label
var info_lbl: Label
var buff_lbl: Label
var region_lbl: Label
var time_lbl: Label
var quest_box: VBoxContainer
var quest_title: Label
var quest_text: Label
var fps_lbl: Label
var hint_lbl: Label
var _hint_raw: String = ""
var state_lbl: Label
var toasts: VBoxContainer
var banner: Label
var cross: Label
var target_box: VBoxContainer
var target_name: Label
var target_bar: ProgressBar
var potion_lbl: Label
var stance_lbl: Label
var slots: Array = []        # [{panel, key, icon, cost, cd, name}]
var flash: TextureRect
var low: TextureRect
var _t: float = 0.0
var _slow_t: float = 0.0
var _hp_shown: float = 100.0
var _oj_shown: float = 60.0
var _banner_tween: Tween = null

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = T.theme()
	add_child(root)
	_build_vignettes()
	_build_status()
	_build_top_right()
	_build_bottom()
	_build_center()
	Events.notify.connect(_on_notify)
	Events.interact_hint.connect(func(t: String):
		_hint_raw = t
		hint_lbl.text = _hint_text())
	Events.input_device_changed.connect(func(_pad: bool): _refresh_keys())
	Events.bindings_changed.connect(_refresh_keys)
	Events.player_damaged.connect(_on_hurt)
	Events.region_entered.connect(func(_r): _slow_t = 0.0)
	visible = false

# =====================================================================
# Building
# =====================================================================
func _vignette(color: Color, from: float) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([from, 1.0])
	g.colors = PackedColorArray([Color(color.r, color.g, color.b, 0.0), color])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var tr := TextureRect.new()
	tr.texture = gt
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate.a = 0.0
	root.add_child(tr)
	return tr

func _build_vignettes() -> void:
	flash = _vignette(Color(0.85, 0.05, 0.03, 0.85), 0.45)
	low = _vignette(Color(0.7, 0.0, 0.0, 0.7), 0.6)

func _bar_with_text(color: Color, w: float, h: float, size: int) -> Array:
	var b := T.bar(color, w, h)
	var l := T.label("", size, Color.WHITE, 4)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(l)
	return [b, l]

func _build_status() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", T.box(Color(0.08, 0.05, 0.03, 0.72), Color("#6b4e2a"), 8, 1, 10))
	card.position = Vector2(14, 12)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(card)
	var v := T.vbox(4)
	card.add_child(v)
	name_lbl = T.label("", 17, T.GOLD, 3)
	v.add_child(name_lbl)
	var a := _bar_with_text(Color("#c0392b"), 300, 22, 14)
	hp_bar = a[0]
	hp_txt = a[1]
	v.add_child(hp_bar)
	var b := _bar_with_text(Color("#3b7dd8"), 300, 17, 12)
	oj_bar = b[0]
	oj_txt = b[1]
	v.add_child(oj_bar)
	info_lbl = T.label("", 15, T.INK, 3)
	v.add_child(info_lbl)
	buff_lbl = T.label("", 14, Color("#ffd98a"), 3)
	v.add_child(buff_lbl)

func _build_top_right() -> void:
	var col := T.vbox(2)
	col.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	col.offset_left = -360
	col.offset_right = -16
	col.offset_top = 12
	col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)
	region_lbl = T.label("", 22, T.GOLD, 5)
	region_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(region_lbl)
	time_lbl = T.label("", 16, T.INK, 4)
	time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(time_lbl)
	fps_lbl = T.label("", 14, T.DIM, 3)
	fps_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(fps_lbl)
	col.add_child(T.spacer(10))
	quest_box = T.vbox(2)
	quest_title = T.label("", 17, Color("#8ad0ff"), 4)
	quest_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_text = T.para("", 15, T.INK)
	quest_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quest_box.add_child(quest_title)
	quest_box.add_child(quest_text)
	col.add_child(quest_box)

func _build_bottom() -> void:
	# hint line above the hotbar
	hint_lbl = T.label("", 24, T.INK, 7)
	hint_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_lbl.offset_top = -168
	hint_lbl.offset_bottom = -128
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_lbl)
	state_lbl = T.label("", 20, Color("#9fd0ff"), 6)
	state_lbl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	state_lbl.offset_top = -200
	state_lbl.offset_bottom = -170
	state_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(state_lbl)
	# hotbar
	var bar_row := T.hbox(8)
	bar_row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar_row.offset_bottom = -16
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar_row)
	var left := T.vbox(0)
	left.alignment = BoxContainer.ALIGNMENT_END
	potion_lbl = T.label("", 17, T.INK, 4)
	potion_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	left.add_child(potion_lbl)
	bar_row.add_child(left)
	for i in 6:
		var s := _make_slot(i)
		slots.append(s)
		bar_row.add_child(s["panel"])
	var right := T.vbox(0)
	right.alignment = BoxContainer.ALIGNMENT_END
	stance_lbl = T.label("", 16, T.DIM, 4)
	right.add_child(stance_lbl)
	bar_row.add_child(right)

func _make_slot(i: int) -> Dictionary:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(66, 66)
	p.add_theme_stylebox_override("panel", T.box(Color(0.08, 0.05, 0.03, 0.8), Color("#6b4e2a"), 8, 2, 4))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(holder)
	var icon := T.label("", 24, Color.WHITE, 5)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(icon)
	var cd := ColorRect.new()
	cd.color = Color(0, 0, 0, 0.6)
	cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd.anchor_top = 1.0
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cd)
	var key := T.label(str(i + 1), 13, T.GOLD, 4)
	key.position = Vector2(2, 0)
	holder.add_child(key)
	var cost := T.label("", 12, Color("#9fd0ff"), 4)
	cost.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	cost.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.add_child(cost)
	return {"panel": p, "key": key, "icon": icon, "cost": cost, "cd": cd, "id": "?"}

func _build_center() -> void:
	toasts = T.vbox(2)
	toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toasts.offset_top = 178
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)
	banner = T.label("", 46, T.GOLD, 10)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.offset_top = 70
	banner.modulate.a = 0.0
	root.add_child(banner)
	cross = T.label("+", 34, Color.WHITE, 6)
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cross.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cross.visible = false
	root.add_child(cross)
	target_box = T.vbox(2)
	target_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	target_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	target_box.offset_top = 14
	target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_name = T.label("", 18, Color("#ff9a6a"), 5)
	target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_bar = T.bar(Color("#d6452e"), 320, 12)
	target_box.add_child(target_name)
	target_box.add_child(target_bar)
	target_box.visible = false
	root.add_child(target_box)

## Hint text as the player should read it: the strings say [E], which is whatever key (or gamepad button) interact has now.
func _hint_text() -> String:
	return _hint_raw.replace("[E]", "[%s]" % Bindings.label("interact", Game.pad_active))

## Siddhi slot labels: 1-6 on the keyboard, LT + A / B / X / Y / left / right on a gamepad.
const PAD_SLOT_KEYS := ["LT+A", "LT+B", "LT+X", "LT+Y", "LT+←", "LT+→"]

func _refresh_keys() -> void:
	hint_lbl.text = _hint_text()
	for i in slots.size():
		slots[i]["key"].text = PAD_SLOT_KEYS[i] if Game.pad_active else Bindings.label("siddhi_%d" % (i + 1), false)
	if Game.in_game and not Game.hero.is_empty():
		_update_texts()

## A panel is open: the "[E] ..." hint would only be in the way.
func set_modal(on: bool) -> void:
	hint_lbl.visible = not on

# =====================================================================
# Frame
# =====================================================================
func _process(delta: float) -> void:
	if not visible or not Game.in_game or Game.hero.is_empty():
		return
	_t += delta
	var hmax := Game.hp_max()
	var omax := Game.ojas_max()
	var k := clampf(delta * 10.0, 0.0, 1.0)
	_hp_shown = lerpf(_hp_shown, float(Game.hero.hp), k)
	_oj_shown = lerpf(_oj_shown, float(Game.hero.ojas), k)
	hp_bar.max_value = hmax
	hp_bar.value = _hp_shown
	oj_bar.max_value = omax
	oj_bar.value = _oj_shown
	hp_txt.text = "%s %d / %d" % [Loc.t("UI_PRANA"), int(Game.hero.hp), int(hmax)]
	oj_txt.text = "%s %d / %d" % [Loc.t("UI_OJAS"), int(Game.hero.ojas), int(omax)]
	low.modulate.a = (0.35 + 0.25 * sin(_t * 5.0)) if float(Game.hero.hp) < hmax * 0.25 and float(Game.hero.hp) > 0.0 else 0.0
	_update_slots()
	_update_combat_state()
	_slow_t -= delta
	if _slow_t <= 0.0:
		_slow_t = 0.25
		_update_texts()

func _update_texts() -> void:
	var pl = Game.player
	var mult: int = pl.combat_mult if pl != null else 0
	name_lbl.text = "%s  ·  %s" % [str(Game.hero.get("name", "")), Loc.t(Game.ashrama().get("name", {})).get_slice(" (", 0)]
	info_lbl.text = "%s %d     %s %d     x%d" % [Loc.t("UI_GOLD").capitalize(), int(Game.hero.gold), Loc.t("UI_TAPAS"), int(Game.hero.tapas_total), mult]
	var rid: String = Game.state.get("region", "")
	region_lbl.text = Loc.t(Data.region(rid).get("name", {}))
	time_lbl.text = "%s %d  ·  %s%s" % [Loc.t("UI_DAY"), int(Game.state.get("day", 1)), Game.time_string(), ("  ·  " + Loc.t("UI_NIGHT")) if Game.is_night() else ""]
	fps_lbl.text = "%d fps" % Engine.get_frames_per_second() if bool(Game.settings.get("show_fps", false)) else ""
	var pad: bool = Game.pad_active
	potion_lbl.text = "[%s] %s x%d\n[%s] %s x%d" % [Bindings.label("potion_prana", pad), Loc.t("UI_PRANA"), Game.potion_count("heal"), Bindings.label("potion_ojas", pad), Loc.t("UI_OJAS"), Game.potion_count("ojas")]
	var ranged: bool = pl != null and pl.combat.ranged_stance()
	stance_lbl.text = "[%s] " % Bindings.label("ranged_toggle", pad) + Loc.t("UI_RANGED_STANCE" if ranged else "UI_MELEE_STANCE")
	_update_buffs()
	_update_quest()

func _update_buffs() -> void:
	var parts: Array = []
	for st in ["damage", "speed", "ojas_regen", "ugra"]:
		var left := Game.buff_remaining(st)
		if left > 0.0:
			parts.append("%s %ds" % [Loc.t(BUFF_NAMES[st]), int(ceil(left))])
	buff_lbl.text = "  ".join(parts)
	buff_lbl.visible = not parts.is_empty()

func _update_quest() -> void:
	var best := ""
	for id in Game.quests.active_quests():
		var qd: Dictionary = Data.quest(id)
		if best == "" or (qd.get("type", "") == "main" and Data.quest(best).get("type", "") != "main"):
			best = id
	if best == "":
		quest_box.visible = false
		return
	quest_box.visible = true
	var st: Dictionary = Game.quests.current_stage(best)
	var prog: String = Game.quests.progress_text(best)
	quest_title.text = Loc.t(Data.quest(best).get("name", {}))
	quest_text.text = Loc.t(st.get("text", {})) + ("  (%s)" % prog if prog != "" else "")

func _update_slots() -> void:
	var pl = Game.player
	var pc = pl.combat if pl != null else null
	for i in 6:
		var s: Dictionary = slots[i]
		var id: String = str(Game.hero.hotbar[i])
		var sd: Dictionary = Data.siddhi(id)
		var lvl: int = Game.siddhi_level(id) if id != "" else 0
		if id != s["id"]:
			s["id"] = id
			s["icon"].text = str(sd.get("icon", "")) if lvl > 0 else ""
			s["icon"].add_theme_color_override("font_color", Color.html(str(sd.get("color", "#ffffff"))))
			(s["panel"] as PanelContainer).tooltip_text = Loc.t(sd.get("name", {})) if lvl > 0 else ""
		var cost := 0.0
		var cdr := 0.0
		if lvl > 0 and pc != null:
			cost = float(Game.siddhi_params(id).get("cost", 0)) * Game.siddhi_cost_mult()
			var total := maxf(0.01, float(sd.get("cooldown", 1.0)))
			cdr = clampf(pc.cooldown_left(id) / total, 0.0, 1.0)
		s["cost"].text = str(int(round(cost))) if lvl > 0 else ""
		(s["cd"] as ColorRect).anchor_top = 1.0 - cdr
		var poor := lvl > 0 and float(Game.hero.ojas) < cost
		(s["panel"] as PanelContainer).modulate = Color(1, 0.55, 0.55) if poor else (Color.WHITE if lvl > 0 else Color(1, 1, 1, 0.45))

func _update_combat_state() -> void:
	var pl = Game.player
	var pc = pl.combat if pl != null else null
	if pc == null:
		return
	cross.visible = pc.ranged_stance() and not pl.dead
	state_lbl.text = Loc.t("UI_MEDITATING") if pc.is_meditating() else ""
	if pc.lock_valid():
		var e = pc.lock
		target_box.visible = true
		target_name.text = "%s  (%s %d)" % [e.display_name(), Loc.t("UI_LEVEL"), int(e.data.get("level", 1))]
		target_bar.max_value = e.hp_max
		target_bar.value = e.hp
	else:
		target_box.visible = false

# =====================================================================
# Messages
# =====================================================================
func _on_notify(text: String, kind: String) -> void:
	if kind == "region" or kind == "boss":
		_show_banner(text, T.kind_color(kind))
		if kind == "region":
			return
	var l := T.label(text, 22, T.kind_color(kind), 7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toasts.add_child(l)
	while toasts.get_child_count() > MAX_TOASTS:
		var old := toasts.get_child(0)
		toasts.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)

func _show_banner(text: String, color: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.modulate.a = 0.0
	_banner_tween = banner.create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.4)
	_banner_tween.tween_interval(2.0)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.8)

func _on_hurt(amount: float) -> void:
	var strength := clampf(amount / maxf(1.0, Game.hp_max()) * 3.0 + 0.25, 0.25, 0.9)
	flash.modulate.a = strength
	var tw := flash.create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.5)
