extends SceneTree
const Draft = preload("res://scripts/shogi_import_draft.gd")
const Exchange = preload("res://scripts/shogi_exchange.gd")
const Preferences = preload("res://scripts/shogi_preferences.gd")
var checks = 0
var failures = []
var directory: String

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ", label)

func _init() -> void:
	directory = ProjectSettings.globalize_path("res://../review/app/chessis30")
	if "--chessis31-regression" in OS.get_cmdline_user_args(): directory = ProjectSettings.globalize_path("res://../review/app/chessis31")
	DirAccess.make_dir_recursive_absolute(directory)
	var draft = Draft.new()
	check(draft.source.is_empty() and draft.preview().is_empty() and not draft.locked(), "empty draft")
	check(draft.replace("x".repeat(16000)) and not draft.locked(), "exact preview boundary remains editable")
	check(draft.replace("x".repeat(16001)) and draft.locked() and draft.source.length() == 16001, "long source remains complete")
	check(draft.preview().length() < 16010 and draft.preview().ends_with("…"), "bounded preview")
	var game = Exchange.new().parse("position startpos moves 7g7f 3c3d 8h2b+ 3a2b B*4e")
	check(game != null, "legal capture, promotion and drop fixture")
	game.comments["2"] = "原文注釈を保持".repeat(2500)
	game.comments["5"] = "最終手の注釈"
	var text = Exchange.export_game(game, "JSON")
	check(draft.replace(text, "fixture.json") and draft.locked(), "large valid record gets read-only preview")
	var parsed = Exchange.new().parse(draft.source)
	check(parsed != null and parsed.comments == game.comments and parsed.moves == game.moves, "loading full source retains text beyond preview cutoff")
	FileAccess.open(directory.path_join("long-record.json"), FileAccess.WRITE).store_string(text)
	var before: String = draft.source
	var revision: int = draft.revision
	check(not draft.replace("字".repeat(Draft.MAX_BYTES / 3 + 1)), "UTF-8 byte limit differs from character count")
	check(draft.source == before and draft.revision == revision and draft.source_name == "fixture.json", "oversize rejection preserves valid source and revision")
	check(draft.replace("position startpos") and not draft.locked() and draft.source_name.is_empty(), "short replacement unlocks preview")
	check(draft.read_bytes(PackedByteArray([0xef,0xbb,0xbf]) + "position startpos".to_utf8_buffer()), "UTF-8 BOM import")
	check(draft.source == "position startpos", "BOM is removed from parser input")
	before = draft.source
	check(not draft.read_bytes(PackedByteArray([0x81])) and draft.source == before, "invalid CP932 does not replace draft")
	var japanese = "先手：先手\n後手：後手"
	var encoded = PackedByteArray([0x90,0xe6,0x8e,0xe8,0x81,0x46,0x90,0xe6,0x8e,0xe8,0x0a,0x8c,0xe3,0x8e,0xe8,0x81,0x46,0x8c,0xe3,0x8e,0xe8])
	check(draft.read_bytes(encoded) and draft.source == japanese, "known CP932 byte fixture decodes correctly")
	var kif = Exchange.export_game(game, "KIF")
	check(draft.read_bytes(kif.to_utf8_buffer()) and Exchange.new().parse(draft.source).comments["2"].strip_edges() == game.comments["2"], "file decoding preserves comments rather than applying tournament stripping")
	FileAccess.open(directory.path_join("source.kif"), FileAccess.WRITE).store_string(kif)
	for format in ["KIF", "CSA", "USI", "SFEN", "JSON"]:
		var codec = Exchange.new()
		check(draft.replace(Exchange.export_game(game, format)), "accept " + format)
		var next = codec.parse(draft.source)
		check(next != null and next.position.key() == game.position.key(), "valid final position " + format)
	check(draft.replace("") and draft.preview().is_empty() and not draft.locked(), "clear discards both preview and full payload")
	var config = ConfigFile.new()
	config.set_value("preferences", "studio", {"analysis_tab": 17})
	config.save(directory.path_join("preferences.cfg"))
	var prefs = Preferences.new(); prefs.load_from(directory.path_join("preferences.cfg"))
	check(prefs.studio.analysis_tab == 1, "last-source preference is bounded")
	prefs.studio.analysis_tab = 0; prefs.save_to(directory.path_join("preferences.cfg"))
	var restored = Preferences.new(); restored.load_from(directory.path_join("preferences.cfg"))
	check(restored.studio.analysis_tab == 0, "last-source preference survives round trip")
	FileAccess.open(directory.path_join("import-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("IMPORT30: ", checks, " checks, failures: ", failures)
	quit(0 if failures.is_empty() else 1)
