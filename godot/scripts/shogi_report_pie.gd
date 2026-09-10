extends Control
signal selected(category: String)
const Report = preload("res://scripts/shogi_report.gd")
var counts: Dictionary = {}
var active: String = ""
var text_color = Color.WHITE
var ranges: Array = []

func _ready() -> void:
	custom_minimum_size = Vector2(120, 200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _draw() -> void:
	var center = size / 2
	var radius = minf(size.x, size.y) * 0.43
	var total = 0
	for value in counts.values(): total += int(value)
	ranges.clear()
	var angle = -PI / 2
	if total == 0: draw_arc(center, radius, 0, TAU, 80, Color(0.5, 0.5, 0.5, 0.3), radius * 0.44, true)
	for category in Report.CATEGORIES:
		var count = int(counts.get(category, 0))
		if count == 0: continue
		var end = angle + TAU * count / total
		ranges.append({"start": angle, "end": end, "category": category})
		var points = PackedVector2Array([center])
		for i in range(61): points.append(center + Vector2.from_angle(lerpf(angle, end, i / 60.0)) * radius)
		draw_colored_polygon(points, Report.category_color(category).lightened(0.2) if category == active else Report.category_color(category))
		angle = end
	var font = get_theme_default_font()
	var caption = str(total) + " 手"
	var width = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(center.x - width / 2, size.y - 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, text_color)

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		var offset: Vector2 = event.position - size / 2
		if offset.length() > minf(size.x, size.y) * 0.43: return
		var angle = offset.angle()
		if angle < -PI / 2: angle += TAU
		for segment in ranges:
			if angle >= segment.start and angle <= segment.end:
				active = segment.category
				selected.emit(active)
				queue_redraw()
				accept_event()
				return
