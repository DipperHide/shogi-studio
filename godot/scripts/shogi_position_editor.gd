extends VBoxContainer
signal submitted(sfen: String)
const Rules = preload("res://scripts/shogi_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var pos = Rules.new()
var brush: int = 1
var menu
var cells: Array[Button] = []
var sfen_field: TextEdit
var feedback: Label
var counters: Dictionary = {}

func build(owner_menu, source) -> void:
	menu = owner_menu
	pos = source.copy()
	add_theme_constant_override("separation", 8)
	var top = HBoxContainer.new()
	add_child(top)
	for entry in [["初始", func(): pos = Rules.new(); refresh()], ["清空", func(): pos = Rules.new(false); refresh()], ["翻转执方", func(): pos.turn *= -1; refresh()]]:
		top.add_child(menu.button(entry[0], entry[1]))
	var picker = GridContainer.new()
	picker.columns = 8
	add_child(picker)
	for side in [1, -1]:
		for kind in range(1, 9):
			var value: int = kind * side
			var item = menu.button(("☗" if side == 1 else "☖") + Rules.NAMES[kind], func(): brush = value; refresh())
			item.custom_minimum_size = Vector2(0, 40)
			item.add_theme_font_size_override("font_size", 12)
			item.autowrap_mode = TextServer.AUTOWRAP_OFF
			for state in ["normal", "hover", "pressed", "focus", "disabled"]: item.add_theme_stylebox_override(state, menu.Design.box(menu.app.palette().soft, 5, 2))
			picker.add_child(item)
	var tools = HBoxContainer.new()
	add_child(tools)
	tools.add_child(menu.button("橡皮", func(): brush = 0; refresh()))
	tools.add_child(menu.button("升变笔", func():
		if absi(brush) not in [0, 5, 8]: brush = (absi(brush) + 8 if absi(brush) < 8 else absi(brush) - 8) * signi(brush)
		refresh()
	))
	feedback = menu.label("", 13)
	add_child(feedback)
	var grid = GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	add_child(grid)
	for square in range(81):
		var sq = square
		var item = preload("res://scripts/shogi_editor_cell.gd").new()
		item.pressed.connect(func(): pos.board[sq] = brush; refresh())
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.custom_minimum_size = Vector2(0, 36)
		item.add_theme_font_size_override("font_size", 18)
		for state in ["normal", "hover", "pressed", "focus", "disabled"]: item.add_theme_stylebox_override(state, menu.Design.box(Color("ddbc8b"), 0, 0))
		item.add_theme_color_override("font_color", Color("2a1d12"))
		grid.add_child(item)
		cells.append(item)
	for side in [1, -1]:
		add_child(menu.label("先手持驹" if side == 1 else "后手持驹", 14))
		var row = GridContainer.new()
		row.columns = 2
		add_child(row)
		for kind in range(1, 8):
			var k = kind
			var s = side
			var box = HBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(box)
			box.add_theme_constant_override("separation", 6)
			var title = menu.label(Rules.NAMES[kind], 13)
			title.custom_minimum_size.x = 20
			title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			box.add_child(title)
			var counter = SpinBox.new()
			counter.min_value = 0
			counter.max_value = 18 if kind == 1 else 2 if kind in [6, 7] else 4
			counter.value = pos.hands[side][kind]
			counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			counter.custom_minimum_size = Vector2(0, 42)
			counter.get_line_edit().add_theme_font_size_override("font_size", 12)
			counter.value_changed.connect(func(value): pos.hands[s][k] = int(value); refresh())
			box.add_child(counter)
			counters[str(s) + "/" + str(k)] = counter
	sfen_field = TextEdit.new()
	sfen_field.custom_minimum_size.y = 84
	sfen_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	sfen_field.add_theme_font_size_override("font_size", 13)
	add_child(sfen_field)
	var actions = HBoxContainer.new()
	add_child(actions)
	actions.add_child(menu.button("读取 SFEN", func():
		var parsed = Codec.parse_sfen(sfen_field.text.strip_edges().trim_prefix("sfen "))
		if parsed == null: feedback.text = "SFEN 格式错误。"; return
		pos = parsed
		refresh()
	))
	actions.add_child(menu.button("应用局面", func():
		var problem = preload("res://scripts/shogi_game.gd").position_error(pos)
		if not problem.is_empty(): feedback.text = problem; return
		submitted.emit(Codec.sfen(pos))
	))
	refresh()

func refresh() -> void:
	for square in range(cells.size()):
		var value = pos.board[square]
		cells[square].piece = value
		cells[square].queue_redraw()
		cells[square].tooltip_text = ("后手 " if value < 0 else "先手 ") + Rules.NAMES[absi(value)]
	for side in [1, -1]:
		for kind in range(1, 8):
			var key = str(side) + "/" + str(kind)
			if counters.has(key): counters[key].set_value_no_signal(pos.hands[side][kind])
	if feedback != null: feedback.text = ("先手行棋" if pos.turn == 1 else "后手行棋") + "   ·   当前：" + ("橡皮" if brush == 0 else ("☗" if brush > 0 else "☖") + Rules.NAMES[absi(brush)])
	if sfen_field != null: sfen_field.text = Codec.sfen(pos)
