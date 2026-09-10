extends Control
signal selected(group: int)
const Quality = preload("res://scripts/shogi_report_quality.gd")
var counts: Dictionary = {}
var active: int = -1
var side: int = 1
var ranges: Array = []
var rotation_angle = -PI / 2
var reveal: float = 1
var reveal_tween: Tween
var velocity: float = 0
var pointer: int = -2
var press_position = Vector2.ZERO
var last_angle: float = 0
var last_time: int = 0
var dragged: bool = false

func _ready() -> void:
	custom_minimum_size.y = 200
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	visibility_changed.connect(func():
		if is_visible_in_tree(): animate_reveal()
		else: pointer = -2; velocity = 0
	)
	resized.connect(func(): pointer = -2; velocity = 0; queue_redraw())
	refresh_description()
	if is_visible_in_tree(): animate_reveal()

func geometry() -> Dictionary:
	# PieChart's 5/10/5/5 offsets and 5 px selection reserve.
	return {"center": Vector2(size.x / 2, (size.y + 5) / 2), "radius": maxf(0, minf(size.x - 10, size.y - 15) / 2 - 5)}

func refresh_description() -> void:
	var values = Quality.weights(counts)
	var parts = []
	for i in range(3): parts.append("%s %.1f%%" % [Quality.TITLES[i], Quality.percentage(values, i)])
	accessibility_name = ("先手" if side == 1 else "后手") + "着手质量，加权占比；" + "，".join(parts)
	tooltip_text = accessibility_name + "。左右键选择，拖动旋转。"

func animate_reveal() -> void:
	if is_instance_valid(reveal_tween): reveal_tween.kill()
	reveal = 0
	reveal_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	reveal_tween.tween_method(func(value): reveal = value; queue_redraw(), 0.0, 1.0, 0.8)

func finish_reveal() -> void:
	if is_instance_valid(reveal_tween): reveal_tween.kill()
	reveal = 1
	queue_redraw()

func _process(delta: float) -> void:
	if pointer != -2 or absf(velocity) < 0.001 or not is_visible_in_tree(): return
	rotation_angle = wrapf(rotation_angle + velocity * delta, -PI, PI)
	velocity *= pow(0.9, delta * 60)
	queue_redraw()

func wedge(center: Vector2, outer: float, inner: float, start: float, sweep: float, color: Color) -> void:
	if sweep <= 0 or outer <= inner: return
	var points = PackedVector2Array()
	var steps = maxi(3, ceili(sweep * outer / 3))
	for i in range(steps + 1): points.append(center + Vector2.from_angle(start + sweep * i / steps) * outer)
	for i in range(steps, -1, -1): points.append(center + Vector2.from_angle(start + sweep * i / steps) * inner)
	draw_colored_polygon(points, color)

func _draw() -> void:
	var geo = geometry()
	var center: Vector2 = geo.center
	var radius: float = geo.radius
	if radius <= 0: return
	var values = Quality.weights(counts)
	var total: int = values.reduce(func(a, b): return a + b, 0)
	ranges.clear()
	var angle: float = rotation_angle
	var positive: int = values.filter(func(value): return value > 0).size()
	for group in range(3):
		if values[group] <= 0: continue
		var sweep = TAU * values[group] / total
		ranges.append({"start": angle, "sweep": sweep, "group": group})
		var outer = radius + (5 if active == group else 0)
		var gap = minf(3.0 / outer, sweep * 0.8) if positive > 1 else 0.0
		wedge(center, outer, radius * 0.5, rotation_angle + (angle - rotation_angle) * reveal + gap / 2, maxf(0, sweep * reveal - gap), Quality.COLORS[group])
		angle += sweep
	if total == 0: draw_arc(center, radius * 0.75, 0, TAU, 96, Color("ffffff30"), radius * 0.5, true)
	# Reference's white hole and translucent 61% ring.
	draw_circle(center, radius * 0.61, Color(1, 1, 1, 105.0 / 255), true, -1, true)
	draw_circle(center, radius * 0.5, Color.WHITE, true, -1, true)
	if reveal >= 1:
		var font = get_theme_default_font()
		for segment in ranges:
			var caption = "%.1f" % Quality.percentage(values, segment.group)
			var at: Vector2 = center + Vector2.from_angle(segment.start + segment.sweep / 2) * radius * 0.75
			at += Vector2(-font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x / 2, font.get_ascent(10) / 2)
			draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.BLACK)
	if has_focus(): draw_arc(center, radius + 7, 0, TAU, 96, Color("58a6ff"), 1.5, true)

func hit_group(at: Vector2) -> int:
	var geo = geometry()
	var offset: Vector2 = at - geo.center
	if offset.length() <= geo.radius * 0.5: return -1
	var values = Quality.weights(counts)
	var start = 0.0
	var angle = fposmod(offset.angle() - rotation_angle, TAU)
	for group in range(3):
		var sweep = TAU * Quality.percentage(values, group) / 100
		if values[group] > 0 and angle >= start and angle < start + sweep:
			return group if offset.length() <= geo.radius + (5 if active == group else 0) else -1
		start += sweep
	return -1

func choose(group: int) -> void:
	if group < 0 or group > 2 or Quality.weights(counts)[group] <= 0: return
	finish_reveal()
	active = group
	selected.emit(group)
	queue_redraw()

func pointer_down(id: int, at: Vector2) -> void:
	if pointer != -2 or hit_group(at) < 0: return
	pointer = id; press_position = at; dragged = false; velocity = 0
	last_angle = (at - geometry().center).angle(); last_time = Time.get_ticks_msec()
	finish_reveal(); grab_focus(); accept_event()

func pointer_move(id: int, at: Vector2) -> void:
	if pointer != id: return
	dragged = dragged or at.distance_to(press_position) > 8
	var angle = (at - geometry().center).angle()
	var delta_angle = wrapf(angle - last_angle, -PI, PI)
	var now = Time.get_ticks_msec()
	if dragged:
		rotation_angle += delta_angle
		velocity = clampf(delta_angle / maxf(0.016, (now - last_time) / 1000.0), -12, 12)
	last_angle = angle; last_time = now
	queue_redraw(); accept_event()

func pointer_up(id: int, at: Vector2, canceled: bool = false) -> void:
	if pointer != id: return
	pointer = -2
	if canceled: velocity = 0
	elif not dragged: choose(hit_group(at))
	elif Time.get_ticks_msec() - last_time > 100: velocity = 0
	accept_event()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: pointer_down(-1, event.position)
		else: pointer_up(-1, event.position)
	elif event is InputEventMouseMotion: pointer_move(-1, event.position)
	elif event is InputEventScreenTouch:
		if event.pressed: pointer_down(event.index, event.position)
		else: pointer_up(event.index, event.position, event.canceled)
	elif event is InputEventScreenDrag: pointer_move(event.index, event.position)
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END]:
		var available = []
		var values = Quality.weights(counts)
		for i in range(3):
			if values[i] > 0: available.append(i)
		if not available.is_empty():
			var index = available.find(active)
			if event.keycode == KEY_HOME: index = 0
			elif event.keycode == KEY_END: index = available.size() - 1
			else: index = posmod(index + (1 if event.keycode == KEY_RIGHT else -1), available.size())
			choose(available[index]); accept_event()
