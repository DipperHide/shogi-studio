extends Control
signal selected(side: int, phase: int)
signal accuracy_selected(side: int)
signal acpl_selected(side: int)
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Design = preload("res://scripts/shogi_design.gd")
var report
var show_cpl: bool = false
var hits: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(100, 242)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "点击阶段评分查看阶段明细；点击准确率查看每手表现。"

func centered(text: String, rect: Rect2, font_size: int, color: Color) -> void:
	var font = get_theme_default_font()
	if rect.size.x < 16: return
	var caption = text
	while caption.length() > 1 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 4:
		caption = caption.left(caption.length() - 2) + "…"
	var width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(rect.position.x + (rect.size.x - width) / 2, rect.position.y + (rect.size.y - font.get_height(font_size)) / 2 + font.get_ascent(font_size)), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	hits.clear()
	if report == null or report.game == null: return
	var phases: Array = report.phases()
	var total: int = report.game.moves.size()
	if total < 1: return
	draw_line(Vector2(8, 0), Vector2(size.x - 8, 0), Color(1, 1, 1, 0.18))
	draw_rect(Rect2(8, 6, size.x - 16, 22), Color(0, 0, 0, 0.18))
	for segment in phases:
		var bounds = Metrics.span(segment, total)
		var rect = Rect2(8 + bounds.x / total * (size.x - 16), 6, (bounds.y - bounds.x) / total * (size.x - 16), 22)
		centered(segment.name, rect, 12, Color("fff6e6"))
	for side_index in range(2):
		var side = 1 if side_index == 0 else -1
		var y = 32 + side_index * 104
		var group = Rect2(8, y, size.x - 16, 88)
		draw_style_box(Design.box(Color("ffffff0b"), 6, 0), group)
		for segment in phases:
			var stats: Dictionary = report.phase_summary(side, segment)
			var color = Metrics.accuracy_color(stats.accuracy) if stats.has_accuracy else Color("8d6e63")
			var bounds = Metrics.span(segment, total)
			var rect = Rect2(8 + bounds.x / total * (size.x - 16) + 1, y, maxf(1, (bounds.y - bounds.x) / total * (size.x - 16) - 2), 34)
			draw_style_box(Design.box(Color(color, 92.0 / 255), 5, 0), rect)
			centered("%.1f" % stats.accuracy if stats.has_accuracy else "定式" if stats.count > 0 and stats.book == stats.count else "—", rect, 14, Color("fff8ed"))
			hits.append({"rect": rect, "side": side, "phase": segment.type})
		var name = ("☗ " if side == 1 else "☖ ") + report.player_name(side)
		if report.game.winner == side: name += " · 胜"
		centered(name, Rect2(14, y + 36, size.x - 28, 24), 12, Color("fff8ed"))
		var overall: Dictionary = report.summary(side)
		var caption = "准确率 %.1f" % overall.accuracy if overall.has_accuracy else "准确率 —"
		var color = Metrics.accuracy_color(overall.accuracy) if overall.has_accuracy else Color("8d6e63")
		var captions=[caption]
		if show_cpl: captions.append("ACPL %d" % roundi(overall.average_loss) if overall.has_accuracy else "ACPL —")
		var widths=[]
		var total_width=0.0
		for text in captions:
			var width=get_theme_default_font().get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x+18
			widths.append(width)
			total_width+=width
		var scale=minf(1,(size.x-36)/maxf(1,total_width))
		total_width=total_width*scale+(6 if show_cpl else 0)
		var x=(size.x-total_width)/2
		for i in range(captions.size()):
			var chip=Rect2(x,y+61,widths[i]*scale,26)
			draw_style_box(Design.box(Color(color,102.0/255) if i==0 else Color("ffffff16"),6,0),chip)
			centered(captions[i],chip,14 if i==0 else 12,Color("fff8ed"))
			hits.append({"rect":chip,"side":side,"phase":0,"kind":"accuracy" if i==0 else "acpl"})
			x+=chip.size.x+6

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		for hit in hits:
			if hit.rect.has_point(event.position):
				if hit.get("kind","")=="accuracy": accuracy_selected.emit(hit.side)
				elif hit.get("kind","")=="acpl": acpl_selected.emit(hit.side)
				else: selected.emit(hit.side, hit.phase)
				accept_event()
				return
