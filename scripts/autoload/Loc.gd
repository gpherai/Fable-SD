## Localization. UI strings live in res://localization/strings.csv (key,en,nl).
## Content text in the JSON data is stored inline as {"nl": "...", "en": "..."}.
## Loc.t() handles both. Translations are also registered with the TranslationServer
## so that Node.tr("KEY") works in every Control.
extends Node

const LANGS := ["nl", "en"]
var lang: String = "nl"
var _strings: Dictionary = {}

func _ready() -> void:
	_load_csv("res://localization/strings.csv")
	_register_translations()
	set_lang(lang)

func _load_csv(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Loc: cannot open " + path)
		return
	var header := f.get_csv_line()
	var cols := {}
	for i in header.size():
		cols[header[i].strip_edges()] = i
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2 or row[0].strip_edges() == "":
			continue
		var entry := {}
		for l in LANGS:
			if cols.has(l) and cols[l] < row.size():
				entry[l] = row[cols[l]]
		_strings[row[0].strip_edges()] = entry
	f.close()

func _register_translations() -> void:
	for l in LANGS:
		var t := Translation.new()
		t.locale = l
		for key in _strings.keys():
			var e: Dictionary = _strings[key]
			if e.has(l):
				t.add_message(key, e[l])
		TranslationServer.add_translation(t)

func set_lang(l: String) -> void:
	if not LANGS.has(l):
		l = "en"
	lang = l
	TranslationServer.set_locale(l)
	Events.language_changed.emit(l)

func toggle() -> void:
	set_lang("en" if lang == "nl" else "nl")

## Translate a key (String) or an inline bilingual dictionary. Supports {name} style args.
func t(v, args: Dictionary = {}) -> String:
	var s := ""
	if v is Dictionary:
		var d: Dictionary = v
		if d.has(lang):
			s = str(d[lang])
		elif d.has("en"):
			s = str(d["en"])
		elif d.has("nl"):
			s = str(d["nl"])
	elif v is String:
		if _strings.has(v):
			var e: Dictionary = _strings[v]
			s = str(e.get(lang, e.get("en", v)))
		else:
			s = v
	else:
		s = str(v)
	if args.size() > 0:
		for k in args.keys():
			s = s.replace("{" + str(k) + "}", str(args[k]))
	return s

func has_key(k: String) -> bool:
	return _strings.has(k)

func count() -> int:
	return _strings.size()
