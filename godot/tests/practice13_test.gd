extends SceneTree
const Practice = preload("res://scripts/shogi_mistake_practice.gd")
const Report = preload("res://scripts/shogi_report.gd")
const Exchange = preload("res://scripts/shogi_exchange.gd")
const Progress = preload("res://scripts/shogi_tutorial_progress.gd")
class TestTutorial:
	var progress = preload("res://scripts/shogi_tutorial_progress.gd").new()
	func _ensure_loaded() -> void: pass
class TestUI:
	var tutorial = TestTutorial.new()
class TestApp:
	var ui = TestUI.new()
var checks = 0
var failures: Array = []

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("PRACTICE FAIL: ", name)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var output = ProjectSettings.globalize_path("res://../review/app/chessis13")
	DirAccess.make_dir_recursive_absolute(output)
	var service = Practice.new()
	service.initialize(TestApp.new())
	service.progress().path = output.path_join("filter-progress.json")
	var report = Report.new()
	report.game = Exchange.new().parse("position startpos moves 7g7f 3c3d 8h2b+ 3a2b B*4e")
	report.rows = [
		{"ply": 1, "side": 1, "category": "失误", "label": "fixture", "best": "2g2f"},
		{"ply": 2, "side": -1, "category": "漏着", "label": "fixture", "best": "8c8d"},
		{"ply": 3, "side": 1, "category": "不精确", "label": "fixture", "best": "8h2b+"},
		{"ply": 4, "side": -1, "category": "失误", "label": "fixture", "best": "3a2b"},
		{"ply": 5, "side": 1, "category": "漏着", "label": "fixture", "best": "B*4e"}]
	report.samples = [{"pv": ["2g2f", "8c8d"]}, {"pv": ["8c8d"]}, {"pv": ["8h2b+", "3a2b"]}, {"pv": ["3a2b"]}, {"pv": ["B*4e", "invalid"]}]
	var options = {"side": 0, "categories": ["失误", "漏着"], "skip_tried": true}
	var entries = service.eligible(report, options)
	check(entries.size() == 4, "default types exclude inaccuracies")
	options.side = 1
	entries = service.eligible(report, options)
	check(entries.size() == 2 and entries.all(func(entry): return entry.side == 1), "sente filter uses mover, not current end position")
	options.side = -1
	entries = service.eligible(report, options)
	check(entries.size() == 2 and entries.all(func(entry): return entry.side == -1), "gote filter uses mover")
	options.side = 0
	options.categories = []
	check(service.eligible(report, options).is_empty(), "no types yields no exercises")
	options.categories = ["不精确"]
	entries = service.eligible(report, options)
	check(entries.size() == 1 and entries[0].best.promote, "promotion choice retained in solution")
	options.categories = ["漏着"]
	entries = service.eligible(report, options)
	check(entries.back().best.drop == 6 and entries.back().pv == ["B*4e"], "drop retained and illegal PV suffix removed")
	var key: String = entries.back().key
	service.progress().note_mistake("mistakes", key, 0, key)
	check(service.eligible(report, options).size() == 1, "previous wrong attempt is skipped")
	options.skip_tried = false
	check(service.eligible(report, options).size() == 2, "disabling skip restores attempted item")
	service.progress().record("mistakes", key, 0, false, 0, true, key)
	options.skip_tried = true
	check(service.eligible(report, options).size() == 1, "revealed item also counts as tried")
	var restored = Progress.new()
	restored.load_from(service.progress().path)
	check(not restored.blocked_corrupt and not restored.blocked_read and restored.state("mistakes", key, 0, key).revealed, "attempts persist in existing validated learning format")
	check(not restored.state("mistakes", key, 0, key).mastered, "revealed solution not stored as mastery")
	var original_key = Practice.fingerprint(report.game, 1, "2g2f")
	report.game.metadata["先手"] = "renamed"
	check(Practice.fingerprint(report.game, 1, "2g2f") == original_key, "renaming player does not forget attempts")
	check(Practice.fingerprint(report.game, 1, "7g7f") != original_key, "changed best move invalidates old exercise fingerprint")
	var board_only = preload("res://scripts/shogi_game.gd").new()
	board_only.set_initial(preload("res://scripts/shogi_usi_codec.gd").sfen(report.game.positions[4]))
	check(Practice.fingerprint(board_only, 1, "B*4e") != key, "history-dependent positions do not collapse onto bare SFEN")
	report.rows[1].best = "7g7f"
	options.skip_tried = false
	check(service.eligible(report, options).size() == 1, "wrong-side best move rejected")
	report.rows[4].best = "P*4e"
	check(service.eligible(report, options).is_empty(), "drop unavailable in hand rejected")
	report.rows[4].best = "B*4e"
	report.samples[4].pv = ["7f7e"]
	check(service.eligible(report, options)[0].pv == ["B*4e"], "mismatched PV does not reveal a different solution")
	report.rows[4].ply = 99
	check(service.eligible(report, options).is_empty(), "out-of-range row ignored")
	FileAccess.open(output.path_join("practice-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	report.free()
	print("PRACTICE 13: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
