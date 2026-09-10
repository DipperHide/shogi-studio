extends Button
var piece: int = 0
var editor
var square = -1
var palette_piece = false
var face_font = preload("res://assets/fonts/NotoSerifJP.ttf")

func _get_minimum_size() -> Vector2:
	return Vector2.ZERO

func _ready() -> void:
	for style in ["normal", "hover", "pressed", "disabled", "focus"]: add_theme_stylebox_override(style, StyleBoxEmpty.new())

func _draw() -> void:
	if editor == null: return
	var app = editor.menu.app
	var colors: Dictionary = app.palette()
	var selected = palette_piece and piece != 0 and signi(editor.brush) == signi(piece) and editor.Rules.base(editor.brush) == absi(piece)
	var shown: int = editor.brush if selected else piece
	draw_rect(Rect2(Vector2.ZERO, size), Color("51402a") if palette_piece else colors.board)
	if not palette_piece: draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), Color("785735"), false, 1.0)
	if selected or has_focus(): draw_rect(Rect2(Vector2.ZERO, size).grow(-1), colors.accent, false, 2)
	if shown == 0 or (square >= 0 and editor.interaction != null and editor.interaction.dragging and editor.interaction.source_square == square): return
	var edge = minf(size.x, size.y)
	var inverted: bool = (shown < 0) != editor.flipped
	draw_set_transform(size / 2, PI if inverted else 0)
	var points = PackedVector2Array([Vector2(0, -0.43), Vector2(0.29, -0.28), Vector2(0.39, 0.43), Vector2(-0.39, 0.43), Vector2(-0.29, -0.28)])
	for i in range(points.size()): points[i] *= edge
	draw_colored_polygon(points, Color("f4d293"))
	points.append(points[0])
	draw_polyline(points, Color("8c622d"), 0.7, true)
	var ink = Color("962d21") if absi(shown) > 8 else Color("2a1d12")
	if app.preferences.piece_font == "ryoko":
		var name: String = "Ousho" if shown == -8 else app.board_view.FACE_NAMES[absi(shown)]
		var texture: Texture2D = app.board_view.faces.get(name)
		if texture != null:
			var area = Vector2.ONE * edge * 0.74
			var ratio = texture.get_width() / float(texture.get_height())
			area.x = minf(area.x, area.y * ratio); area.y = minf(area.y, area.x / ratio)
			draw_texture_rect(texture, Rect2(-area / 2, area), false, ink)
	else:
		var value: String = "王" if shown == -8 else app.GLYPHS[absi(shown)]
		var font_size = maxi(9, int(edge * (0.36 if value.length() > 1 else 0.56)))
		var extent = face_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(face_font, Vector2(-extent.x / 2, (face_font.get_ascent(font_size) - face_font.get_descent(font_size)) / 2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
	draw_set_transform(Vector2.ZERO)
