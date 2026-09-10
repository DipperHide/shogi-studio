class_name ShogiRules
extends RefCounted
## Pure position model. Positive pieces are sente; rows run from gote to sente.
## Promotion adds 8 to a piece type. UI, AI and replay share this rule source.

const PAWN = 1
const LANCE = 2
const KNIGHT = 3
const SILVER = 4
const GOLD = 5
const BISHOP = 6
const ROOK = 7
const KING = 8
const NAMES = ["", "歩", "香", "桂", "銀", "金", "角", "飛", "玉", "と", "成香", "成桂", "成銀", "", "馬", "龍"]
const GOLD_STEPS = [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,1)]
const KING_STEPS = [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]
const DIAGONALS = [Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
const ORTHOGONALS = [Vector2i(0,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(0,1)]

var board: Array[int] = []
var hands: Dictionary = {1: [0,0,0,0,0,0,0,0], -1: [0,0,0,0,0,0,0,0]}
var turn: int = 1

func _init(initial: bool = true) -> void:
	board.resize(81)
	board.fill(0)
	if initial:
		var back = [LANCE, KNIGHT, SILVER, GOLD, KING, GOLD, SILVER, KNIGHT, LANCE]
		for x in range(9):
			board[x] = -back[x]
			board[18+x] = -PAWN
			board[54+x] = PAWN
			board[72+x] = back[x]
		board[10] = -ROOK
		board[16] = -BISHOP
		board[64] = BISHOP
		board[70] = ROOK

func copy() -> ShogiRules:
	var result = ShogiRules.new(false)
	result.board = board.duplicate()
	result.hands = hands.duplicate(true)
	result.turn = turn
	return result

static func base(piece: int) -> int:
	var kind = absi(piece)
	return kind - 8 if kind > 8 else kind

static func in_zone(square: int, side: int) -> bool:
	return square < 27 if side == 1 else square >= 54

static func forced(kind: int, square: int, side: int) -> bool:
	var rank = square / 9 if side == 1 else 8 - square / 9
	return (kind in [PAWN, LANCE] and rank == 0) or (kind == KNIGHT and rank < 2)

func targets(square: int) -> Array[int]:
	var out: Array[int] = []
	var piece = board[square]
	if piece == 0:
		return out
	var side = signi(piece)
	var kind = absi(piece)
	var steps: Array = []
	var rays: Array = []
	match kind:
		PAWN: steps = [Vector2i(0,-1)]
		LANCE: rays = [Vector2i(0,-1)]
		KNIGHT: steps = [Vector2i(-1,-2), Vector2i(1,-2)]
		SILVER: steps = [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
		GOLD, 9, 10, 11, 12: steps = GOLD_STEPS
		BISHOP: rays = DIAGONALS
		ROOK: rays = ORTHOGONALS
		KING: steps = KING_STEPS
		14:
			rays = DIAGONALS
			steps = ORTHOGONALS
		15:
			rays = ORTHOGONALS
			steps = DIAGONALS
	var origin = Vector2i(square % 9, square / 9)
	for step in steps:
		var dest: Vector2i = origin + step * side
		if _inside(dest):
			out.append(dest.y * 9 + dest.x)
	for ray in rays:
		var dest: Vector2i = origin + ray * side
		while _inside(dest):
			var index = dest.y * 9 + dest.x
			out.append(index)
			if board[index] != 0:
				break
			dest += ray * side
	return out

static func _inside(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < 9 and p.y >= 0 and p.y < 9

func in_check(side: int) -> bool:
	var king = board.find(side * KING)
	if king == -1:
		return true
	for square in range(81):
		if board[square] * side < 0 and king in targets(square):
			return true
	return false

func is_legal_move(move: Dictionary) -> bool:
	# Validate one USI/PV move without generating every alternative on the board.
	# Keep the same king-safety and pawn-drop-mate rules as legal_moves().
	var dest: int = move.get("to", -1)
	var origin: int = move.get("from", -1)
	var drop: int = move.get("drop", 0)
	var promote: bool = move.get("promote", false)
	if dest < 0 or dest >= 81: return false
	if drop != 0:
		if drop < PAWN or drop > ROOK or origin != -1 or promote: return false
		if hands[turn][drop] <= 0 or board[dest] != 0 or forced(drop, dest, turn): return false
		if drop == PAWN:
			for row in range(9):
				if board[row * 9 + dest % 9] == turn * PAWN: return false
		var next = after(move)
		if next.in_check(turn): return false
		if drop == PAWN and dest - turn * 9 == next.board.find(-turn * KING):
			if next.legal_moves(true, true).is_empty(): return false
		return true
	if origin < 0 or origin >= 81 or board[origin] * turn <= 0: return false
	if board[dest] * turn > 0 or absi(board[dest]) == KING or dest not in targets(origin): return false
	var kind = absi(board[origin])
	if promote:
		if kind not in [PAWN, LANCE, KNIGHT, SILVER, BISHOP, ROOK]: return false
		if not in_zone(origin, turn) and not in_zone(dest, turn): return false
	elif forced(kind, dest, turn): return false
	return _safe(move)

func legal_moves(board_only: bool = false, first_only: bool = false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for square in range(81):
		if board[square] * turn <= 0:
			continue
		var kind = absi(board[square])
		for dest in targets(square):
			if board[dest] * turn > 0 or absi(board[dest]) == KING:
				continue
			var can_promote = kind in [PAWN,LANCE,KNIGHT,SILVER,BISHOP,ROOK] and (in_zone(square, turn) or in_zone(dest, turn))
			var choices = [true] if forced(kind, dest, turn) else ([false,true] if can_promote else [false])
			for promote in choices:
				var move = {"from": square, "to": dest, "drop": 0, "promote": promote}
				if _safe(move):
					out.append(move)
					if first_only:
						return out
	if board_only:
		return out
	for kind in range(1,8):
		if hands[turn][kind] == 0:
			continue
		for dest in range(81):
			if board[dest] != 0 or forced(kind, dest, turn):
				continue
			if kind == PAWN:
				var nifu = false
				for row in range(9):
					if board[row*9 + dest%9] == turn * PAWN:
						nifu = true
						break
				if nifu:
					continue
			var move = {"from": -1, "to": dest, "drop": kind, "promote": false}
			var next = after(move)
			if next.in_check(turn):
				continue
			# An adjacent pawn check can only be answered by moving/capturing on board;
			# no drop can interpose, so this exact test does not recurse into drop rules.
			if kind == PAWN and dest - turn * 9 == next.board.find(-turn * KING):
				if next.legal_moves(true, true).is_empty():
					continue
			out.append(move)
			if first_only:
				return out
	return out

func _safe(move: Dictionary) -> bool:
	return not after(move).in_check(turn)

func declaration_status(side: int) -> Dictionary:
	# CSA 27-point declaration: sente needs 28, gote 27. Only pieces in
	# the enemy camp and pieces in hand count; promoted majors remain 5.
	var king = board.find(side * KING)
	var count = 0
	var points = 0
	for square in range(81):
		if board[square] * side <= 0 or absi(board[square]) == KING or not in_zone(square, side):
			continue
		count += 1
		points += 5 if base(board[square]) in [BISHOP, ROOK] else 1
	for kind in range(1, 8):
		points += hands[side][kind] * (5 if kind in [BISHOP, ROOK] else 1)
	var threshold = 28 if side == 1 else 27
	var king_inside = king >= 0 and in_zone(king, side)
	var checked = in_check(side)
	return {"valid": side == turn and king_inside and not checked and count >= 10 and points >= threshold, "king_inside": king_inside, "in_check": checked, "pieces": count, "points": points, "threshold": threshold, "own_turn": side == turn}

func after(move: Dictionary) -> ShogiRules:
	var result = copy()
	result.apply_unchecked(move)
	return result

func apply_unchecked(move: Dictionary) -> void:
	# Internal only: callers must select from legal_moves().
	var dest: int = move.to
	if move.drop != 0:
		hands[turn][move.drop] -= 1
		board[dest] = turn * int(move.drop)
	else:
		if board[dest] != 0:
			hands[turn][base(board[dest])] += 1
		board[dest] = board[move.from] + (turn * 8 if move.promote else 0)
		board[move.from] = 0
	turn = -turn

func key() -> String:
	return str(board) + str(hands[1]) + str(hands[-1]) + str(turn)

func notation(move: Dictionary) -> String:
	var kind = move.drop if move.drop else absi(board[move.from])
	var ranks = ["一","二","三","四","五","六","七","八","九"]
	return ("☗ " if turn == 1 else "☖ ") + str(9 - int(move.to)%9) + ranks[int(move.to)/9] + NAMES[kind] + ("打" if move.drop else ("成" if move.promote else ""))
