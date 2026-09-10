extends SceneTree
const Rules = preload("res://scripts/shogi_tutorial_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Model = preload("res://scripts/shogi_tutorial_model.gd")
var checks: int = 0
var failures: Array[String] = []
var steps: int = 0
var actions: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CH4 FAIL: ", message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://../review/app/complete/tutorial-opening-ch4-supplement.json"))
	for lesson in data.lessons:
		for index in range(lesson.steps.size()):
			var step = lesson.steps[index]
			var label = str(lesson.id) + " step " + str(index)
			steps += 1
			var model = Model.new()
			check(model.start(step), label + " starts: " + model.error)
			if not model.error.is_empty(): continue
			match step.kind:
				"choice":
					check(model.choose(int(step.answer)), label + " choice")
				"targets":
					for square in step.targets: model.toggle_target(square)
					check(model.submit_targets(), label + " targets")
				"move":
					for move in step.accepted:
						var variant = Model.new()
						variant.start(step)
						check(variant.submit_move(move), label + " alternative " + move)
						check(variant.mastered(), label + " alternative mastered")
					check(model.submit_move(step.accepted[0]), label + " move")
				"sequence":
					while not model.solved:
						if not model.submit_move(step.moves[model.cursor]):
							check(false, label + " sequence " + str(model.cursor))
							break
						actions += 1
			if step.kind != "text": check(model.mastered(), label + " actual input mastered")
	for figure in data.validation.source_figures:
		check(Rules.from_sfen(figure.position) != null, "source figure " + figure.id)
	for proof in data.validation.checks:
		if proof.kind == "checkmate":
			var pos = Rules.from_sfen(proof.position)
			for usi in proof.moves:
				var move = Codec.parse_move(usi, pos)
				check(not move.is_empty(), proof.label + " legal " + usi)
				if move.is_empty(): break
				pos.apply_unchecked(move)
			check(pos.in_check(pos.turn) and pos.legal_moves().is_empty(), proof.label + " mate")
		elif proof.kind == "hisshi":
			var pos = Rules.from_sfen(proof.position)
			var count: int = 0
			for defense in pos.legal_moves():
				var next = pos.copy()
				next.apply_unchecked(defense)
				check(not next.in_check(next.turn), "anaguma cannot immediately check")
				var found: bool = false
				for attack in ["G*3b", "G*5b"]:
					var response = Codec.parse_move(attack, next)
					if response.is_empty(): continue
					var final_position = next.copy()
					final_position.apply_unchecked(response)
					if final_position.in_check(final_position.turn) and final_position.legal_moves().is_empty(): found = true
				check(found, "anaguma double gold-drop threat survives defense")
				count += 1
			check(count == int(proof.defenses_checked), "both engines agree on all defenses")
	var file = FileAccess.open("res://../review/app/complete/tutorial-opening-ch4-godot-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"steps":steps,"actual_sequence_inputs":actions,"source_figures":data.validation.source_figures.size()}, "\t"))
	file.close()
	print("CH4 CHECKS: ", checks, " failures: ", failures.size(), " steps: ", steps)
	quit(0 if failures.is_empty() else 1)
