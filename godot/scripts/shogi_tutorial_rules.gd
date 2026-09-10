extends "res://scripts/shogi_rules.gd"
## Partial teaching diagrams may omit kings. All other production rules apply.

func in_check(side: int) -> bool:
	return false if board.find(side * KING) < 0 else super.in_check(side)

func copy() -> ShogiRules:
	var result = get_script().new(false)
	result.board = board.duplicate()
	result.hands = hands.duplicate(true)
	result.turn = turn
	return result

static func from_sfen(value: String) -> ShogiRules:
	var codec = load("res://scripts/shogi_usi_codec.gd")
	var source = load("res://scripts/shogi_rules.gd").new() if value == "startpos" else codec.parse_sfen(value)
	if source == null: return null
	var result = load("res://scripts/shogi_tutorial_rules.gd").new(false)
	result.board = source.board.duplicate()
	result.hands = source.hands.duplicate(true)
	result.turn = source.turn
	return result
