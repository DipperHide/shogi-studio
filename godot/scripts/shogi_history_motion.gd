extends RefCounted
## Track physical piece identities through captures and drops, including equal kinds.

const Scene = preload("res://scripts/shogi_scene_layout.gd")
const Hand = preload("res://scripts/shogi_hand_layout.gd")

static func state(initial: ShogiRules, moves: Array, ply_count: int) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	for square in range(81):
		if initial.board[square] != 0:
			tokens.append({"square":square,"value":initial.board[square]})
	for side in [-1,1]:
		for kind in range(1,8):
			for count in range(initial.hands[side][kind]):
				tokens.append({"square":-1,"value":side*kind})
	var side = initial.turn
	for ply in range(ply_count):
		var move = moves[ply]
		var moving = -1
		if move.drop > 0:
			moving = Hand.layout(tokens).groups[side*move.drop].top
		else:
			for id in range(tokens.size()):
				if tokens[id].square == move.from:
					moving = id
					break
		assert(moving >= 0,"History must refer to an existing physical piece")
		for id in range(tokens.size()):
			if id != moving and tokens[id].square == move.to:
				tokens[id].square = -1
				tokens[id].value = side*ShogiRules.base(tokens[id].value)
				tokens[id]["hand_order"] = ply+1
				break
		tokens[moving].square = move.to
		if move.promote:
			tokens[moving].value += side*8
		side = -side
	return tokens

static func pose(tokens: Array, id: int, hands: Dictionary) -> Dictionary:
	var token = tokens[id]
	if token.square < 0:
		return hands.poses[id]
	return {"position":Scene.square_position(token.square),"rotation":PI if token.value<0 else 0.0,"scale":1.0}

static func location(tokens: Array, id: int) -> Vector3:
	return pose(tokens,id,Hand.layout(tokens)).position

static func tracks(before: Array, after: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var a = Hand.layout(before)
	var b = Hand.layout(after)
	for id in range(before.size()):
		var start = pose(before,id,a)
		var finish = pose(after,id,b)
		out.append({"id":id,"before":before[id],"after":after[id],"start":start.position,"end":finish.position,"start_pose":start,"end_pose":finish})
	return out

static func plan(initial: ShogiRules, moves: Array, source: int, target: int) -> Array[Dictionary]:
	return tracks(state(initial,moves,source),state(initial,moves,target))

static func stages(initial: ShogiRules, moves: Array, source: int, target: int) -> Array:
	var before = state(initial,moves,source)
	var after = state(initial,moves,target)
	if absi(target-source) == 1:
		var move = moves[mini(source,target)]
		if move.drop == 0:
			var forward = target > source
			var earlier = before if forward else after
			var later = after if forward else before
			for id in range(earlier.size()):
				if earlier[id].square == move.to:
					var middle = earlier.duplicate(true)
					middle[id] = later[id].duplicate()
					return [tracks(before,middle),tracks(middle,after)]
	return [tracks(before,after)]
