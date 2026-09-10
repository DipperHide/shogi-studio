extends Control
var app
var compact: bool = false
var home: bool = false
var home_button: Button
var picture = preload("res://assets/brand/ai-home.png")

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 174 if home else 136 if compact else 190
	resized.connect(queue_redraw)
	resized.connect(layout_action)

func layout_action() -> void:
	if is_instance_valid(home_button):
		home_button.position = Vector2(18, size.y - 66)
		home_button.size = Vector2(minf(150, size.x * 0.46), 48)

func _draw() -> void:
	if app == null: return
	draw_style_box(app.Design.box(Color("fff4e3"), 16, 0), Rect2(Vector2.ZERO, size))
	# Limit the artwork's aspect ratio so wide desktop cards retain the full face.
	var art_width = minf(size.x, size.y * 2.1)
	var art_left = size.x - art_width
	var source = Rect2(Vector2.ZERO, Vector2(picture.get_width(), minf(picture.get_height(), picture.get_width() * size.y / art_width)))
	draw_texture_rect_region(picture, Rect2(Vector2(art_left, 0), Vector2(art_width, size.y)), source)
	if art_left > 0:
		var cream = Color("fff4e3")
		var clear = Color(cream, 0)
		draw_polygon(PackedVector2Array([Vector2(art_left, 0), Vector2(art_left + 32, 0), Vector2(art_left + 32, size.y), Vector2(art_left, size.y)]), PackedColorArray([cream, clear, clear, cream]))
	var font: Font = app.Design.heading_font(app.text_font)
	var heading: String = app.t("一起进步吧") if compact else app.t("来下一局吧")
	var font_size = 20 if size.x < 380 else 25
	var title_y = size.y * 0.30 if home else size.y * 0.38
	draw_string(font, Vector2(18, title_y), heading, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.47, font_size, Color("283c58"))
	draw_string(font, Vector2(18, title_y + 27), app.t("每一步，都是新的可能。"), HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.49, 11, Color("65768a"))
