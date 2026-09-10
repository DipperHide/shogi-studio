extends Control
signal selected(ply: int)
var samples: Array = []
var accent = Color("58a6ff")
var active: int = -1
var phases: Array = []
var total_plies: int = 0
const Metrics = preload("res://scripts/shogi_report_metrics.gd")

func point_for(ply: int) -> Vector2:
	return Vector2(8 + ply * (size.x - 16) / maxf(1, maxf(total_plies, samples.size() - 1)), size.y * (0.5 - 0.46 * clampf(samples[ply].score / Metrics.CP_SCALE / 1000.0, -1, 1)))

func _ready() -> void:
	custom_minimum_size = Vector2(100, 150)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _draw() -> void:
	draw_style_box(preload("res://scripts/shogi_design.gd").box(Color(0, 0, 0, 0.2), 8, 0), Rect2(Vector2.ZERO, size))
	if samples.size() < 2: return
	var points = PackedVector2Array()
	for i in range(samples.size()): points.append(point_for(i))
	var middle = size.y / 2
	for i in range(1, points.size()):
		var a = points[i - 1]
		var b = points[i]
		if is_equal_approx(a.y, middle) and is_equal_approx(b.y, middle): continue
		if (a.y - middle) * (b.y - middle) < 0:
			var crossing = Vector2(lerpf(a.x, b.x, (middle - a.y) / (b.y - a.y)), middle)
			fill_area(PackedVector2Array([Vector2(a.x, middle), a, crossing]), Color("e9edf2aa") if a.y < middle else Color("050607d9"))
			fill_area(PackedVector2Array([crossing, b, Vector2(b.x, middle)]), Color("e9edf2aa") if b.y < middle else Color("050607d9"))
		else:
			var polygon = PackedVector2Array([Vector2(a.x, middle)])
			if not is_equal_approx(a.y, middle): polygon.append(a)
			polygon.append(b)
			if not is_equal_approx(b.y, middle): polygon.append(Vector2(b.x, middle))
			fill_area(polygon, Color("e9edf2aa") if minf(a.y, b.y) < middle else Color("050607d9"))
	draw_line(Vector2(8, middle), Vector2(size.x - 8, middle), Color(1, 1, 1, 0.22))
	for segment in phases:
		if segment.start == 1: continue
		var x = 8 + (segment.start - 0.5) / maxf(1, total_plies) * (size.x - 16)
		draw_dashed_line(Vector2(x, 4), Vector2(x, size.y - 4), Color(1, 1, 1, 0.35), 1, 3)
	draw_polyline(points, accent, 2.5, true)
	if active >= 0 and active < points.size():
		draw_line(Vector2(points[active].x, 0), Vector2(points[active].x, size.y), Color.WHITE, 1)
		draw_circle(points[active], 4, Color.WHITE)

func fill_area(polygon: PackedVector2Array, color: Color) -> void:
	# Each segment is a convex triangle or trapezoid. Direct triangles avoid the
	# polygon tessellator rejecting near-zero slivers at score crossings on long games.
	for i in range(1, polygon.size() - 1):
		draw_primitive(PackedVector2Array([polygon[0], polygon[i], polygon[i + 1]]), PackedColorArray([color]), PackedVector2Array())

func _gui_input(event: InputEvent) -> void:
	if samples.is_empty(): return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT) or event is InputEventScreenDrag:
		active = clampi(roundi((event.position.x - 8) / maxf(1, size.x - 16) * maxf(total_plies, samples.size() - 1)), 0, maxi(0, samples.size() - 1))
		selected.emit(active)
		queue_redraw()
		accept_event()
