extends Button
## A single accessible hit target with a title, supporting text and leading icon.
var title: String
var subtitle: String
var symbol: String = "play"
var app
var filled: bool = false

func _ready() -> void:
	text = title
	clip_text = true
	tooltip_text = title
	custom_minimum_size.y = 76
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	var p: Dictionary = app.palette()
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, app.Design.box(p.soft if state in ["hover", "pressed"] or filled else Color.TRANSPARENT, 12, 12))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	resized.connect(queue_redraw)

func _draw() -> void:
	if app == null: return
	var p: Dictionary = app.palette()
	var y = (size.y - 40) / 2
	draw_style_box(app.Design.box(p.surface if filled else p.soft, 12, 0), Rect2(12, y, 40, 40))
	draw_texture_rect(app.Design.icon(symbol, p.accent), Rect2(22, y + 10, 20, 20), false)
	var available = maxf(40, size.x - 98)
	var font: Font = app.text_font
	# Shaping/ellipsis comes from TextLine, so long record and translated titles fit.
	_draw_line(title, Vector2(64, y + 17), available, 16, p.ink)
	_draw_line(subtitle, Vector2(64, y + 37), available, 12, p.muted)
	draw_string(font, Vector2(size.x - 23, size.y / 2 + 6), "›", HORIZONTAL_ALIGNMENT_LEFT, 16, 22, p.muted)

func _draw_line(value: String, at: Vector2, width: float, font_size: int, color: Color) -> void:
	var line = TextLine.new()
	line.add_string(value, app.Design.heading_font(app.text_font) if font_size >= 16 else app.text_font, font_size)
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.width = width
	line.draw(get_canvas_item(), at - Vector2(0, line.get_line_ascent()), color)
