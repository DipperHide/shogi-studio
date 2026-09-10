extends VBoxContainer
var ui
var signature = ""
var content: VBoxContainer
var model: Dictionary = {}

func setup(menu) -> void:
	ui = menu
	name = "GameStory"
	content = ui.report_panel(self, Color("1b1511e6"), Color("f4c76b80"), 14)
	content.get_parent().get_theme_stylebox("panel").content_margin_top=12
	content.get_parent().get_theme_stylebox("panel").content_margin_bottom=12
	content.add_theme_constant_override("separation",0)
	refresh()

func gap(height: int) -> void:
	var space=Control.new()
	space.custom_minimum_size.y=height
	space.mouse_filter=Control.MOUSE_FILTER_IGNORE
	content.add_child(space)

func refresh() -> void:
	model = ui.report.story()
	visible = not model.summary.is_empty()
	var next = JSON.stringify(model) + str(ui.report_story_expanded)
	if signature == next: return
	signature = next
	for child in content.get_children(): content.remove_child(child); child.queue_free()
	if not visible: return
	var summary = ui.label(model.summary, 17)
	summary.name = "GameStorySummary"
	summary.add_theme_constant_override("line_spacing",3)
	content.add_child(summary)
	if model.moments.is_empty(): return
	gap(4)
	var info = ui.compact_button("关键时刻 ⓘ", ui.show_story_info, 32)
	info.name = "StoryMomentsHelp"
	info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_theme_color_override("font_color", Color("d9cab4"))
	info.add_theme_font_size_override("font_size",12)
	info.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
	content.add_child(info)
	gap(14)
	var list = VBoxContainer.new()
	list.name = "StoryMoments"
	list.add_theme_constant_override("separation", 4)
	content.add_child(list)
	for moment in model.moments.slice(0, 10 if ui.report_story_expanded else 1): add_card(list, moment)
	if model.moments.size() > 1:
		gap(6)
		var toggle = ui.compact_button("收起关键时刻" if ui.report_story_expanded else "展开全部关键时刻（%d）" % model.moments.size(), func(): ui.report_story_expanded = not ui.report_story_expanded; refresh(), 32)
		toggle.name = "ToggleStoryMoments"
		toggle.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		toggle.add_theme_font_size_override("font_size",13)
		toggle.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
		var plain=StyleBoxEmpty.new()
		plain.content_margin_left=8; plain.content_margin_right=8
		toggle.add_theme_stylebox_override("normal",plain)
		toggle.add_theme_color_override("font_color", Color("58a6ff"))
		content.add_child(toggle)

func add_card(parent: Control, moment: Dictionary) -> void:
	var panel = PanelContainer.new()
	panel.name = "StoryCard%d" % moment.ply
	var style = ui.Design.box(Color("ffffff0f"), 6, 8)
	style.border_color = Color("ffffff18")
	style.set_border_width_all(1)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var column = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	panel.add_child(column)
	var row = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	row.add_child(ui.classification_icon(moment.category, 18))
	var side=PanelContainer.new()
	side.name="StoryMoveSide"
	side.custom_minimum_size=Vector2(12,12)
	side.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	side.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var side_style=ui.Design.box(Color("f5f1e8") if moment.side==1 else Color("17150f"),3,0)
	side_style.border_color=Color("ffffff4d")
	side_style.set_border_width_all(1)
	side.add_theme_stylebox_override("panel",side_style)
	row.add_child(side)
	var title = ui.label("第 %d 手 · %s" % [moment.ply, moment.label], 13)
	title.name = "StoryMoveTitle"
	title.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", ui.report.category_color(moment.category))
	row.add_child(title)
	add_evaluation(row, moment.before, "Before")
	var arrow = ui.label("→", 14)
	arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(arrow)
	add_evaluation(row, moment.after, "After")
	var explanation = ui.label(moment.reason, 13)
	explanation.name = "StoryMoveReason"
	explanation.add_theme_color_override("font_color", Color("d9cab4"))
	var inset=MarginContainer.new()
	inset.mouse_filter=Control.MOUSE_FILTER_IGNORE
	inset.add_theme_constant_override("margin_left",24)
	inset.add_child(explanation)
	column.add_child(inset)
	var hit = Button.new()
	hit.name = "StoryMoment%d" % moment.ply
	hit.tooltip_text = title.text + " · " + moment.category + "\n" + moment.reason
	hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	hit.add_theme_stylebox_override("hover", ui.Design.box(Color("ffffff0a"), 4, 0))
	hit.add_theme_stylebox_override("pressed", ui.Design.box(Color("58a6ff25"), 4, 0))
	hit.add_theme_stylebox_override("focus", ui.Design.box(Color("58a6ff15"), 4, 0))
	var ply: int = moment.ply
	hit.pressed.connect(func(): ui.select_report_move(ply); ui.page_scroll.ensure_control_visible(ui.report_selection))
	panel.add_child(hit)

func add_evaluation(parent: Control, sample: Dictionary, identity: String) -> void:
	var marker = preload("res://scripts/shogi_report_eval_marker.gd").new()
	marker.sample = sample
	parent.add_child(marker)
	var text: String
	if sample.get("mate", false): text = ("#" if sample.score > 0 else "−#") + str(absi(int(sample.get("mate_distance", 0))))
	else: text = "%+.2f" % (float(sample.score) / 100)
	var score = ui.label(text, 11)
	score.name = "StoryMoveScore" + identity
	score.autowrap_mode = TextServer.AUTOWRAP_OFF
	score.add_theme_color_override("font_color", Color("d9cab4"))
	parent.add_child(score)
