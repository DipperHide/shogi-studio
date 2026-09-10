extends RefCounted
## Bounded local exchange analysis using shogi legality, promotions and hand values.
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const VALUES = preload("res://scripts/shogi_ai.gd").VALUES
const MAX_EXCHANGES = 6

static func capture_value(piece: int) -> int:
	var kind = absi(piece)
	if kind in [0, 8]: return 0
	return VALUES[kind] + VALUES[kind - 8 if kind > 8 else kind]

static func gain(position, move: Dictionary) -> int:
	var value = capture_value(position.board[move.to])
	if move.promote: value += VALUES[absi(position.board[move.from]) + 8] - VALUES[absi(position.board[move.from])]
	return value

static func reply_gain(position, square: int, depth: int = MAX_EXCHANGES) -> int:
	if depth <= 0: return 0
	var best = 0
	# Drops cannot capture an occupied square, so the board-only generator suffices.
	for move in captures_to(position, square):
		best = maxi(best, gain(position, move) - reply_gain(position.after(move), square, depth - 1))
	return best

static func captures_to(position, square: int) -> Array:
	var moves: Array = []
	if position.board[square] * position.turn >= 0 or absi(position.board[square]) == 8: return moves
	for origin in range(81):
		if position.board[origin] * position.turn <= 0 or square not in position.targets(origin): continue
		var kind = absi(position.board[origin])
		var promote: bool = kind in [1, 2, 3, 4, 6, 7] and (position.in_zone(origin, position.turn) or position.in_zone(square, position.turn))
		var choices = [true] if position.forced(kind, square, position.turn) else [false, true] if promote else [false]
		for choice in choices:
			var move = {"from": origin, "to": square, "drop": 0, "promote": choice}
			if position._safe(move): moves.append(move)
	return moves

static func exchange(position, move: Dictionary) -> int:
	return gain(position, move) - reply_gain(position.after(move), move.to)

static func hanging(position, side: int) -> Dictionary:
	var enemy = position.copy()
	enemy.turn = -side
	var risks = {}
	for move in enemy.legal_moves(true):
		var piece: int = enemy.board[move.to]
		if piece * side <= 0 or absi(piece) in [1, 8]: continue
		var net = exchange(enemy, move)
		if net > 0: risks[move.to] = maxi(int(risks.get(move.to, 0)), net)
	return risks

static func candidate(game, ply: int) -> Dictionary:
	var result = {"candidate": false, "sacrifice": false, "new_risk": 0, "fork_targets": [], "reason": "普通最佳着"}
	if ply < 3: return result
	var before = game.positions[ply - 1]
	var after = game.positions[ply]
	var move: Dictionary = game.moves[ply - 1]
	var earlier = game.positions[ply - 2]
	var old_risks = hanging(earlier, before.turn)
	var new_risks = hanging(after, before.turn)
	var captured = capture_value(before.board[move.to])
	for square in new_risks:
		if old_risks.has(square): continue
		if square == move.to and move.from >= 0 and old_risks.has(move.from): continue
		result.new_risk = maxi(result.new_risk, int(new_risks[square]))
	result.sacrifice = result.new_risk > captured + 100 and absi(after.board[move.to]) != 1
	var previous: Dictionary = game.moves[ply - 2]
	var recapture: bool = previous.to == move.to and before.board[move.to] != 0
	var free_capture: bool = captured > 0 and exchange(before, move) >= captured
	# A newly created multiple attack can be hard to find even without a sacrifice.
	for square in after.targets(move.to):
		var piece: int = after.board[square]
		if piece * before.turn < 0 and absi(piece) != 1:
			if move.from >= 0 and square in before.targets(move.from): continue
			result.fork_targets.append(square)
	var fork: bool = result.fork_targets.size() >= 2
	result.candidate = result.sacrifice or (fork and not recapture and not free_capture and not before.in_check(before.turn))
	result.reason = "新出现的非步子力牺牲" if result.sacrifice else "新形成的多子攻击" if result.candidate else "排除普通吃回、白吃和常规应将"
	return result

static func missed_material(position, played: Dictionary, best_usi: String) -> Dictionary:
	var answer = Codec.parse_move(best_usi, position)
	var missed = 0
	if not answer.is_empty() and answer in position.legal_moves() and position.board[answer.to] != 0:
		missed = maxi(0, exchange(position, answer) - (maxi(0, exchange(position, played)) if position.board[played.to] != 0 else 0))
	var allowed = maxi(0, -exchange(position, played))
	var after = position.after(played)
	# An opponent PV may capture a different hanging piece. Limit this to legal captures.
	for move in after.legal_moves(true):
		if after.board[move.to] * position.turn > 0: allowed = maxi(allowed, exchange(after, move))
	return {"missed": missed, "allowed": allowed, "loss": maxi(missed, allowed)}
