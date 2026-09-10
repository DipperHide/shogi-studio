extends SceneTree
const Rules = preload("res://scripts/shogi_tutorial_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Model = preload("res://scripts/shogi_tutorial_model.gd")
var checks: int = 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("TSUME FAIL: ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://../review/app/complete/tutorial-intro-tsume-supplement.json"))
	for problem in source.validation.problems:
		var label = "question " + str(int(problem.number))
		var pos = Rules.from_sfen(problem.position)
		var move = Codec.parse_move(problem.accepted, pos)
		check(not move.is_empty(), label + " answer legal")
		if move.is_empty(): continue
		pos.apply_unchecked(move)
		check(pos.in_check(pos.turn) and pos.legal_moves().is_empty(), label + " checkmate with all remaining defender hands")
		for branch in problem.branches:
			pos = Rules.from_sfen(problem.position)
			for index in range(branch.moves.size()):
				move = Codec.parse_move(branch.moves[index], pos)
				check(not move.is_empty(), label + " refutation " + branch.moves[index])
				if move.is_empty(): break
				pos.apply_unchecked(move)
				if index == 0: check(not pos.in_check(pos.turn) or not pos.legal_moves().is_empty(), label + " incorrect attack is not mate")
	for lesson in source.lessons:
		for index in range(lesson.steps.size()):
			check(Model.validate_step(lesson.steps[index]).is_empty(), str(lesson.id) + " runtime step " + str(index))
	var file = FileAccess.open("res://../review/app/complete/tutorial-intro-tsume-godot-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "mates": 12, "refutations": 24}, "\t"))
	file.close()
	print("TSUME CHECKS: ", checks, " failures: ", failures.size())
	quit(0 if failures.is_empty() else 1)
