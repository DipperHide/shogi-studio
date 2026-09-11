extends RefCounted
## Presentation of a validated move; never changes the move or position.
const Rules = preload("res://scripts/shogi_rules.gd")
const COLORS = [Color("8cc65c"), Color("58a6ff"), Color("dca34c"), Color("b898e2"), Color("e27880")]

static func choice(position, move: Dictionary) -> String:
	if move.is_empty() or int(move.get("drop", 0)) > 0: return ""
	var origin = int(move.get("from", -1)); var target = int(move.get("to", -1))
	if origin < 0 or origin >= 81 or target < 0 or target >= 81: return ""
	var piece = int(position.board[origin])
	if piece * position.turn <= 0 or absi(piece) not in [Rules.PAWN, Rules.LANCE, Rules.KNIGHT, Rules.SILVER, Rules.BISHOP, Rules.ROOK]: return ""
	if not position.in_zone(origin, position.turn) and not position.in_zone(target, position.turn): return ""
	return "升变" if move.get("promote", false) else "不升变"

static func notation(position, move: Dictionary) -> String:
	return position.notation(move) + ("不成" if choice(position, move) == "不升变" else "")

static func color(line: int) -> Color:
	return COLORS[maxi(0, line - 1) % COLORS.size()]

static func short_label(decision: String, line: int, language: String = "zh") -> String:
	if decision.is_empty(): return ""
	var mark = ("+" if decision == "升变" else "=") if language == "en" else ("成" if decision == "升变" else "不成")
	return (str(line) + " " if line > 0 else "") + mark

static func badge_rect(target: Rect2, bounds: Rect2, extent: Vector2, occupied: Array) -> Rect2:
	# Keep nearby alternatives distinct, including two moves to the same square.
	var anchor = Vector2(target.end.x - extent.x, target.position.y)
	var result = Rect2(anchor, extent)
	for row in [0, -1, 1, -2, 2, -3, 3, -4, 4]:
		for column in [0, -1, 1]:
			var point = anchor + Vector2(column * (extent.x + 2), row * (extent.y + 2))
			point.x = clampf(point.x, bounds.position.x, bounds.end.x - extent.x)
			point.y = clampf(point.y, bounds.position.y, bounds.end.y - extent.y)
			result = Rect2(point, extent)
			if occupied.all(func(other): return not result.grow(1).intersects(other)): return result
	return result
