## An altar (payload "dharma" or "asura").
## Dharma: gold offered to the temple purifies karma (1 per 20 gold) and is counted in
## `counters.donated`; at 5000 in total the flag `mandir_daan_5000` (the Surya Mandir quest) is set.
## Asura: at night, 3 Preta bones and 1000 gold are burnt for Andhaka; sets `andhaka_bali_done`
## (the quest pays the karma).
extends "res://scripts/ui/UIPanel.gd"

const DONATIONS := [10, 50, 100, 500, 1000]
const BONES := "preta_asthi"
const SACRIFICE_BONES := 3
const SACRIFICE_GOLD := 1000

var shrine: String = "dharma"

func init() -> void:
	kind = "shrine"
	shrine = str(payload) if str(payload) != "" else "dharma"
	win_size = Vector2(700, 520)
	set_title(Loc.t("UI_SHRINE_ASURA" if shrine == "asura" else "UI_SHRINE_DHARMA"))

func build() -> void:
	if shrine == "asura":
		_build_asura()
	else:
		_build_dharma()
	body.add_child(T.spacer(0, 0, true))

func _build_dharma() -> void:
	body.add_child(T.para(Loc.t("UI_SHRINE_DHARMA_TEXT"), 19))
	body.add_child(T.label(Loc.t("UI_DONATED_TOTAL", {"n": int(Game.hero.counters.get("donated", 0))}), 17, T.GOLD))
	body.add_child(T.label("%s: %d" % [Loc.t("UI_GOLD").capitalize(), int(Game.hero.gold)], 17, Color("#ffd24a")))
	body.add_child(T.label(Loc.t("UI_SHRINE_DONATE"), 20, T.GOLD))
	for n in DONATIONS:
		var amount: int = n
		var b := T.button(Loc.t("UI_DONATE_AMOUNT", {"n": amount}), func(): _donate(amount), 0, 42)
		b.disabled = Game.hero.gold < amount
		body.add_child(b)

func _build_asura() -> void:
	body.add_child(T.para(Loc.t("UI_SHRINE_ASURA_TEXT"), 19))
	var bones := Game.count(BONES)
	body.add_child(T.label("%s: %d / %d     %s: %d / %d" % [Loc.t(Data.item(BONES).get("name", {})), bones, SACRIFICE_BONES, Loc.t("UI_GOLD").capitalize(), int(Game.hero.gold), SACRIFICE_GOLD], 17, T.INK))
	if not Game.is_night():
		body.add_child(T.label(Loc.t("UI_NEED_NIGHT"), 17, T.BAD))
	var b := T.button(Loc.t("UI_SACRIFICE"), _sacrifice, 0, 48)
	b.disabled = not Game.is_night() or bones < SACRIFICE_BONES or Game.hero.gold < SACRIFICE_GOLD
	body.add_child(b)

func _donate(amount: int) -> void:
	if not Game.spend_gold(amount):
		return
	Game.hero.counters.donated = int(Game.hero.counters.get("donated", 0)) + amount
	Game.add_karma(maxi(1, amount / 20))
	if int(Game.hero.counters.donated) >= 5000 and not Game.flag("mandir_daan_5000"):
		Game.set_flag("mandir_daan_5000", true)
	Audio.play("bell")
	Events.notify.emit(Loc.t("UI_THANKS"), "good")

func _sacrifice() -> void:
	if not Game.is_night() or Game.count(BONES) < SACRIFICE_BONES:
		Events.notify.emit(Loc.t("UI_NEED_SACRIFICE"), "bad")
		return
	if not Game.spend_gold(SACRIFICE_GOLD):
		return
	Game.take(BONES, SACRIFICE_BONES)
	Game.set_flag("andhaka_bali_done", true)
	Audio.play("cast")
	Events.notify.emit(Loc.t("UI_SACRIFICED"), "bad")
