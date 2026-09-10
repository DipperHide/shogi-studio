extends SceneTree
const C = preload("res://scripts/shogi_move_classification.gd")
const T = preload("res://scripts/shogi_report_tactics.gd")
const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Report = preload("res://scripts/shogi_report.gd")
var checks = 0
var failures: Array = []

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("CLASSIFICATION FAIL: ", name)

func source(sfen: String, sequence: String):
	var game = Game.new()
	check(game.set_initial(sfen), "valid tactical fixture")
	for value in sequence.split(" ", false):
		var move = Codec.parse_move(value, game.position)
		check(not move.is_empty() and game.play(move), "legal fixture move " + value)
	return game

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Expectations come from branch boundaries in the original N0 DEX, including
	# saturated evaluations where a fixed loss threshold gives a different result.
	for fixture in [[0, 30, 5], [0, -19, 5], [0, -20, 6], [0, -60, 6], [0, -61, 7],
		[0, -90, 7], [0, -91, 8], [0, -220, 8], [0, -221, 9], [-100, -281, 9],
		[500, 200, 10], [499, 200, 9], [1000, 850, 6], [1000, 300, 8], [3000, 2400, 6],
		[-1000, -3000, 7], [99997, 99995, 6], [99999, 99994, 7], [99993, 200, 10],
		[99999, 300, 7], [0, -99997, 9], [-3000, -99997, 7], [-99995, -99998, 6]]:
		check(C.score_category(fixture[0], fixture[1]) == fixture[2], "reference score boundary " + str(fixture))
	check(C.NAMES.size() == 11 and Report.CATEGORIES.size() == 10, "all ten reference categories represented")
	var sentinel = {"score": -30000, "mate": true, "mate_distance": -5}
	check(C.score(sentinel, -1) == 99995 and C.score(sentinel, 1) == -99995, "mate sentinel respects analyzed side")
	check(is_equal_approx(C.score({"score": 600}, 1), 600 / C.Metrics.CP_SCALE), "shogi evaluation converted by shared win-chance scale")
	var bounded = Codec.parse_info("info depth 9 multipv 2 score cp 120 lowerbound nodes 80 pv 7g7f")
	check(bounded.bound == "lowerbound" and bounded.pv == ["7g7f"], "USI score bounds retained")
	var game = source("8k/9/4p4/9/4R4/9/9/9/K8 b - 1", "9i9h 1a1b 5e5d")
	var tactical = T.candidate(game, 3)
	check(tactical.candidate and tactical.sacrifice and tactical.new_risk == 2100, "new rook sacrifice accounts for lost rook and captured hand rook")
	var before = game.positions[2]
	var hanging = T.hanging(game.position, 1)
	check(hanging.has(31) and hanging[31] == 2100, "legal pawn capture identifies hanging rook")
	var safe = source("9/9/4r1k1p/9/4S4/9/9/9/K8 b - 1", "9i9h 1c1d 5e4d")
	var fork = T.candidate(safe, 3)
	check(fork.candidate and not fork.sacrifice and fork.fork_targets.size() == 2, "new fork separated from an already hanging moving piece")
	for position in [game.positions[0], game.positions[2], game.position, safe.position]:
		for square in range(81):
			if position.board[square] * position.turn >= 0 or absi(position.board[square]) == 8: continue
			var expected = position.legal_moves(true).filter(func(m): return m.to == square)
			check(T.captures_to(position, square) == expected, "targeted exchange captures preserve full shogi legality at " + str(square))
	var row = {"best": "5e5d", "classification": {"endgame": false, "tactics": tactical}}
	var first = {"score_type": "cp", "score": 100, "depth": 10, "pv": ["5e5d"]}
	var second = {"score_type": "cp", "score": -10, "depth": 10, "pv": ["5e5c+"]}
	var proof = C.verify_best(row, {1: first, 2: second})
	check(proof.accepted and proof.category_id == 2, "sacrifice plus independently supplied sufficient gap qualifies")
	second.score = 95
	check(not C.verify_best(row, {1: first, 2: second}).accepted, "tiny alternative gap cannot qualify")
	second.score = -10
	first.bound = "upperbound"
	check(not C.verify_best(row, {1: first, 2: second}).accepted, "bound-only score cannot grant rare category")
	first.erase("bound")
	first.pv = ["5e5c+"]
	check(not C.verify_best(row, {1: first, 2: second}).accepted, "changed verification best cannot grant rare category")
	first.pv = ["5e5d"]
	first.score = -700
	second.score = -1000
	check(not C.verify_best(row, {1: first, 2: second}).accepted, "still substantially losing cannot earn rare category")
	row.classification.tactics = fork
	first.score = 0
	second.score = -300
	proof = C.verify_best(row, {1: first, 2: second})
	check(proof.accepted and proof.category_id == 3, "fork with clearly inferior alternative qualifies as sharp")
	check(not C.verify_best(row, {1: first}).accepted, "single candidate is insufficient")
	var metrics = C.Metrics.move_metrics({"score": 1400}, {"score": 0}, 1, false, false, 30)
	var result = C.classify(game, 3, {"score": 1400, "pv": ["5e5c+"], "legal_count": 30}, {"score": 0}, metrics)
	check(result.category == "错失胜机" and not result.forced, "winning advantage lost is distinct from blunder")
	metrics.book = true
	check(C.classify(game, 3, {"score": 1400, "pv": ["5e5c+"], "legal_count": 30}, {"score": 0}, metrics).category == "定式", "book category precedes score classification")
	metrics.book = false
	result = C.classify(game, 3, {"score": 1400, "pv": ["5e5d"], "legal_count": 1}, {"score": 0}, metrics)
	check(result.category == "最佳" and result.forced and result.classification.tactics.is_empty(), "forced move cannot be rare best")
	result = C.classify(game, 3, {"score": 0, "pv": ["5e5c+"], "legal_count": 30}, {"score": -280}, metrics, true)
	check(result.classification.endgame, "passed endgame context stays active away from the king")
	var report = Report.new()
	report.candidates_by_depth = {8: {1: {"depth": 8, "pv": ["5e5d"]}, 2: {"depth": 8, "pv": ["5e5c+"]}}, 9: {1: {"depth": 9, "pv": ["5e5d"]}}}
	check(report._coherent_candidates(2)[1].depth == 8, "unfinished newer depth cannot replace complete candidate pair")
	report.candidates_by_depth[9][2] = {"depth": 9, "pv": ["5e5c+"]}
	check(report._coherent_candidates(2)[1].depth == 9, "newer completed depth supersedes earlier pair")
	report.free()
	var out = ProjectSettings.globalize_path("res://../review/app/chessis14")
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("classification-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("CLASSIFICATION 14: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
