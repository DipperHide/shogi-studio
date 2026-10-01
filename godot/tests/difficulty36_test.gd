extends SceneTree
const Game = preload("res://scripts/shogi_game.gd")
const AI = preload("res://scripts/shogi_ai.gd")
const Profiles = preload("res://scripts/shogi_difficulty.gd")
const Coach = preload("res://scripts/shogi_coach.gd")
var checks = 0
var failures: Array = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var game = Game.new()
	check(game.engine_level == 7, "fresh games select enlightenment")
	for id in range(10):
		game.engine_level = id
		var restored = Game.from_data(game.to_data())
		check(restored != null and restored.engine_level == id, "stable difficulty save ID %d" % id)
	var old = game.to_data(); old.erase("engine_level")
	check(Game.from_data(old).engine_level == 2, "legacy missing level retains old default")
	for invalid in [-1, 10, 2.5]:
		old.engine_level = invalid
		check(Game.from_data(old) == null, "reject invalid difficulty")
	check(Profiles.ORDER == [6,7,8,9,0,1,2,3,4,5], "display order does not renumber saves")
	var engine = AI.new()
	var fixture = Game.new()
	check(fixture.set_initial("4k4/9/9/4r4/4R4/9/9/9/4K4 b - 1"), "free rook tactical fixture")
	var results: Array = []
	for id in range(6,10):
		var random_count = 0; var captures = 0; var elapsed = 0
		for seed_value in range(64):
			var start = Time.get_ticks_msec()
			var result = engine.choose_profile(fixture.position, id, -1, seed_value)
			elapsed += Time.get_ticks_msec() - start
			check(fixture.position.is_legal_move(result.move), "weak %d seed %d returns legal move" % [id, seed_value])
			if result.random: random_count += 1
			if result.move.to == 31: captures += 1
			if seed_value < 3:
				check(engine.choose_profile(fixture.position, id, -1, seed_value).move == result.move, "seed reproduces selection")
		results.append({"level": id, "random": random_count, "free_rook_captures": captures, "mean_ms": elapsed / 64.0})
	check(results[0].random == 64 and results[1].random > results[2].random and results[2].random > results[3].random, "randomness decreases across weak levels")
	check(results[0].free_rook_captures < results[1].free_rook_captures and results[1].free_rook_captures <= results[2].free_rook_captures and results[2].free_rook_captures <= results[3].free_rook_captures, "tactical fixture separates weak grades")
	# Both seats, captures and drops are exercised through full legal positions.
	var matches: Array = []
	for reversed in [false, true]:
		var match_game = Game.new()
		for ply in range(40):
			var id = (6 if match_game.position.turn == 1 else 9) if not reversed else (9 if match_game.position.turn == 1 else 6)
			var response = engine.choose_profile(match_game.position, id, -1, 1000 + ply)
			if response.is_empty(): break
			check(match_game.play(response.move), "weak pairing legal ply %d" % ply)
			if not match_game.result.is_empty(): break
		matches.append({"reversed": reversed, "plies": match_game.moves.size(), "result": match_game.result, "evaluation": engine._evaluate(match_game.position) * match_game.position.turn})
	check(Coach.category({"score": 0, "depth": 10, "score_type": "cp"}, {"score": 1000, "depth": 10, "score_type": "cp"}) in [8,9,10], "large loss triggers existing report classifier")
	check(Coach.category({"score": 0, "depth": 10, "bound": "lowerbound"}, {"score": 1000, "depth": 10}) == 0, "bounds cannot produce warning")
	check(Coach.category({}, {"score": 1000, "depth": 10}) == 0, "missing evaluation cannot produce warning")
	var path = ProjectSettings.globalize_path("res://../review/app/experience36/difficulty.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var summary = {"checks": checks, "failures": failures, "tactical": results, "pairings": matches}
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(summary, "\t"))
	print("DIFFICULTY36 ", JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
