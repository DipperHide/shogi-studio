extends SceneTree
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Report = preload("res://scripts/shogi_report.gd")
const Exchange = preload("res://scripts/shogi_exchange.gd")
const Game = preload("res://scripts/shogi_game.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
var checks = 0
var failures: Array = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("METRICS FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(is_equal_approx(Metrics.chance(0), 50), "equal evaluation gives equal chances")
	check(absf(Metrics.chance(600) - 73.1058579) < 0.0001, "report uses the live shogi win-chance scale")
	for value in [-30000, -6000, -100, 0, 100, 6000, 30000]:
		check(absf(Metrics.chance(value) + Metrics.chance(-value) - 100) < 0.00001, "side-symmetric chances " + str(value))
	var samples = [{"score": 600}, {"score": -300}]
	var sente = Metrics.move_metrics(samples[0], samples[1], 1, false, false, 30)
	var gote = Metrics.move_metrics({"score": -600}, {"score": 300}, -1, false, false, 30)
	check(sente == gote, "identical decisions for either side produce identical metrics")
	check(sente.accuracy < 40 and sente.wpl > 35 and absf(sente.shogi_cpl - 900) < 0.001, "large reversal penalizes accuracy with native shogi ACPL")
	var best = Metrics.move_metrics(samples[0], samples[1], 1, true, false, 30)
	check(best.accuracy == 100 and best.cpl == 0 and best.wpl == 0, "actual engine best gets full credit despite deeper score change")
	check(Report.classify(0, false) != "最佳" and Report.classify(900, true) == "最佳", "best is actual PV identity, not loss threshold")
	var empty = Metrics.aggregate([], 1)
	check(not empty.has_accuracy and empty.count == 0, "no samples do not fabricate 100 accuracy")
	var fixture: Array = []
	for i in range(3):
		fixture.append({"side": 1, "ply": i * 2 + 1, "category": ["最佳", "好棋", "失误"][i], "metrics": {"accuracy": [100, 90, 60][i], "cpl": [0, 25, 200][i], "wpl": [0, 2, 10][i], "weight": 1.0, "book": false, "before_chance": 50, "after_chance": 40}})
	check(Metrics.aggregate(fixture, 1, 1, 5, false).accuracy == 73.5, "reference aggregate formula golden fixture = 73.5")
	check(Metrics.aggregate(fixture, 1).accuracy == 72.8, "one mistake applies the reference 0.7 overall penalty")
	check(Metrics.aggregate(fixture, -1).count == 0, "other side does not contaminate statistics")
	check(Metrics.aggregate(fixture, 1, 3, 3, false).accuracy == 90, "single evaluated move retains its own accuracy")
	var excluded = fixture.duplicate(true)
	for row in excluded: row.metrics.weight = 0; row.metrics.book = true
	var stats = Metrics.aggregate(excluded, 1)
	check(not stats.has_accuracy and stats.book == 3 and stats.count == 3, "book-only phase retains counts without fictional score")
	for row in excluded: row.metrics.book = false
	stats = Metrics.aggregate(excluded, 1)
	check(not stats.has_accuracy and stats.forced == 3, "forced-only phase is excluded")
	check(Metrics.rounded(99.999) == 99.9 and Metrics.rounded(100) == 100, "rounded estimate never promotes a nonperfect score to 100")
	var line = Exchange.new().parse("position startpos moves 7g7f 3c3d 8h2b+ 3a2b B*4e")
	check(Metrics.book_prefix(line) == 2, "only matched curated prefix excluded, later captures and drop included")
	var phases = Metrics.phases(line)
	check(phases.size() == 1 and phases[0].type == 1 and phases[0].start == 1 and phases[0].end == 5, "short opening is not arbitrarily split into thirds")
	var custom = Game.new()
	custom.set_initial(preload("res://scripts/shogi_usi_codec.gd").sfen(line.positions[4]))
	custom.play(line.moves[4])
	check(Metrics.book_prefix(custom) == 0 and Metrics.phases(custom)[0].type == 2, "custom position does not assume known opening")
	var mates = [{"mate": true}]
	check(Metrics.phases(custom, mates)[0].type == 3, "mate at initial custom position starts in endgame")
	var sparse = Rules.new(false)
	sparse.board[4] = -8; sparse.board[76] = 8
	sparse.hands[1][7] = 2
	check(Metrics.king_pressure(sparse) == 0, "pieces in hand and low board material alone do not imply endgame")
	sparse.board[13] = 15; sparse.board[14] = 4
	check(Metrics.king_pressure(sparse) >= 4, "dragon and supporting silver at king imply endgame pressure")
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var full = historic.game_for(historic.entries()[0])
	phases = Metrics.phases(full)
	var covered = 0
	var previous_type = 0
	var previous_edge = 0.0
	for segment in phases:
		check(segment.start == covered + 1 and segment.end >= segment.start and segment.type > previous_type, "historic phases are ordered, contiguous and nonempty")
		var bounds = Metrics.span(segment, full.moves.size())
		check(bounds.x == previous_edge and bounds.y > bounds.x, "phase chart boundaries align without gaps")
		covered = segment.end
		previous_type = segment.type
		previous_edge = bounds.y
	check(covered == full.moves.size() and previous_edge == covered, "phases cover every historical ply exactly once")
	check(phases.size() >= 2, "historical opening transitions into combat")
	var output = ProjectSettings.globalize_path("res://../review/app/chessis12")
	if "--chessis14-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis14/metrics-regression")
	if "--chessis15-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis15/metrics-regression")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/metrics-regression")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/metrics-regression")
	if "--chessis18-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis18/metrics-regression")
	if "--chessis19-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis19/metrics-regression")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/report12_test")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("metrics.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "historic_phases": phases, "golden_accuracy": Metrics.aggregate(fixture, 1).accuracy}, "  "))
	print("REPORT 12: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
