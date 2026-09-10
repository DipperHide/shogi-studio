extends RefCounted
## Owns an editable analysis record while the live match remains paused.
const Variations = preload("res://scripts/shogi_variation_tree.gd")
const Game = preload("res://scripts/shogi_game.gd")
var app
var active = false
var paused = false
var tree
var view
var current
var line_ids: Array = []
var metadata: Dictionary = {}
var original_moves: Array = []
var original_outcome: Dictionary = {}
var initial_sfen = ""
var context: Dictionary = {}
var record_path = ""
var title = "变化分析"
var dirty = false
var error = ""
var history: Array = []
var last_action = ""

func effective() -> bool:
	return active and not paused and view != null and current != null and app.review_game == view

func start(source, ply: int = -1, source_path: String = "") -> bool:
	if app.session != null or app._practice_active(): error = "请先结束联机或退出失误练习。"; return false
	if active and not stop(false): return false
	var next = Variations.from_game(source)
	if next == null: error = "棋谱的变化数据无法读取。"; return false
	context = {"game": app.review_game, "path": app.review_path, "ply": app.replay_index, "live": app.ui.live_enabled}
	tree = next
	initial_sfen = source.initial_sfen
	metadata = source.metadata.duplicate(true)
	original_moves = source.moves.duplicate(true)
	original_outcome = {"resigned": source.resigned, "resigned_side": source.resigned_side, "agreed_draw": source.agreed_draw,
		"declared_side": source.declared_side, "clock": source.clock.to_data()}
	if ply >= 0: tree.cursor = tree.main[mini(ply, tree.main.size()) - 1] if ply > 0 and not tree.main.is_empty() else 0
	history.clear()
	last_action = ""
	error = ""
	var reuse = source.variation_tree != null and not source_path.is_empty() and source_path.get_base_dir() == app.records.root
	record_path = source_path if reuse else ""
	title = "变化分析 · " + str(metadata.get("先手", "先手")) + " – " + str(metadata.get("后手", "后手"))
	if reuse:
		for record in app.records.list_all():
			if record.path == source_path: title = record.title
	active = true
	paused = false
	dirty = true
	if not save(): active = false; return false
	app.ui._board_keep()
	app.ui.live_enabled = not app.testing
	select(tree.cursor)
	return true

func game_for(ids: Array):
	var game = Game.new()
	game.mode = "local"
	game.initial_sfen = initial_sfen
	game.metadata = metadata.duplicate(true)
	game.engine_provider = app.engine_provider
	game.engine_level = app.engine_level
	game.positions = [tree.nodes[0].position.copy()]
	var all_ids = [0] + ids
	for ply in range(all_ids.size()):
		var node: Dictionary = tree.nodes[all_ids[ply]]
		if not node.comment.is_empty(): game.comments[str(ply)] = node.comment
		if not node.annotations.is_empty(): game.annotations[str(ply)] = node.annotations.duplicate(true)
		if ply == 0: continue
		game.labels.append(game.positions.back().notation(node.move))
		game.moves.append(node.move.duplicate())
		game.positions.append(node.position.copy())
	game.position = game.positions.back().copy()
	game.clock.finish_turn(game.position.turn)
	game.clock.paused = true
	game.update_result()
	return game

func document():
	var result = game_for(tree.main)
	if result.moves == original_moves:
		for field in ["resigned", "resigned_side", "agreed_draw", "declared_side"]: result.set(field, original_outcome[field])
		result.clock = Game.Clock.from_data(original_outcome.clock)
		result.clock.paused = true
		result.update_result()
	result.variation_tree = tree
	return result

func fork_at_cursor(ply: int = -1):
	var selected: int = tree.cursor
	if ply >= 0: selected = line_ids[mini(ply, line_ids.size()) - 1] if ply > 0 and not line_ids.is_empty() else 0
	var result = game_for(tree.path(selected))
	result.variation_tree = Variations.from_data(tree.to_data(), tree.nodes[0].position)
	# Serialization renumbers IDs; recover the matching selected move path.
	var id = 0
	var path: Array = []
	for move in result.moves:
		id = result.variation_tree.append(id, move)
		path.append(id)
	result.variation_tree.main = path
	result.variation_tree.cursor = id
	return result

func save() -> bool:
	if tree == null: return true
	var record = document()
	var success = false
	if record_path.is_empty():
		record_path = app.records.archive(record, title)
		success = not record_path.is_empty()
	else: success = app.records.write(record_path, record, title)
	error = "" if success else app.records.error
	dirty = not success
	return success

func remember(action: String) -> void:
	history.append({"tree": tree.to_data(), "metadata": metadata.duplicate(true), "action": action})
	if history.size() > 8: history.pop_front()
	last_action = action

func select(id: int, keep_line: bool = false) -> void:
	if not active or not tree.nodes.has(id): return
	var before: Array = app._view_tokens()
	if not keep_line or id not in [0] + line_ids: line_ids = tree.line_through(id)
	tree.cursor = id
	view = game_for(line_ids)
	current = game_for(tree.path(id))
	app._pause_search()
	app._clear_selection()
	app.review_game = view
	app.review_path = record_path
	app.replay_index = tree.nodes[id].depth
	app.ui.ribbon_key = ""
	app.ui.live_key = ""
	app.ui.live_details.clear()
	app.ui.arrows.clear()
	app.ui.clear_pv_rows()
	app.ui.report_board_active = false
	app.ui.report_inline.hide()
	app._refresh()
	app._present_transition(before, false)

func seek(ply: int) -> void:
	select(line_ids[clampi(ply, 1, line_ids.size()) - 1] if ply > 0 and not line_ids.is_empty() else 0, true)

func commit(move: Dictionary, confirmed: bool = false) -> bool:
	if not effective() or not current.result.is_empty() or not current.position.is_legal_move(move): return false
	var parent: int = tree.cursor
	var old_main: int = tree.main_next(parent)
	var existing = -1
	for child in tree.nodes[parent].children:
		if tree.nodes[child].move == move: existing = child
	var on_main = parent == 0 or parent in tree.main
	var alternative = (old_main >= 0 and existing != old_main) or not on_main
	if alternative and not confirmed and not app.preferences.studio.variation_policy_confirmed:
		app.ui.show_variation_policy(move, current.position.key(), parent)
		return false
	var replacing = alternative and app.preferences.studio.variation_policy == "replace"
	var extending = on_main and old_main < 0
	if existing >= 0 and not replacing and not extending:
		select(existing)
		return true
	remember("添加变化")
	var id: int = tree.append(parent, move)
	if id < 0:
		history.pop_back()
		error = tree.error
		return false
	if replacing:
		var next_path: Array = tree.path(id)
		for index in range(mini(next_path.size(), tree.main.size())):
			if next_path[index] != tree.main[index]:
				tree.remove(tree.main[index])
				break
		tree.promote(id)
		last_action = "替换主线"
	elif extending:
		tree.main = tree.path(id)
	select(id)
	dirty = true
	save()
	app._play_sound()
	return true

func promote(id: int) -> void:
	if not tree.nodes.has(id) or id == 0: return
	remember("提升为主线")
	tree.promote(id)
	select(id)
	dirty = true
	save()

func remove(id: int) -> void:
	if not tree.nodes.has(id) or id == 0: return
	remember("删除变化")
	tree.remove(id)
	select(tree.cursor)
	dirty = true
	save()

func undo() -> void:
	if history.is_empty(): return
	var snapshot: Dictionary = history.pop_back()
	tree = Variations.from_data(snapshot.tree, tree.nodes[0].position)
	metadata = snapshot.metadata.duplicate(true)
	last_action = ""
	select(tree.cursor)
	dirty = true
	save()

func persist_view() -> void:
	remember("修改注释与标记")
	metadata = view.metadata.duplicate(true)
	var ids = [0] + line_ids
	for ply in range(ids.size()):
		tree.nodes[ids[ply]].comment = str(view.comments.get(str(ply), ""))
		tree.nodes[ids[ply]].annotations = Variations.canonical_marks(view.annotations.get(str(ply), []))
	dirty = true
	save()

func resume() -> void:
	if not active: return
	if not app.ui.pv_context.is_empty(): app.ui.stop_pv(false)
	paused = false
	app.review_game = view
	app.replay_index = tree.nodes[tree.cursor].depth
	app.ui._board_keep()
	select(tree.cursor, true)

func stop(restore: bool = true) -> bool:
	if not active: return true
	if not save(): return false
	if not app.ui.pv_context.is_empty(): app.ui.stop_pv(false)
	active = false
	paused = false
	app._pause_search()
	if restore:
		app.ui.close()
		app.review_game = context.game
		app.review_path = context.path
		app.replay_index = context.ply
		app.ui.live_enabled = context.live
	app.ui.ribbon_key = ""
	app._refresh()
	return true
