extends SceneTree
const Rules = preload("res://scripts/shogi_rules.gd")
const Game = preload("res://scripts/shogi_game.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("DECLARATION FAIL: ", title)

func eligible(side: int):
	var position = Rules.new(false)
	position.turn = side
	position.board[4 if side == 1 else 76] = side * Rules.KING
	position.board[80 if side == 1 else 0] = -side * Rules.KING
	for square in [0,1,2,3,5,6,7,8,9,10]:
		position.board[square if side == 1 else 80-square] = side * Rules.PAWN
	position.hands[side][Rules.ROOK] = 2
	position.hands[side][Rules.BISHOP] = 1
	position.hands[side][Rules.PAWN] = 3 if side == 1 else 2
	return position

func _initialize() -> void:
	check(not Rules.new().declaration_status(1).valid, "initial position cannot declare")
	for side in [1,-1]:
		var position = eligible(side)
		var status = position.declaration_status(side)
		check(status.valid and status.pieces == 10 and status.points == status.threshold, "threshold accepted for side %d" % side)
		position.hands[side][Rules.PAWN] -= 1
		check(not position.declaration_status(side).valid, "one point short rejected for side %d" % side)
		position.hands[side][Rules.PAWN] += 1
		position.board[0 if side == 1 else 80] = 0
		position.hands[side][Rules.PAWN] += 1
		check(not position.declaration_status(side).valid, "nine pieces in camp rejected despite enough points")
		position = eligible(side)
		position.turn = -side
		check(not position.declaration_status(side).valid, "cannot declare on opponent turn")
		position = eligible(side)
		position.board[40] = -side * Rules.ROOK
		check(position.declaration_status(side).in_check and not position.declaration_status(side).valid, "king in check cannot declare")
		position = eligible(side)
		position.board[0 if side == 1 else 80] = side * 9
		check(position.declaration_status(side).points == (28 if side == 1 else 27), "promoted minor still one point")
		position.board[0 if side == 1 else 80] = side * 15
		check(position.declaration_status(side).points == (32 if side == 1 else 31), "promoted major still five points")
		position.board[40] = side * Rules.ROOK
		check(position.declaration_status(side).points == (32 if side == 1 else 31), "pieces outside enemy camp excluded")
		var game = Game.new()
		game.position = eligible(side)
		check(game.declare_win(side) and game.declared_side == side, "game accepts verified declaration")
		check(not game.declare_win(-side), "finished game cannot redeclare")
		check(game.result.begins_with("先手获胜" if side == 1 else "后手获胜"), "declaration awards correct winner")
	var forged = Game.new().to_data()
	forged.declared_side = 1
	check(Game.from_data(forged) == null, "forged saved declaration rejected")
	var game = Game.new()
	game.agreed_draw = true
	game.update_result()
	game.undo()
	check(not game.agreed_draw and game.result.is_empty(), "undo clears zero-move agreed draw")
	var output = FileAccess.open(ProjectSettings.globalize_path("res://../review/app/complete/declaration-tests.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "rule": "CSA 27-point declaration"}, "  "))
	output.close()
	print("DECLARATION TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
