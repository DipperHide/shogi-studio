extends Button
var piece: int = 0
var face_font = preload("res://assets/fonts/NotoSerifJP.ttf")

func _get_minimum_size() -> Vector2:
	return Vector2(28, 34)

func _draw() -> void:
	if piece == 0: return
	var value: String = preload("res://scripts/shogi_rules.gd").NAMES[absi(piece)]
	var font_size = 17 if value.length() == 1 else 12
	var extent = face_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_set_transform(size / 2, PI if piece < 0 else 0)
	draw_string(face_font, Vector2(-extent.x / 2, (face_font.get_ascent(font_size) - face_font.get_descent(font_size)) / 2), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("962d21") if absi(piece) > 8 else Color("2a1d12"))
	draw_set_transform(Vector2.ZERO)
