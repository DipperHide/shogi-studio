extends RefCounted
## Independent report exercises: the live game is never replaced or saved as a puzzle.
const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var app
var active: bool = false
var stage: String = ""
var source
var exercise
var entries: Array = []
var index: int = 0
var hint_level: int = 0
var message: String = ""
var error: String = ""
var context: Dictionary = {}
var results: Dictionary = {}
var assisted: bool = false
var revealed_answer: bool = false
var mistakes: int = 0
var delay: float = 0.0
var preview_playing: bool = false
var preview_return: String = ""
var pending_action: String = ""
var options = {"side": 0, "categories": ["漏着", "错失胜机", "失误"], "skip_tried": true}

func initialize(owner_app) -> void:
	app = owner_app

func progress():
	app.ui.tutorial._ensure_loaded()
	return app.ui.tutorial.progress

static func fingerprint(game, ply: int, best: String) -> String:
	var sequence = PackedStringArray()
	for move in game.moves.slice(0, ply - 1): sequence.append(Codec.move_name(move))
	return (game.initial_command() + " moves " + " ".join(sequence) + " | " + best).sha256_text()

func eligible(report, settings: Dictionary) -> Array:
	var found: Array = []
	if report.game == null: return found
	var history = progress()
	for row in report.rows:
		if int(settings.side) != 0 and row.side != int(settings.side): continue
		if row.category not in settings.categories: continue
		var ply = int(row.ply)
		if ply < 1 or ply >= report.game.positions.size() or ply - 1 >= report.samples.size(): continue
		var position = report.game.positions[ply - 1]
		var move = Codec.parse_move(str(row.get("best", "")), position)
		if move.is_empty() or move not in position.legal_moves(): continue
		var key = fingerprint(report.game, ply, Codec.move_name(move))
		var old: Dictionary = history.state("mistakes", key, 0, key)
		if settings.skip_tried and (old.get("attempts", 0) > 0 or old.get("mistakes", 0) > 0): continue
		var line: Array = []
		for item in report.samples[ply - 1].get("pv", []):
			var next = Codec.parse_move(str(item), position)
			if next.is_empty() or next not in position.legal_moves(): break
			line.append(str(item))
			position = position.after(next)
			if line.size() >= 32: break
		if line.is_empty() or line[0] != Codec.move_name(move): line = [Codec.move_name(move)]
		found.append({"ply": ply, "side": int(row.side), "category": row.category, "label": row.label,
			"best": move, "pv": line, "key": key, "sfen": Codec.sfen(report.game.positions[ply - 1])})
	return found

func start(report, settings: Dictionary) -> bool:
	if app.session != null: error = "请结束联机对局后再练习。"; return false
	var selected = eligible(report, settings)
	if selected.is_empty(): error = "没有符合筛选条件且已有最佳线路的着手。"; return false
	if active: stop(false)
	if not app.ui.pv_context.is_empty(): app.ui.stop_pv(false)
	context = {"review": app.review_game, "path": app.review_path, "ply": app.replay_index,
		"flipped": app.flipped, "live": app.ui.live_enabled, "report": app.ui.retry_from_report, "autoplay": app.ui.autoplay_on}
	source = Game.from_data(report.game.to_data())
	if source == null: context.clear(); error = "原棋谱无法读取。"; return false
	options = settings.duplicate(true)
	entries = selected
	results.clear()
	index = 0
	error = ""
	app.ui._board_keep()
	app._pause_search()
	app.ui.live_enabled = false
	app.ui.autoplay_on = false
	app.ui.clear_pv_rows()
	app.ui.arrows.clear()
	active = true
	load_entry()
	return true

func can_answer() -> bool:
	return active and stage == "answer" and exercise != null

func entry() -> Dictionary:
	return entries[index] if index >= 0 and index < entries.size() else {}

func new_exercise():
	var game = Game.new()
	if not game.set_initial(entry().sfen): return null
	game.mode = "local"
	game.metadata = source.metadata.duplicate()
	if not game.metadata.has("先手"): game.metadata["先手"] = "先手"
	if not game.metadata.has("后手"): game.metadata["后手"] = "后手"
	return game

func load_entry() -> void:
	if index >= entries.size():
		stage = "complete"
		preview_playing = false
		message = "本轮练习结束"
		update()
		return
	exercise = new_exercise()
	stage = "answer"
	hint_level = 0
	mistakes = 0
	assisted = false
	revealed_answer = false
	pending_action = ""
	delay = 0
	preview_playing = false
	message = "请为%s找出最佳着。" % ("先手" if entry().side == 1 else "后手")
	app._cancel_motion()
	app._clear_selection()
	app.review_game = exercise
	app.review_path = ""
	app.replay_index = -1
	app.flipped = entry().side == -1
	app._refresh()
	update()

func update() -> void:
	app.ui.update_practice()
	app._redraw()

func submit(move: Dictionary) -> void:
	if not can_answer() or app.motion_progress < 1 or move not in exercise.position.legal_moves(): return
	var correct = Codec.move_name(move) == Codec.move_name(entry().best)
	var before: Array = app._view_tokens()
	var visual_start = {}
	if app.wood_view != null and app.pointer_moved and is_instance_valid(app.wood_view.dragged_node):
		for id in range(before.size()):
			if before[id].square == move.from and move.from >= 0: visual_start[id] = app.wood_view.dragged_node.position
	if not exercise.play(move): return
	app._clear_selection()
	app.revision += 1
	if correct:
		stage = "solved"
		message = "正确！" + exercise.labels[0]
		results[index] = "assisted" if assisted or mistakes > 0 else "solved"
		progress().record("mistakes", entry().key, 0, not assisted and mistakes == 0, 0, revealed_answer, entry().key)
	else:
		stage = "wrong"
		mistakes += 1
		message = "这不是报告中的最佳着，再试一次。"
		progress().note_mistake("mistakes", entry().key, 0, entry().key)
		delay = maxf(0.8, app.preferences.studio.animation + 0.4)
	check_save()
	app._refresh()
	app._present_transition(before, true, visual_start)
	update()

func check_save() -> void:
	error = progress().error

func reset_position() -> void:
	var before: Array = app._view_tokens()
	exercise = new_exercise()
	app.review_game = exercise
	app.replay_index = -1
	app._clear_selection()
	app._refresh()
	app._present_transition(before, false)

func hint() -> void:
	if not can_answer() or app.motion_progress < 1: return
	assisted = true
	hint_level = mini(2, hint_level + 1)
	var move: Dictionary = entry().best
	if hint_level == 1:
		var kind = move.drop if move.drop > 0 else absi(exercise.position.board[move.from])
		message = ("考虑打入%s；再点提示查看落点。" if move.drop > 0 else "考虑移动这枚%s；再点提示查看完整着手。") % app.GLYPHS[kind]
	else:
		var hint = preload("res://scripts/shogi_move_hint.gd")
		var decision = hint.choice(exercise.position, move)
		message = "建议：" + hint.notation(exercise.position, move) + (" · " + app.t(decision) if not decision.is_empty() else "")
	update()

func reveal() -> void:
	if not can_answer() or app.motion_progress < 1: return
	assisted = true
	hint_level = 2
	revealed_answer = true
	var before: Array = app._view_tokens()
	if not exercise.play(entry().best): return
	stage = "revealed"
	message = "答案：" + exercise.labels[0]
	results[index] = "revealed"
	progress().record("mistakes", entry().key, 0, false, 0, true, entry().key)
	check_save()
	app._clear_selection()
	app._refresh()
	app._present_transition(before, false)
	update()

func retry() -> void:
	if not active or stage in ["complete", "wrong"]: return
	if app.motion_progress < 1: pending_action = "retry"; return
	preview_playing = false
	stage = "answer"
	hint_level = 0
	message = "重新寻找最佳着。"
	reset_position()
	update()

func next() -> void:
	if not active or stage in ["wrong", "complete"]: return
	if app.motion_progress < 1: pending_action = "next"; return
	if not results.has(index): results[index] = "skipped"
	index += 1
	load_entry()

func show_line() -> void:
	if not active or stage not in ["solved", "revealed"]: return
	if app.motion_progress < 1: pending_action = "show_line"; return
	var line = new_exercise()
	for value in entry().pv:
		var move = Codec.parse_move(value, line.position)
		if move.is_empty() or not line.play(move): break
	if line.moves.is_empty(): return
	preview_return = stage
	stage = "preview"
	preview_playing = true
	delay = 0.5
	message = "答案线路 · 可逐手回放"
	var before: Array = app._view_tokens()
	app.review_game = line
	app.replay_index = 0
	app._refresh()
	app._present_transition(before, false)
	update()

func seek(delta: int) -> void:
	if stage != "preview" or app.motion_progress < 1: return
	app._set_replay(clampi(app.replay_index + delta, 0, app.review_game.moves.size()))
	delay = maxf(0.5, app.preferences.studio.autoplay)
	update()

func end_preview() -> void:
	if stage != "preview": return
	if app.motion_progress < 1: pending_action = "end_preview"; return
	var before: Array = app._view_tokens()
	preview_playing = false
	stage = preview_return
	message = "正确！" + exercise.labels[0] if stage == "solved" else "答案：" + exercise.labels[0]
	app.review_game = exercise
	app.replay_index = -1
	app._refresh()
	app._present_transition(before, false)
	update()

func tick(delta: float) -> void:
	if not active or not app.active or app.ui.page != null: return
	if not pending_action.is_empty() and app.motion_progress >= 1:
		var action = pending_action
		pending_action = ""
		call(action)
		return
	if stage == "wrong":
		delay -= delta
		if delay <= 0 and app.motion_progress >= 1:
			stage = "answer"
			reset_position()
			update()
	elif stage == "preview" and preview_playing and app.motion_progress >= 1:
		delay -= delta
		if delay <= 0:
			if app.replay_index < app.review_game.moves.size(): seek(1)
			else: preview_playing = false; update()

func stop(return_report: bool = true) -> void:
	if not active: return
	active = false
	stage = ""
	preview_playing = false
	pending_action = ""
	app._pause_search()
	app._cancel_motion()
	app._clear_selection()
	app.review_game = context.review
	app.review_path = context.path
	app.replay_index = context.ply
	app.flipped = context.flipped
	app.ui.live_enabled = context.live
	app.ui.autoplay_on = context.autoplay
	app.ui.live_key = ""
	app.ui.ribbon_key = ""
	var show_report: bool = context.report
	context.clear()
	app._refresh()
	app.ui.update_practice()
	app.ui.update_inline_report()
	if return_report and show_report: app.ui.show_report()

func totals() -> Dictionary:
	var summary = {"solved": 0, "assisted": 0, "revealed": 0, "skipped": 0}
	for value in results.values(): summary[value] += 1
	return summary
