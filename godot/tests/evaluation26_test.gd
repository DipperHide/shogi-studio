extends SceneTree
const Bar = preload("res://scripts/shogi_evaluation_bar.gd")
const Preferences = preload("res://scripts/shogi_preferences.gd")
var checks = 0
var failures = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func _initialize() -> void:
	var neutral = Bar.sample({}, 1)
	check(not neutral.available and neutral.fraction == 0.5 and neutral.text == "—", "unknown evaluation is neutral and explicitly unavailable")
	for turn in [1, -1]:
		for entry in [[0, 0.5], [220.9248, 0.6], [-220.9248, 0.4], [1104.624, 1.0], [-1104.624, 0.0], [50000, 1.0], [-50000, 0.0]]:
			var result = Bar.sample({"score": entry[0] * turn, "depth": 17}, turn)
			check(is_equal_approx(result.fraction, entry[1]), "reference linear scale and saturation %s / %s" % [turn, entry])
			check(result.depth == 17 and result.available and result.score == entry[0], "engine scores normalized to sente, depth preserved")
		for distance in [-9, 7]:
			var result = Bar.sample({"score": distance, "score_type": "mate", "depth": 23}, turn)
			check(result.fraction == (1.0 if distance * turn > 0 else 0.0), "mate fill uses global winner")
			check(result.text == ("+詰" if distance * turn > 0 else "−詰") + str(abs(distance)), "mate caption uses actual distance")
	for winner in [-1, 0, 1]:
		var result = Bar.sample({"score": 123, "depth": 5}, 1, true, winner, "终局")
		check(result.terminal and result.fraction == (winner + 1) / 2.0 and result.depth == 0 and result.text == "终局", "actual result replaces stale final engine evaluation")
	var preferences = Preferences.new()
	check(preferences.studio.eval_position == "smart", "new and legacy preferences default to smart")
	for mode in ["smart", "left", "bottom", "left_on_game_report", "invalid"]:
		preferences.studio.eval_position = mode
		check(preferences.save_to("user://evaluation26-test.cfg") == OK, "save position preference")
		var restored = Preferences.new()
		restored.load_from("user://evaluation26-test.cfg")
		check(restored.studio.eval_position == ("smart" if mode == "invalid" else mode), "persist and validate position preference")
	DirAccess.remove_absolute("user://evaluation26-test.cfg")
	var output = ProjectSettings.globalize_path("res://../review/app/chessis26")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("evaluation-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("EVALUATION 26: ", checks, " checks; failures: ", failures)
	quit(0 if failures.is_empty() else 1)
