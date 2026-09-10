extends VBoxContainer
const Quality = preload("res://scripts/shogi_report_quality.gd")
const Pie = preload("res://scripts/shogi_report_pie.gd")
const Phases = preload("res://scripts/shogi_report_phases.gd")
const Design = preload("res://scripts/shogi_design.gd")
var ui
var report
var cells: Dictionary = {}
var pies: Array = []
var expand: Button
var insight: PanelContainer
var insight_title: Label
var insight_body: Label
var insight_percent: Label
var insight_accent: ColorRect
var insight_tween: Tween

func control_style(button: Button) -> void:
	button.set_meta("report_statistics_control", true)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, Design.box(Color("ffffff10") if state in ["hover", "pressed"] else Color.TRANSPARENT, 4, 0))
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), Color("f8f1e6"))
	var focus = Design.box(Color.TRANSPARENT, 4, 0)
	focus.border_color = Color("58a6ff")
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_font_size_override("font_size", 14)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 32

func setup(owner_ui) -> void:
	ui = owner_ui; report = ui.report
	name = "ReportStatistics"
	add_theme_constant_override("separation", 0)
	var table = GridContainer.new()
	table.name = "ClassificationTable"
	table.columns = 3
	table.add_theme_constant_override("h_separation", 0)
	table.add_theme_constant_override("v_separation", 0)
	add_child(table)
	for side in [1, 0, -1]:
		if side == 0:
			var help = Button.new()
			help.name = "ClassificationHelp"; help.text = "ⓘ 着手"
			help.custom_minimum_size.x = 104
			control_style(help)
			help.size_flags_horizontal = Control.SIZE_FILL
			help.pressed.connect(ui.show_classifications)
			table.add_child(help)
		else:
			var heading = ui.label(Phases.player_caption(report.player_name(side), side), 13)
			heading.name = "StatisticsPlayer" + str(side)
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			heading.autowrap_mode = TextServer.AUTOWRAP_OFF
			heading.clip_text = true
			heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			heading.tooltip_text = heading.text
			heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			heading.custom_minimum_size.y = 32
			heading.add_theme_font_override("font", Design.heading_font(ui.app.text_font))
			table.add_child(heading)
	for category in report.CATEGORIES:
		cells[category] = []
		for side in [1, 0, -1]:
			var item = Button.new()
			control_style(item)
			item.pressed.connect(func(): ui.select_report_category(0, category))
			item.accessibility_name = "%s，先手 %d 手，后手 %d 手，定位下一处" % [category, report.summary(1).counts.get(category, 0), report.summary(-1).counts.get(category, 0)]
			if side == 0:
				item.name = "ClassificationRow_" + category
				item.custom_minimum_size.x = 104
				item.size_flags_horizontal = Control.SIZE_FILL
				var center = CenterContainer.new()
				center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				center.mouse_filter = Control.MOUSE_FILTER_IGNORE
				item.add_child(center)
				var content = HBoxContainer.new()
				content.mouse_filter = Control.MOUSE_FILTER_IGNORE
				content.add_theme_constant_override("separation", 3)
				center.add_child(content)
				content.add_child(ui.classification_icon(category, 22))
				var caption = ui.label(category, 14)
				caption.name = "ClassificationName"
				caption.autowrap_mode = TextServer.AUTOWRAP_OFF
				caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
				content.add_child(caption)
			else:
				item.name = "ClassificationCount%d_%s" % [side, category]
				item.text = str(report.summary(side).counts.get(category, 0))
				item.add_theme_font_override("font", Design.heading_font(ui.app.text_font))
			table.add_child(item)
			cells[category].append(item)
	for side in [1, 0, -1]:
		if side == 0:
			table.add_child(Control.new())
			continue
		var pie = Pie.new()
		pie.name = "SentePie" if side == 1 else "GotePie"
		pie.side = side
		pie.counts = report.summary(side).counts
		pie.selected.connect(func(group): show_insight(side, group))
		table.add_child(pie)
		pies.append(pie)
	insight = PanelContainer.new()
	insight.name = "QualityInsight"
	insight.custom_minimum_size.y = 68
	insight.add_theme_stylebox_override("panel", Design.box(Color("101215cc"), 5, 0))
	add_child(insight)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	insight.add_child(row)
	insight_accent = ColorRect.new()
	insight_accent.custom_minimum_size = Vector2(4, 68)
	row.add_child(insight_accent)
	var text_inset = MarginContainer.new()
	text_inset.add_theme_constant_override("margin_top", 9)
	text_inset.add_theme_constant_override("margin_bottom", 9)
	text_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_inset)
	var texts = VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	text_inset.add_child(texts)
	insight_title = ui.label("", 14)
	insight_body = ui.label("", 12)
	insight_body.add_theme_color_override("font_color", Color("d9cab4"))
	texts.add_child(insight_title); texts.add_child(insight_body)
	var percent_inset = MarginContainer.new()
	percent_inset.add_theme_constant_override("margin_right", 10)
	row.add_child(percent_inset)
	insight_percent = ui.label("", 20)
	insight_percent.autowrap_mode = TextServer.AUTOWRAP_OFF
	percent_inset.add_child(insight_percent)
	insight.hide()
	expand = Button.new()
	expand.name = "ExpandReportMoves"
	expand.text = "⌄"
	expand.tooltip_text = "展开全部着手分类与质量饼图"
	expand.accessibility_name = expand.tooltip_text
	control_style(expand)
	expand.add_theme_font_size_override("font_size", 24)
	expand.custom_minimum_size.y = 40
	expand.pressed.connect(func(): ui.report_moves_expanded = true; refresh_visibility())
	add_child(expand)
	refresh_visibility()

func refresh_visibility() -> void:
	var counts = [report.summary(1).counts, report.summary(-1).counts]
	for category in cells:
		for cell in cells[category]: cell.visible = Quality.row_visible(category, ui.report_moves_expanded, counts)
	for pie in pies: pie.visible = ui.report_moves_expanded
	expand.visible = not ui.report_moves_expanded
	if not ui.report_moves_expanded: insight.hide()

func show_insight(side: int, group: int) -> void:
	var values = Quality.weights(report.summary(side).counts)
	insight_title.text = ("先手" if side == 1 else "后手") + " · " + Quality.TITLES[group]
	insight_body.text = Quality.BODIES[group] + " 图中为加权占比。"
	insight_percent.text = "%.1f%%" % Quality.percentage(values, group)
	insight_percent.add_theme_color_override("font_color", Quality.COLORS[group])
	insight_accent.color = Quality.COLORS[group]
	insight.accessibility_name = insight_title.text + "，" + insight_percent.text + "，" + insight_body.text
	insight.show()
	if is_instance_valid(insight_tween): insight_tween.kill()
	insight.modulate.a = 0
	insight_tween = create_tween()
	insight_tween.tween_property(insight, "modulate:a", 1.0, 0.14)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree() and ui.page_name == "report": ui.page_scroll.ensure_control_visible(insight)
