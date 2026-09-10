extends SceneTree
const Settings = preload("res://scripts/shogi_report_settings.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
const Client = preload("res://scripts/shogi_usi_engine.gd")
const Exchange = preload("res://scripts/shogi_exchange.gd")
var checks = 0
var failures: Array = []
var received: Dictionary = {}
var details: Dictionary = {}
var output = ProjectSettings.globalize_path("res://../review/app/chessis10")

func _initialize() -> void:
	create_timer(100).timeout.connect(func(): printerr("REPORT TEST TIMEOUT"); quit(2))
	call_deferred("run")

func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok: failures.append(name); printerr("REPORT FAIL: ", name)

func until(predicate: Callable, seconds: float = 20) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func run() -> void:
	if "--chessis12-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis12/engine-regression")
	if "--chessis14-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis14/engine-regression")
	if "--chessis15-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis15/engine-regression")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/engine-regression")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/report10_test")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/engine-regression")
	DirAccess.make_dir_recursive_absolute(output)
	var options = Settings.normalized({})
	check(options.quick_mode == "depth" and options.quick_depth == 14 and is_equal_approx(options.quick_time, 0.6), "original quick defaults")
	check(options.deep_mode == "time" and is_equal_approx(options.deep_time, 1.2) and options.deep_depth == 18 and options.deep_lines == 1 and not options.smart, "original deep and smart defaults")
	var invalid = Settings.normalized({"quick_mode": "invalid", "quick_depth": -4, "deep_time": NAN, "deep_lines": 99})
	check(invalid.quick_mode == "depth" and invalid.quick_depth == 1 and invalid.deep_time == 1.2 and invalid.deep_lines == 5, "malformed settings normalize safely")
	var preferences = preload("res://scripts/shogi_preferences.gd").new()
	options.smart = true
	options.deep_lines = 3
	options.quick_time = 2.7
	preferences.report = options
	var path = output.path_join("preferences-test.cfg")
	check(preferences.save_to(path) == OK, "report settings persisted")
	var restored = preload("res://scripts/shogi_preferences.gd").new()
	restored.load_from(path)
	check(restored.report == options, "all report settings restored")
	var position = Rules.new()
	options.quick_depth = 25
	options.deep_time = 10.0
	check(Settings.limits(options, false, position, position.legal_moves()).depth == 12, "simple shogi position gets reduced smart depth")
	check(Settings.limits(options, true, position, position.legal_moves()).milliseconds == 1500, "simple shogi position gets reduced smart time")
	var game = Exchange.new().parse("position startpos moves 7g7f 3c3d 8h2b+ 3a2b B*4e")
	var tactical = game.positions[4]
	check(Settings.limits(options, false, tactical, tactical.legal_moves()).depth == 25, "many legal drops preserve full smart depth")
	options.smart = false
	check(Settings.limits(options, false, position, position.legal_moves()).depth == 25, "disabled smart uses exact selected depth")
	var client = Client.new()
	root.add_child(client)
	client.best_move.connect(func(id, move, special): received[id] = {"move": move, "special": special})
	client.analysis.connect(func(id, info): details[id] = info)
	client.failed.connect(func(message): check(false, message))
	client.launch()
	check(await until(func(): return client.available()), "actual engine ready")
	client.search(position, [], 20, 5, true, "startpos", 0, {"depth": 4})
	check(client.transcript.back() == "> go depth 4", "depth command has no silent time or node cap")
	check(await until(func(): return received.has(20)), "actual depth search completes")
	check(int(details.get(20, {}).get("depth", 0)) >= 4, "actual requested depth reached")
	client.search(position, [], 21, 5, true, "startpos", 0, {"milliseconds": 200})
	check(client.transcript.back() == "> go movetime 200", "explicit time command preserves chosen budget")
	check(await until(func(): return received.has(21)), "actual timed search completes")
	client.shutdown()
	client.queue_free()
	var report = preload("res://scripts/shogi_report.gd").new()
	root.add_child(report)
	options.deep_mode = "depth"
	options.deep_depth = 4
	options.deep_lines = 3
	report.start(game, true, options, {"threads": 3, "hash": 32})
	check(await until(func(): return report.samples.size() >= 2 or not report.running), "partial report created")
	check(report.engine.thread_count == 3 and report.engine.hash_size == 32 and report.engine.analysis_count == 3, "report honors resources and independent MultiPV")
	report.cancel()
	var prefix = report.samples.duplicate(true)
	check(report.can_resume() and not prefix.is_empty(), "stopped report can resume")
	options.deep_depth = 30
	check(report.settings.deep_depth == 4, "running report owns immutable settings snapshot")
	report.resume()
	check(await until(func(): return not report.running), "resume finishes")
	check(report.error.is_empty() and report.rows.size() == 5 and report.samples.size() == 6, "report covers every position exactly once")
	check(report.samples.slice(0, prefix.size()) == prefix, "resume retains finished samples unchanged")
	check(report.samples.all(func(s): return s.candidates.size() == 3 and s.depth >= 4), "three actual alternatives retained for every position")
	check(not report.can_resume(), "finished report cannot append duplicates")
	check(game.moves.size() == 5 and game.position.key() == report.game.position.key(), "analysis preserves original game")
	FileAccess.open(output.path_join("report-engine.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "searches": report.searches, "samples": report.samples}, "  "))
	report.queue_free()
	print("REPORT 10: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
