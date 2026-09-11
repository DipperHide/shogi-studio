extends "res://scripts/shogi_tutorial_board.gd"
## Read-only mini board; shares physical piece paths and painted-frame animation.
var preview
var flipped = false

func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE

func _layout() -> void:
	var limit = size.x - 22
	if app != null:
		var safe: Rect2 = app.safe_rect()
		limit = minf(limit, maxf(126, safe.size.y - 164 if safe.size.x > safe.size.y else safe.size.y * 0.60))
	cell = maxf(12, floorf(limit / 9))
	board_rect = Rect2(Vector2((size.x - cell * 9 - 16) / 2, 48), Vector2.ONE * cell * 9)
	custom_minimum_size.y = board_rect.end.y + 40
	queue_redraw()

func square_rect(square: int) -> Rect2:
	var visible_square = 80 - square if flipped else square
	return Rect2(board_rect.position + Vector2(visible_square % 9, visible_square / 9) * cell, Vector2.ONE * cell)

func hand_rect(side: int, kind: int) -> Rect2:
	var slot = (board_rect.size.x - 30) / 7.0
	var top = (side == -1) != flipped
	return Rect2(Vector2(board_rect.position.x + 30 + (kind - 1) * slot, 0 if top else board_rect.end.y + 5), Vector2(slot, 30))

func animate_to(next: Array) -> void:
	if app.preferences.studio.animation <= 0:
		if is_instance_valid(motion_tween): motion_tween.kill()
		from_tokens = tokens.duplicate(true); tokens = next.duplicate(true)
		from_rects = []; motion = 1; queue_redraw()
	else: super.animate_to(next)

func flip_board() -> void:
	if is_instance_valid(motion_tween): motion_tween.kill()
	motion = 1
	flipped = not flipped
	queue_redraw()

func _draw() -> void:
	if preview == null or preview.game == null or app == null: return
	var colors = app.palette()
	var pos: ShogiRules = preview.game.positions[preview.ply]
	draw_rect(board_rect, colors.board)
	if preview.ply > 0:
		var move: Dictionary = preview.game.moves[preview.ply - 1]
		for square in [move.from, move.to]:
			if square >= 0: draw_rect(square_rect(square).grow(-1), Color("e7bf51", 0.52))
	for index in range(10):
		draw_line(board_rect.position + Vector2(index * cell, 0), Vector2(board_rect.position.x + index * cell, board_rect.end.y), Color("785735"), 1, true)
		draw_line(board_rect.position + Vector2(0, index * cell), Vector2(board_rect.end.x, board_rect.position.y + index * cell), Color("785735"), 1, true)
	for index in range(9):
		_text(str(index + 1 if flipped else 9 - index), Rect2(board_rect.position + Vector2(index * cell, -18), Vector2(cell, 18)), 12, Color("f8f1e6"))
		_text(["一", "二", "三", "四", "五", "六", "七", "八", "九"][8 - index if flipped else index], Rect2(Vector2(board_rect.end.x, board_rect.position.y + cell * index), Vector2(18, cell)), 12, Color("f8f1e6"))
	for side in [-1, 1]:
		var y = hand_rect(side, 1).position.y
		_text(app.t("后手" if side == -1 else "先手"), Rect2(Vector2(board_rect.position.x, y), Vector2(28, 30)), 11, Color("f8f1e6"))
		if pos.hands[side].slice(1).all(func(count): return count == 0):
			_text(app.t("持驹：无"), Rect2(Vector2(board_rect.position.x + 30, y), Vector2(84, 30)), 12, Color("d4c8b5"))
	for i in range(tokens.size()):
		var value: int = from_tokens[i].value if motion < 0.5 and i < from_tokens.size() else tokens[i].value
		_piece(-value if flipped else value, visual_rect(i), colors)
	for side in [-1, 1]:
		for kind in range(1, 8):
			if pos.hands[side][kind] > 1:
				var area = hand_rect(side, kind)
				_text(str(pos.hands[side][kind]), Rect2(area.end - Vector2(12, 14), Vector2(12, 14)), 11, Color.WHITE)

func _gui_input(_event: InputEvent) -> void:
	pass
