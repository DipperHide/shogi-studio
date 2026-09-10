extends SceneTree
const I18n = preload("res://scripts/shogi_i18n.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for locale in ["zh", "ja", "en"]:
		var font = load("res://assets/fonts/NotoSansJP.ttf" if locale == "ja" else "res://assets/fonts/NotoSansSC.ttf")
		var translator = I18n.new()
		translator.language = locale
		var all_characters: Dictionary = {}
		for source in I18n.CATALOG.data:
			var translated = translator.text(source)
			checks += 1
			if translated.is_empty(): failures.append(locale + " empty: " + source)
			for character in translated:
				if character not in ["\n", "\t", "\r"]: all_characters[character] = true
		for character in all_characters:
			checks += 1
			if not font.has_char(character.unicode_at(0)): failures.append(locale + " missing glyph: " + character)
	var pieces = load("res://assets/fonts/NotoSerifJP.ttf")
	for character in "歩香桂銀金角飛玉王と成馬龍":
		checks += 1
		if not pieces.has_char(character.unicode_at(0)): failures.append("Mincho missing piece glyph: " + character)
	var report = {"checks": checks, "failures": failures, "languages": ["zh", "ja", "en"]}
	var output = FileAccess.open("res://../review/app/unified/localization-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t")); output.close()
	print("LOCALIZATION_TESTS: ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
