class_name ChuGame
extends RefCounted
const Rules = preload("res://scripts/chu_rules.gd")
const C = preload("res://scripts/chu_catalog.gd")
const Clock = preload("res://scripts/shogi_clock.gd")
const MAX_SAVE_BYTES = 2097152
const MAX_MOVES = 10000
var variant = "chu"
var mode = "local"
var human_side = 1
var position = Rules.new()
var positions: Array = []
var moves: Array = []
var labels: Array = []
var keys: Array = []
var clock = Clock.new()
var clock_authority = true
var metadata: Dictionary = {}
var comments: Dictionary = {}
var annotations: Dictionary = {}
var result = ""
var result_code = ""
var winner = 0
var resigned_side = 0
var agreed_draw = false
var error = ""

func _init() -> void:
	positions = [position.copy()]; keys = [position.key()]

static func position_error(p) -> String:
	if p == null: return "局面数据无效。"
	var counts: Dictionary = {}
	for piece in p.board:
		if piece == 0: continue
		var identity = signi(piece)*C.base(piece)
		counts[identity] = counts.get(identity,0)+1
	for side in [1,-1]:
		if p.royals(side).is_empty(): return "双方至少各有一枚玉将或太子。"
		for base in range(1,22):
			var limit = 12 if base == C.PAWN else 1 if base in [C.KING,C.ELEPHANT,C.KIRIN,C.PHOENIX,C.LION,C.QUEEN] else 2
			if counts.get(side*base,0) > limit: return "某种棋子的原始数量超过中将棋上限。"
	return ""

func set_initial(p) -> bool:
	error = position_error(p)
	if not error.is_empty() or not p.immunity.is_empty(): return false
	position = p.copy(); positions = [position.copy()]; keys = [position.key()]
	moves.clear(); labels.clear(); comments.clear(); annotations.clear()
	resigned_side = 0; agreed_draw = false; clock.finish_turn(position.turn)
	update_result()
	return true

func state_key() -> String:
	# History is part of the state: equal boards need not have equal repetition rights.
	return (JSON.stringify(positions[0].to_data()) + JSON.stringify(moves) + str(resigned_side) + str(agreed_draw)).sha256_text()

func fork() -> ChuGame:
	var g = ChuGame.new()
	g.position = position.copy(); g.positions = positions.duplicate(); g.keys = keys.duplicate()
	g.moves = moves.duplicate(true); g.labels = labels.duplicate(); g.metadata = metadata.duplicate(true); g.comments = comments.duplicate(true)
	g.clock = Clock.from_data(clock.to_data()); g.clock_authority = clock_authority
	g.result = result; g.result_code = result_code; g.winner = winner; g.resigned_side = resigned_side; g.agreed_draw = agreed_draw
	return g

func _attacking(p, side: int, royal_only: bool) -> bool:
	for i in range(144):
		if p.board[i]*side >= 0 or (royal_only and C.kind(p.board[i]) not in [C.KING,C.PRINCE]): continue
		if p.threatened(i,side): return true
	return false

func repetition_responsibility(start: int, end: int) -> int:
	var all_check = {1:true,-1:true}; var any_attack = {1:false,-1:false}
	var all_pass = true
	for i in range(start,end):
		var side: int = positions[i].turn
		all_check[side] = all_check[side] and _attacking(positions[i+1],side,true)
		any_attack[side] = any_attack[side] or _attacking(positions[i+1],side,false)
		all_pass = all_pass and moves[i].path.back() == moves[i].from and positions[i].captures(moves[i].from,moves[i].path).is_empty()
	if all_pass: return positions[start].turn
	if all_check[1] != all_check[-1]: return 1 if all_check[1] else -1
	if any_attack[1] != any_attack[-1]: return 1 if any_attack[1] else -1
	return positions[end].turn

func repetition_error(move: Dictionary) -> String:
	# Before a fourth cycle, the responsible player must choose a different
	# resulting position. Different paths for the same pass do not evade this.
	if moves.size() >= 2 and int(move.path.back()) == int(move.from) and position.captures(move.from,move.path).is_empty():
		var passes = true
		for i in range(moves.size()-2,moves.size()):
			passes = passes and int(moves[i].path.back()) == int(moves[i].from) and positions[i].captures(moves[i].from,moves[i].path).is_empty()
		if passes: return "双方连续往返后，先往返的一方必须变着。"
	var repeated: Array = []
	for i in range(keys.size()):
		if keys[i] == keys.back(): repeated.append(i)
	if repeated.size() < 3: return ""
	var previous: int = repeated[-2]
	if repetition_responsibility(previous,moves.size()) == position.turn and position.after(move).key() == keys[previous+1]:
		return "重复局面：本方负有变着责任，请选择其他着手。"
	return ""

func valid_move(move: Variant) -> bool:
	error = "对局已结束" if not result.is_empty() else ""
	if not error.is_empty(): return false
	if not position.valid_move(move): error = position.error; return false
	error = repetition_error(move)
	return error.is_empty()

func play(move: Dictionary) -> bool:
	if clock_authority:
		clock.tick(clock.paused)
		if clock.expired_side != 0: update_result(); return false
	if moves.size() >= MAX_MOVES or not valid_move(move): return false
	var canonical = {"from":int(move.from),"path":move.path.map(func(v): return int(v)),"promote":bool(move.promote)}
	labels.append(position.notation(canonical)); moves.append(canonical)
	position = position.after(canonical); positions.append(position.copy()); keys.append(position.key())
	clock.finish_turn(position.turn); update_result()
	return true

func _can_capture_royals(p, victim: int) -> bool:
	var royals = p.royals(victim)
	if royals.is_empty(): return true
	var attack = p.copy(); attack.turn = -victim
	for i in range(144):
		if attack.board[i]*victim >= 0: continue
		if not royals.any(func(square): return attack.attacks(i,square)): continue
		for path in attack.paths(i):
			if royals.all(func(square): return square in path) and attack.lion_allowed(i,path): return true
	return false

func _dead(piece: int, square: int) -> bool:
	return not C.promoted(piece) and C.base(piece) in [C.PAWN,C.LANCE] and (square < 12 if piece > 0 else square >= 132)

func _bare_winner() -> int:
	var material: Array = []
	for i in range(144):
		if position.board[i] != 0 and not _dead(position.board[i],i): material.append(i)
	if material.size() != 3: return 0
	var extras = material.filter(func(i): return C.kind(position.board[i]) not in [C.KING,C.PRINCE])
	if not extras.is_empty() and C.kind(position.board[extras[0]]) in [C.PAWN,C.GO_BETWEEN]: return 0
	var side = 1 if material.filter(func(i): return position.board[i] > 0).size() == 2 else -1
	if position.turn == -side:
		for move in position.legal_moves():
			if not position.captures(move.from,move.path).is_empty(): return 0
	return side

func update_result() -> void:
	result = ""; result_code = ""; winner = 0
	if resigned_side != 0: result_code = "resign"; winner = -resigned_side
	elif agreed_draw: result_code = "draw"
	elif clock.expired_side != 0: result_code = "timeout"; winner = -clock.expired_side
	elif position.royals(position.turn).is_empty(): result_code = "royal_capture"; winner = -position.turn
	elif position.royals(-position.turn).is_empty(): result_code = "royal_capture"; winner = position.turn
	else:
		winner = _bare_winner()
		if winner != 0: result_code = "bare_king"
		elif _can_capture_royals(position,position.turn):
			var escape = false
			for move in position.legal_moves():
				var after = position.after(move)
				if after.royals(-position.turn).is_empty() or not _can_capture_royals(after,position.turn): escape = true; break
			if not escape: result_code = "mate"; winner = -position.turn
	if not result_code.is_empty():
		var names = {"resign":"认输","draw":"双方同意和棋","timeout":"超时","royal_capture":"王与太子均被吃","bare_king":"残局胜利","mate":"将死"}
		result = ("先手获胜 · " if winner == 1 else "后手获胜 · " if winner == -1 else "") + names[result_code]
		clock.paused = true

func resign(side: int = 0) -> void:
	if result.is_empty(): resigned_side = position.turn if side == 0 else side; update_result()

func undo() -> void:
	if not moves.is_empty(): moves.pop_back(); labels.pop_back(); positions.pop_back(); keys.pop_back()
	position = positions.back().copy(); resigned_side = 0; agreed_draw = false
	clock.expired_side = 0; clock.finish_turn(position.turn)
	for key in comments.keys():
		if int(key) > moves.size(): comments.erase(key)
	update_result()

func to_data() -> Dictionary:
	return {"version":1,"variant":"chu","rules_id":C.RULES_ID,"mode":"local","initial":positions[0].to_data(),"moves":moves.duplicate(true),"clock":clock.to_data(),"resigned_side":resigned_side,"agreed_draw":agreed_draw,"metadata":metadata.duplicate(true),"comments":comments.duplicate(true)}

static func from_data(data: Variant) -> ChuGame:
	if not data is Dictionary or data.get("version") != 1 or data.get("variant") != "chu" or data.get("rules_id") != C.RULES_ID or data.get("mode") != "local": return null
	if not data.get("moves") is Array or data.moves.size() > MAX_MOVES or not data.get("agreed_draw",false) is bool: return null
	if not Rules.integer(data.get("resigned_side",0)) or int(data.get("resigned_side",0)) not in [-1,0,1]: return null
	var g = ChuGame.new()
	if not g.set_initial(Rules.from_data(data.get("initial"))): return null
	for move in data.moves:
		if not move is Dictionary or not g.play(move): return null
	for field in ["metadata","comments"]:
		var values = data.get(field,{})
		if not values is Dictionary or values.size() > (100 if field == "metadata" else MAX_MOVES+1): return null
		for key in values:
			if not key is String or not values[key] is String or key.length() > 200 or values[key].length() > (1000 if field == "metadata" else 20000): return null
			if field == "comments" and (not key.is_valid_int() or int(key) < 0 or int(key) > g.moves.size()): return null
		g.set(field,values.duplicate(true))
	if data.get("resigned_side",0) != 0:
		if not g.result.is_empty(): return null
		g.resign(int(data.resigned_side))
	if data.get("agreed_draw",false):
		if not g.result.is_empty(): return null
		g.agreed_draw = true; g.update_result()
	var saved_clock = Clock.from_data(data.get("clock"))
	if saved_clock == null or saved_clock.turn != g.position.turn or (saved_clock.expired_side != 0 and not g.result.is_empty()): return null
	g.clock = saved_clock; g.clock.paused = true; g.update_result()
	return g

func save_to(path: String) -> Error:
	var text = JSON.stringify(to_data())
	if text.to_utf8_buffer().size() > MAX_SAVE_BYTES: return ERR_INVALID_DATA
	var file = FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text); file.flush(); var code = file.get_error(); file.close()
	if code != OK: return code
	if FileAccess.file_exists(path):
		code = DirAccess.copy_absolute(path,path+".bak")
		if code != OK: return code
	return DirAccess.rename_absolute(path+".tmp",path)

static func load_from(path: String) -> ChuGame:
	for candidate in [path,path+".bak"]:
		var file = FileAccess.open(candidate,FileAccess.READ)
		if file != null and file.get_length() <= MAX_SAVE_BYTES:
			var g = from_data(JSON.parse_string(file.get_as_text()))
			if g != null: return g
	return null
