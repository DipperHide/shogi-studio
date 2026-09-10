extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var points = PackedVector2Array()
	for p in [Vector2(0.025,0),Vector2(1,0),Vector2(.975,.86),Vector2(.53,.86),Vector2(.505,1),Vector2(.482,.86),Vector2(0,.86)]:
		points.append(p*size)
	draw_colored_polygon(points,Color("eff0e8"))
	points.append(points[0])
	draw_polyline(points,Color("ffffff"),2.5,true)
