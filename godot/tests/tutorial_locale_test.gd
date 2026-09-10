extends SceneTree
const App = preload("res://scripts/shogi_app.gd")
const I18n = preload("res://scripts/shogi_i18n.gd")
const Tutorial = preload("res://scripts/shogi_tutorial.gd")
var checks: int = 0
var failures: Array[String] = []
var course_characters: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func characters(value, result: Dictionary) -> void:
	if value is String:
		for character in value:
			if character not in ["\n", "\t", "\r"]: result[character] = true
	elif value is Array:
		for item in value: characters(item, result)
	elif value is Dictionary:
		for item in value.values(): characters(item, result)

func run() -> void:
	for path in Tutorial.BOOK_PATHS:
		characters(JSON.parse_string(FileAccess.get_file_as_string(path)), course_characters)
	var app = App.new()
	for locale in ["zh", "ja", "en"]:
		app.preferences.language = locale
		app._update_font()
		var translator = I18n.new()
		translator.language = locale
		var all_characters = course_characters.duplicate()
		for source in I18n.TUTORIAL_CATALOG.data:
			var translated = translator.text(source)
			checks += 1
			if translated.is_empty(): failures.append(locale + " empty: " + source)
			characters(translated, all_characters)
		for character in all_characters:
			checks += 1
			if not app.text_font.has_char(character.unicode_at(0)):
				failures.append(locale + " missing glyph: " + character)
	app.free()
	var report = {"checks": checks, "failures": failures, "course_characters": course_characters.size(), "languages": ["zh", "ja", "en"]}
	var file = FileAccess.open("res://../review/app/complete/tutorial-localization-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("TUTORIAL LOCALE: ", checks, " checks, failures: ", failures)
	quit(0 if failures.is_empty() else 1)
