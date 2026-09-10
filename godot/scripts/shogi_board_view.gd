extends Control
## Minimal renderer and the shared, language-aware board overlay.
var app
var avatar = preload("res://assets/brand/ai-icon.png")
const FACE_NAMES = ["", "Fu", "Kyosha", "Keima", "Ginsho", "Kinsho", "Kakugyo", "Hisha", "Gyokusho", "Tokin", "Narikyo", "Narikei", "Narigin", "", "Uma", "Ryu"]
var faces: Dictionary = {}
var mincho = preload("res://assets/fonts/NotoSerifJP.ttf")
var workbench_background = preload("res://assets/reference-ui/wood_dark.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for name in FACE_NAMES + ["Ousho"]:
		if not name.is_empty(): faces[name] = load("res://assets/glyphs/" + name + ".svg")

func text(value: String, rect: Rect2, font_size: int, color: Color, inverted: bool = false, font: Font = null) -> void:
	if font == null: font = app.text_font
	font_size = maxi(10, font_size)
	while font_size > 10 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 4:
		font_size -= 1
	if font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 4:
		while value.length() > 1 and font.get_string_size(value + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 4:
			value = value.left(value.length() - 1)
		value += "…"
	var extent = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline = Vector2(-extent.x / 2, (font.get_ascent(font_size) - font.get_descent(font_size)) / 2)
	draw_set_transform(rect.get_center(), PI if inverted else 0)
	draw_string(font, baseline, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_set_transform(Vector2.ZERO)

func glyph(value: int, rect: Rect2, color: Color) -> void:
	rect = piece_rect(rect)
	var inverted: bool = (value < 0) != app.flipped
	if app.preferences.appearance == "anime2d":
		var p: Dictionary = app.palette()
		var half = rect.size * Vector2(0.39, 0.43)
		var points = PackedVector2Array([Vector2(0, -half.y), Vector2(half.x * 0.72, -half.y * 0.62), Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x * 0.72, -half.y * 0.62)])
		draw_set_transform(rect.get_center() + Vector2(0, 1.4), PI if inverted else 0)
		draw_colored_polygon(points, Color(0.1, 0.08, 0.05, 0.22))
		draw_set_transform(rect.get_center(), PI if inverted else 0)
		draw_colored_polygon(points, p.piece)
		points.append(points[0])
		draw_polyline(points, p.board_line, 0.7, true)
		draw_set_transform(Vector2.ZERO)
		color = Color("963d35") if absi(value) > 8 else p.piece_ink
		rect = rect.grow(-rect.size.x * 0.08)
	if app.preferences.piece_font == "ryoko":
		var name: String = "Ousho" if value == -8 else FACE_NAMES[absi(value)]
		var texture: Texture2D = faces.get(name)
		if texture == null: return
		var area = rect.size * 0.82
		var aspect = texture.get_size().x / texture.get_size().y
		area.x = minf(area.x, area.y * aspect)
		area.y = minf(area.y, area.x / aspect)
		draw_set_transform(rect.get_center(), PI if inverted else 0)
		draw_texture_rect(texture, Rect2(-area / 2, area), false, color)
		draw_set_transform(Vector2.ZERO)
	else:
		var name: String = "王" if value == -8 else app.GLYPHS[absi(value)]
		text(name, rect, int(rect.size.y * (0.46 if name.length() > 1 else 0.64)), color, inverted, mincho)

func piece_rect(slot: Rect2) -> Rect2:
	var edge = minf(slot.size.x, slot.size.y)
	return Rect2(slot.get_center() - Vector2.ONE * edge / 2, Vector2.ONE * edge)

func token_rect(token: Dictionary) -> Rect2:
	return app.square_rect(token.square) if token.square >= 0 else app.hand_slot(signi(token.value), absi(token.value))

func corners(rect: Rect2, color: Color) -> void:
	var r = rect.grow(-3)
	var length = minf(10, r.size.x * 0.25)
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var dx = length if p.x == r.position.x else -length
		var dy = length if p.y == r.position.y else -length
		draw_line(p, p + Vector2(dx, 0), color, 2, true)
		draw_line(p, p + Vector2(0, dy), color, 2, true)

func _draw() -> void:
	if app == null: return
	if app.first_board_frame_ms < 0: app.first_board_frame_ms = Time.get_ticks_msec()
	var p: Dictionary = app.palette()
	var wood: bool = app.wood_view != null
	var position = app._display_position()
	var viewed = app._view_game()
	var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
	if app.dark and wood:
		var gap: Rect2 = app.board_rect.grow(2)
		for region in [Rect2(0, 0, size.x, gap.position.y), Rect2(0, gap.end.y, size.x, size.y - gap.end.y), Rect2(0, gap.position.y, gap.position.x, gap.size.y), Rect2(gap.end.x, gap.position.y, size.x - gap.end.x, gap.size.y)]:
			if region.size.x > 0 and region.size.y > 0: draw_texture_rect_region(workbench_background, region, Rect2(region.position / size * workbench_background.get_size(), region.size / size * workbench_background.get_size()))
	if not wood:
		draw_rect(Rect2(Vector2.ZERO, size), p.background)
		if app.dark:
			draw_texture_rect(workbench_background, Rect2(Vector2.ZERO, size), false)
		if app.preferences.appearance == "anime2d":
			draw_style_box(app.Design.box(p.board, 3, 0), app.board_rect.grow(2))
			for grain in range(45):
				var x: float = app.board_rect.position.x + (grain + 0.3) * app.board_rect.size.x / 45
				draw_line(Vector2(x, app.board_rect.position.y), Vector2(x + sin(grain) * 3, app.board_rect.end.y), Color(0.4, 0.24, 0.08, 0.035), 0.8, true)
		for side in [1, -1]:
			var slot: Rect2 = app.hand_slot(side, 7)
			var tray = Rect2(app.bottom_player_rect.position.x if app.wide_layout else app.board_rect.position.x, slot.position.y, app.bottom_player_rect.size.x if app.wide_layout else app.board_rect.size.x, 42)
			draw_style_box(app.Design.box(p.soft, 10, 0), tray)
			if app.hand_rects[side].is_empty(): text(app.t("持驹：无"), tray, 12, p.muted)
		if app.preferences.last_move and ply > 0:
			var last: Dictionary = viewed.moves[ply - 1]
			draw_rect(app.square_rect(last.to).grow(-1), p.last)
			if last.from >= 0: corners(app.square_rect(last.from), p.accent)
			else: corners(app.hand_slot(-position.turn, last.drop), p.accent)
		if app.selection >= 0: draw_rect(app.square_rect(app.selection).grow(-1), p.selected)
		if app.selected_drop > 0: draw_rect(app.hand_slot(position.turn, app.selected_drop).grow(-2), p.selected)
		for square in app.checked_cells:
			draw_rect(app.square_rect(square).grow(-0.7), p.danger_fill)
			draw_rect(app.square_rect(square).grow(-1.5), p.danger, false, 2.4)
		for i in range(10):
			var offset: float = i * app.cell
			var width = 1.4 if i in [0, 9] else 0.8
			draw_line(app.board_rect.position + Vector2(offset, 0), Vector2(app.board_rect.position.x + offset, app.board_rect.end.y), p.board_line if app.preferences.appearance == "anime2d" else p.line, width, true)
			draw_line(app.board_rect.position + Vector2(0, offset), Vector2(app.board_rect.end.x, app.board_rect.position.y + offset), p.board_line if app.preferences.appearance == "anime2d" else p.line, width, true)
		if not app.transition.is_empty() and app.motion_progress < 1:
			var shown_hands: Dictionary = {}
			for track in app.transition:
				var before: Dictionary = track.before
				var after: Dictionary = track.after
				var resting_hand: bool = before.square < 0 and after.square < 0 and motion_rect(track).is_equal_approx(token_rect(after))
				if resting_hand:
					if shown_hands.has(after.value): continue
					shown_hands[after.value] = true
				glyph(motion_value(track), motion_rect(track), p.ink)
		else:
			for square in range(81):
				if position.board[square] != 0:
					if app.pointer_moved and app.drag_source == square: continue
					glyph(position.board[square], app.square_rect(square), p.ink)
			for side in [1, -1]:
				for kind in app.hand_rects[side]:
					if app.pointer_moved and app.drag_drop == kind and side == position.turn: continue
					glyph(side * kind, app.hand_slot(side, kind), p.ink)
		for side in [1, -1]:
			for kind in app.hand_rects[side]:
				var count: int = position.hands[side][kind]
				if count > 1:
					var rect: Rect2 = app.hand_slot(side, kind)
					text(str(count), Rect2(rect.end - Vector2(20, 19), Vector2(20, 19)), 13, p.muted)
		if app.preferences.hints and app.replay_index < 0:
			var seen: Dictionary = {}
			for move in app.legal:
				if ((app.selection >= 0 and move.from == app.selection) or (app.selected_drop > 0 and move.drop == app.selected_drop)) and not seen.has(move.to):
					seen[move.to] = true
					var center: Vector2 = app.square_rect(move.to).get_center()
					if position.board[move.to] != 0: corners(app.square_rect(move.to), p.accent)
					else: draw_circle(center, maxf(2.4, app.cell * 0.06), p.accent)
		if app.pointer_moved and (app.drag_source >= 0 or app.drag_drop > 0):
			var value: int = position.board[app.drag_source] if app.drag_source >= 0 else position.turn * app.drag_drop
			glyph(value, Rect2(app.pointer_current - Vector2.ONE * app.cell / 2, Vector2.ONE * app.cell), p.ink)
		if app.preferences.coordinates:
			for index in range(9):
				var rank: int = 8 - index if app.flipped else index
				text(str(9 - rank), Rect2(app.board_rect.position + Vector2(index * app.cell, 0), Vector2(10, 10)), 8, p.piece_ink)
				text(["一", "二", "三", "四", "五", "六", "七", "八", "九"][rank], Rect2(Vector2(app.board_rect.end.x - 10, app.board_rect.position.y + (index + 1) * app.cell - 10), Vector2(10, 10)), 8, p.piece_ink)
	if wood:
		for side in [1, -1]:
			var player: Rect2 = app.bottom_player_rect if (side == 1) != app.flipped else app.top_player_rect
			var hand_y: float = player.end.y + 4 if app.wide_layout else app.board_rect.end.y + 4 if (side == 1) != app.flipped else app.board_rect.position.y - 46
			var tray = Rect2(player.position.x, hand_y, player.size.x, 42)
			if tray.size.x <= 0: continue
			draw_style_box(app.Design.box(p.soft, 10, 0), tray)
			if app.hand_rects[side].is_empty(): text(app.t("持驹：无"), tray, 12, p.muted)
			for kind in app.hand_rects[side]:
				var rect: Rect2 = app.hand_slot(side, kind)
				if app.selected_drop == kind and position.turn == side: draw_style_box(app.Design.box(p.selected, 8, 0), rect)
				glyph(side * kind, rect, p.ink)
				if position.hands[side][kind] > 1: text(str(position.hands[side][kind]), Rect2(rect.end - Vector2(16, 16), Vector2(16, 16)), 11, p.ink)
		for square in app.checked_cells: draw_rect(app.square_rect(square).grow(-1), p.danger, false, 2)
	# Shared overlays retain identical semantics over either renderer.
	if wood and app.preferences.last_move and ply > 0:
		var last: Dictionary = viewed.moves[ply - 1]
		corners(app.square_rect(last.from) if last.from >= 0 else app.hand_hit_rect(-position.turn, last.drop), p.accent)
	if app.keyboard_visible:
		var focus: Rect2 = app.square_rect(app.keyboard_square) if app.keyboard_hand == 0 else app.hand_hit_rect(position.turn, app.keyboard_hand)
		corners(focus, p.accent)
	if app.preferences.last_move and ply > 0 and app.motion_progress < 1:
		var rect: Rect2 = app.square_rect(viewed.moves[ply - 1].to)
		corners(rect.grow(2 * (1 - app.motion_progress)), p.accent)
	if not app.ui.is_open() or app.ui.sheet:
		var bottom_side: int = -1 if app.flipped else 1
		_player(-bottom_side, app.top_player_rect, p, position, viewed)
		_player(bottom_side, app.bottom_player_rect, p, position, viewed)
	if app.ui.has_method("receive_info"):
		workbench_overlays(position, viewed, ply, p)
		return
	if not app.ui.is_open():
		var safe: Rect2 = app.safe_rect()
		text(app.t("网络对战") if app.session != null else app.t("人机对弈") if app.game.mode == "ai" else app.t("同机双人"), Rect2(safe.position + Vector2(66, 6), Vector2(safe.size.x - 132, 40)), 17, p.ink)
		var status = app.t("轮到你") if app._can_play() else app.t("思考中…") if app._ai_allowed() else app.t("等待对手")
		if not app.checked_cells.is_empty(): status = app.t("将军")
		if not viewed.result.is_empty(): status = app.i18n.result(viewed)
		if app.session != null and not app.session.connected_ready: status = app.t("联机未连接")
		var info_y: float = maxf(app.bottom_player_rect.end.y + 12, app.result_rect.position.y - 65)
		var info = Rect2(safe.position.x + 16, info_y, safe.size.x - 32, maxf(38, app.result_rect.position.y - info_y))
		if app.wide_layout: info = Rect2(app.bottom_player_rect.position.x, app.bottom_player_rect.end.y + 54, app.bottom_player_rect.size.x, 54)
		if info.end.y < safe.end.y - 60 and info.size.x > 0:
			draw_style_box(app.Design.box(p.soft, 14, 0), info)
			text(status, Rect2(info.position, Vector2(info.size.x, 30)), 16, p.danger if not app.checked_cells.is_empty() else p.ink)
			if info.size.y > 52:
				var last = app.t("初始局面") if ply == 0 else str(ply) + "  ·  " + viewed.labels[ply - 1]
				text(last, Rect2(info.position + Vector2(0, 29), Vector2(info.size.x, 22)), 12, p.muted)
		if not app.game.result.is_empty():
			text(app.t("查看对局结果"), app.result_rect, 17, p.accent)
		elif not app.notice.is_empty() and app.notice not in ["轮到你", "等待对手"]:
			text(app.i18n.message(app.notice), app.result_rect, 13, p.muted)

func _player(side: int, area: Rect2, p: Dictionary, position, viewed) -> void:
	if area.size.x < 100: return
	draw_style_box(app.Design.box(p.surface, 12, 0), area)
	var local: bool = side == (app.session.local_side if app.session != null else app.game.human_side)
	if app._practice_active(): local = side == app.ui.practice.exercise.positions[0].turn
	if local:
		draw_circle(area.position + Vector2(21, 21), 16, p.soft)
		text("玉", Rect2(area.position + Vector2(5, 5), Vector2(32, 32)), 20, p.ink, false, mincho)
	else:
		draw_circle(area.position + Vector2(21, 21), 16, p.soft)
		text("玉" if app._practice_active() else "AI" if app.game.mode == "ai" and app.session == null else app.t("友"), Rect2(area.position + Vector2(5, 5), Vector2(32, 32)), 12, p.accent)
	var name = app.t("你") if local else app.t("对手") if app.session != null else app.t("电脑") if app.game.mode == "ai" else app.t("棋友")
	if local: name = app.preferences.studio.username
	if app.game.engine_match: name = "YaneuraOu"
	if viewed.metadata.has("先手" if side == 1 else "后手"): name = str(viewed.metadata["先手" if side == 1 else "后手"])
	if name != app.t("先手" if side == 1 else "后手"): name += " · " + app.t("先手" if side == 1 else "后手")
	text(name, Rect2(area.position + Vector2(42, 0), Vector2(area.size.x - 142, 42)), 13, p.ink)
	var clock: String = viewed.clock.text_for(side, app.session != null and not app.session.is_host)
	if clock.is_empty(): clock = app.t("行棋中") if side == position.turn and viewed.result.is_empty() else app.t("不限时")
	if app._practice_active(): clock = "答题方" if local else "对方"
	var clock_area = Rect2(area.end.x - 92, area.position.y + 5, 87, 32)
	draw_style_box(app.Design.box(p.accent if side == position.turn else p.soft, 8, 0), clock_area)
	text(clock, clock_area, 14, p.background if side == position.turn else p.muted)

func arrow(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction = (to - from).normalized()
	var normal = Vector2(-direction.y, direction.x)
	draw_line(from, to - direction * width * 1.2, color, width, true)
	draw_colored_polygon(PackedVector2Array([to, to - direction * width * 2.5 + normal * width * 1.4, to - direction * width * 2.5 - normal * width * 1.4]), color)

func motion_rect(track: Dictionary) -> Rect2:
	var a: Rect2 = track.get("visual_rect", token_rect(track.before))
	var b: Rect2 = token_rect(track.after)
	return Rect2(a.position.lerp(b.position, app.motion_progress), a.size.lerp(b.size, app.motion_progress))

func motion_value(track: Dictionary) -> int:
	return track.get("visual_value", track.before.value) if app.motion_progress < 0.5 else track.after.value

func workbench_overlays(position, viewed, ply: int, p: Dictionary) -> void:
	if app.ui.page != null and not app.ui.sheet: return
	if app._practice_active():
		var practice = app.ui.practice
		if practice.hint_level > 0 and practice.stage == "answer":
			var move: Dictionary = practice.entry().best
			var area: Rect2 = app.square_rect(move.from) if move.from >= 0 else app.hand_slot(position.turn, move.drop)
			corners(area, Color("75c7ff"))
			if practice.hint_level >= 2: arrow(area.get_center(), app.square_rect(move.to).get_center(), Color("75c7ff"), app.cell * 0.1)
		return
	if app.preferences.studio.threats:
		for square in range(81):
			if position.board[square] == 0: continue
			for enemy in range(81):
				if position.board[enemy] * position.board[square] < 0 and square in position.targets(enemy):
					corners(app.square_rect(square), Color("e29444"))
					break
	if app.preferences.studio.arrows and app.ui.live_enabled and app.ui.live_key == position.key():
		for index in range(app.ui.arrows.size()):
			var move: Dictionary = app.ui.arrows[index]
			var from: Vector2 = app.square_rect(move.from).get_center() if move.from >= 0 else app.hand_slot(position.turn, move.drop).get_center()
			var color = [Color("8cc65c"), Color("58a6ff"), Color("dca34c"), Color("b898e2"), Color("e27880")][index % 5]
			color.a = 0.72
			arrow(from, app.square_rect(move.to).get_center(), color, app.cell * 0.1)
	var marks = viewed.annotations.get(str(ply), [])
	if marks is Array:
		for mark in marks.slice(0, 64):
			if not mark is Array or mark.size() != 2: continue
			if not (mark[0] is int or mark[0] is float) or not (mark[1] is int or mark[1] is float): continue
			if mark[0] < 0 or mark[0] >= 81 or mark[1] < 0 or mark[1] >= 81: continue
			var from: Vector2 = app.square_rect(int(mark[0])).get_center()
			var to: Vector2 = app.square_rect(int(mark[1])).get_center()
			if from == to: draw_arc(from, app.cell * 0.4, 0, TAU, 40, Color("72be4d"), 3, true)
			else: arrow(from, to, Color(0.4, 0.75, 0.25, 0.78), app.cell * 0.11)
	var detail: Dictionary = app.ui.evaluation()
	if app.preferences.studio.eval_bar and detail.has("score"):
		var fraction = app.ui.Coach.sente_chance(detail, position.turn)
		if app.flipped: fraction = 1.0 - fraction
		var area = Rect2(app.board_rect.position + Vector2(0, -4), Vector2(app.board_rect.size.x, 3))
		draw_rect(area, Color("211910"))
		area.size.x *= fraction
		draw_rect(area, Color("f7efdf"))
