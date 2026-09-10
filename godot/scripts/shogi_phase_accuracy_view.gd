extends VBoxContainer
## C4573k / dialog_phase_accuracy: compact, read-only phase cards.
const Metrics=preload("res://scripts/shogi_report_metrics.gd")
const BAD=["错失胜机","漏着","失误","不精确"]
var model: Dictionary
var ui

static func snapshot(report,side: int) -> Dictionary:
	var result={"side":side,"player":report.player_name(side),"overall":report.summary(side),"phases":[]}
	for segment in report.phases():
		var stats: Dictionary=report.phase_summary(side,segment)
		if stats.count==0: continue
		var errors=[]
		if stats.has_accuracy:
			for category in BAD:
				var count=int(stats.counts.get(category,0))
				if count>0: errors.append({"category":category,"count":count})
		result.phases.append({"type":segment.type,"name":segment.name,"stats":stats,"errors":errors})
	return result

static func score_text(stats: Dictionary, phase: bool=true) -> String:
	if stats.has_accuracy: return "%.1f" % stats.accuracy
	return "定式" if phase and stats.count>0 and stats.book==stats.count else "—"

static func score_ink(stats: Dictionary) -> Color:
	return Color.BLACK if stats.has_accuracy and stats.accuracy>=80 else Color.WHITE

func pill(text: String, fill: Color, ink: Color, font_size: int=13) -> Label:
	var item=ui.label(text,font_size)
	item.autowrap_mode=TextServer.AUTOWRAP_OFF
	item.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	item.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
	item.add_theme_color_override("font_color",ink)
	var style=ui.Design.box(fill,20,0)
	style.content_margin_left=10; style.content_margin_right=10
	style.content_margin_top=3; style.content_margin_bottom=3
	item.add_theme_stylebox_override("normal",style)
	return item

func score_pill(stats: Dictionary, phase: bool=true) -> Label:
	return pill(score_text(stats,phase),Metrics.accuracy_color(stats.accuracy) if stats.has_accuracy else Color("8d6e63"),score_ink(stats))

func build(menu,side: int) -> void:
	ui=menu
	model=snapshot(ui.report,side)
	name="PhaseAccuracyView"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",8)
	var header=HBoxContainer.new()
	header.add_theme_constant_override("separation",7)
	add_child(header)
	var side_name="先手" if side==1 else "后手"
	var player=ui.label(("☗ " if side==1 else "☖ ")+side_name+(" · "+model.player if model.player!=side_name else ""),15)
	player.name="PhasePlayerName"
	player.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
	player.autowrap_mode=TextServer.AUTOWRAP_OFF
	player.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	player.tooltip_text=player.text
	player.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(player)
	var overall=score_pill(model.overall,false)
	overall.name="PhaseOverallScore"
	header.add_child(overall)
	var cards=VBoxContainer.new()
	cards.name="PhaseCards"
	cards.add_theme_constant_override("separation",8)
	add_child(cards)
	for entry in model.phases:
		var card=PanelContainer.new()
		card.name="Phase"+str(entry.type)
		var style=ui.Design.box(Color("00000059"),8,10)
		style.border_color=Color("ffffff38")
		style.set_border_width_all(1)
		card.add_theme_stylebox_override("panel",style)
		cards.add_child(card)
		var body=VBoxContainer.new()
		body.add_theme_constant_override("separation",7)
		card.add_child(body)
		var title_row=HBoxContainer.new()
		title_row.add_theme_constant_override("separation",8)
		body.add_child(title_row)
		var title=ui.label("%s（%d 手）" % [entry.name,entry.stats.count],16)
		title.name="PhaseTitle"+str(entry.type)
		title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		title.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
		title_row.add_child(title)
		var score=score_pill(entry.stats)
		score.name="PhaseScore"+str(entry.type)
		title_row.add_child(score)
		var description=title.text+" · "+score.text
		if entry.stats.has_accuracy:
			var chips=HFlowContainer.new()
			chips.name="PhaseErrors"+str(entry.type)
			chips.add_theme_constant_override("h_separation",7)
			chips.add_theme_constant_override("v_separation",5)
			body.add_child(chips)
			if entry.errors.is_empty():
				add_error_chip(chips,"","没有失误")
				description+=" · 没有失误"
			else:
				for entry_error in entry.errors:
					add_error_chip(chips,entry_error.category,str(entry_error.count))
					description+=" · %s %d" % [entry_error.category,entry_error.count]
		elif score.text=="—":
			description+=" · 本阶段暂无可计分着手"
		card.tooltip_text=description
	if model.phases.is_empty():
		var empty=ui.label("本方暂无已分析着手。",14)
		empty.name="PhaseEmpty"
		add_child(empty)
	ui.fit_wood_dialog()

func add_error_chip(parent: Control,category: String,count: String) -> void:
	var chip=PanelContainer.new()
	chip.name="PhaseError"+(category if not category.is_empty() else "Clean")
	var style=ui.Design.box(Color("0000004d"),20,0)
	style.content_margin_left=7; style.content_margin_right=9
	style.content_margin_top=3; style.content_margin_bottom=3
	chip.add_theme_stylebox_override("panel",style)
	chip.tooltip_text=category+" "+count if not category.is_empty() else count
	parent.add_child(chip)
	var row=HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	chip.add_child(row)
	if not category.is_empty(): row.add_child(ui.classification_icon(category,16))
	else:
		var icon=TextureRect.new()
		icon.texture=ui.reference_icon("ic_circle_check")
		icon.modulate=Color("46c000")
		icon.custom_minimum_size=Vector2(16,16)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var text=ui.label(count,13)
	text.autowrap_mode=TextServer.AUTOWRAP_OFF
	text.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font))
	row.add_child(text)
