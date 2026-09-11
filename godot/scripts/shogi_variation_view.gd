extends RefCounted
## Two-row move ribbon and selectable variation rows from the reference layout.
var ui
var bar_key = ""

func update_bar() -> void:
	if ui.study_bar == null: return
	var study = ui.study
	ui.study_bar.visible = study.active
	if not study.active: bar_key = ""; return
	var key = str([study.effective(), study.tree.nodes.size(), study.history.size(), study.dirty, study.error, study.last_action])
	if key == bar_key: return
	bar_key = key
	for child in ui.study_bar.get_children(): ui.study_bar.remove_child(child); child.queue_free()
	var resume = ui.compact_button(ui.app.t("变化 · %d") % maxi(0, segments().size() - 1) if study.effective() else "返回变化分析", ui.show_variations if study.effective() else study.resume, 28)
	resume.name = "OpenVariations"
	ui.study_bar.add_child(resume)
	var main = ui.compact_button("主线", func(): study.resume(); study.select(study.tree.main.back() if not study.tree.main.is_empty() else 0), 28)
	main.name = "VariationMainLine"
	ui.study_bar.add_child(main)
	if study.dirty:
		var retry = ui.compact_button("保存" if study.error.is_empty() else "重试保存", func(): study.save(); bar_key = "", 28)
		retry.name = "RetryVariationSave"
		retry.tooltip_text = study.error
		ui.study_bar.add_child(retry)
	var done = ui.compact_button("结束", ui.finish_study, 28)
	done.name = "ExitVariations"
	ui.study_bar.add_child(done)

func move_button(id: int, primary: bool) -> Button:
	var study = ui.study
	var node: Dictionary = study.tree.nodes[id]
	var caption = "起局" if id == 0 else "%d. %s" % [node.depth, study.tree.nodes[node.parent].position.notation(node.move)]
	if not node.comment.is_empty(): caption += " ▪"
	var item = ui.compact_button(caption, func(): study.select(id), 28)
	item.name = ("MainMove_" if primary else "VariationMove_") + str(id)
	item.custom_minimum_size = Vector2(30, 28)
	item.autowrap_mode = TextServer.AUTOWRAP_OFF
	item.add_theme_font_size_override("font_size", 15 if primary else 14)
	item.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item.add_theme_stylebox_override("normal", ui.Design.box(ui.app.palette().accent if study.tree.cursor == id else Color(0, 0, 0, 0.16), 4, 3))
	if study.tree.cursor == id: item.add_theme_color_override("font_color", Color.WHITE)
	item.tooltip_text = caption + " · 长按可查看变化、注释或提升主线"
	bind_long_press(item, id)
	return item

func bind_long_press(control: Control, id: int) -> void:
	var state = {"held": false, "point": Vector2.ZERO}
	control.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			control.accept_event()
			show_move(id)
		elif event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
			state.held = event.pressed
			if event.pressed:
				state.point = event.position
				ui.app.get_tree().create_timer(0.45).timeout.connect(func():
					if is_instance_valid(control) and state.held and ui.study.effective() and ui.study.tree.nodes.has(id):
						state.held = false
						show_move(id)
				)
		elif event is InputEventScreenDrag or event is InputEventMouseMotion:
			if event.position.distance_to(state.point) > 12: state.held = false
	)

func update_ribbon() -> void:
	var study = ui.study
	var key = str(["variations", study.tree.get_instance_id(), study.tree.nodes.size(), study.tree.main, study.tree.cursor, study.line_ids])
	if ui.ribbon_key == key: return
	ui.ribbon_key = key
	for child in ui.move_strip.get_children(): ui.move_strip.remove_child(child); child.queue_free()
	ui.move_strip.add_child(move_button(0, true))
	var selected: Control
	var length = maxi(study.tree.main.size(), study.line_ids.size())
	for ply in range(length):
		var column = VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		ui.move_strip.add_child(column)
		var main_id: int = study.tree.main[ply] if ply < study.tree.main.size() else -1
		var alt_id: int = study.line_ids[ply] if ply < study.line_ids.size() else -1
		if main_id >= 0:
			var main = move_button(main_id, true)
			column.add_child(main)
			if main_id == study.tree.cursor: selected = main
		else:
			var spacer = Control.new()
			spacer.custom_minimum_size.y = 28
			column.add_child(spacer)
		if alt_id >= 0 and alt_id != main_id:
			var alternative = move_button(alt_id, false)
			column.add_child(alternative)
			if alt_id == study.tree.cursor: selected = alternative
	if selected != null: ui.reveal_ribbon.call_deferred(selected.get_instance_id())

func segments() -> Array:
	var tree = ui.study.tree
	var result: Array = [{"primary": true, "root": tree.main[0] if not tree.main.is_empty() else 0, "ids": tree.main.duplicate(), "depth": 0}]
	var pending: Array = [{"id": 0, "depth": 0}]
	while not pending.is_empty():
		var parent: Dictionary = pending.pop_back()
		var preferred: int = tree.main_next(parent.id) if parent.id == 0 or parent.id in tree.main else tree.nodes[parent.id].children[0] if not tree.nodes[parent.id].children.is_empty() else -1
		for child in tree.nodes[parent.id].children:
			var alternate = child != preferred
			var depth: int = parent.depth + (1 if alternate else 0)
			if alternate:
				var line: Array = tree.line_through(child)
				result.append({"primary": false, "root": child, "ids": line.slice(tree.nodes[child].depth - 1), "depth": depth})
			pending.append({"id": child, "depth": depth})
	return result

func escaped(value: String) -> String:
	var result = ""
	for character in value:
		result += "[lb]" if character == "[" else "[rb]" if character == "]" else character
	return result

func line_text(ids: Array) -> String:
	var tokens: Array[String] = []
	for id in ids:
		var node: Dictionary = ui.study.tree.nodes[id]
		var move: String = ui.study.tree.nodes[node.parent].position.notation(node.move)
		var value = "[url=%d]%d. %s[/url]" % [id, node.depth, escaped(move)]
		if id == ui.study.tree.cursor: value = "[bgcolor=#347de4]" + value + "[/bgcolor]"
		if not node.comment.is_empty():
			var words = node.comment.replace("\n", " ").replace("\t", " ").split(" ", false)
			var snippet = " ".join(words.slice(0, 4)).left(80)
			value += " [color=#aab0b7]" + escaped(snippet) + ("…" if words.size() > 4 or node.comment.length() > 80 else "") + "[/color]"
		tokens.append(value)
	return "   ".join(tokens)

func show_lines() -> void:
	var study = ui.study
	if not study.active: ui.start_variation_analysis(); return
	if not study.effective(): study.resume()
	var column = ui._page("变化线路", "variations")
	column.add_child(ui.label("点击着手定位棋盘，长按着手可编辑。修改后可选择保存或不保存；仅回放不会新增存档。", 13))
	for entry in segments():
		column.add_child(ui.label("主线" if entry.primary else "第 %d 手起 · %s变化" % [study.tree.nodes[entry.root].depth, "嵌套" if entry.depth > 1 else ""], 13))
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		column.add_child(row)
		var moves = RichTextLabel.new()
		moves.name = "VariationLine_" + str(entry.root)
		moves.bbcode_enabled = true
		moves.scroll_active = true
		moves.fit_content = false
		moves.focus_mode = Control.FOCUS_ALL
		moves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		moves.custom_minimum_size.y = 34
		moves.add_theme_font_size_override("normal_font_size", 14)
		moves.add_theme_color_override("default_color", ui.app.palette().ink)
		moves.text = line_text(entry.ids) if not entry.ids.is_empty() else "初始局面"
		row.add_child(moves)
		var root: int = entry.root
		moves.meta_clicked.connect(func(meta): ui._board_keep(); study.select(int(str(meta))))
		moves.gui_input.connect(func(event):
			if event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				moves.accept_event(); ui._board_keep(); study.select(root)
		)
		bind_long_press(moves, root)
		var fit = func():
			if is_instance_valid(moves): moves.custom_minimum_size.y = clampf(moves.get_content_height() + 12, 34, 126)
		moves.resized.connect(func(): fit.call_deferred())
		fit.call_deferred()
		if not entry.primary:
			var remove = ui.compact_button("×", func(): study.remove(root); show_lines(), 24)
			remove.name = "RemoveVariation_" + str(root)
			ui.set_reference_icon(remove, "ic_remove_variation")
			remove.tooltip_text = "删除变化"
			remove.custom_minimum_size = Vector2(24, 24)
			remove.size_flags_horizontal = Control.SIZE_SHRINK_END
			remove.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(remove)
	if not study.history.is_empty():
		var undo = ui.compact_button("变化已删除 · 撤销" if study.last_action == "删除变化" else "撤销上次改动", func(): study.undo(); show_lines(), 38)
		undo.name = "UndoVariationChange"
		column.add_child(undo)
	column.add_child(ui.button("返回棋盘", ui._board_keep))

func show_move(id: int) -> void:
	var study = ui.study
	if not study.active or not study.tree.nodes.has(id): return
	var node: Dictionary = study.tree.nodes[id]
	var column = ui._page("第 %d 手" % node.depth, "variation-move", true)
	column.add_child(ui.button("在棋盘上查看", func(): ui._board_keep(); study.select(id)))
	if id > 0:
		var promote = ui.button("提升为主线", func(): ui._board_keep(); study.promote(id))
		promote.name = "PromoteVariation"
		column.add_child(promote)
		var remove = ui.button("删除此手及后续变化", func(): study.remove(id); show_lines())
		remove.name = "DeleteVariationSubtree"
		column.add_child(remove)
	column.add_child(ui.button("编辑注释", func(): ui._board_keep(); study.select(id); ui.show_comment()))
	if not node.children.is_empty():
		column.add_child(ui.label("后续着手", 14))
		for child in node.children:
			var target: int = child
			column.add_child(ui.button(study.tree.nodes[id].position.notation(study.tree.nodes[child].move), func(): ui._board_keep(); study.select(target)))

func show_policy(move: Dictionary, key: String, parent: int) -> void:
	var column = ui._page("分析棋盘的新变化", "variation-policy", true)
	column.add_child(ui.label("替换主线会移除原来的后续着手及其注释和变化。保留主线则把新着手另存为变化，之后可长按着手提升为主线。", 14))
	for option in [["保留主线，另存为变化", "never"], ["替换后续主线", "replace"]]:
		var value: String = option[1]
		var choose = ui.button(option[0], func():
			ui.set_extra("variation_policy", value)
			ui.set_extra("variation_policy_confirmed", true)
			ui._board_keep()
			if ui.study.effective() and ui.study.tree.cursor == parent and ui.study.current.position.key() == key: ui.study.commit(move, true)
		)
		choose.name = "VariationPolicy_" + value
		column.add_child(choose)
	column.add_child(ui.label("可在设置 → 棋盘与棋子中修改。", 12))
