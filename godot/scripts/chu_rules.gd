class_name ChuRules
extends RefCounted
const C = preload("res://scripts/chu_catalog.gd")
var board: Array[int] = []
var turn = 1
var immunity: Array[int] = []
var error = ""

func _init(initial: bool = true) -> void:
	board.resize(144); board.fill(0)
	if not initial: return
	var rows = [
		[C.LANCE,C.LEOPARD,C.COPPER,C.SILVER,C.GOLD,C.KING,C.ELEPHANT,C.GOLD,C.SILVER,C.COPPER,C.LEOPARD,C.LANCE],
		[C.REVERSE,0,C.BISHOP,0,C.TIGER,C.KIRIN,C.PHOENIX,C.TIGER,0,C.BISHOP,0,C.REVERSE],
		[C.SIDE,C.VERTICAL,C.ROOK,C.HORSE,C.DRAGON,C.LION,C.QUEEN,C.DRAGON,C.HORSE,C.ROOK,C.VERTICAL,C.SIDE],
		[C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN,C.PAWN],
		[0,0,0,C.GO_BETWEEN,0,0,0,0,C.GO_BETWEEN,0,0,0]]
	for y in range(5):
		for x in range(12):
			board[(11-y)*12+x] = rows[y][x]
			board[y*12+11-x] = -rows[y][x]

func copy() -> ChuRules:
	var p = ChuRules.new(false)
	p.board = board.duplicate(); p.turn = turn; p.immunity = immunity.duplicate()
	return p

func key() -> String: return str(board) + ":" + str(turn) + ":" + str(immunity)
func to_data() -> Dictionary: return {"board":board.duplicate(),"turn":turn,"immunity":immunity.duplicate()}
static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value)
static func from_data(data: Variant) -> ChuRules:
	if not data is Dictionary or not data.get("board") is Array or data.board.size() != 144 or not integer(data.get("turn")) or int(data.turn) not in [-1,1]: return null
	var p = ChuRules.new(false)
	for i in range(144):
		if not integer(data.board[i]) or not C.valid(int(data.board[i])): return null
		p.board[i] = int(data.board[i])
	p.turn = int(data.turn)
	if not data.get("immunity",[]) is Array: return null
	for value in data.get("immunity",[]):
		if not integer(value) or value < 0 or value >= 144 or int(value) in p.immunity: return null
		if C.kind(p.board[int(value)]) != C.LION or p.board[int(value)] * p.turn >= 0: return null
		p.immunity.append(int(value))
	p.immunity.sort()
	return p

func royals(side: int) -> Array:
	return range(144).filter(func(i): return board[i]*side > 0 and C.kind(board[i]) in [C.KING,C.PRINCE])

func paths(origin: int) -> Array:
	var out: Array = []
	if origin < 0 or origin >= 144 or board[origin]*turn <= 0: return out
	var kind = C.kind(board[origin]); var motion = C.motion(kind)
	var xy = Vector2i(origin%12,origin/12)
	for vector in motion.steps + motion.jumps + motion.twice + motion.twice.map(func(v): return v*2):
		var dest: Vector2i = xy + vector*turn
		if C.inside(dest) and board[dest.y*12+dest.x]*turn <= 0:
			var path = [dest.y*12+dest.x]
			if path not in out: out.append(path)
	for vector in motion.rays:
		var dest: Vector2i = xy + vector*turn
		while C.inside(dest):
			var index = dest.y*12+dest.x
			if board[index]*turn <= 0 and [index] not in out: out.append([index])
			if board[index] != 0: break
			dest += vector*turn
	for vector in motion.twice:
		var via: Vector2i = xy + vector*turn
		if not C.inside(via) or board[via.y*12+via.x]*turn > 0: continue
		var seconds: Array = C.KING_STEPS if kind == C.LION else [vector,-vector]
		for next in seconds:
			var dest: Vector2i = via + next*turn
			if not C.inside(dest): continue
			var target = dest.y*12+dest.x
			if target != origin and board[target]*turn > 0: continue
			out.append([via.y*12+via.x,target])
	return out

func captures(origin: int, path: Array) -> Array:
	var found: Array = []
	for square in path:
		if square != origin and board[square]*board[origin] < 0 and square not in found: found.append(square)
	return found

func can_promote(origin: int, path: Array) -> bool:
	var piece = board[origin]
	if C.promoted(piece) or not C.PROMOTES.has(C.base(piece)): return false
	var end: int = path.back()
	if not C.zone(origin,turn) and C.zone(end,turn): return true
	if not captures(origin,path).is_empty() and (C.zone(origin,turn) or C.zone(end,turn)): return true
	return C.base(piece) in [C.PAWN,C.LANCE] and (end/12 == 0 if turn == 1 else end/12 == 11)

func attacks(origin: int, square: int) -> bool:
	if origin == square or board[origin] == 0: return false
	var side = signi(board[origin]); var motion = C.motion(C.kind(board[origin]))
	var xy = Vector2i(origin%12,origin/12); var target = Vector2i(square%12,square/12)
	var delta = (target-xy)*side
	if delta in motion.steps or delta in motion.jumps or delta in motion.twice or delta in motion.twice.map(func(v): return v*2): return true
	for ray in motion.rays:
		var dest: Vector2i = xy + ray*side
		while C.inside(dest):
			if dest == target: return true
			if board[dest.y*12+dest.x] != 0: break
			dest += ray*side
	return false

func threatened(square: int, side: int) -> bool:
	for i in range(144):
		if board[i]*side > 0 and attacks(i,square): return true
	return false

func lion_allowed(origin: int, path: Array) -> bool:
	var taken = captures(origin,path)
	var lion = C.kind(board[origin]) == C.LION
	for target in taken:
		if C.kind(board[target]) != C.LION: continue
		# Foot and adjacency are evaluated for the whole move, never after the
		# first leg. Removing a pawn/go-between defender is not tsukegui.
		var tsukegui: bool = lion and path.size() == 2 and target == path[1] and path[0] in taken and C.kind(board[path[0]]) not in [C.PAWN,C.GO_BETWEEN]
		if target in immunity and not tsukegui: return false
		if lion and C.distance(origin,target) == 2 and not tsukegui:
			var test = copy(); test.board[origin] = 0
			if test.threatened(target,-turn): return false
	return true

func legal_moves(origin: int = -1) -> Array:
	var out: Array = []
	for square in (range(144) if origin < 0 else [origin]):
		for path in paths(square):
			if not lion_allowed(square,path): continue
			out.append({"from":square,"path":path,"promote":false})
			if can_promote(square,path): out.append({"from":square,"path":path,"promote":true})
	return out

func valid_move(move: Variant) -> bool:
	error = "非法着手"
	if not move is Dictionary or move.size() != 3 or not integer(move.get("from")) or not move.get("path") is Array or not move.get("promote") is bool: return false
	var origin = int(move.from)
	if origin < 0 or origin >= 144 or move.path.size() not in [1,2] or board[origin]*turn <= 0: return false
	for square in move.path:
		if not integer(square) or square < 0 or square >= 144: return false
	var path = move.path.map(func(v): return int(v))
	if path not in paths(origin): return false
	if move.promote and not can_promote(origin,path): error = "这一步不能升变"; return false
	if not lion_allowed(origin,path): error = "这一步违反狮子交换规则"; return false
	error = ""; return true

func after(move: Dictionary) -> ChuRules:
	var next = copy(); var origin = int(move.from); var piece = board[origin]
	var ate_lion = captures(origin,move.path).any(func(i): return C.kind(board[i]) == C.LION)
	next.board[origin] = 0
	for square in move.path: next.board[int(square)] = 0
	next.board[int(move.path.back())] = piece + 32*turn if move.promote else piece
	next.immunity.clear()
	if ate_lion and C.kind(piece) != C.LION:
		for i in range(144):
			if next.board[i]*turn > 0 and C.kind(next.board[i]) == C.LION and next.threatened(i,turn): next.immunity.append(i)
	next.turn = -turn
	return next

func notation(move: Dictionary) -> String:
	var parts = PackedStringArray()
	for square in move.path: parts.append(C.square(int(square)))
	return ("▲" if turn == 1 else "△") + C.NAMES[C.kind(board[int(move.from)])] + " " + C.square(int(move.from)) + "→" + "→".join(parts) + ("成" if move.promote else "不成" if can_promote(int(move.from),move.path) else "")
