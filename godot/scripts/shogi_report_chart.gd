extends Control
signal selected(ply: int)
const Model = preload("res://scripts/shogi_report_chart_model.gd")
const Design = preload("res://scripts/shogi_design.gd")
const SENTE_BACKGROUND = Color("323a42")
const GOTE_BACKGROUND = Color("090c10")
const ZERO_COLOR = Color("f8f1e691")
const PHASE_COLOR = Color("f8f1e6dc")
const HIGHLIGHT = Color("58a6ffaa")
var samples: Array = []
var rows: Array = []
var phases: Array = []
var total_plies: int = 0
var accent = Color("58a6ff")
var active: int = -1
var markers: Array = []
var textures: Dictionary = {}
var reveal_time = 0.0
var reveal = 0.0
var pointer_down = false
var down_position = Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(100, 168)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	accessibility_name = "局面评分图；左右方向键选择着手，Home 和 End 跳至首尾"
	resized.connect(refresh)
	refresh()
	set_process(samples.size() > 1)
	if samples.size() <= 1: reveal = 1.0

func _process(delta: float) -> void:
	reveal_time = minf(0.8, reveal_time + delta)
	# The reference configures 800 ms with its cubic-in interpolator.
	reveal = pow(reveal_time / 0.8, 3)
	if reveal_time >= 0.8: set_process(false)
	queue_redraw()

func complete_reveal() -> void:
	reveal_time = 0.8
	reveal = 1.0
	set_process(false)
	queue_redraw()

func point_for(ply: int) -> Vector2:
	if ply < 0 or ply >= samples.size(): return Vector2.ZERO
	return Model.point(ply, samples[ply].score, Model.plot_rect(size), maxi(total_plies, samples.size() - 1))

func refresh() -> void:
	markers = Model.markers(rows, samples, size, maxi(total_plies, samples.size() - 1))
	for entry in markers:
		if not textures.has(entry.icon): textures[entry.icon] = load("res://assets/reference-ui/" + entry.icon + ".svg")
	queue_redraw()

func visible_markers() -> Array:
	return markers.filter(func(entry): return entry.ply <= (samples.size() - 1) * reveal)

func _draw() -> void:
	var plot = Model.plot_rect(size)
	var middle = plot.get_center().y
	# CustomLineChart paints its large target zones before the plot renderer;
	# the view clips them, so the fill also covers the vertical plot insets.
	draw_rect(Rect2(Vector2(plot.position.x, 0), Vector2(plot.size.x, middle)), SENTE_BACKGROUND)
	draw_rect(Rect2(Vector2(plot.position.x, middle), Vector2(plot.size.x, size.y - middle)), GOTE_BACKGROUND)
	draw_line(Vector2(plot.position.x, middle), Vector2(plot.end.x, middle), ZERO_COLOR, 1.1, true)
	for segment in phases:
		if segment.start <= 1: continue
		var x = Model.point(segment.start - 0.5, 0, plot, maxi(1, total_plies)).x
		draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), PHASE_COLOR, 1.1, 3, true)
	if samples.size() > 1:
		var last = (samples.size() - 1) * reveal
		var end = floori(last)
		var points = PackedVector2Array()
		for ply in range(end + 1): points.append(point_for(ply))
		if end + 1 < samples.size() and last > end: points.append(point_for(end).lerp(point_for(end + 1), last - end))
		if points.size() > 1: draw_polyline(points, accent, 2.2, true)
	if active >= 0 and active < samples.size():
		var point = point_for(active)
		draw_line(Vector2(point.x, plot.position.y), Vector2(point.x, plot.end.y), HIGHLIGHT, 1, true)
		draw_line(Vector2(plot.position.x, point.y), Vector2(plot.end.x, point.y), HIGHLIGHT, 1, true)
	for entry in visible_markers():
		if entry.connector: draw_line(entry.line_start, entry.line_end, Color("d2dae28c"), 0.6, true)
		var icon: Texture2D = textures.get(entry.icon)
		if icon != null: draw_texture_rect(icon, Rect2(entry.center - Vector2.ONE * Model.ICON_SIZE / 2, Vector2.ONE * Model.ICON_SIZE), false)
	var font = Design.heading_font(get_theme_default_font())
	var baseline = plot.position.y + font.get_ascent(10) + 2
	draw_string(font, Vector2(plot.position.x + 4, baseline), "先手", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f8f1e6"))
	baseline = plot.end.y - font.get_descent(10) - 2 - 22
	draw_string(font, Vector2(plot.position.x + 4, baseline), "后手", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("f8f1e6"))
	if has_focus():
		var focus = Design.box(Color.TRANSPARENT, 4, 0)
		focus.border_color = accent
		focus.set_border_width_all(1)
		draw_style_box(focus, Rect2(Vector2.ZERO, size))

func choose(ply: int) -> void:
	if samples.is_empty(): return
	complete_reveal()
	ply = clampi(ply, 0, samples.size() - 1)
	if active == ply: return
	active = ply
	accessibility_name = "局面评分图 · 第 %d 手" % ply
	selected.emit(ply)
	queue_redraw()

func choose_point(position: Vector2, prefer_marker: bool) -> void:
	if prefer_marker:
		var marker = Model.marker_at(position, visible_markers())
		if marker >= 0: choose(marker); return
	var plot = Model.plot_rect(size)
	choose(roundi((position.x - plot.position.x) / plot.size.x * maxi(total_plies, samples.size() - 1)))

func _gui_input(event: InputEvent) -> void:
	if samples.is_empty(): return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: choose(maxi(0, active - 1))
			KEY_RIGHT: choose(maxi(0, active) + 1)
			KEY_HOME: choose(0)
			KEY_END: choose(samples.size() - 1)
			_: return
		accept_event()
	elif event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			pointer_down = true
			down_position = event.position
			grab_focus()
			choose_point(event.position, true)
		elif pointer_down:
			pointer_down = false
			choose_point(event.position, event.position.distance_squared_to(down_position) < Model.ICON_SIZE * Model.ICON_SIZE)
		accept_event()
	elif pointer_down and (event is InputEventScreenDrag or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		choose_point(event.position, false)
		accept_event()
