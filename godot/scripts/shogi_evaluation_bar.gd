extends Control
## activity_main score strip: linear score scale, nine ticks and 750 ms easing.
const CP_SCALE = preload("res://scripts/shogi_report_metrics.gd").CP_SCALE
const LIGHT = Color("e7dfde")
const DARK = Color("483d41")
var ui
var side = false
var smart_key = ""
var smart_left = false
var progress = 0.5
var target = 0.5
var start = 0.5
var elapsed = 0.75
var state: Dictionary = {}
var options_button: Button
var engine_index = 0
var continue_index = 0
var data_key = ""

static func sample(details: Dictionary, turn: int, ended: bool = false, winner: int = 0, result_text: String = "") -> Dictionary:
	if ended: return {"available": true, "fraction": (winner + 1) / 2.0, "text": result_text, "depth": 0, "score": 0, "terminal": true}
	if not details.has("score"): return {"available": false, "fraction": 0.5, "text": "—", "depth": 0, "score": 0, "terminal": false}
	var score = float(details.score) * turn
	var mate = details.get("score_type") == "mate"
	var fraction = (1.0 if score > 0 else 0.0) if mate else clampf(0.5 + score / CP_SCALE / 1000.0, 0, 1)
	var caption = ("+詰" if score > 0 else "−詰") + str(absi(int(details.score))) if mate else "%+.2f" % (score / 100.0)
	return {"available": true, "fraction": fraction, "text": caption, "depth": int(details.get("depth", 0)), "score": score, "terminal": false}

func setup(owner_ui) -> void:
	ui = owner_ui
	name = "EvaluationBar"
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_PASS
	engine_index = ui.engine_toggle.get_index()
	continue_index = ui.continue_button.get_index()
	options_button = ui.compact_button("⋯", ui.show_evaluation_options, 28)
	options_button.name = "SideEngineOptions"
	options_button.tooltip_text = "引擎与评价条选项"
	options_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ui.set_reference_icon(options_button, "ic_engine_options_subtle")
	ui.root.add_child(options_button)
	options_button.hide()
	gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			accept_event(); ui.show_evaluation_options()
	)

func allowed() -> bool:
	return ui != null and ui.app.preferences.studio.eval_bar and ui.app.session == null and not ui.practice_active() and ui.pv_context.is_empty()

func reserve(usable: Rect2) -> bool:
	if not allowed(): return false
	var mode: String = ui.app.preferences.studio.eval_position
	var report_active = ui.report != null and ui.app.replay_index >= 0 and ui.report.game == ui.app._view_game()
	var wide = usable.size.x > usable.size.y
	var key = str([mode, wide, report_active])
	if key != smart_key: smart_key = key; smart_left = false
	if mode == "left": return true
	if mode == "bottom": return false
	if mode == "left_on_game_report": return report_active
	if report_active and not smart_left:
		var full_width = usable.size.x - 14
		var board_height = usable.size.y - 433 - (30 if ui.study_active() else 0)
		# Like the reference, switch at most once per report/orientation. Shogi
		# includes two hand panels, so use its actual board height budget.
		smart_left = usable.size.y < 480 if wide else board_height < full_width - 16
	return smart_left

func layout_bar() -> void:
	var next_side = reserve(ui.app.safe_rect())
	if next_side != side:
		side = next_side
		if side:
			ui.engine_toggle.reparent(ui.root)
			ui.continue_button.reparent(ui.win_row)
		else:
			ui.continue_button.reparent(ui.eval_row)
			ui.eval_row.move_child(ui.continue_button, mini(continue_index, ui.eval_row.get_child_count() - 1))
			ui.engine_toggle.reparent(ui.eval_row)
			ui.eval_row.move_child(ui.engine_toggle, mini(engine_index, ui.eval_row.get_child_count() - 1))
	ui.eval_row.visible = not side
	ui.eval_label.visible = not allowed()
	ui.score_slot.visible = allowed() and not side
	visible = allowed() and ui.live_panel.visible and (ui.page == null or ui.sheet)
	options_button.visible = visible and side
	if side:
		position = ui.app.board_rect.position - Vector2(28, 0)
		size = Vector2(24, ui.app.board_rect.size.y)
		var bottom = ui.app.board_rect.end.y + 4 if ui.app.wide_layout else ui.app.bottom_player_rect.position.y + 7
		ui.engine_toggle.position = Vector2(position.x, bottom)
		ui.engine_toggle.size = Vector2(28, 28)
		ui.engine_toggle.visible = visible
		options_button.position = Vector2(position.x + 30, bottom) if ui.app.wide_layout else Vector2(position.x, ui.app.top_player_rect.position.y + 7)
		options_button.size = Vector2(28, 28)
	else:
		ui.engine_toggle.show()
		position = ui.score_slot.global_position
		size = ui.score_slot.size

func synchronize(delta: float) -> void:
	if reserve(ui.app.safe_rect()) != side: ui.app._layout()
	layout_bar()
	var viewed = ui.app._view_game()
	var ply: int = ui.app.replay_index if ui.app.replay_index >= 0 else viewed.moves.size()
	var ended = ply == viewed.moves.size() and not viewed.result.is_empty()
	var next = sample(ui.evaluation(), ui.app._display_position().turn, ended, viewed.winner, ui.app.i18n.result(viewed))
	var key = str([next, ui.app.flipped, ui.app.palette().accent, side, visible, size])
	if next != state:
		var changed = state.is_empty() or next.fraction != target
		state = next
		if changed:
			start = progress
			target = state.fraction
			elapsed = 0.0
			if not state.available or ui.app.preferences.studio.animation <= 0: elapsed = 0.75; progress = target
	if elapsed < 0.75:
		elapsed = minf(0.75, elapsed + delta)
		progress = lerpf(start, target, (1.0 - cos(PI * elapsed / 0.75)) / 2.0)
		queue_redraw()
	if key != data_key:
		data_key = key
		accessibility_name = "局面评价 · " + state.text + (" · 深度 %d" % state.depth if state.depth > 0 else "")
		if not ended: accessibility_name += "；正数为先手优势，负数为后手优势" if state.available else "；此局面尚无评分"
		tooltip_text = accessibility_name + "。按回车打开选项。"
		queue_redraw()

func fill_rect() -> Rect2:
	var area = Rect2(Vector2(5, 5), Vector2(maxf(0, size.x - 10), 24)) if not side else Rect2(Vector2(5, 0), Vector2(14, size.y))
	if side:
		var length = area.size.y * progress
		if not ui.app.flipped: area.position.y += area.size.y - length
		area.size.y = length
	else:
		area.size.x *= progress
	return area

func _draw() -> void:
	if ui == null or state.is_empty() or size.x <= 0 or size.y <= 0: return
	var area = Rect2(Vector2(5, 5), Vector2(maxf(0, size.x - 10), 24)) if not side else Rect2(Vector2(5, 0), Vector2(14, size.y))
	draw_rect(area, DARK)
	draw_rect(fill_rect(), LIGHT)
	var accent: Color = ui.app.palette().accent
	for i in range(9):
		var factor = i / 8.0
		if side:
			var y = clampf(area.position.y + factor * area.size.y, 1, size.y - 1)
			draw_line(Vector2(0, y), Vector2(5, y), accent, 3 if i == 4 else 1)
		else:
			var x = area.position.x + factor * area.size.x
			draw_line(Vector2(x, 0), Vector2(x, 5), accent, 3 if i == 4 else 1)
	var caption = ("d%d" % state.depth if state.depth > 0 else "") if side else state.text + (ui.app.t("  (深度 %d)") % state.depth if state.depth > 0 and not state.text.contains("詰") else "")
	var font: Font = ui.Design.heading_font(ui.app.text_font)
	var font_size = 10 if side else 14
	while font_size > (7 if side else 8) and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - (0 if side else 10): font_size -= 1
	while caption.length() > 1 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x - (0 if side else 10): caption = caption.left(-2) + "…"
	var extent = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline = Vector2((size.x - extent.x) / 2.0, size.y - 8 if side else 17 + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0)
	draw_string(font, baseline, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, accent)
	if has_focus(): draw_rect(Rect2(Vector2.ZERO, size).grow(-1), accent, false, 1)
