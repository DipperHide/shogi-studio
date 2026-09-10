extends PanelContainer
const Move = preload("res://scripts/shogi_report_move.gd")
var ui
var ply: int

func setup(menu, selected: int) -> void:
	ui = menu
	ply = selected
	name = "ReportMoveCard"
	custom_minimum_size.y = 82
	var entry: Dictionary = ui.report.rows[ply - 1]
	var color: Color = ui.report.category_color(entry.category)
	var style = ui.Design.box(Color("1d252dd9"), 8, 0)
	style.border_color = Color("58a6ff66")
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	var hit = Button.new()
	hit.name = "OpenReportMoveBoard"
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", ui.Design.box(Color("ffffff08"), 8, 0))
	hit.add_theme_stylebox_override("pressed", ui.Design.box(Color("58a6ff20"), 8, 0))
	hit.add_theme_stylebox_override("focus", ui.Design.box(Color("58a6ff16"), 8, 0))
	hit.pressed.connect(func(): ui.open_report_position(ply))
	add_child(hit)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var stripe = ColorRect.new()
	stripe.name = "ReportMoveAccent"
	stripe.color = color
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.custom_minimum_size.x = 4
	row.add_child(stripe)
	row.add_child(ui.classification_icon(entry.category, 28, entry.get("forced", false)))
	var inset = MarginContainer.new()
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_top", 10)
	inset.add_theme_constant_override("margin_bottom", 10)
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(inset)
	var column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	inset.add_child(column)
	var title = ui.label("第 %d 手 · %s%s" % [ply, entry.label, Move.SUFFIX.get(entry.category, "")], 15)
	title.name = "ReportMoveTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(title)
	var evaluations = HBoxContainer.new()
	evaluations.mouse_filter = Control.MOUSE_FILTER_IGNORE
	evaluations.add_theme_constant_override("separation", 5)
	column.add_child(evaluations)
	add_evaluation(evaluations, ui.report.samples[ply - 1], "Before")
	var arrow = ui.label("→", 14)
	arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	evaluations.add_child(arrow)
	add_evaluation(evaluations, ui.report.samples[ply], "After")
	var text = Move.transition(ui.report.samples[ply - 1], ui.report.samples[ply], entry.side)
	if not text.is_empty():
		var reason = ui.label(text, 12)
		reason.name = "ReportMoveTransition"
		reason.add_theme_color_override("font_color", Color("d9cab4"))
		column.add_child(reason)
	var controls = VBoxContainer.new()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.custom_minimum_size.x = 32
	row.add_child(controls)
	var dismiss = ui.compact_button("×", ui.clear_report_selection, 32)
	dismiss.name = "DismissReportMove"
	dismiss.tooltip_text = "取消选中着手"
	dismiss.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		dismiss.add_theme_color_override(state, Color("f8f1e6"))
	controls.add_child(dismiss)
	var forward = ui.label("›", 24)
	forward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forward.size_flags_vertical = Control.SIZE_EXPAND_FILL
	forward.autowrap_mode = TextServer.AUTOWRAP_OFF
	controls.add_child(forward)
	hit.tooltip_text = title.text + " · " + entry.category + "\n" + Move.state_label(ui.report.samples[ply-1]) + " " + Move.score_label(ui.report.samples[ply-1]) + " → " + Move.state_label(ui.report.samples[ply]) + " " + Move.score_label(ui.report.samples[ply]) + ("\n" + text if not text.is_empty() else "") + "\n点击在棋盘查看"

func add_evaluation(parent: Control, sample: Dictionary, identity: String) -> void:
	var marker = preload("res://scripts/shogi_report_eval_marker.gd").new()
	marker.sample = sample
	marker.custom_minimum_size = Vector2(8, 30)
	parent.add_child(marker)
	var stack = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 0)
	parent.add_child(stack)
	var state = ui.label(Move.state_label(sample), 12)
	state.name = "ReportState" + identity
	state.autowrap_mode = TextServer.AUTOWRAP_OFF
	stack.add_child(state)
	var value = ui.label(Move.score_label(sample), 11)
	value.name = "ReportScore" + identity
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.add_theme_color_override("font_color", Color("d9cab4"))
	stack.add_child(value)
