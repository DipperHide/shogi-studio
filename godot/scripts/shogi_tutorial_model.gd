extends RefCounted
## Each attempt owns a fresh position; answers never touch the active game.
const LessonRules = preload("res://scripts/shogi_tutorial_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var step: Dictionary = {}
var position: ShogiRules
var solved: bool = false
var revealed: bool = false
var mistakes: int = 0
var cursor: int = 0
var chosen_move: String = ""
var feedback: String = ""
var error: String = ""
var selected_targets: Array[String] = []

func start(value: Dictionary) -> bool:
	step = value.duplicate(true)
	solved = false
	revealed = false
	mistakes = 0
	cursor = 0
	chosen_move = ""
	feedback = ""
	selected_targets.clear()
	position = null
	error = validate_step(step)
	if not error.is_empty(): return false
	if step.kind == "sequence": step.student_side = int(step.get("student_side", 0))
	if step.kind in ["move", "targets", "sequence"]:
		position = LessonRules.from_sfen(step.position)
	if step.kind == "sequence": _advance_opponent()
	return true

static func validate_step(value: Dictionary) -> String:
	var kind = value.get("kind", "")
	if kind == "text": return "" if value.get("body", "") is String and not value.get("body", "").is_empty() else "缺少讲解正文"
	if kind not in ["choice", "move", "targets", "sequence"]: return "未知题型"
	if not value.get("prompt", "") is String or value.get("prompt", "").is_empty(): return "缺少题目说明"
	if kind == "choice":
		var options = value.get("options", [])
		var answer = value.get("answer", -1)
		if not options is Array or options.size() < 2: return "选择题选项不足"
		if not (answer is int or answer is float) or int(answer) != answer or answer < 0 or answer >= options.size(): return "选择题答案无效"
		for option in options:
			if not option is String: return "选择题选项无效"
		return ""
	if not value.get("position", "") is String: return "局面格式无效"
	var pos = LessonRules.from_sfen(value.get("position", ""))
	if pos == null: return "局面格式无效"
	if kind == "targets":
		var origin = Codec.parse_square(str(value.get("from", "")))
		if origin < 0 or pos.board[origin] == 0: return "目标题缺少起点棋子"
		var targets = value.get("targets", [])
		if not targets is Array: return "目标集合无效"
		var seen: Array = []
		for target in targets:
			if not target is String or Codec.parse_square(target) < 0 or target in seen: return "目标坐标无效或重复"
			seen.append(target)
		return ""
	var moves = value.get("accepted" if kind == "move" else "moves", [])
	if not moves is Array or moves.is_empty(): return "缺少指定着法"
	if kind == "sequence":
		var student_side = value.get("student_side", 0)
		if not (student_side is int or student_side is float) or int(student_side) != student_side or int(student_side) not in [0, 1, -1]: return "练习方无效"
	var student_moves = 0
	for item in moves:
		if kind == "move": pos = LessonRules.from_sfen(value.position)
		if not item is String: return "着法格式无效"
		var move = Codec.parse_move(item, pos)
		if move.is_empty(): return "非法着法：" + item
		if value.get("student_side", 0) == 0 or value.get("student_side", 0) == pos.turn: student_moves += 1
		pos.apply_unchecked(move)
		if kind == "move":
			if not value.get("reply", []) is Array: return "回应序列无效"
			for response in value.get("reply", []):
				if not response is String: return "回应着法格式无效"
				var reply = Codec.parse_move(response, pos)
				if reply.is_empty(): return "非法回应：" + response
				pos.apply_unchecked(reply)
	if kind == "sequence" and student_moves == 0: return "序列没有学员着法"
	return ""

func _wrong(message: String) -> bool:
	mistakes += 1
	feedback = message
	return false

func choose(index: int) -> bool:
	if solved or not error.is_empty() or step.get("kind") != "choice": return false
	if index < 0 or index >= step.options.size(): return false
	if index != int(step.answer): return _wrong("再想一想。可以重选，也可以显示答案后重练。")
	_finish()
	return true

func submit_move(value: String) -> bool:
	if solved or not error.is_empty() or step.get("kind") not in ["move", "sequence"]: return false
	var move = Codec.parse_move(value, position)
	if move.is_empty(): return _wrong("这步不符合将棋规则。请重新选择。")
	var expected: Array = step.accepted if step.kind == "move" else [step.moves[cursor]]
	if value not in expected: return _wrong("这步可以走，但没有完成这道题的任务。请再试一次。")
	position.apply_unchecked(move)
	if step.kind == "move":
		chosen_move = value
		for response in step.get("reply", []): position.apply_unchecked(Codec.parse_move(response, position))
		_finish()
	else:
		cursor += 1
		_advance_opponent()
		if not solved: feedback = "这一步正确，继续下一步。"
	return true

func _advance_opponent() -> void:
	while cursor < step.moves.size() and step.get("student_side", 0) != 0 and position.turn != int(step.student_side):
		position.apply_unchecked(Codec.parse_move(step.moves[cursor], position))
		cursor += 1
	if cursor >= step.moves.size(): _finish()

func toggle_target(square: String) -> void:
	if solved or not error.is_empty() or step.get("kind") != "targets" or Codec.parse_square(square) < 0: return
	if square in selected_targets: selected_targets.erase(square)
	else: selected_targets.append(square)

func submit_targets() -> bool:
	if solved or not error.is_empty() or step.get("kind") != "targets": return false
	var expected = step.targets.duplicate()
	expected.sort()
	var actual = selected_targets.duplicate()
	actual.sort()
	if actual != expected: return _wrong("目标还不完整或多选了格子。再次点选可取消，再提交一次。")
	_finish()
	return true

func reveal() -> void:
	if solved or not error.is_empty() or step.get("kind") == "text": return
	revealed = true
	if step.kind == "targets":
		selected_targets.assign(step.targets)
	elif step.kind == "move":
		chosen_move = step.accepted[0]
		position = LessonRules.from_sfen(step.position)
		position.apply_unchecked(Codec.parse_move(step.accepted[0], position))
		for response in step.get("reply", []): position.apply_unchecked(Codec.parse_move(response, position))
	elif step.kind == "sequence":
		while cursor < step.moves.size():
			position.apply_unchecked(Codec.parse_move(step.moves[cursor], position))
			cursor += 1
	_finish()

func _finish() -> void:
	solved = true
	feedback = ("已查看答案。重新独立做对后才会记为掌握。" if revealed else "回答正确。") + "\n" + str(step.get("explanation", ""))
	if revealed and step.kind == "choice": feedback += "\n答案：" + str(step.options[int(step.answer)])

func mastered() -> bool:
	return solved and not revealed and mistakes == 0
