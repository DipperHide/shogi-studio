extends CanvasLayer
## Shared page navigation, touch-friendly forms and responsive home layout.

const Design = preload("res://scripts/shogi_design.gd")
var app
var toolbar: HBoxContainer
var navigation: HBoxContainer
var board_origin: bool = false
var page_scroll: ScrollContainer
var result_shown: String = ""
var keyboard_height: float = 0
var confirmation_callback: Callable
var root: Control
var page: PanelContainer
var page_name: String = ""
var menu_button: Button
var analysis_label: Label
var history_label: Label
var sheet: bool = false
var connection_label: Label
var bluetooth_label: Label
var devices_column: VBoxContainer
var bluetooth_devices: Dictionary = {}
var platform: Object
var backdrop: ColorRect
var record_path: String = ""
var file_dialog: FileDialog
var tutorial
var home_columns: BoxContainer
var home_art: Control

func initialize(owner_node) -> void:
	app = owner_node
	tutorial = preload("res://scripts/shogi_tutorial.gd").new()
	tutorial.initialize(self)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	backdrop = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.visible = false
	root.add_child(backdrop)
	menu_button = button(app.t("菜单"), show_menu)
	menu_button.text = "‹"
	menu_button.tooltip_text = app.t("首页")
	menu_button.custom_minimum_size = Vector2(48, 48)
	menu_button.pressed.disconnect(show_menu)
	menu_button.pressed.connect(show_home)
	root.add_child(menu_button)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	root.add_child(toolbar)
	toolbar.add_child(button("悔棋", func():
		if app.session != null:
			if not app.session.request("undo"): show_message(app.t("当前不能请求悔棋"))
		else: app._undo_move()
	))
	toolbar.add_child(button("棋谱", func(): show_history(app.game.moves.size())))
	toolbar.add_child(button("更多", show_menu))
	navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 4)
	root.add_child(navigation)
	for entry in [["首页", show_home], ["学习", tutorial.show_catalog], ["棋谱", show_archives], ["设置", show_settings]]:
		navigation.add_child(button(entry[0], entry[1]))
	navigation.visible = false
	app.resized.connect(layout)
	if Engine.has_singleton("ShogiPlatform"):
		platform = Engine.get_singleton("ShogiPlatform")
		platform.bluetooth_status.connect(_bluetooth_status)
		platform.bluetooth_device.connect(_bluetooth_device)
		if platform.has_signal("record_imported"):
			platform.record_imported.connect(_import_text)
			platform.record_exported.connect(func(ok): show_message(app.t("已导出棋谱") if ok else app.t("保存棋谱失败")))
	apply_theme()
	layout()

func is_open() -> bool:
	return page != null

func button(value: String, action: Callable) -> Button:
	var item = Button.new()
	item.text = app.t(value)
	item.custom_minimum_size.y = 50
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.pressed.connect(action)
	var icon_names = {app.t("首页"): "home", app.t("学习"): "learn", app.t("棋谱"): "history", app.t("设置"): "settings", app.t("悔棋"): "undo", app.t("更多"): "more", app.t("开始对弈"): "play", app.t("网络对战"): "network"}
	if icon_names.has(value):
		item.icon = Design.icon(icon_names[value], app.palette().ink)
		item.expand_icon = true
		item.add_theme_constant_override("icon_max_width", 18)
		item.add_theme_constant_override("h_separation", 6)
	if value in [app.t("开始"), app.t("开始对弈"), app.t("继续对局"), app.t("连接"), app.t("创建"), app.t("确认落子"), app.t("同意"), app.t("查看")]:
		if icon_names.has(value): item.icon = Design.icon(icon_names[value], app.palette().background)
		item.add_theme_stylebox_override("normal", Design.box(app.palette().accent, 12, 12))
		item.add_theme_stylebox_override("hover", Design.box(app.palette().accent.lightened(0.08), 12, 12))
		item.add_theme_stylebox_override("pressed", Design.box(app.palette().accent.darkened(0.08), 12, 12))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: item.add_theme_color_override(state, app.palette().background)
	return item

func label(value: String, font_size: int = 18) -> Label:
	var item = Label.new()
	item.text = app.t(value)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", font_size)
	if font_size >= 19: item.add_theme_font_override("font", Design.heading_font(app.text_font))
	if font_size <= 16: item.add_theme_color_override("font_color", app.palette().muted)
	return item

func _page(title: String, name: String, use_sheet: bool = false) -> VBoxContainer:
	if page != null:
		root.remove_child(page)
		page.queue_free()
	app._pause_search()
	if page_name.is_empty(): board_origin = true
	if name == "home": board_origin = false
	page_name = name
	sheet = use_sheet
	analysis_label = null
	history_label = null
	connection_label = null
	bluetooth_label = null
	devices_column = null
	page = PanelContainer.new()
	page.name = name
	var background = StyleBoxFlat.new()
	background.bg_color = app.palette().background
	background.set_content_margin_all(16)
	if sheet:
		background.border_color = app.palette().line
		background.border_width_top = 1
	page.add_theme_stylebox_override("panel", background)
	root.add_child(page)
	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	page.add_child(outer)
	var header = HBoxContainer.new()
	outer.add_child(header)
	var heading = label(title, 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var back_button = button("‹", back)
	back_button.custom_minimum_size.x = 48
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back_button.tooltip_text = app.t("返回")
	header.add_child(back_button)
	header.move_child(back_button, 0)
	if name == "home": back_button.visible = false
	var board_button = button(app.t("棋盘"), close)
	board_button.custom_minimum_size.x = 56
	board_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	board_button.visible = name != "home" and not use_sheet
	header.add_child(board_button)
	var scroll = preload("res://scripts/shogi_page_scroll.gd").new()
	page_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	menu_button.visible = false
	toolbar.visible = false
	navigation.visible = name in ["home", "settings", "archives", "tutorial_catalog"]
	var selected_nav = ["home", "tutorial_catalog", "archives", "settings"].find(name)
	for index in range(navigation.get_child_count()):
		var item: Button = navigation.get_child(index)
		item.text = app.t(["首页", "学习", "棋谱", "设置"][index])
		item.add_theme_font_size_override("font_size", 14)
		item.icon = Design.icon(["home", "learn", "history", "settings"][index], app.palette().accent if index == selected_nav else app.palette().muted)
		item.add_theme_stylebox_override("normal", Design.box(app.palette().soft if index == selected_nav else app.palette().background, 12, 8))
	backdrop.visible = not sheet
	layout()
	app._layout()
	return column

func layout() -> void:
	var safe: Rect2 = app.safe_rect()
	menu_button.position = safe.position + Vector2(4, 2)
	toolbar.position = Vector2(safe.position.x + 12, safe.end.y - 58)
	toolbar.size = Vector2(safe.size.x - 24, 50)
	if app.wide_layout:
		toolbar.position.x = app.bottom_player_rect.position.x
		toolbar.size.x = maxf(200, app.bottom_player_rect.size.x)
	navigation.position = Vector2(safe.position.x + 12, safe.end.y - 60)
	navigation.size = Vector2(safe.size.x - 24, 52)
	if safe.size.x >= 760:
		navigation.size.x = 560
		navigation.position.x = safe.get_center().x - 280
	if page == null: return
	var available = safe
	available.size.y -= keyboard_height
	if navigation.visible and keyboard_height <= 0: available.size.y -= 70
	if sheet:
		page.position = Vector2(safe.end.x - sheet_width(), safe.position.y) if sheet_width() > 0 else Vector2(safe.position.x, safe.end.y - sheet_height())
		page.size = Vector2(sheet_width(), safe.size.y) if sheet_width() > 0 else Vector2(safe.size.x, sheet_height())
	else:
		var width = minf(1000 if page_name == "home" else 720, safe.size.x)
		page.position = available.position + Vector2((available.size.x - width) / 2, 0)
		page.size = Vector2(width, available.size.y)
	if page_name == "home" and is_instance_valid(home_columns):
		home_columns.vertical = safe.size.x < 760
		if is_instance_valid(home_art):
			home_art.custom_minimum_size.y = 174 if home_columns.vertical or safe.size.y < 520 else 280

func handles_point(point: Vector2) -> bool:
	return (menu_button.visible and menu_button.get_global_rect().has_point(point)) or (toolbar.visible and toolbar.get_global_rect().has_point(point))

func _process(_delta: float) -> void:
	if app == null: return
	var next_keyboard: float = 0
	if OS.has_feature("mobile"):
		next_keyboard = DisplayServer.virtual_keyboard_get_height() * app.size.y / maxf(1, DisplayServer.screen_get_size().y)
	if next_keyboard != keyboard_height:
		keyboard_height = next_keyboard
		layout()
		if page_scroll != null and is_instance_valid(page_scroll):
			var focus = root.get_viewport().gui_get_focus_owner()
			if focus != null: page_scroll.ensure_control_visible.call_deferred(focus)
	if app._practice_active(): return
	if app.game.result.is_empty(): result_shown = ""
	elif page == null and app.motion_progress >= 1.0 and result_shown != str([app.game.moves, app.game.result]):
		result_shown = str([app.game.moves, app.game.result])
		show_result.call_deferred()

func back() -> void:
	if file_dialog != null and is_instance_valid(file_dialog) and file_dialog.visible:
		file_dialog.hide()
		return
	for option in root.find_children("*", "OptionButton", true, false):
		if option.get_popup().visible:
			option.get_popup().hide()
			return
	if keyboard_height > 0:
		DisplayServer.virtual_keyboard_hide()
		var focus = root.get_viewport().gui_get_focus_owner()
		if focus != null: focus.release_focus()
		return
	match page_name:
		# Home is the navigation root. Back must neither quit nor reopen a result.
		"home": pass
		"setup", "network", "bluetooth": show_play()
		"host", "join": show_network()
		"record-details", "paste": show_archives()
		"rename-record", "delete-record": show_record_details(record_path)
		"promotion", "confirm-move": app._clear_selection(); close()
		"settings", "archives", "tutorial_catalog":
			if board_origin: close()
			else: show_home()
		"tutorial_lesson", "tutorial_answer", "tutorial_chapter": tutorial.show_catalog()
		"play", "result": show_home()
		"engine": show_settings()
		_:
			if page_name.begins_with("tutorial_"): tutorial.show_catalog()
			else: close()

func close() -> void:
	app._pause_search()
	if page != null:
		root.remove_child(page)
		page.queue_free()
	page = null
	page_name = ""
	sheet = false
	analysis_label = null
	history_label = null
	connection_label = null
	bluetooth_label = null
	devices_column = null
	app._leave_review()
	menu_button.visible = true
	toolbar.visible = true
	navigation.visible = false
	app._clear_selection()
	backdrop.visible = false
	app._cancel_motion()
	app._refresh()

func show_menu() -> void:
	app._leave_review()
	app._refresh()
	var column = _page(app.t("对局操作"), "menu", true)
	column.add_child(button(app.t("继续对局"), close))
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for entry in [["新开局", show_play], ["翻转棋盘", func(): app.flipped = not app.flipped; close()], ["提示与分析", show_analysis], ["保存棋谱", func():
		if app._archive_game(): show_archives()
		else: show_message(app.notice)
	], ["设置", show_settings], ["入玉宣言", show_declaration], ["认输", show_resign], ["主页", show_home]]:
		grid.add_child(button(app.t(entry[0]), entry[1]))
	if app.session != null: column.add_child(button(app.t("当前联机"), show_connection))
	if app.save_failed: column.add_child(button(app.t("重新保存"), func(): app._retry_save(); show_menu()))

func show_play() -> void:
	var column = _page(app.t("开始对弈"), "play")
	column.add_child(label(app.t("选择一位对手"), 26))
	column.add_child(label(app.t("从容练习，或与朋友切磋。"), 15))
	for entry in [["人机对弈", "按自己的节奏练习", "play", func(): show_setup()], ["同机双人", "和身边的朋友共用棋盘", "people", func(): show_setup(1)], ["网络对战", "创建房间或加入朋友的对局", "network", show_network], ["蓝牙对战", "与附近的安卓设备连接", "bluetooth", show_bluetooth]]:
		column.add_child(action_row(entry[0], entry[1], entry[2], entry[3], true))

func choice(column: VBoxContainer, title: String, values: Array[String], selected: int, inline: bool = false) -> OptionButton:
	var parent: Container = column
	var caption = label(title, 15 if inline else 18)
	if inline:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)
		parent = row
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(caption)
	var item = OptionButton.new()
	for value in values:
		item.add_item(app.t(value))
	item.selected = clampi(selected, 0, values.size() - 1)
	item.custom_minimum_size.y = 50
	item.clip_text = true
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if inline:
		item.size_flags_horizontal = Control.SIZE_SHRINK_END
		item.custom_minimum_size.x = 160
		item.add_theme_font_size_override("font_size", 14)
	parent.add_child(item)
	return item

func show_setup(initial_mode: int = 0) -> void:
	var column = _page(app.t("新开局"), "setup")
	var mode = choice(column, app.t("对弈方式"), [app.t("人机对弈"), app.t("同机双人")], initial_mode)
	var side = choice(column, app.t("我的先后手"), [app.t("先手"), app.t("后手"), app.t("随机")], 0)
	var engine = choice(column, app.t("电脑"), ["YaneuraOu", app.t("基础电脑")], 0 if app.engine_provider == "yaneuraou" else 1)
	var levels: Array[String] = []
	for level in app.USI.LEVELS:
		levels.append(level.name)
	var level = choice(column, app.t("难度"), levels, app.engine_level)
	var clock_names: Array[String] = []
	for preset in app.Game.Clock.PRESETS: clock_names.append(preset.name)
	var clock_option = choice(column, app.t("用时"), clock_names, 0)
	column.add_child(label(app.t("人机与同机对局打开菜单时暂停计时。悔棋不返还已用时间。"), 16))
	column.add_child(label(app.t("开局前会保存当前棋谱。"), 16))
	column.add_child(button(app.t("开始"), func():
		var human = (1 if randi() % 2 == 0 else -1) if side.selected == 2 else (1 if side.selected == 0 else -1)
		var mode_value = "ai" if mode.selected == 0 else "local"
		var level_value = level.selected
		var provider_value = "yaneuraou" if engine.selected == 0 else "basic"
		var clock_value = clock_option.selected
		replace_game(func():
			app._start_match(mode_value, human, level_value, provider_value, clock_value)
			close()
		)
	))

func show_settings() -> void:
	var column = _page(app.t("设置"), "settings")
	section_heading(column, app.t("棋盘"))
	var appearance = choice(column, app.t("外观"), [app.t("清晰木纹"), app.t("经典平面"), app.t("立体木制")], ["anime2d", "minimal", "wood"].find(app.preferences.appearance), true)
	appearance.item_selected.connect(func(index): app.set_preference("appearance", ["anime2d", "minimal", "wood"][index]))
	var colors = choice(column, app.t("明暗"), [app.t("跟随系统"), app.t("浅色"), app.t("深色")], ["system", "light", "dark"].find(app.preferences.color_mode), true)
	colors.item_selected.connect(func(index): app.set_preference("color_mode", ["system", "light", "dark"][index]); show_settings.call_deferred())
	var language = choice(column, app.t("界面语言"), [app.t("简体中文"), app.t("日本語"), "English"], ["zh", "ja", "en"].find(app.preferences.language), true)
	language.item_selected.connect(func(index): app.set_preference("language", ["zh", "ja", "en"][index]); show_settings.call_deferred())
	var lettering = choice(column, app.t("棋字"), [app.t("菱湖书法"), app.t("日文明朝体")], 0 if app.preferences.piece_font == "ryoko" else 1, true)
	lettering.item_selected.connect(func(index): app.set_preference("piece_font", "ryoko" if index == 0 else "mincho"))
	section_heading(column, app.t("对局"))
	var pace = choice(column, app.t("落子节奏"), [app.t("快"), app.t("标准"), app.t("慢")], app.preferences.move_pace, true)
	pace.item_selected.connect(func(index): app.set_preference("move_pace", index))
	for entry in [[app.t("落子前确认"), "confirm_move"], [app.t("落子声音"), "sound"], [app.t("落点提示"), "hints"], [app.t("上一步标记"), "last_move"], [app.t("棋盘坐标"), "coordinates"], [app.t("同机自动转向"), "auto_flip"]]:
		var key: String = entry[1]
		var toggle = CheckButton.new()
		toggle.text = app.t(entry[0])
		toggle.custom_minimum_size.y = 50
		toggle.add_theme_font_size_override("font_size", 15)
		toggle.button_pressed = app.preferences.get(key)
		toggle.toggled.connect(func(value): app.set_preference(key, value))
		column.add_child(toggle)
	column.add_child(label(app.t("音量"), 16))
	var slider = HSlider.new()
	slider.max_value = 1
	slider.step = 0.05
	slider.value = app.preferences.volume
	slider.custom_minimum_size.y = 48
	slider.value_changed.connect(func(value): app.set_preference("volume", value))
	column.add_child(slider)
	column.add_child(button(app.t("试听"), func(): app._play_sound(true)))
	column.add_child(button(app.t("引擎与署名"), show_engine))

func show_resign() -> void:
	var column = _page(app.t("认输"), "resign")
	column.add_child(label(app.t("结束当前对局？")))
	column.add_child(button(app.t("确认认输"), func(): app._resign_game(); close()))
	column.add_child(button(app.t("继续下棋"), close))

func show_declaration() -> void:
	var column = _page(app.t("入玉宣言"), "declaration")
	var side: int = app.session.local_side if app.session != null else app.game.human_side if app.game.mode == "ai" else app.game.position.turn
	var status: Dictionary = app.game.position.declaration_status(side)
	column.add_child(label(app.t("本游戏采用 CSA 27 点宣言法。飞、角各计 5 点，其他子计 1 点，玉不计点；升变前后点值不变。只计敌阵内的己方子与持驹。"), 16))
	column.add_child(label(app.t("轮到自己：%s\n玉已入敌阵：%s\n玉未被将军：%s\n敌阵内除玉：%d / 10 枚\n得点：%d / %d") % [app.t("是") if status.own_turn else app.t("否"), app.t("是") if status.king_inside else app.t("否"), app.t("否") if status.in_check else app.t("是"), status.pieces, status.points, status.threshold]))
	var declare = button(app.t("宣言获胜"), func():
		if app._declare_win(): close()
		else: show_declaration()
	)
	declare.disabled = not status.valid or not app.game.result.is_empty() or (app.session != null and not app.session.can_move())
	column.add_child(declare)

func show_history(ply: int) -> void:
	app._set_replay(ply)
	var viewed = app._view_game()
	var column = _page(app.t("棋谱"), "history", true)
	history_label = label(app.t("%d / %d 手  %s", [app.replay_index, viewed.moves.size(), viewed.labels[app.replay_index - 1] if app.replay_index > 0 else app.t(app.t("初始局面"))]), 15)
	column.add_child(history_label)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for item in [[app.t("上一手"), -1], [app.t("下一手"), 1]]:
		var delta: int = item[1]
		var step = button(item[0], func(): show_history(app.replay_index + delta))
		step.disabled = app.replay_index == (0 if delta == -1 else viewed.moves.size())
		row.add_child(step)
	var seek = HSlider.new()
	seek.max_value = viewed.moves.size()
	seek.step = 1
	seek.value = app.replay_index
	seek.custom_minimum_size.y = 28
	seek.drag_ended.connect(func(_changed): show_history(int(seek.value)))
	seek.value_changed.connect(func(value): app._set_replay(int(value)); history_label.text = app.t("%d / %d 手  %s", [app.replay_index, viewed.moves.size(), viewed.labels[app.replay_index - 1] if app.replay_index > 0 else app.t(app.t("初始局面"))]))
	column.add_child(seek)
	column.add_child(button(app.t("分析此局面"), show_analysis))
	column.add_child(button(app.t("复制 USI 棋谱"), func(): DisplayServer.clipboard_set(app.Codec.history_command(viewed.moves)); show_message(app.t("已复制"))))
	if app.review_game != null: column.add_child(button(app.t("继续此局"), show_continue_record))

func show_analysis() -> void:
	var column = _page(app.t("局面分析"), "analysis", true)
	analysis_label = label(app.t("引擎准备中…"), 16)
	column.add_child(analysis_label)
	column.add_child(button(app.t("重新分析"), func(): app._request_analysis()))
	app._request_analysis()

func update_analysis(lines: String) -> void:
	if analysis_label != null and is_instance_valid(analysis_label):
		analysis_label.text = app.i18n.message(lines)

func show_archives() -> void:
	var column = _page(app.t("已存棋谱"), "archives")
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	column.add_child(actions)
	actions.add_child(button(app.t("导入棋谱"), import_record))
	actions.add_child(button(app.t("粘贴 JSON 导入"), show_paste))
	var records: Array = app._list_archives()
	if records.is_empty(): column.add_child(label(app.t("尚无已存棋谱。")))
	for record in records:
		var path: String = record.path
		column.add_child(action_row(record_display_title(record.title), app.t("复盘这局"), "history", func(): show_record_details(path)))

func record_display_title(value: String) -> String:
	# Format only the automatically generated timestamp; keep custom titles intact.
	var timestamp = RegEx.new()
	timestamp.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}-\\d{2}-\\d{2}$")
	if timestamp.search(value) == null: return value
	return value.left(10).replace("-", "/") + "   " + value.substr(11, 5).replace("-", ":")

func field(column: VBoxContainer, title: String, value: String, numeric: bool = false) -> LineEdit:
	column.add_child(label(title))
	var input = LineEdit.new()
	input.name = title
	input.text = value
	input.custom_minimum_size.y = 50
	input.max_length = 6 if numeric else 253
	input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if numeric else LineEdit.KEYBOARD_TYPE_DEFAULT
	column.add_child(input)
	input.focus_entered.connect(func():
		if page_scroll != null and is_instance_valid(page_scroll): page_scroll.ensure_control_visible.call_deferred(input)
	)
	return input

func show_network() -> void:
	if app.session != null:
		show_connection()
		return
	var column = _page(app.t("网络对战"), "network")
	column.add_child(button(app.t("创建对局"), show_host))
	column.add_child(button(app.t("加入对局"), show_join))
	column.add_child(label(app.t("同一网络可直接输入对方地址。跨网络连接需要可达的公网地址和开放的对局端口。"), 16))

func show_host() -> void:
	var column = _page(app.t("创建对局"), "host")
	var side = choice(column, app.t("我的先后手"), [app.t("先手"), app.t("后手"), app.t("随机")], 0)
	var port = field(column, app.t("端口"), "9231", true)
	var clock_names: Array[String] = []
	for preset in app.Game.Clock.PRESETS: clock_names.append(preset.name)
	var clock_option = choice(column, app.t("用时"), clock_names, 0)
	column.add_child(label(app.t("联机打开菜单仍计时。掉线与协商请求期间暂停，悔棋不返还已用时间。"), 16))
	var error = label("", 14)
	error.add_theme_color_override("font_color", app.palette().danger)
	column.add_child(error)
	column.add_child(button(app.t("创建"), func():
		if not port.text.is_valid_int() or int(port.text) < 1024 or int(port.text) > 65535:
			error.text = app.t("端口应为 1024 至 65535")
			return
		var seat = (1 if randi() % 2 == 0 else -1) if side.selected == 2 else (1 if side.selected == 0 else -1)
		app._host_network(int(port.text), seat, clock_option.selected)
		show_connection()
	))

func show_join() -> void:
	var column = _page(app.t("加入对局"), "join")
	var address = field(column, app.t("对方地址"), "")
	var port = field(column, app.t("端口"), "9231", true)
	var code = field(column, app.t("六位房间码"), "", true)
	var error = label("", 14)
	error.add_theme_color_override("font_color", app.palette().danger)
	column.add_child(error)
	column.add_child(button(app.t("连接"), func():
		if address.text.strip_edges().is_empty():
			error.text = app.t("请输入对方地址")
			return
		if not port.text.is_valid_int() or int(port.text) < 1024 or int(port.text) > 65535:
			error.text = app.t("端口应为 1024 至 65535")
			return
		if code.text.length() != 6 or not code.text.is_valid_int():
			error.text = app.t("请输入六位房间码")
			return
		app._join_network(address.text, int(port.text), code.text)
		show_connection()
	))

func show_connection() -> void:
	if app.session == null:
		show_network()
		return
	var column = _page(app.t("当前联机"), "connection")
	connection_label = label("")
	column.add_child(connection_label)
	update_connection()
	column.add_child(button(app.t("返回对局"), close))
	column.add_child(button(app.t("重新连接"), func(): app.session.reconnect()))
	if app.session.transport == "bluetooth" and platform != null:
		column.add_child(button(app.t("允许蓝牙权限"), func(): platform.requestBluetoothPermissions()))
		column.add_child(button(app.t("开启蓝牙"), func(): platform.enableBluetooth()))
		if app.session.is_host:
			column.add_child(button(app.t("让对方发现本机"), func(): platform.makeDiscoverable()))
	column.add_child(button(app.t("请求悔一手"), func():
		if not app.session.request("undo"): app._network_status(app.t("当前不能请求悔棋"))
	))
	column.add_child(button(app.t("提议和棋"), func():
		if not app.session.request("draw"): app._network_status(app.t("当前不能提议和棋"))
	))
	column.add_child(button(app.t("再战并交换先后手"), func():
		if not app.session.request("rematch"): app._network_status(app.t("结束本局后可以请求再战"))
	))
	if not app.session.offer.is_empty():
		column.add_child(button(app.t("查看对局请求"), show_offer))
	column.add_child(button(app.t("认输"), show_resign))
	column.add_child(button(app.t("退出联机"), show_leave_network))

func update_connection() -> void:
	if connection_label == null or not is_instance_valid(connection_label) or app.session == null:
		return
	var session = app.session
	var lines: Array[String] = [app.i18n.message(app.network_status), app.t("我的执方：") + (app.t("先手") if session.local_side == 1 else app.t("后手"))]
	lines.append(app.t("用时：") + app.t(app.Game.Clock.PRESETS[app.game.clock.preset].name))
	if session.transport == "tcp":
		lines.append(app.t("房间码：%s    端口：%d") % [session.room_code, session.port])
		if session.is_host:
			var addresses: Array[String] = []
			for address in IP.get_local_addresses():
				if ":" not in address and not address.begins_with("127.") and not address.begins_with("169.254."):
					addresses.append(address)
			lines.append(app.t("本机地址：") + ("、".join(addresses) if not addresses.is_empty() else app.t("未连接网络")))
		else:
			lines.append(app.t("对方地址：") + session.address)
	else:
		lines.append(app.t("蓝牙对战"))
	connection_label.text = "\n".join(lines)

func show_offer() -> void:
	if app.session == null or app.session.offer.is_empty():
		return
	var request: Dictionary = app.session.offer
	var names = {"undo": app.t("悔一手"), "draw": app.t("和棋"), "rematch": app.t("再战并交换先后手")}
	var local: bool = request.sender == app.session.local_side
	var column = _page(app.t("对局请求"), "offer")
	column.add_child(label((app.t("已请求") if local else app.t("对手请求")) + app.t(names[request.action])))
	if local:
		column.add_child(label(app.t("等待对方回应；30 秒后自动取消。")))
	else:
		column.add_child(button(app.t("同意"), func(): app.session.answer(true)))
		column.add_child(button(app.t("不同意"), func(): app.session.answer(false)))

func show_leave_network() -> void:
	var column = _page(app.t("退出联机"), "leave-network")
	column.add_child(label(app.t("退出后会断开连接并保存棋谱；对手可看到掉线状态。")))
	column.add_child(button(app.t("保存棋谱并退出"), func():
		if not app._archive_game():
			column.add_child(label(app.notice))
			return
		if not app._leave_network():
			column.add_child(label(app.notice))
			return
		app._new_game()
		close()
	))
	column.add_child(button(app.t("继续联机"), show_connection))

func show_bluetooth() -> void:
	if app.session != null:
		show_connection()
		return
	var column = _page(app.t("蓝牙对战"), "bluetooth")
	if platform == null or not platform.bluetoothSupported():
		column.add_child(label(app.t("蓝牙对战支持装有本游戏的两台安卓设备。当前设备请使用网络对战。")))
		column.add_child(button(app.t("网络对战"), show_network))
		return
	bluetooth_label = label(app.t("先允许附近设备权限并打开蓝牙，再创建或加入对局。"))
	column.add_child(bluetooth_label)
	column.add_child(button(app.t("允许蓝牙权限"), func(): platform.requestBluetoothPermissions()))
	column.add_child(button(app.t("开启蓝牙"), func(): platform.enableBluetooth()))
	var side = choice(column, app.t("创建对局时我的先后手"), [app.t("先手"), app.t("后手")], 0)
	var clock_names: Array[String] = []
	for preset in app.Game.Clock.PRESETS: clock_names.append(preset.name)
	var clock_option = choice(column, app.t("用时"), clock_names, 0)
	column.add_child(button(app.t("创建蓝牙对局"), func():
		if not platform.bluetoothPermissionsGranted():
			platform.requestBluetoothPermissions()
			return
		platform.makeDiscoverable()
		app._connect_bluetooth(true, "", 1 if side.selected == 0 else -1, clock_option.selected)
		show_connection()
	))
	column.add_child(button(app.t("搜索附近设备"), func(): platform.scanDevices()))
	column.add_child(button(app.t("停止搜索"), func(): platform.stopScan()))
	column.add_child(label(app.t("点击设备加入；未配对时会弹出系统配对提示。"), 16))
	devices_column = VBoxContainer.new()
	devices_column.add_theme_constant_override("separation", 8)
	column.add_child(devices_column)
	bluetooth_devices.clear()
	if platform.bluetoothPermissionsGranted():
		var paired = JSON.parse_string(platform.pairedDevices())
		if paired is Array:
			for device in paired: _bluetooth_device(JSON.stringify(device))

func _bluetooth_status(_state: String, message: String) -> void:
	if bluetooth_label != null and is_instance_valid(bluetooth_label):
		bluetooth_label.text = app.i18n.message(message)

func _bluetooth_device(json: String) -> void:
	if devices_column == null or not is_instance_valid(devices_column):
		return
	var device = JSON.parse_string(json)
	if not device is Dictionary or not device.get("address") is String:
		return
	if bluetooth_devices.has(device.address):
		return
	bluetooth_devices[device.address] = true
	var address: String = device.address
	devices_column.add_child(button(str(device.get("name", app.t("未命名设备"))) + "\n" + address, func():
		platform.stopScan()
		app._connect_bluetooth(false, address)
		show_connection()
	))

func sheet_height() -> float:
	return 0.0 if app.size.x > app.size.y else minf(290, app.safe_rect().size.y * 0.38)

func sheet_width() -> float:
	return minf(380, app.safe_rect().size.x * 0.46) if app.size.x > app.size.y else 0.0

func apply_theme() -> void:
	var p: Dictionary = app.palette()
	var theme = Theme.new()
	theme.default_font = app.text_font
	theme.default_font_size = 16
	# Popup entries need the same finger-sized targets as the surrounding form.
	theme.set_constant("v_separation", "PopupMenu", 32)
	for type in ["Button", "CheckButton", "OptionButton", "Label", "LineEdit", "TextEdit", "PopupMenu", "FileDialog", "Tree", "ItemList"]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_selected_color", "font_uneditable_color"]: theme.set_color(state, type, p.ink)
		theme.set_color("font_disabled_color", type, p.muted)
		theme.set_color("font_placeholder_color", type, p.muted)
		theme.set_color("caret_color", type, p.accent)
		if type == "Label": continue
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled", "panel", "read_only", "selected", "selected_focus"]:
			var style = Design.box(p.soft if state in ["hover", "pressed", "hover_pressed", "selected"] else p.surface, 12, 12)
			style.border_color = p.accent if state == "focus" else p.line
			style.set_border_width_all(2 if state == "focus" else 1 if type in ["LineEdit", "TextEdit"] else 0)
			theme.set_stylebox(state, type, style)
	for checked in [false, true]:
		for disabled in [false, true]:
			var key = ("checked" if checked else "unchecked") + ("_disabled" if disabled else "")
			theme.set_icon(key, "CheckButton", Design.toggle_icon(checked, disabled, p))
	for type in ["HSlider", "VScrollBar", "HScrollBar"]:
		for state in ["slider", "scroll", "grabber_area", "grabber_area_highlight", "grabber", "grabber_highlight", "grabber_pressed"]:
			var color: Color = p.accent if "grabber" in state else p.soft
			if type != "HSlider": color = p.line if "grabber" in state else Color.TRANSPARENT
			theme.set_stylebox(state, type, Design.box(color, 3, 2 if type != "HSlider" else 3))
	root.theme = theme
	if toolbar != null and toolbar.get_child_count() == 3:
		for index in range(toolbar.get_child_count()):
			toolbar.get_child(index).text = app.t(["悔棋", "棋谱", "更多"][index])
			toolbar.get_child(index).icon = Design.icon(["undo", "history", "more"][index], p.ink)
	for item in root.find_children("*", "Label", true, false):
		if item.has_theme_color_override("font_color"): item.add_theme_color_override("font_color", p.muted)
	backdrop.color = p.background
	if page != null:
		var style = page.get_theme_stylebox("panel").duplicate()
		if style is StyleBoxFlat:
			style.bg_color = p.background
			style.border_color = p.line
		page.add_theme_stylebox_override("panel", style)
	if file_dialog != null: file_dialog.theme = theme

func card_column(parent: Control) -> VBoxContainer:
	var card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", Design.box(app.palette().surface, 16, 14))
	parent.add_child(card)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	return column

func banner(parent: Control, compact: bool = false) -> void:
	var art = preload("res://scripts/shogi_brand_banner.gd").new()
	art.app = app
	art.compact = compact
	parent.add_child(art)

func action_row(title: String, subtitle: String, symbol: String, action: Callable, filled: bool = false) -> Button:
	var item = preload("res://scripts/shogi_action_row.gd").new()
	item.app = app
	item.title = app.t(title)
	item.subtitle = app.t(subtitle)
	item.symbol = symbol
	item.filled = filled
	item.pressed.connect(action)
	return item

func section_heading(parent: Control, title: String, detail: String = "", action: Callable = Callable()) -> void:
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 40 if not action.is_valid() else 48
	parent.add_child(row)
	var heading = label(title, 19)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(heading)
	if action.is_valid():
		var link = button(detail, action)
		link.size_flags_horizontal = Control.SIZE_SHRINK_END
		link.autowrap_mode = TextServer.AUTOWRAP_OFF
		link.custom_minimum_size.y = 48
		link.add_theme_font_size_override("font_size", 13)
		link.add_theme_stylebox_override("normal", Design.box(Color.TRANSPARENT, 8, 8))
		link.add_theme_color_override("font_color", app.palette().accent)
		row.add_child(link)
	elif not detail.is_empty():
		var caption = label(detail, 12)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(caption)

func show_home() -> void:
	app._leave_review()
	var column = _page(app.t("将棋"), "home")
	home_columns = BoxContainer.new()
	home_columns.vertical = app.safe_rect().size.x < 760
	home_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_columns.add_theme_constant_override("separation", 20)
	column.add_child(home_columns)
	var main = VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_stretch_ratio = 1.25
	main.add_theme_constant_override("separation", 12)
	home_columns.add_child(main)
	home_art = preload("res://scripts/shogi_brand_banner.gd").new()
	home_art.app = app
	home_art.home = true
	main.add_child(home_art)
	var start = button(app.t("开始对弈"), show_play)
	start.name = "HomeStart"
	start.autowrap_mode = TextServer.AUTOWRAP_OFF
	home_art.add_child(start)
	home_art.home_button = start
	home_art.layout_action.call_deferred()
	if not app.game.moves.is_empty() or app.session != null:
		var finished: bool = not app.game.result.is_empty()
		main.add_child(action_row(app.t("查看对局结果") if finished else app.t("继续对局"), app.i18n.result(app.game) if finished else app.t("第 %d 手", [app.game.moves.size() + 1]), "history" if finished else "play", show_result if finished else close, true))
	var aside = VBoxContainer.new()
	aside.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aside.add_theme_constant_override("separation", 4)
	home_columns.add_child(aside)
	tutorial._ensure_loaded()
	var mastered = 0
	for state in tutorial.progress.data.steps.values():
		if state.get("mastered", false): mastered += 1
	section_heading(aside, app.t("每日一点进步"), app.t("已掌握 %d 个练习", [mastered]))
	aside.add_child(action_row(app.t("继续上次学习") if not tutorial.progress.data.resume.is_empty() else app.t("开始学习"), app.t("每一步，都是新的可能。"), "learn", tutorial.show_catalog, true))
	section_heading(aside, app.t("最近棋谱"), app.t("全部棋谱"), show_archives)
	var saved: Array = app._list_archives()
	if saved.is_empty(): aside.add_child(label(app.t("下完一局，在这里回顾你的每一步。"), 14))
	else:
		for entry in saved.slice(0, 2):
			var path: String = entry.path
			aside.add_child(action_row(record_display_title(entry.title), app.t("复盘这局"), "history", func(): show_record_details(path)))
	layout()

func show_promotion() -> void:
	var moves = app.promotion_moves.duplicate(true)
	var column = _page(app.t("选择升变"), "promotion", true)
	column.add_child(label(app.t("进入敌阵，可以让棋子更强。"), 14))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for move in moves:
		var choice: Dictionary = move
		var before: int = absi(app._play_game().position.board[choice.from])
		var name: String = app.GLYPHS[before + 8 if choice.promote else before]
		var item = button(app.t("升变") if choice.promote else app.t("不变"), func():
			close()
			app._propose_move(choice)
		)
		item.custom_minimum_size.y = 74
		item.icon = piece_icon(name)
		item.add_theme_color_override("icon_normal_color", app.palette().ink)
		item.add_theme_color_override("icon_hover_color", app.palette().ink)
		item.add_theme_color_override("icon_pressed_color", app.palette().ink)
		item.expand_icon = true
		item.add_theme_constant_override("icon_max_width", 42)
		row.add_child(item)
	column.add_child(button(app.t("取消"), func(): app._clear_selection(); close()))

func piece_icon(glyph: String) -> Texture2D:
	var image = Image.create(80, 80, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	# The actual preview is rendered by the existing piece-face SVG resources.
	var index: int = app.GLYPHS.find(glyph)
	if index > 0:
		return load("res://assets/glyphs/" + app.board_view.FACE_NAMES[index] + ".svg")
	return ImageTexture.create_from_image(image)

func show_move_confirmation() -> void:
	var column = _page(app.t("确认这一步"), "confirm-move", true)
	column.add_child(label(app._play_game().position.notation(app.pending_move), 26))
	column.add_child(label(app.t("确认后落子；取消可重新选择。"), 14))
	column.add_child(button(app.t("确认落子"), func(): app._confirm_pending_move()))
	column.add_child(button(app.t("取消"), func(): app._clear_selection(); close()))

func show_result() -> void:
	if app.game.result.is_empty(): return
	result_shown = str([app.game.moves, app.game.result])
	var column = _page(app.t("对局结束"), "result")
	banner(column, true)
	var row = HBoxContainer.new()
	column.add_child(row)
	var portrait = TextureRect.new()
	portrait.texture = load("res://assets/brand/ai-icon.png")
	portrait.custom_minimum_size = Vector2(64, 64)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var outcome = label(app.i18n.result(app.game), 23)
	outcome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(outcome)
	column.add_child(label(app.t("共 %d 手", [app.game.moves.size()]), 14))
	column.add_child(button(app.t("复盘这局"), func(): show_history(app.game.moves.size())))
	column.add_child(button(app.t("再来一局"), func(): app._restart_request(); close()))
	column.add_child(button(app.t("回到首页"), show_home))

func show_engine() -> void:
	var column = _page(app.t("引擎与署名"), "engine")
	column.add_child(label(app.usi.engine_name if app.usi != null and not app.usi.engine_name.is_empty() else app.t(app.t("未启动"))))
	if app.usi != null and not app.usi.last_error.is_empty(): column.add_child(label(app.i18n.message(app.usi.last_error)))
	column.add_child(label(app.t("难度通过搜索深度、局面数和思考时间调整，不代表段位评级。"), 15))
	var levels: Array[String] = []
	for level in app.USI.LEVELS: levels.append(level.name)
	var level = choice(column, app.t("电脑难度"), levels, app.engine_level)
	level.item_selected.connect(func(index): app.engine_level = index; app._save_settings())
	column.add_child(button(app.t("重新启动引擎"), func(): app._load_engine(); show_engine()))
	column.add_child(button(app.t("基础电脑"), func(): app.engine_provider = "basic"; app._save_settings(); close()))
	column.add_child(button("YaneuraOu", func(): app.engine_provider = "yaneuraou"; app._save_settings(); app._load_engine(); close()))
	column.add_child(label(app.t("YaneuraOu：GPL-3.0-or-later；源码和许可证随引擎提供。"), 15))
	column.add_child(label(app.t("菱湖字面：LuffyKudo · CC BY-SA 4.0。字体：Noto Sans SC / JP、Noto Serif JP · SIL OFL 1.1。"), 15))
	column.add_child(button(app.t("素材署名"), func(): OS.shell_open("https://github.com/LuffyKudo/Shogi-Themes/tree/main/Ryoko")))
	column.add_child(button(app.t("查看源码与许可证"), func():
		var info = _page(app.t("查看源码与许可证"), "licenses")
		for path in ["res://assets/licenses/yaneuraou-NOTICE.md", "res://assets/licenses/ARTWORK-NOTICE.txt", "res://assets/fonts/OFL-NotoSerifJP.txt"]:
			if FileAccess.file_exists(path): info.add_child(label(FileAccess.get_file_as_string(path), 13))
	))

func show_message(message: String) -> void:
	if page != null:
		var controls = page.find_children("*", "VBoxContainer", true, false)
		if not controls.is_empty(): controls[0].add_child(label(app.i18n.message(message), 14))
	else:
		app.notice = message
		app._redraw()

func show_record_details(path: String) -> void:
	record_path = path
	var game = app.records.read(path)
	if game == null: show_archives(); show_message(app.records.error); return
	var column = _page(app.t("棋谱"), "record-details")
	var title = path.get_file().trim_suffix(".json")
	for entry in app.records.list_all():
		if entry.path == path: title = entry.title
	column.add_child(label(record_display_title(title), 22))
	column.add_child(label(str(game.moves.size()) + "  ·  " + app.i18n.result(game)))
	column.add_child(button(app.t("查看"), func():
		if app._load_archive(path): show_history(app.review_game.moves.size())
		else: show_message(app.t("联机中只能查看当前棋谱，退出联机后可继续其他棋局。") if app.session != null else app.records.error)
	))
	column.add_child(button(app.t("重命名"), func():
		var form = _page(app.t("重命名"), "rename-record")
		var input = field(form, app.t("棋谱名称"), title)
		form.add_child(button(app.t("确定"), func():
			if app.records.rename_record(path, input.text): show_record_details(path)
			else: show_message(app.records.error)
		))
	))
	column.add_child(button(app.t("导出棋谱"), func(): export_record(path)))
	column.add_child(button(app.t("复制 JSON"), func(): DisplayServer.clipboard_set(JSON.stringify(game.to_data(), "\t")); show_message(app.t("已复制"))))
	column.add_child(button(app.t("删除"), func():
		var confirm = _page(app.t("删除这份棋谱？"), "delete-record")
		confirm.add_child(label(title))
		confirm.add_child(button(app.t("删除"), func():
			if app.records.delete_record(path): show_archives()
			else: show_message(app.records.error)
		))
		confirm.add_child(button(app.t("取消"), func(): show_record_details(path)))
	))

func show_continue_record() -> void:
	var column = _page(app.t("继续此局"), "continue-record")
	column.add_child(label(app.t("这将归档当前对局，并从查看的局面继续。")))
	column.add_child(button(app.t("确定"), func():
		if app._continue_review(): close()
		else: show_message(app.notice)
	))
	column.add_child(button(app.t("取消"), func(): show_history(app.replay_index)))

func import_record() -> void:
	if platform != null and platform.has_method("pickRecord"):
		platform.pickRecord()
		return
	_open_file(false, func(path):
		var game = app.records.read(path)
		if game == null: show_message(app.records.error); return
		var saved = app.records.archive(game, path.get_file().trim_suffix(".json"))
		if saved.is_empty(): show_message(app.records.error)
		else: show_record_details(saved)
	)

func export_record(path: String) -> void:
	var game = app.records.read(path)
	if game == null: show_message(app.records.error); return
	if platform != null and platform.has_method("exportRecord"):
		platform.exportRecord(JSON.stringify(game.to_data(), "\t"))
		return
	_open_file(true, func(destination):
		show_message(app.t("已导出棋谱") if app.records.write(destination, game, destination.get_file().trim_suffix(".json")) else app.records.error)
	)

func _open_file(save: bool, callback: Callable) -> void:
	if file_dialog != null: file_dialog.queue_free()
	file_dialog = FileDialog.new()
	file_dialog.theme = root.theme
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = app.t("导出棋谱") if save else app.t("导入棋谱")
	file_dialog.add_filter("*.json", app.t("棋谱"))
	if save: file_dialog.current_file = "shogi-record.json"
	file_dialog.file_selected.connect(callback)
	root.add_child(file_dialog)
	file_dialog.popup_centered_ratio(0.85)
	file_dialog.get_ok_button().text = app.t("导出棋谱") if save else app.t("导入棋谱")
	file_dialog.get_cancel_button().text = app.t("取消")

func show_paste() -> void:
	var column = _page(app.t("粘贴 JSON 导入"), "paste-record")
	var input = TextEdit.new()
	input.custom_minimum_size.y = 200
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.text = DisplayServer.clipboard_get().left(2097152)
	column.add_child(input)
	column.add_child(button(app.t("导入"), func(): _import_text(input.text)))

func _import_text(text: String) -> void:
	if text.length() > 2097152: show_message(app.t("这份棋谱无法读取。")); return
	var parser = JSON.new()
	var data = parser.data if parser.parse(text) == OK else null
	var game = app.Game.from_data(data.get("game", data) if data is Dictionary else data)
	if game == null: show_message(app.t("这份棋谱无法读取。")); return
	var saved = app.records.archive(game)
	if saved.is_empty(): show_message(app.records.error)
	else: show_record_details(saved)

func replace_game(action: Callable) -> void:
	if app.game.moves.is_empty() and app.session == null:
		if app._archive_game(): action.call()
		else: show_message(app.notice)
		return
	confirmation_callback = action
	var column = _page(app.t("开始新的对局？"), "replace-game")
	column.add_child(label(app.t("当前棋谱将保存；联机对局会断开连接。"), 16))
	column.add_child(button(app.t("保存并开始"), func():
		if app._archive_game(): confirmation_callback.call()
		else: show_message(app.notice)
	))
	column.add_child(button(app.t("继续对局"), close))
