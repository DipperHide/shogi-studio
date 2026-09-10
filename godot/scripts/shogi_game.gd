class_name ShogiGame
extends RefCounted

const Rules = preload("res://scripts/shogi_rules.gd")
const Clock = preload("res://scripts/shogi_clock.gd")
var clock = Clock.new()
var clock_authority: bool = true
var position = Rules.new()
var positions: Array = []
var moves: Array[Dictionary] = []
var labels: Array[String] = []
var mode: String = "ai"
var human_side: int = 1
var difficulty: int = 1
var engine_level: int = 2
var engine_provider: String = "yaneuraou"
var result: String = ""
var result_code: String = ""
var winner: int = 0
var resigned: bool = false
var resigned_side: int = 0
var agreed_draw: bool = false
var declared_side: int = 0
var initial_sfen: String = ""
var metadata: Dictionary = {}
var comments: Dictionary = {}
var annotations: Dictionary = {}
var engine_match: bool = false
var variation_tree
const MAX_SAVE_BYTES = 2097152

func initial_command() -> String:
	return "startpos" if initial_sfen.is_empty() else "sfen " + initial_sfen

func set_initial(value: String) -> bool:
	var parsed = preload("res://scripts/shogi_usi_codec.gd").parse_sfen(value)
	if parsed == null or not position_error(parsed).is_empty(): return false
	initial_sfen = preload("res://scripts/shogi_usi_codec.gd").sfen(parsed)
	position = parsed
	positions = [parsed.copy()]
	moves.clear()
	labels.clear()
	variation_tree = null
	return true

static func position_error(pos) -> String:
	if pos.board.count(8) != 1 or pos.board.count(-8) != 1: return "棋盘上必须各有一枚王和玉。"
	var counts = [0, 0, 0, 0, 0, 0, 0, 0, 0]
	for square in range(81):
		var piece: int = pos.board[square]
		if piece == 0: continue
		counts[Rules.base(piece)] += 1
		var rank: int = square / 9 if piece > 0 else 8 - square / 9
		if (absi(piece) in [1, 2] and rank == 0) or (absi(piece) == 3 and rank < 2): return "存在没有合法走法的未升变棋子。"
	for side in [1, -1]:
		for kind in range(1, 8): counts[kind] += pos.hands[side][kind]
		for file in range(9):
			var pawns = 0
			for rank in range(9):
				if pos.board[rank * 9 + file] == side: pawns += 1
			if pawns > 1: return "同一方在同一筋上不能有两枚未升变的步。"
	for kind in range(1, 9):
		if counts[kind] > [0, 18, 4, 4, 4, 4, 2, 2, 2][kind]: return "棋子总数超过标准将棋的数量。"
	if pos.in_check(-pos.turn): return "非行棋方的玉正在被将军，请检查行棋方或摆放。"
	return ""

func _init() -> void:
	positions = [position.copy()]

func play(move: Dictionary) -> bool:
	if clock_authority: clock.tick(clock.paused)
	if clock_authority and clock.expired_side != 0:
		update_result()
		return false
	if not result.is_empty() or move not in position.legal_moves():
		return false
	if variation_tree != null and variation_tree.append_main(move) < 0: return false
	labels.append(position.notation(move))
	moves.append(move.duplicate())
	position = position.after(move)
	clock.finish_turn(position.turn)
	positions.append(position.copy())
	update_result()
	return true

func update_result() -> void:
	result = ""
	result_code = ""
	winner = 0
	if resigned:
		result_code = "resign"
		winner = -resigned_side
		result = ("先手" if winner == 1 else "后手") + "获胜 · 投了"
		clock.paused = true
		return
	if clock.expired_side != 0:
		result_code = "timeout"
		winner = -clock.expired_side
		result = ("后手" if clock.expired_side == 1 else "先手") + "获胜 · 超时"
		clock.paused = true
		return
	if declared_side != 0:
		result_code = "declaration"
		winner = declared_side
		result = ("先手" if declared_side == 1 else "后手") + "获胜 · 入玉宣言"
		clock.paused = true
		return
	if agreed_draw:
		result_code = "draw"
		winner = 0
		result = "双方同意 · 和棋"
		clock.paused = true
		return
	if position.legal_moves(false, true).is_empty():
		result_code = "mate" if position.in_check(position.turn) else "no_moves"
		winner = -position.turn
		result = ("后手" if position.turn == 1 else "先手") + "获胜 · " + ("将死" if position.in_check(position.turn) else "无合法着手")
		clock.paused = true
		return
	var repeats: Array[int] = []
	var current_key = position.key()
	for i in range(positions.size()):
		if positions[i].key() == current_key:
			repeats.append(i)
	if repeats.size() < 4:
		return
	for side in [1,-1]:
		var continuous = true
		for i in range(repeats[-4]+1, positions.size()):
			if positions[i].turn == -side and not positions[i].in_check(-side):
				continuous = false
				break
		if continuous:
			result_code = "perpetual_check"
			winner = -side
			result = ("先手" if side == 1 else "后手") + "判负 · 连续王手千日手"
			clock.paused = true
			return
	result_code = "repetition"
	result = "千日手 · 本局和棋，请重新开局"
	clock.paused = true

func resign(side: int = 0) -> void:
	if clock_authority: clock.tick(clock.paused)
	if clock.expired_side != 0: update_result()
	if result.is_empty():
		resigned = true
		resigned_side = position.turn if side == 0 else side
		result_code = "resign"
		winner = -resigned_side
		result = ("后手" if resigned_side == 1 else "先手") + "获胜 · 投了"
		clock.paused = true

func undo() -> void:
	clock.expired_side = 0
	agreed_draw = false
	declared_side = 0
	if moves.is_empty():
		clock.finish_turn(position.turn)
		resigned = false
		resigned_side = 0
		update_result()
		return
	var count = 2 if mode == "ai" and position.turn == human_side and moves.size() >= 2 else 1
	for i in range(count):
		moves.pop_back()
		labels.pop_back()
		positions.pop_back()
	position = positions.back().copy()
	if variation_tree != null:
		variation_tree.main = variation_tree.main.slice(0, moves.size())
		variation_tree.cursor = variation_tree.main.back() if not variation_tree.main.is_empty() else 0
	for key in comments.keys():
		if str(key).is_valid_int() and int(key) > moves.size(): comments.erase(key)
	for key in annotations.keys():
		if str(key).is_valid_int() and int(key) > moves.size(): annotations.erase(key)
	clock.finish_turn(position.turn)
	resigned = false
	resigned_side = 0
	update_result()

func to_data() -> Dictionary:
	var data = {"version": 1, "mode": mode, "moves": moves, "resigned": resigned, "resigned_side": resigned_side, "agreed_draw": agreed_draw, "declared_side": declared_side, "clock": clock.to_data(), "human_side":human_side,"difficulty":difficulty,"engine_level":engine_level,"engine_provider":engine_provider, "initial_sfen": initial_sfen, "metadata": metadata, "comments": comments, "annotations": annotations, "engine_match": engine_match}
	if variation_tree != null:
		variation_tree.main_notes(comments, annotations)
		data["variations"] = variation_tree.to_data()
	return data

static func truncate_data(data: Dictionary, ply: int) -> void:
	data.moves = data.moves.slice(0, ply)
	if data.has("variations"):
		data.variations.main = data.variations.main.slice(0, ply)
		data.variations.cursor = data.variations.main.back() if not data.variations.main.is_empty() else 0

func declare_win(side: int) -> bool:
	if clock_authority: clock.tick(clock.paused)
	if clock.expired_side != 0: update_result()
	if not result.is_empty() or side not in [1, -1] or not position.declaration_status(side).valid:
		return false
	declared_side = side
	update_result()
	return true

static func from_data(data: Variant) -> ShogiGame:
	if not data is Dictionary or data.get("version") != 1 or data.get("mode") not in ["ai", "local"]:
		return null
	if not data.get("moves") is Array or data.moves.size() > 2000 or not data.get("resigned", false) is bool or not data.get("agreed_draw", false) is bool:
		return null
	var game = ShogiGame.new()
	game.mode = data.mode
	var initial = data.get("initial_sfen", "")
	if not initial is String or (not initial.is_empty() and not game.set_initial(initial)): return null
	for key in ["metadata", "comments", "annotations"]:
		if not data.get(key, {}) is Dictionary: return null
		game.set(key, data.get(key, {}).duplicate(true))
	if game.metadata.size() > 100 or game.comments.size() > 2001 or game.annotations.size() > 2001: return null
	for key in game.metadata:
		if not key is String or not game.metadata[key] is String or key.length() > 200 or game.metadata[key].length() > 1000: return null
	for key in game.comments:
		if not key is String or not key.is_valid_int() or int(key) < 0 or not game.comments[key] is String or game.comments[key].length() > 20000: return null
	for key in game.annotations:
		if not key is String or not key.is_valid_int() or int(key) < 0 or not game.annotations[key] is Array or game.annotations[key].size() > 64: return null
		for mark in game.annotations[key]:
			if not mark is Array or mark.size() != 2: return null
			for square in mark:
				if (not square is int and not square is float) or not is_finite(float(square)) or int(square) != square or square < 0 or square >= 81: return null
	if not data.get("engine_match", false) is bool: return null
	game.engine_match = data.get("engine_match", false)
	var level = data.get("engine_level", 2)
	if (not level is int and not level is float) or not is_finite(float(level)) or level != int(level) or int(level) < 0 or int(level) > 5:
		return null
	game.engine_level = int(level)
	if data.get("engine_provider", "yaneuraou") not in ["yaneuraou", "basic"]:
		return null
	game.engine_provider = data.get("engine_provider", "yaneuraou")
	for field in ["human_side","difficulty"]:
		var value = data.get(field,1)
		if not value is int and not value is float:
			return null
		if not is_finite(float(value)) or value != int(value):
			return null
		var allowed = [1,-1] if field == "human_side" else [0,1]
		if int(value) not in allowed:
			return null
		game.set(field,int(value))
	for raw in data.moves:
		if not raw is Dictionary or not raw.get("promote") is bool:
			return null
		for field in ["from", "to", "drop"]:
			if not raw.get(field) is float and not raw.get(field) is int:
				return null
			if raw[field] != int(raw[field]):
				return null
		var move = {"from": int(raw.from), "to": int(raw.to), "drop": int(raw.drop), "promote": raw.promote}
		if not game.play(move):
			return null
	if data.get("resigned", false):
		var side = data.get("resigned_side", game.position.turn)
		if (not side is int and not side is float) or not is_finite(float(side)) or side != int(side) or int(side) not in [1, -1]:
			return null
		game.resign(int(side))
	if data.get("agreed_draw", false):
		if not game.result.is_empty():
			return null
		game.agreed_draw = true
		game.update_result()
	var declaration = data.get("declared_side", 0)
	if declaration != 0:
		if (declaration != 1 and declaration != -1) or not game.declare_win(int(declaration)):
			return null
	if data.has("clock"):
		var restored_clock = Clock.from_data(data.clock)
		if restored_clock == null or restored_clock.turn != game.position.turn: return null
		if restored_clock.expired_side != 0:
			if not game.result.is_empty(): return null
			game.clock = restored_clock
			game.update_result()
		else:
			game.clock = restored_clock
		game.clock.paused = true
	if data.has("variations"):
		game.variation_tree = preload("res://scripts/shogi_variation_tree.gd").from_data(data.variations, game.positions[0], game.moves)
		if game.variation_tree == null: return null
		game.variation_tree.main_notes(game.comments, game.annotations)
	return game

func save_to(path: String) -> Error:
	var serialized = JSON.stringify(to_data())
	if serialized.to_utf8_buffer().size() > MAX_SAVE_BYTES: return ERR_INVALID_DATA
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(serialized)
	file.flush()
	var write_error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	if FileAccess.file_exists(path):
		var backup_error = DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK:
			return backup_error
	return DirAccess.rename_absolute(path + ".tmp", path)

static func load_from(path: String) -> ShogiGame:
	for candidate in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file = FileAccess.open(candidate, FileAccess.READ)
		if file == null or file.get_length() > MAX_SAVE_BYTES:
			continue
		var parser = JSON.new()
		if parser.parse(file.get_as_text()) != OK:
			continue
		var game = from_data(parser.data)
		if game != null:
			return game
	return null
