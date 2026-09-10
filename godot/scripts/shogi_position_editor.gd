extends VBoxContainer
signal submitted(sfen: String)
const Rules = preload("res://scripts/shogi_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Game = preload("res://scripts/shogi_game.gd")
const History = preload("res://scripts/shogi_editor_history.gd")
var pos = Rules.new()
var brush = 0
var flipped = false
var menu
var cells: Array[Button] = []
var palette: Dictionary = {}
var turn_buttons: Dictionary = {}
var sfen_field: TextEdit
var feedback: Label
var counters: Dictionary = {}
var history = History.new()
var analysis
var evaluation
var board_area: Control
var board_rect: Rect2
var footer: HBoxContainer
var undo_button: Button
var redo_button: Button
var previous_button: Button
var next_button: Button
var promote_button: Button
var flip_button: Button
var saved_label: Label
var input_due = -1
var input_problem = ""
var rendering_text = false
var interaction

func action(title: String, callback: Callable, id: String, icon: String = "", height: int = 36) -> Button:
	var item = menu.compact_button(title, callback, height)
	item.name = id
	item.tooltip_text = title
	item.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item.add_theme_color_override("font_color", Color("f8f1e6"))
	item.add_theme_color_override("font_hover_color", Color.WHITE)
	for state in ["font_pressed_color", "font_hover_pressed_color", "font_focus_color"]: item.add_theme_color_override(state, Color.WHITE)
	item.add_theme_color_override("font_disabled_color", Color("92979e"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		var style = menu.Design.box(Color("314050") if state in ["hover", "pressed", "hover_pressed"] else Color("282828"), 5, 4)
		if state == "focus": style.border_color = menu.app.palette().accent; style.set_border_width_all(1)
		item.add_theme_stylebox_override(state, style)
	if not icon.is_empty(): menu.set_reference_icon(item, icon)
	item.add_theme_color_override("icon_normal_color", Color("f8f1e6"))
	return item

func build(owner_menu, source) -> void:
	menu = owner_menu
	pos = source.copy()
	flipped = menu.app.flipped
	history.begin(Codec.sfen(pos), menu.app.preferences.studio.editor_positions)
	analysis = preload("res://scripts/shogi_editor_analysis.gd").new()
	analysis.threads = 1
	analysis.hash_size = mini(64, menu.app.preferences.studio.hash)
	add_child(analysis)
	preload("res://scripts/shogi_editor_layout.gd").new().build(self)
	interaction = preload("res://scripts/shogi_editor_input.gd").new()
	interaction.editor = self
	add_child(interaction)
	resized.connect(layout_board)
	menu.app.get_viewport().size_changed.connect(layout_board)
	refresh()
	layout_board.call_deferred()

func layout_board() -> void:
	if board_area == null or menu == null: return
	var gutter = 20 if menu.app.preferences.studio.editor_eval_bar else 0
	var available: Vector2 = menu.app.safe_rect().size
	var height_limit = available.y - 126 if available.x > available.y else available.y - 12
	var edge = floorf(maxf(144, minf(size.x - gutter, height_limit)) / 9.0) * 9
	board_area.custom_minimum_size.y = edge + 4
	board_rect = Rect2(Vector2((size.x - edge - gutter) / 2 + gutter, 2), Vector2.ONE * edge)
	evaluation.visible = gutter > 0
	evaluation.position = board_rect.position - Vector2(20, 0)
	evaluation.size = Vector2(18, edge)
	for square in range(cells.size()):
		var visual: int = 80 - square if flipped else square
		cells[square].position = board_rect.position + Vector2(visual % 9, visual / 9) * edge / 9
		cells[square].size = Vector2.ONE * edge / 9
		cells[square].queue_redraw()
	board_area.queue_redraw()

func edited() -> void:
	input_due = -1
	input_problem = ""
	history.push(Codec.sfen(pos))
	refresh()

func refresh() -> void:
	for square in range(cells.size()):
		cells[square].piece = pos.board[square]
		cells[square].accessibility_name = Codec.square_name(square) + " " + ("空格" if pos.board[square] == 0 else ("后手 " if pos.board[square] < 0 else "先手 ") + Rules.NAMES[absi(pos.board[square])])
		cells[square].queue_redraw()
	for value in palette: palette[value].queue_redraw()
	palette[0].set_pressed_no_signal(brush == 0)
	for side in [1, -1]:
		turn_buttons[side].set_pressed_no_signal(pos.turn == side)
		for kind in range(1, 8): counters[str(side) + "/" + str(kind)].set_value_no_signal(pos.hands[side][kind])
	promote_button.disabled = absi(brush) in [0, 5, 8]
	promote_button.set_pressed_no_signal(absi(brush) > 8)
	feedback.text = input_problem if not input_problem.is_empty() else Game.position_error(pos)
	if feedback.text.is_empty(): feedback.text = ("先手行棋" if pos.turn == 1 else "后手行棋") + " · " + ("橡皮" if brush == 0 else Rules.NAMES[absi(brush)])
	if input_problem.is_empty() and input_due < 0 and sfen_field.text != Codec.sfen(pos):
		rendering_text = true
		sfen_field.text = Codec.sfen(pos)
		rendering_text = false
	undo_button.disabled = not history.can_undo()
	redo_button.disabled = not history.can_redo()
	previous_button.disabled = history.index <= 0
	next_button.disabled = history.index >= history.entries.size() - 1
	saved_label.text = "局面 %d / %d" % [history.index + 1, history.entries.size()]
	menu.set_reference_icon(flip_button, "ic_flipped_board" if flipped else "ic_non_flipped_board")
	flip_button.add_theme_color_override("icon_normal_color", Color("f8f1e6"))
	update_analysis()
	layout_board()

func apply_theme() -> void:
	for item in find_children("*", "Label", true, false): item.add_theme_color_override("font_color", Color("f8f1e6"))
	for cell in cells: cell.queue_redraw()

func update_analysis() -> void:
	analysis.update(pos if input_due < 0 and input_problem.is_empty() else null, menu.app.preferences.studio.editor_eval_bar and menu.app.preferences.studio.editor_eval_running)

func text_edited() -> void:
	if rendering_text: return
	input_due = Time.get_ticks_msec() + 250
	update_analysis()

func choose_brush(value: int) -> void:
	brush = value
	refresh()

func toggle_promotion() -> void:
	if absi(brush) in [0, 5, 8]: return
	brush = (absi(brush) + 8 if absi(brush) < 8 else absi(brush) - 8) * signi(brush)
	refresh()

func flip_board() -> void:
	flipped = not flipped
	refresh()

func toggle_hands() -> void:
	var hands = find_child("EditorHandCounts", true, false)
	hands.visible = not hands.visible

func toggle_evaluation() -> void:
	menu.set_extra("editor_eval_running", not menu.app.preferences.studio.editor_eval_running)
	update_analysis()

func paint(square: int) -> void:
	pos.board[square] = brush
	edited()

func restore() -> void:
	pos = Codec.parse_sfen(history.current())
	input_problem = ""
	input_due = -1
	refresh()

func undo() -> void:
	if history.undo(): restore()

func redo() -> void:
	if history.redo(): restore()

func seek_saved(delta: int) -> void:
	if history.seek(history.index + delta): restore()

func read_sfen(value: String) -> bool:
	var text = value.strip_edges().trim_prefix("sfen ")
	var parsed = Codec.parse_sfen(text) if text.length() <= 512 else null
	if parsed == null:
		input_problem = "SFEN 格式错误，尚未改变棋盘。"
		feedback.text = input_problem
		update_analysis()
		return false
	pos = parsed
	edited()
	return true

func paste_sfen() -> void:
	var text = DisplayServer.clipboard_get()
	if read_sfen(text): flipped = pos.turn == -1; refresh()

func copy_sfen() -> void:
	DisplayServer.clipboard_set(Codec.sfen(pos))
	feedback.text = "已复制 SFEN。"

func remember() -> bool:
	var old = menu.app.preferences.studio.editor_positions
	menu.app.preferences.studio.editor_positions = history.remember(Codec.sfen(pos))
	if not menu.app.testing and menu.app.preferences.save_to() != OK:
		menu.app.preferences.studio.editor_positions = old
		feedback.text = "局面列表保存失败，请重试。"
		return false
	return true

func checked() -> bool:
	input_due = -1
	if not input_problem.is_empty() or sfen_field.text != Codec.sfen(pos):
		if not read_sfen(sfen_field.text): return false
	var problem = Game.position_error(pos)
	if not problem.is_empty(): feedback.text = problem; return false
	return true

func save_position() -> void:
	if not checked(): return
	var saved = Game.new()
	saved.set_initial(Codec.sfen(pos))
	saved.mode = "local"
	saved.metadata["棋战"] = "保存的编辑局面"
	var path: String = menu.app.records.archive(saved, "编辑局面 " + Time.get_datetime_string_from_system())
	if path.is_empty(): feedback.text = menu.app.records.error; return
	if not remember(): return
	refresh()
	feedback.text = "局面已保存到棋谱库。"

func complete() -> void:
	if checked() and remember(): submitted.emit(Codec.sfen(pos))

func _process(_delta: float) -> void:
	if input_due >= 0 and Time.get_ticks_msec() >= input_due:
		input_due = -1
		read_sfen(sfen_field.text)

func square_at(point: Vector2) -> int:
	var local = point - board_area.global_position
	if not board_rect.has_point(local): return -1
	var cell = (local - board_rect.position) / (board_rect.size.x / 9)
	var square = int(cell.y) * 9 + int(cell.x)
	return 80 - square if flipped else square
