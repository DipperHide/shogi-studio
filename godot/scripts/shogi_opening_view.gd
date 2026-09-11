extends RefCounted
const Data = preload("res://scripts/shogi_openings.gd")
var ui
var query = ""
var tab = 0
var side = 0
var scroll = 0
var list: VBoxContainer
var preview
var search_field: LineEdit
var side_buttons: Dictionary = {}
var tab_buttons: Array = []
var count: Label
var visible_entries: Array = []

func action(caption: String, callback: Callable, id: String, icon: String = "", height: int = 44) -> Button:
	var item = ui.compact_button(caption, callback if callback.is_valid() else func(): pass, height)
	item.name = id
	item.tooltip_text = caption
	item.accessibility_name = caption
	if not icon.is_empty(): ui.set_reference_icon(item, icon)
	style_button(item)
	return item

func style_button(item: Button) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color"]: item.add_theme_color_override(state, Color("f8f1e6"))
	item.add_theme_color_override("font_disabled_color", Color("a39784"))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		item.add_theme_stylebox_override(state, ui.Design.box(Color("736044") if state in ["pressed", "hover_pressed"] else Color("493c29"), 4, 5))

func text(caption: String, font_size: int = 14) -> Label:
	var item = ui.label(caption, font_size)
	item.add_theme_color_override("font_color", Color("f8f1e6") if font_size > 12 else Color("d4c8b5"))
	return item

func page(title: String, name: String) -> VBoxContainer:
	var content = ui._page(title, name)
	var outer = ui.page.get_child(0)
	outer.add_theme_constant_override("separation", 6)
	var wood = StyleBoxTexture.new()
	wood.texture = load("res://assets/reference-ui/wood_dark.png"); wood.set_content_margin_all(10)
	ui.page.add_theme_stylebox_override("panel", wood)
	var header = outer.get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var title_label = text(title, 22 if name == "openings" else 18)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)
	header.add_child(action("关闭", ui.back, "OpeningClose", "ic_close", 44))
	header.get_child(1).size_flags_horizontal = Control.SIZE_SHRINK_END
	header.get_child(1).custom_minimum_size.x = 44
	return content

func show_list(value: Variant = null) -> void:
	if value != null: query = str(value); scroll = 0
	list = page("开局与围玉", "openings")
	var outer = ui.page.get_child(0)
	var filters = VBoxContainer.new()
	outer.add_child(filters); outer.move_child(filters, 1)
	var row = HBoxContainer.new(); filters.add_child(row)
	search_field = LineEdit.new()
	search_field.name = "OpeningSearch"; search_field.placeholder_text = "搜索名称或走法主题"
	search_field.text = query; search_field.max_length = 120
	search_field.custom_minimum_size.y = 44; search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_field.add_theme_color_override("font_color", Color("f8f1e6"))
	search_field.add_theme_color_override("font_placeholder_color", Color("d4c8b5"))
	search_field.add_theme_stylebox_override("normal", ui.Design.box(Color("403522"), 4, 8))
	var focus = ui.Design.box(Color("403522"), 4, 8)
	focus.border_color = Color("ddbb69"); focus.set_border_width_all(1)
	search_field.add_theme_stylebox_override("focus", focus)
	row.add_child(search_field)
	row.add_child(action("清除搜索", func(): search_field.text = ""; query = ""; refresh(), "OpeningClear", "ic_close"))
	row.get_child(1).size_flags_horizontal = Control.SIZE_SHRINK_END
	row.get_child(1).custom_minimum_size.x = 44
	search_field.text_changed.connect(func(value): query = value; refresh())
	search_field.text_submitted.connect(func(_value): search_field.release_focus(); DisplayServer.virtual_keyboard_hide())
	var tabs = HBoxContainer.new(); filters.add_child(tabs); tab_buttons.clear()
	for i in range(2):
		var index = i
		var item = action(["开局", "围玉"][i], func(): tab = index; refresh(), "OpeningTab" + str(i), "", 40)
		item.toggle_mode = true; tabs.add_child(item); tab_buttons.append(item)
	var sides = HBoxContainer.new(); filters.add_child(sides); side_buttons.clear()
	for which in [0, 1, -1]:
		var choice: int = which
		var item = action("全部" if which == 0 else Data.side_name(which), func(): side = choice; refresh(), "OpeningSide" + str(which), "", 36)
		item.toggle_mode = true; sides.add_child(item); side_buttons[which] = item
	count = text("", 12); filters.add_child(count)
	refresh(false)
	ui.page_scroll.set_deferred("scroll_vertical", scroll)

func refresh(reset_scroll: bool = true) -> void:
	if not is_instance_valid(list): return
	for child in list.get_children(): list.remove_child(child); child.queue_free()
	visible_entries = Data.search(query, tab, side)
	for which in side_buttons: side_buttons[which].set_pressed_no_signal(which == side)
	for i in range(tab_buttons.size()): tab_buttons[i].set_pressed_no_signal(i == tab)
	count.text = "%d 条教学示例 · 共 9 条 · 双方示例可按任一方筛选" % visible_entries.size()
	if visible_entries.is_empty():
		list.add_child(text("没有匹配的示例。可清除搜索，或选择其他分类和行棋方。", 14))
	for entry in visible_entries:
		var source: Dictionary = entry
		var item = action("", func(): scroll = ui.page_scroll.scroll_vertical; show_info(source), "OpeningEntry" + str(entry.id), "", 0)
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		list.add_child(item)
		var row = HBoxContainer.new(); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; item.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12; row.offset_right = -12; row.offset_top = 10; row.offset_bottom = -10
		var badge = text("☗" if entry.side == 1 else "☗\n☖", 20); badge.custom_minimum_size.x = 25; row.add_child(badge)
		var words = VBoxContainer.new(); words.size_flags_horizontal = Control.SIZE_EXPAND_FILL; words.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(words)
		words.add_child(text(entry.name, 16))
		words.add_child(text(Data.notation(entry), 13))
		words.add_child(text(Data.side_name(entry.side) + " · " + entry.group + " · 无对局胜率数据", 12))
		item.accessibility_name = entry.name + "，" + Data.side_name(entry.side) + "，" + entry.description
		for child in row.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.minimum_size_changed.connect(func(): if is_instance_valid(item): item.custom_minimum_size.y = row.get_combined_minimum_size().y + 20)
		item.custom_minimum_size.y = 98
	if reset_scroll: scroll = 0; ui.page_scroll.scroll_vertical = 0

func show_info(entry: Dictionary) -> void:
	var game = Data.game_for(entry)
	if game == null: ui.show_message("开局谱无效。"); return
	var content = page(entry.name, "opening-info")
	preview = preload("res://scripts/shogi_opening_preview.gd").new()
	content.add_child(preview)
	preview.build(self, entry, game)
	var footer = HBoxContainer.new()
	footer.name = "OpeningFooter"
	ui.page.get_child(0).add_child(footer)
	footer.add_child(action("载入主棋盘", load_preview, "OpeningLoad", "", 48))
	preview.footer = footer
	ui.layout()

func load_preview() -> void:
	if not is_instance_valid(preview): return
	var next = preview.game
	var ply: int = preview.ply
	var flipped: bool = preview.board.flipped
	if not ui.finish_study(true, func(): load_position(next, ply, flipped)): return
	load_position(next, ply, flipped)

func load_position(next, ply: int, flipped: bool) -> void:
	ui.autoplay_on = false
	ui.app.review_game = next; ui.app.review_path = ""; ui.app.replay_index = ply
	ui.app.flipped = flipped
	ui._board_keep()
	ui.live_text.text = str(next.metadata.get("棋战", ""))

func stop_preview() -> void:
	if is_instance_valid(preview): preview.stop()
	preview = null

func apply_theme() -> void:
	for item in ui.page.find_children("*", "Label", true, false): item.add_theme_color_override("font_color", Color("f8f1e6"))
	for item in ui.page.find_children("*", "Button", true, false): style_button(item)
