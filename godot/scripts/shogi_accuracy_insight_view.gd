extends VBoxContainer
const Insight=preload("res://scripts/shogi_accuracy_insight.gd")
const Move=preload("res://scripts/shogi_report_move.gd")
var ui
var model: Dictionary
var chart
var chart_scroll: ScrollContainer
var selection: VBoxContainer

func build(menu, side: int) -> void:
	ui=menu
	model=Insight.build(ui.report,side)
	name="AccuracyInsight"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	var side_name="先手" if side==1 else "后手"
	var player=ui.label(("☗ " if side==1 else "☖ ")+side_name+(" · "+model.player if model.player!=side_name else ""),15)
	player.name="AccuracyInsightPlayer"
	player.max_lines_visible=2
	player.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	player.tooltip_text=player.text
	add_child(player)
	var hero=ui.report_panel(self,Color("192028ed"),Color("58a6ff66"),14)
	var value=ui.label(ui.accuracy_text(model.overall),30)
	value.name="AccuracyInsightValue"
	value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(value)
	var caption=ui.label("根据本局已分析的着手",11)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hero.add_child(caption)
	add_child(ui.label("准确率衡量你的着手与引擎选择的接近程度。显著改变取胜机会的决定，通常比胜负已明显时的波动影响更大。",13))
	add_child(ui.label("每手表现",12))
	var panel=ui.report_panel(self,Color("192028ed"),Color("58a6ff66"),10)
	var total=ui.label("整局 "+ui.accuracy_text(model.overall),11)
	total.name="AccuracyOverallLineLabel"
	total.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	total.add_theme_color_override("font_color",Color("58a6ff"))
	panel.add_child(total)
	if model.points.is_empty():
		var empty=ui.label("本方暂无可计分着手。定式与唯一合法着不计入准确率。",13)
		empty.name="AccuracyChartEmpty"
		empty.custom_minimum_size.y=96
		empty.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		empty.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(empty)
	else:
		chart_scroll=ScrollContainer.new()
		chart_scroll.name="AccuracyChartScroll"
		chart_scroll.custom_minimum_size.y=144
		chart_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_NEVER
		chart_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(chart_scroll)
		chart=preload("res://scripts/shogi_accuracy_chart.gd").new()
		chart.name="AccuracyDeviationChart"
		chart.points=model.points
		chart.overall=model.overall.accuracy
		chart.active_ply=model.impact.get("ply",-1)
		chart_scroll.add_child(chart)
		chart.point_selected.connect(select_point)
		selection=VBoxContainer.new()
		selection.name="AccuracySelectedMove"
		panel.add_child(selection)
		panel.add_child(ui.label("每条线代表一手已分析着手，向下越深表示与引擎最佳选择偏离越大。虚线为整局准确率。点击棋点查看详情，横向滑动查看更多。",12))
	var note=ui.report_panel(self,Color("00000059"),Color("ffffff38"),11)
	note.add_child(ui.label("局面复杂程度、对局长度与搜索深度都会影响结果。比较不同对局的准确率时，应结合具体着手，不宜单凭一局判断棋力。",13))
	ui.style_report_buttons()
	ui.fit_wood_dialog()

func select_point(index: int) -> void:
	if index<0 or index>=model.points.size(): return
	for child in selection.get_children(): selection.remove_child(child); child.queue_free()
	var point: Dictionary=model.points[index]
	var color=ui.report.category_color(point.category)
	var card=PanelContainer.new()
	card.name="AccuracySelectedMoveCard"
	card.custom_minimum_size.y=88
	var style=ui.Design.box(Color("1d252dd9"),8,0)
	style.border_color=Color("58a6ff66")
	style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel",style)
	selection.add_child(card)
	var hit=Button.new()
	hit.name="OpenAccuracyMoveBoard"
	for state in ["normal","hover","pressed","focus"]: hit.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	hit.pressed.connect(func(): ui.open_report_position(point.ply))
	card.add_child(hit)
	var row=HBoxContainer.new()
	row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",10)
	card.add_child(row)
	var accent=ColorRect.new()
	accent.color=color
	accent.mouse_filter=Control.MOUSE_FILTER_IGNORE
	accent.custom_minimum_size.x=4
	row.add_child(accent)
	var margin=MarginContainer.new()
	margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_top",10)
	margin.add_theme_constant_override("margin_bottom",10)
	margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(margin)
	var body=VBoxContainer.new()
	body.mouse_filter=Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation",2)
	margin.add_child(body)
	var title=ui.label("第 %d 手 · %s%s" % [point.ply,point.label,Move.SUFFIX.get(point.category,"")],14)
	title.name="AccuracyMoveTitle"
	title.autowrap_mode=TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(title)
	var category=ui.label(point.category,11)
	category.add_theme_color_override("font_color",color)
	body.add_child(category)
	var score=ui.label("本手准确率："+Insight.accuracy_label(point),12)
	score.name="AccuracyMoveScore"
	body.add_child(score)
	var evaluation=ui.label(Insight.engine_label(point),12)
	evaluation.name="AccuracyMoveEngine"
	body.add_child(evaluation)
	var arrow=ui.label("›",24)
	arrow.custom_minimum_size.x=28
	arrow.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)
	hit.tooltip_text=title.text+" · "+point.category+"\n"+score.text+"\n"+evaluation.text+"\n点击在棋盘查看"
	var x=chart.point_for(index).x
	if x<chart_scroll.scroll_horizontal+34: chart_scroll.scroll_horizontal=maxi(0,roundi(x-40))
	elif x>chart_scroll.scroll_horizontal+chart_scroll.size.x-6: chart_scroll.scroll_horizontal=roundi(x-chart_scroll.size.x+12)
	ui.fit_wood_dialog()
