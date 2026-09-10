extends RefCounted

func build(e) -> void:
	var menu = e.menu
	e.add_theme_constant_override("separation", 5)
	var outer = menu.page.get_child(0)
	outer.get_child(0).hide()
	outer.add_theme_constant_override("separation", 5)
	var wood = StyleBoxTexture.new()
	wood.texture = load("res://assets/reference-ui/wood_dark.png")
	wood.set_content_margin_all(5)
	menu.page.add_theme_stylebox_override("panel", wood)
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	e.add_child(top)
	var reset = VBoxContainer.new()
	reset.add_theme_constant_override("separation", 2)
	top.add_child(reset)
	reset.add_child(e.action("重置", func(): e.pos = e.Rules.new(); e.flipped = false; e.edited(), "EditorReset", "ic_refresh", 32))
	reset.add_child(e.action("清空", func(): e.pos = e.Rules.new(false); e.edited(), "EditorClear", "ic_delete", 32))
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var turns = VBoxContainer.new()
	turns.add_child(menu.label("行棋方", 12))
	top.add_child(turns)
	var turn_row = HBoxContainer.new()
	turns.add_child(turn_row)
	for side in [1, -1]:
		var value: int = side
		var item = e.action("先手" if side == 1 else "后手", func(): e.pos.turn = value; e.edited(), "EditorTurn" + str(side))
		item.toggle_mode = true
		turn_row.add_child(item)
		e.turn_buttons[side] = item
	var hands_toggle = e.action("持驹 ▾", e.toggle_hands, "EditorHands")
	top.add_child(hands_toggle)
	hands_toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	e.board_area = Control.new()
	e.board_area.name = "EditorBoard"
	e.board_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.add_child(e.board_area)
	e.board_area.draw.connect(func():
		e.board_area.draw_rect(Rect2(e.board_rect.position.x, 0, e.board_rect.size.x, 2), Color.WHITE if e.flipped else Color("483d41"))
		e.board_area.draw_rect(Rect2(e.board_rect.position.x, e.board_rect.end.y, e.board_rect.size.x, 2), Color("483d41") if e.flipped else Color.WHITE)
	)
	e.evaluation = preload("res://scripts/shogi_editor_eval_bar.gd").new()
	e.board_area.add_child(e.evaluation)
	e.evaluation.setup(e)
	for square in range(81):
		var sq = square
		var item = preload("res://scripts/shogi_editor_cell.gd").new()
		item.name = "EditorSquare" + str(square)
		item.editor = e
		item.square = square
		item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.pressed.connect(func(): e.paint(sq))
		e.board_area.add_child(item)
		e.cells.append(item)
	for side in [1, -1]:
		var row = HBoxContainer.new()
		row.name = "EditorPalette" + str(side)
		row.add_theme_constant_override("separation", 1)
		e.add_child(row)
		var tool = e.action("橡皮", e.choose_brush.bind(0), "EditorEraser", "ic_delete", 38) if side == 1 else e.action("翻转棋盘", e.flip_board, "EditorFlip", "ic_non_flipped_board", 38)
		tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tool)
		if side == 1: e.palette[0] = tool; tool.toggle_mode = true
		else: e.flip_button = tool
		for kind in range(1, 9):
			var value: int = kind * side
			var item = preload("res://scripts/shogi_editor_cell.gd").new()
			item.name = "EditorPiece" + str(value)
			item.editor = e
			item.piece = value
			item.palette_piece = true
			item.mouse_filter = Control.MOUSE_FILTER_IGNORE
			item.custom_minimum_size = Vector2(0, 38)
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item.pressed.connect(func(): e.choose_brush(value))
			row.add_child(item)
			e.palette[value] = item
	e.promote_button = e.action("升变笔", e.toggle_promotion, "EditorPromotion", "", 28)
	e.add_child(e.promote_button)
	e.promote_button.toggle_mode = true
	var hands = VBoxContainer.new()
	hands.name = "EditorHandCounts"
	hands.hide()
	e.add_child(hands)
	for side in [1, -1]:
		hands.add_child(menu.label("先手持驹" if side == 1 else "后手持驹", 12))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		hands.add_child(row)
		for kind in range(1, 8):
			var k = kind
			var s = side
			var box = VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(box)
			var title = menu.label(e.Rules.NAMES[kind], 12)
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(title)
			var counter = SpinBox.new()
			counter.name = "EditorHand_%d_%d" % [s, k]
			counter.max_value = 18 if kind == 1 else 2 if kind in [6, 7] else 4
			counter.custom_minimum_size.y = 34
			counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			counter.get_line_edit().add_theme_font_size_override("font_size", 12)
			counter.get_line_edit().add_theme_constant_override("minimum_character_width", 2)
			for state in ["normal", "focus", "read_only"]:
				var style = menu.Design.box(Color("333333"), 3, 3)
				if state == "focus": style.border_color = menu.app.palette().accent; style.set_border_width_all(1)
				counter.get_line_edit().add_theme_stylebox_override(state, style)
			counter.get_line_edit().add_theme_color_override("font_color", Color.WHITE)
			counter.value_changed.connect(func(value): e.pos.hands[s][k] = int(value); e.edited())
			box.add_child(counter)
			e.counters[str(s) + "/" + str(k)] = counter
	e.feedback = menu.label("", 12)
	e.feedback.name = "EditorFeedback"
	e.add_child(e.feedback)
	var clipboard = HBoxContainer.new()
	e.add_child(clipboard)
	clipboard.add_child(e.action("粘贴 SFEN", e.paste_sfen, "EditorPaste", "", 28))
	clipboard.add_child(e.action("复制 SFEN", e.copy_sfen, "EditorCopy", "", 28))
	var code_row = HBoxContainer.new()
	e.add_child(code_row)
	code_row.add_child(e.action("保存局面", e.save_position, "EditorSave", "ic_save", 36))
	e.sfen_field = TextEdit.new()
	e.sfen_field.name = "EditorSFEN"
	e.sfen_field.custom_minimum_size.y = 64
	e.sfen_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.sfen_field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	e.sfen_field.add_theme_font_size_override("font_size", 12)
	e.sfen_field.text_changed.connect(e.text_edited)
	code_row.add_child(e.sfen_field)
	var navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 8)
	e.add_child(navigation)
	e.saved_label = menu.label("", 12)
	e.saved_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(e.saved_label)
	e.previous_button = e.action("上一个保存局面", e.seek_saved.bind(-1), "EditorPrevious", "ic_nav_previous")
	e.undo_button = e.action("撤销", e.undo, "EditorUndo", "ic_undo")
	e.redo_button = e.action("重做", e.redo, "EditorRedo", "ic_redo")
	e.next_button = e.action("下一个保存局面", e.seek_saved.bind(1), "EditorNext", "ic_nav_next")
	for item in [e.previous_button, e.undo_button, e.redo_button, e.next_button]: navigation.add_child(item)
	e.footer = HBoxContainer.new()
	e.footer.name = "EditorFooter"
	outer.add_child(e.footer)
	e.footer.add_child(e.action("取消", menu._board_keep, "EditorCancel", "", 44))
	e.footer.add_child(e.action("完成", e.complete, "EditorDone", "", 44))
	for item in e.footer.get_children(): item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in e.find_children("*", "Label", true, false): item.add_theme_color_override("font_color", Color("f8f1e6"))
