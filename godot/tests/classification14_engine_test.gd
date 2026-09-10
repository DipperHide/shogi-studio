extends SceneTree
const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Report = preload("res://scripts/shogi_report.gd")
var checks = 0
var failures: Array = []
var report
var output: String
var paused_verification = false

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("CLASSIFICATION ENGINE FAIL: ", name)

func until(predicate: Callable, seconds: float = 20) -> bool:
	var deadline = Time.get_ticks_msec() + seconds * 1000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func fixture(sfen: String, sequence: String):
	var game = Game.new()
	check(game.set_initial(sfen), "valid actual engine fixture")
	for value in sequence.split(" ", false):
		var move = Codec.parse_move(value, game.position)
		check(not move.is_empty() and game.play(move), "legal source move " + value)
	return game

func _initialize() -> void:
	call_deferred("run")

func pause_once() -> void:
	if report.verifying and not paused_verification:
		paused_verification = true
		report.cancel()

func save_report(name: String) -> void:
	FileAccess.open(output.path_join(name + ".json"), FileAccess.WRITE).store_string(JSON.stringify({"source": report.game.to_data(), "rows": report.rows, "samples": report.samples, "searches": report.searches, "verification_searches": report.verification_searches}, "  "))
	FileAccess.open(output.path_join(name + "-transcript.txt"), FileAccess.WRITE).store_string("\n".join(report.engine.transcript))

func run() -> void:
	output = ProjectSettings.globalize_path("res://../review/app/chessis14/engine")
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(65).timeout.connect(func(): quit(2))
	report = Report.new()
	root.add_child(report)
	var source = fixture("9/9/4r1k1p/9/4SP3/9/9/9/K8 b - 1", "9i9h 1c1d 5e4d")
	var original = source.to_data().duplicate(true)
	report.changed.connect(pause_once)
	report.start(source, true, {"deep_mode": "time", "deep_time": 0.5, "deep_lines": 3})
	check(await until(func(): return not report.running), "real fork analysis reaches completion or verification pause")
	check(report.error.is_empty() and report.rows.size() == 3, "all real fork source positions analyzed")
	check(paused_verification and report.can_resume() and report.samples.size() == 4, "verification can pause after preserving main report")
	var prefix: Array = report.samples.duplicate(true)
	var original_searches = report.searches.size()
	var old_generation = report.generation - 1
	report.changed.disconnect(pause_once)
	if report.can_resume():
		report.resume()
		check(await until(func(): return not report.running), "verification resumes and finishes")
	check(report.error.is_empty() and report.samples == prefix and report.searches.size() == original_searches, "resumed verification does not repeat position analysis")
	check(not report.can_resume() and report.verification_cursor == report.rows.size(), "completion includes verification cursor")
	check(report.rows[2].best == "5e4d" and report.rows[2].category == "锐利", "real engine confirms silver fork as sharp")
	var proof: Dictionary = report.rows[2].classification.verification
	check(proof.get("accepted", false) and proof.get("candidates", []).size() == 2, "actual two-candidate evidence retained")
	if proof.get("accepted", false):
		check(proof.candidates[0].depth == proof.candidates[1].depth and proof.candidates.all(func(c): return c.get("bound", "").is_empty()), "verification uses exact scores at one completed depth")
		check("> setoption name PvInterval value 0" in report.engine.transcript, "report requests every completed PV iteration")
	var snapshot = report.rows.duplicate(true)
	report._best(old_generation, {}, "resign")
	check(report.rows == snapshot, "stale analysis callback cannot alter finished report")
	check(source.to_data() == original, "report and verification preserve original game")
	save_report("actual-fork")
	var hanging = fixture("8k/9/4p4/9/4R4/9/9/9/K8 b - 1", "5e5d")
	report.start(hanging, true, {"deep_mode": "time", "deep_time": 0.5, "deep_lines": 2})
	check(await until(func(): return not report.running), "real hanging-rook report completes")
	check(report.error.is_empty() and report.rows.size() == 1 and report.rows[0].category == "错失胜机", "real loss of winning advantage distinguished from ordinary blunder")
	check(report.verification_searches.is_empty(), "new report does not retain previous verification history")
	save_report("actual-lost-win")
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("CLASSIFICATION 14 ENGINE: ", checks, " checks; ", failures)
	report.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
