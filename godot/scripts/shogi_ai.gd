extends RefCounted
## Modest offline opponent, iterative deepening negamax. Not a rated USI engine.
const Rules = preload("res://scripts/shogi_rules.gd")
const VALUES = [0,100,300,320,450,540,850,1050,20000,550,540,540,540,0,1100,1350]
var deadline: int
var nodes: int = 0
var expired: bool = false

func choose(position: ShogiRules, milliseconds: int = 900, max_depth: int = 3) -> Dictionary:
	nodes = 0
	expired = false
	deadline = Time.get_ticks_msec() + milliseconds
	var options = position.legal_moves()
	if options.is_empty():
		return {}
	_order(options, position)
	var best = options[0]
	var completed_depth = 0
	for depth in range(1,clampi(max_depth,1,3)+1):
		var candidate = best
		var alpha = -1000000
		for move in options:
			var score = -_search(position.after(move), depth-1, -1000000, -alpha, 1)
			if expired:
				break
			if score > alpha:
				alpha = score
				candidate = move
		if expired:
			break
		best = candidate
		completed_depth = depth
		options.erase(best)
		options.push_front(best)
	return {"move": best, "depth": completed_depth, "nodes": nodes}

func _search(p: ShogiRules, depth: int, alpha: int, beta: int, ply: int) -> int:
	nodes += 1
	if Time.get_ticks_msec() >= deadline:
		expired = true
		return 0
	if depth == 0:
		if p.legal_moves(false, true).is_empty():
			return -900000 + ply
		return _evaluate(p)
	var options = p.legal_moves()
	if options.is_empty():
		return -900000 + ply
	_order(options, p)
	for move in options:
		var score = -_search(p.after(move), depth-1, -beta, -alpha, ply+1)
		if expired:
			return 0
		alpha = maxi(alpha, score)
		if alpha >= beta:
			break
	return alpha

func _evaluate(p: ShogiRules) -> int:
	var score = 0
	for i in range(81):
		var piece = p.board[i]
		if piece == 0:
			continue
		var side = signi(piece)
		var advance = (8-i/9) if side == 1 else i/9
		var positional = advance * 4 + (4-absi(4-i%9))*3 if absi(piece) != Rules.KING else -advance*5
		score += side * (VALUES[absi(piece)] + positional)
	for kind in range(1,8):
		score += (p.hands[1][kind]-p.hands[-1][kind]) * VALUES[kind]
	return score * p.turn

func _order(options: Array[Dictionary], p: ShogiRules) -> void:
	options.sort_custom(func(a, b): return _priority(a,p) > _priority(b,p))

func _priority(move: Dictionary, p: ShogiRules) -> int:
	return VALUES[absi(p.board[move.to])] * 10 + (400 if move.promote else 0) - (VALUES[absi(p.board[move.from])] / 20 if move.from >= 0 else 0)
