extends Control
signal move_requested(candidates: Array)
signal target_pressed(square: String)
signal invalid_action(message: String)
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
const PIECE_FONT = preload("res://assets/fonts/NotoSerifJP.ttf")
var model
var app
var selected: int = -1
var selected_drop: int = 0
var board_rect: Rect2
var cell: float = 24
var hands: Dictionary = {}
var check_key: String = ""
var checked_cells: Array[int] = []
var pending: bool = false
var pointer: int = -1
var pointer_start: Vector2
var pointer_scrolled: bool = false
var tokens: Array = []
var from_tokens: Array = []
var from_rects: Array = []
var motion: float = 1.0
var motion_tween: Tween

func hand_rect(side: int, kind: int) -> Rect2:
	var slot = (board_rect.size.x - 36) / 7.0
	var y: float = 0 if side == -1 else board_rect.end.y + 8
	return Rect2(Vector2(board_rect.position.x + 36 + (kind - 1) * slot, y), Vector2(slot, 36))

func token_rect(token: Dictionary) -> Rect2:
	return square_rect(token.square) if token.square >= 0 else hand_rect(signi(token.value), ShogiRules.base(token.value))

func visual_rect(index: int) -> Rect2:
	var target = token_rect(tokens[index])
	if motion >= 1 or index >= from_rects.size(): return target
	var start: Rect2 = from_rects[index]
	return Rect2(start.position.lerp(target.position, motion), start.size.lerp(target.size, motion))

func animate_to(next: Array) -> void:
	if tokens == next: return
	var starts: Array = []
	for i in range(tokens.size()): starts.append(visual_rect(i))
	if motion_tween != null: motion_tween.kill()
	from_tokens = tokens.duplicate(true)
	tokens = next.duplicate(true)
	from_rects = starts
	if starts.is_empty() or starts.size() != tokens.size(): motion = 1; queue_redraw(); return
	motion = 0
	motion_tween = create_tween()
	motion_tween.tween_method(func(value): motion = value; queue_redraw(), 0.0, 1.0, maxf(0.12, app.preferences.studio.animation)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _piece(value: int, slot: Rect2, colors: Dictionary) -> void:
	var edge = minf(slot.size.x, slot.size.y)
	var center = slot.get_center()
	var half = Vector2(edge * 0.39, edge * 0.43)
	draw_set_transform(center, PI if value < 0 else 0)
	var points = PackedVector2Array([Vector2(0, -half.y), Vector2(half.x * 0.82, -half.y * 0.65), Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x * 0.82, -half.y * 0.65)])
	draw_colored_polygon(points, Color("e9c487"))
	points.append(points[0])
	draw_polyline(points, Color("705134"), 1, true)
	draw_set_transform(Vector2.ZERO)
	_text(Rules.NAMES[absi(value)], Rect2(center - Vector2.ONE * edge / 2, Vector2.ONE * edge), int(edge * 0.57), Color("9a302a") if absi(value) > 8 else Color("302015"), value < 0, PIECE_FONT)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	cell = maxf(12, floorf((size.x - 22) / 9))
	board_rect = Rect2(Vector2((size.x - cell * 9 - 16) / 2, 58), Vector2.ONE * cell * 9)
	custom_minimum_size.y = board_rect.end.y + 56
	queue_redraw()

func _text(value: String, area: Rect2, font_size: int, color: Color, inverted: bool = false, font: Font = null) -> void:
	font_size = maxi(9, font_size)
	if font == null: font = app.text_font
	while font_size > 9 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > area.size.x - 2: font_size -= 1
	var extent = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_set_transform(area.get_center(), PI if inverted else 0)
	draw_string(font, Vector2(-extent.x / 2, (font.get_ascent(font_size) - font.get_descent(font_size)) / 2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO)

func square_rect(square: int) -> Rect2:
	return Rect2(board_rect.position + Vector2(square % 9, square / 9) * cell, Vector2.ONE * cell)

func _draw() -> void:
	if model == null or model.position == null or app == null: return
	var colors: Dictionary = app.palette()
	var pos: ShogiRules = model.position
	draw_rect(Rect2(Vector2.ZERO, size), colors.background)
	draw_rect(board_rect, Color("ddbc8b"))
	if check_key != pos.key():
		check_key = pos.key()
		checked_cells = preload("res://scripts/shogi_design.gd").checked_squares(pos)
	for square in range(81):
		if square == selected or Codec.square_name(square) in model.selected_targets:
			draw_rect(square_rect(square).grow(-1), colors.selected)
		if square in checked_cells:
			draw_rect(square_rect(square).grow(-1), colors.danger_fill)
			draw_rect(square_rect(square).grow(-1), colors.danger, false, 2)
	if model.step.kind == "targets":
		var source = Codec.parse_square(model.step.from)
		draw_rect(square_rect(source).grow(-2), colors.accent, false, 2)
	for index in range(10):
		draw_line(board_rect.position + Vector2(index * cell, 0), Vector2(board_rect.position.x + index * cell, board_rect.end.y), colors.line, 1, true)
		draw_line(board_rect.position + Vector2(0, index * cell), Vector2(board_rect.end.x, board_rect.position.y + index * cell), colors.line, 1, true)
	for index in range(9):
		_text(str(9 - index), Rect2(board_rect.position + Vector2(index * cell, -20), Vector2(cell, 20)), 12, colors.muted)
		_text(["一", "二", "三", "四", "五", "六", "七", "八", "九"][index], Rect2(Vector2(board_rect.end.x, board_rect.position.y + cell * index), Vector2(18, cell)), 12, colors.muted)
	hands.clear()
	for side in [-1, 1]:
		var y: float = 0 if side == -1 else board_rect.end.y + 8
		_text(app.t("后手" if side == -1 else "先手"), Rect2(Vector2(board_rect.position.x, y), Vector2(40, 36)), 12, colors.muted)
		var occupied: Array[int] = []
		for kind in range(1, 8):
			if pos.hands[side][kind] > 0: occupied.append(kind)
		if occupied.is_empty(): _text(app.t("持驹：无"), Rect2(Vector2(board_rect.position.x + 42, y), Vector2(84, 36)), 13, colors.muted)
		else:
			for index in range(occupied.size()):
				var kind = occupied[index]
				var area = hand_rect(side, kind)
				hands[side * kind] = area
				if side == pos.turn and kind == selected_drop: draw_rect(area, colors.selected)
	for i in range(tokens.size()):
		var value: int = tokens[i].value
		if motion < 0.5 and i < from_tokens.size(): value = from_tokens[i].value
		_piece(value, visual_rect(i), colors)
	for side in [-1, 1]:
		for kind in range(1, 8):
			if pos.hands[side][kind] > 1:
				var area = hand_rect(side, kind)
				_text(str(pos.hands[side][kind]), Rect2(area.end - Vector2(12, 14), Vector2(12, 14)), 11, colors.ink)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventScreenTouch:
		accept_event()
		if event.pressed and pointer < 0:
			pointer = event.index
			pointer_start = event.position
			pointer_scrolled = false
		elif not event.pressed and pointer == event.index:
			pointer = -1
			if not event.canceled and not pointer_scrolled and pointer_start.distance_to(event.position) < 12: tap(event.position)
	elif event is InputEventScreenDrag and event.index == pointer:
		accept_event()
		if pointer_scrolled or pointer_start.distance_to(event.position) >= 12:
			pointer_scrolled = true
			var parent = get_parent()
			while parent != null:
				if parent is ScrollContainer:
					parent.scroll_vertical -= int(event.relative.y)
					break
				parent = parent.get_parent()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not event.pressed and pointer < 0: tap(event.position)

func tap(point: Vector2) -> void:
	if model == null or model.position == null or model.solved or pending or motion < 1 or not model.error.is_empty(): return
	var pos: ShogiRules = model.position
	if board_rect.has_point(point):
		var offset = point - board_rect.position
		var square = int(offset.y / cell) * 9 + int(offset.x / cell)
		if model.step.kind == "targets": target_pressed.emit(Codec.square_name(square)); return
		if selected >= 0 or selected_drop > 0:
			var candidates: Array = []
			for move in pos.legal_moves():
				if move.to == square and move.from == selected and move.drop == selected_drop: candidates.append(move)
			if not candidates.is_empty():
				selected = -1
				selected_drop = 0
				move_requested.emit(candidates)
				queue_redraw()
				return
			if pos.board[square] * pos.turn <= 0:
				invalid_action.emit("这步不符合移动、升变或打入规则，请重新选择。")
		if pos.board[square] * pos.turn > 0:
			selected = -1 if selected == square else square
			selected_drop = 0
	else:
		for key in hands:
			if signi(key) == pos.turn and hands[key].has_point(point):
				selected_drop = 0 if selected_drop == absi(key) else absi(key)
				selected = -1
	queue_redraw()
