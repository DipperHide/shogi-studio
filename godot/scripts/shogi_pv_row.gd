extends HBoxContainer
## best_engine_line.xml: score, horizontally scrollable moves, play, visibility.
signal preview_requested(index: int)
signal arrow_toggled(index: int, enabled: bool)
const Hint = preload("res://scripts/shogi_move_hint.gd")
var index: int
var ui
var hint_label = Label.new()
var score_label = Label.new()
var move_label = Label.new()
var scroll = ScrollContainer.new()
var play_button = Button.new()
var eye_button = Button.new()

func setup(number: int, menu) -> void:
	index = number
	ui = menu
	name = "EngineLine%d" % index
	custom_minimum_size.y = 33
	add_theme_constant_override("separation", 7)
	score_label.custom_minimum_size.x = 45
	score_label.add_theme_font_size_override("font_size", 15)
	score_label.add_theme_font_override("font", menu.Design.heading_font(menu.app.text_font))
	score_label.add_theme_color_override("font_color", menu.app.palette().accent)
	add_child(score_label)
	hint_label.name = "PromotionHint%d" % index
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color("182018"))
	hint_label.add_theme_stylebox_override("normal", menu.Design.box(Hint.color(index), 4, 4))
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label.hide()
	add_child(hint_label)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	move_label.add_theme_font_size_override("font_size", 16)
	move_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	move_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(move_label)
	for b in [play_button, eye_button]:
		b.custom_minimum_size = Vector2(32, 32)
		b.add_theme_stylebox_override("normal", menu.Design.box(Color.TRANSPARENT, 0, 2))
		b.add_theme_stylebox_override("pressed", menu.Design.box(menu.app.palette().soft, 4, 2))
		b.add_theme_font_size_override("font_size", 19)
		add_child(b)
	menu.set_reference_icon(play_button, "ic_play")
	play_button.tooltip_text = "预览这条候选线路"
	play_button.pressed.connect(func(): preview_requested.emit(index))
	menu.set_reference_icon(eye_button, "ic_eye")
	eye_button.toggle_mode = true
	eye_button.button_pressed = true
	eye_button.tooltip_text = "显示这条线路的棋盘箭头"
	eye_button.add_theme_color_override("icon_pressed_color", menu.app.palette().accent)
	eye_button.add_theme_color_override("icon_normal_color", menu.app.palette().muted)
	eye_button.toggled.connect(func(on): arrow_toggled.emit(index, on))

func update_line(details: Dictionary, pos, codec) -> void:
	score_label.text = ("#" + str(details.get("score", "—"))) if details.get("score_type") == "mate" else "%+.2f" % (float(details.get("score", 0)) / 100.0)
	var position = pos.copy()
	var names = PackedStringArray()
	var decision = ""
	for value in details.get("pv", []):
		var move = codec.parse_move(value, position)
		if move.is_empty(): break
		if names.is_empty(): decision = Hint.choice(position, move)
		names.append(Hint.notation(position, move))
		position = position.after(move)
	hint_label.text = str(index) + " " + ui.app.t(decision) if not decision.is_empty() else ""
	hint_label.tooltip_text = hint_label.text
	hint_label.visible = not decision.is_empty()
	move_label.text = "  ".join(names)
	move_label.tooltip_text = move_label.text
	play_button.disabled = names.is_empty()
