## Save slots. payload {"mode": "save" | "load"}. Slot 0 is the quick save / autosave slot
## (F5, sleeping, finishing a quest); slots 1-5 are the player's own.
extends "res://scripts/ui/UIPanel.gd"

var mode: String = "load"
var _armed: String = ""   # "save:2" / "delete:3": the button that waits for a second click

func init() -> void:
	kind = "saves"
	live = false
	mode = str((payload as Dictionary).get("mode", "load")) if payload is Dictionary else "load"
	win_size = Vector2(820, 600)
	set_title(Loc.t("UI_SAVE_GAME") if mode == "save" else Loc.t("UI_LOAD_GAME"))

func build() -> void:
	var list := T.vbox(8)
	for slot in Game.SAVE_SLOTS:
		list.add_child(_row(slot))
	body.add_child(T.scroll(list))

func _row(slot: int) -> Control:
	var row := T.hbox(12)
	var info := T.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := Loc.t("UI_QUICK_SLOT") if slot == 0 else "%s %d" % [Loc.t("UI_SLOT"), slot]
	info.add_child(T.label(head, 18, T.GOLD))
	var exists := Game.has_save(slot)
	if exists:
		var m := Game.save_meta(slot)
		info.add_child(T.label("%s  ·  %s  ·  %s %d  ·  %s" % [str(m.get("name", "?")), Loc.t(Data.region(str(m.get("region", ""))).get("name", {})), Loc.t("UI_DAY"), int(m.get("day", 1)), str(m.get("saved_at", "")).replace("T", " ")], 15, T.INK))
	else:
		info.add_child(T.label(Loc.t("UI_SLOT_EMPTY"), 15, T.DIM))
	row.add_child(info)
	if mode == "save":
		var key := "save:%d" % slot
		var label := Loc.t("UI_OVERWRITE") if _armed == key else Loc.t("UI_SAVE")
		var b := T.button(label, func(): _on_save(slot, exists), 130, 40)
		b.disabled = slot == 0   # slot 0 is written by F5 and by the game itself
		row.add_child(b)
	else:
		var b := T.button(Loc.t("UI_LOAD"), func(): _on_load(slot), 130, 40)
		b.disabled = not exists
		row.add_child(b)
	if exists and slot > 0:
		var dkey := "delete:%d" % slot
		row.add_child(T.button(Loc.t("UI_SURE") if _armed == dkey else Loc.t("UI_DELETE"), func(): _on_delete(slot), 110, 40))
	return T.card(row)

func _on_save(slot: int, exists: bool) -> void:
	var key := "save:%d" % slot
	if exists and _armed != key:
		_armed = key
		rebuild()
		return
	_armed = ""
	if Game.save_game(slot):
		rebuild()
	else:
		Events.notify.emit(Loc.t("UI_SAVE_FAILED"), "bad")

func _on_load(slot: int) -> void:
	ui.main.load_slot(slot)

func _on_delete(slot: int) -> void:
	var key := "delete:%d" % slot
	if _armed != key:
		_armed = key
		rebuild()
		return
	_armed = ""
	Game.delete_save(slot)
	rebuild()
