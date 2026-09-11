extends SceneTree
const Rules = preload("res://scripts/shogi_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Hint = preload("res://scripts/shogi_move_hint.gd")
var checks = 0
var failures = []

func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures.append(title)

func position(side: int, kind: int, square: String):
	var result = Rules.new(false)
	result.turn = side
	result.board[0 if side == 1 else 80] = -8 * side
	result.board[80 if side == 1 else 0] = 8 * side
	if kind == 8: result.board[80 if side == 1 else 0] = 0
	var origin = Codec.parse_square(square)
	result.board[origin if side == 1 else 80 - origin] = kind * side
	return result

func verify_move(side: int, kind: int, origin: String, target: String, promote: bool, expected: String) -> void:
	var pos = position(side, kind, origin)
	var from = Codec.parse_square(origin); var to = Codec.parse_square(target)
	var value = Codec.square_name(from if side == 1 else 80 - from) + Codec.square_name(to if side == 1 else 80 - to) + ("+" if promote else "")
	var move = Codec.parse_move(value, pos)
	check(not move.is_empty(), "legal fixture " + value)
	if move.is_empty(): return
	var before = pos.key(); var saved = move.duplicate(true)
	check(Hint.choice(pos, move) == expected, "correct promotion choice " + value)
	var label = Hint.notation(pos, move)
	check(label.ends_with("不成") if expected == "不升变" else label.ends_with("成") if expected == "升变" else label == pos.notation(move), "unambiguous notation " + value)
	check(pos.key() == before and move == saved, "hint presentation preserves position and move " + value)

func _initialize() -> void:
	for side in [1, -1]:
		for item in [[1,"5d","5c"],[2,"5d","5c"],[3,"5e","4c"],[4,"5d","4c"],[6,"5d","4c"],[7,"5d","5c"],[4,"5c","4d"],[6,"5c","4d"],[7,"5c","5d"]]:
			for promote in [false,true]: verify_move(side,item[0],item[1],item[2],promote,"升变" if promote else "不升变")
		for item in [[1,"5b","5a"],[2,"5b","5a"],[3,"5c","4a"]]: verify_move(side,item[0],item[1],item[2],true,"升变")
		for item in [[1,"5e","5d"],[5,"5c","5b"],[8,"5c","5b"],[9,"5c","5b"],[14,"5c","4b"],[15,"5c","5b"]]: verify_move(side,item[0],item[1],item[2],false,"")
		var pos = position(side,1,"5e"); pos.hands[side][4] = 1
		var drop = Codec.parse_move("S*4b" if side == 1 else "S*6h",pos)
		check(not drop.is_empty() and Hint.choice(pos,drop).is_empty(), "drop inside promotion zone has no promotion mark")
		check(Hint.choice(pos,{}).is_empty(), "empty engine result has no mark")
	for target in [Rect2(0,0,30,30),Rect2(240,0,30,30),Rect2(0,240,30,30),Rect2(240,240,30,30)]:
		var occupied = []
		for i in range(5):
			var rect = Hint.badge_rect(target,Rect2(0,0,270,270),Vector2(38,20),occupied)
			check(Rect2(0,0,270,270).encloses(rect) and occupied.all(func(other): return not rect.intersects(other)), "same destination marks remain visible and separate at board edge")
			occupied.append(rect)
	check(Hint.short_label("升变",2)=="2 成" and Hint.short_label("不升变",5)=="5 不成", "candidate number identifies same-square alternatives")
	check(Hint.short_label("升变",2,"en")=="2 +" and Hint.short_label("不升变",5,"en")=="5 =", "English badge pairs with full translated candidate label")
	var out = ProjectSettings.globalize_path("res://../review/app/chessis32")
	DirAccess.make_dir_recursive_absolute(out)
	FileAccess.open(out.path_join("hint-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("HINT32: ",checks," checks; ",failures)
	quit(0 if failures.is_empty() else 1)
