extends Control
var busy = false
var cached = false
var color = Color("4b9bff")
var icon: Texture2D

func _ready() -> void:
	custom_minimum_size = Vector2(24, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(busy)

func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()

func _draw() -> void:
	var center = size / 2
	if busy:
		var angle = float(Time.get_ticks_msec() % 1100) / 1100 * TAU
		draw_arc(center, 9, angle, angle + TAU * 0.72, 28, color, 2, true)
	elif cached and icon != null: draw_texture_rect(icon, Rect2(center - Vector2(10,10), Vector2(20,20)), false, color)
