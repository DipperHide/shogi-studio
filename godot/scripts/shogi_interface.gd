extends CanvasLayer
## Menus live here; the board view exposes only a small menu button.
const PAPER = Color("faf5e9")
const INK = Color("35433b")
const MUTED = Color("7a8277")
const ACCENT = Color("52634d")
var app
var root: Control
var page: Control
var hud: Control
var modal: Control
var menu_button: Button
var replay_bar: HBoxContainer
var replay_label: Label
var replay_previous: Button
var replay_next: Button
var check_label: Label
const HomeStage = preload("res://scripts/shogi_home_stage.gd")
const HomeCard = preload("res://scripts/shogi_home_card.gd")
var home_stage
var home_card: Control
var home_title: Label
var home_description: Label
var home_preview: TextureRect
var home_enter: Button
var home_buttons: Array[Button] = []
var home_settings: Button
var home_selected: int = 1
var home_continue: Button
var setup_mode: String = "ai"
var setup_side: int = 1
var setup_difficulty: int = 1
var page_name: String = "home"
var icons: Dictionary = {}

func initialize(owner_node) -> void:
	app = owner_node
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme = Theme.new()
	var font = FontVariation.new()
	font.base_font = preload("res://assets/fonts/NotoSansSC.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):420.0}
	theme.default_font = font
	theme.default_font_size = 19
	for type_name in ["Label","Button","CheckButton","ItemList"]:
		theme.set_font("font",type_name,font)
		theme.set_color("font_color",type_name,INK)
	theme.set_color("font_hover_color","Button",INK)
	theme.set_color("font_pressed_color","Button",PAPER)
	theme.set_color("font_disabled_color","Button",Color("adb1a6"))
	theme.set_stylebox("normal","Button",style(Color(1,1,1,0.4),10))
	theme.set_stylebox("hover","Button",style(Color("ffffff"),10))
	theme.set_stylebox("pressed","Button",style(ACCENT,10))
	theme.set_stylebox("disabled","Button",style(Color(1,1,1,0.12),10))
	theme.set_stylebox("focus","Button",style(Color.TRANSPARENT,10,Color("b3bb9e")))
	theme.set_stylebox("panel","ItemList",style(Color("eae9df"),8))
	theme.set_stylebox("selected","ItemList",style(Color("d4ddcc"),6))
	theme.set_stylebox("selected_focus","ItemList",style(Color("d4ddcc"),6))
	theme.set_color("font_selected_color","ItemList",INK)
	root.theme = theme
	_build_hud()
	app.get_viewport().size_changed.connect(layout)

static func style(color: Color, radius: int = 10, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var out = StyleBoxFlat.new()
	out.bg_color = color
	out.set_corner_radius_all(radius)
	out.set_content_margin_all(12)
	if border.a > 0:
		out.set_border_width_all(1)
		out.border_color = border
	return out

func label(value: String, font_size: int = 19, color: Color = INK) -> Label:
	var item = Label.new()
	item.text = value
	item.add_theme_font_size_override("font_size",font_size)
	item.add_theme_color_override("font_color",color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func button(value: String, callback: Callable, primary: bool = false) -> Button:
	var item = Button.new()
	item.text = value
	item.custom_minimum_size.y = 54
	item.pressed.connect(callback)
	if primary:
		item.add_theme_stylebox_override("normal",style(ACCENT))
		item.add_theme_stylebox_override("hover",style(Color("65765c")))
		item.add_theme_color_override("font_color",PAPER)
		item.add_theme_color_override("font_hover_color",Color.WHITE)
	return item

func icon(name: String) -> Texture2D:
	if icons.has(name):
		return icons[name]
	var paths = {"menu":"<path d='M6 9h20M6 16h20M6 23h20'/>","back":"<path d='m19 7-9 9 9 9'/>","close":"<path d='m9 9 14 14M23 9 9 23'/>","next":"<path d='m13 7 9 9-9 9'/>","undo":"<path d='M10 9H5v-5M5 9c8-9 23-1 21 10-1 6-7 10-13 7'/>","settings":"<circle cx='16' cy='16' r='5'/><path d='M16 3v4m0 18v4M3 16h4m18 0h4M7 7l3 3m12 12 3 3M7 25l3-3M22 10l3-3'/>"}
	var svg = "<svg xmlns='http://www.w3.org/2000/svg' width='32' height='32' viewBox='0 0 32 32'><g fill='none' stroke='#455447' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>%s</g></svg>" % paths.get(name,paths.menu)
	var image = Image.new()
	image.load_svg_from_string(svg)
	icons[name] = ImageTexture.create_from_image(image)
	return icons[name]

func icon_button(name: String, hint: String, callback: Callable) -> Button:
	var item = button("",callback)
	item.icon = icon(name)
	item.tooltip_text = hint
	item.custom_minimum_size = Vector2(54,54)
	item.add_theme_stylebox_override("pressed",style(Color("dce2d1"),10))
	return item

func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	menu_button = icon_button("menu","对局菜单",show_pause)
	menu_button.add_theme_stylebox_override("normal",style(Color(0.96,0.95,0.91,0.74),27))
	hud.add_child(menu_button)
	check_label = label("王手",16,Color("813e31"))
	hud.add_child(check_label)
	replay_bar = HBoxContainer.new()
	replay_bar.add_theme_constant_override("separation",16)
	hud.add_child(replay_bar)
	replay_previous = icon_button("back","上一手",func(): app._set_replay(maxi(0,app.replay_index-1)))
	replay_bar.add_child(replay_previous)
	replay_label = label("",17,PAPER)
	replay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	replay_label.custom_minimum_size.x = 100
	replay_bar.add_child(replay_label)
	replay_next = icon_button("next","下一手",func(): app._set_replay(mini(app.game.moves.size(),app.replay_index+1)))
	replay_bar.add_child(replay_next)
	replay_bar.add_child(icon_button("close","结束回放",app._toggle_replay))

func _clear_page() -> void:
	home_stage = null
	home_buttons.clear()
	if page != null:
		root.remove_child(page)
		page.queue_free()
		page = null

func _home_base(title: String, subtitle: String = "") -> VBoxContainer:
	close_modal()
	_clear_page()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var veil = ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.color = Color("e4e7dc")
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(veil)
	var backdrop = Panel.new()
	backdrop.name = "Backdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_theme_stylebox_override("panel",style(Color("eff0e8"),4,Color.WHITE))
	page.add_child(backdrop)
	var column = VBoxContainer.new()
	column.name = "Content"
	column.add_theme_constant_override("separation",16)
	page.add_child(column)
	if title != "将棋":
		var back = icon_button("back","返回主页",show_home)
		back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		column.add_child(back)
	else:
		column.add_child(label("S H O G I",13,MUTED))
	var heading = label(title,80 if title == "将棋" else 36)
	if title == "将棋":
		heading.add_theme_font_override("font",preload("res://assets/fonts/YujiSyuku-Regular.ttf"))
	column.add_child(heading)
	if not subtitle.is_empty():
		column.add_child(label(subtitle,16,MUTED))
	var line = ColorRect.new()
	line.color = Color("a4ad94")
	line.custom_minimum_size = Vector2(40,2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(line)
	layout.call_deferred()
	return column

func show_home() -> void:
	app._go_home()
	page_name = "home"
	close_modal()
	_clear_page()
	page = Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(page)
	var background = ColorRect.new()
	background.color = Color("e4e7dc")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(background)
	home_stage = HomeStage.new()
	page.add_child(home_stage)
	home_stage.setup(app)
	home_stage.chosen.connect(_choose_home)
	home_card = HomeCard.new()
	page.add_child(home_card)
	home_preview = TextureRect.new()
	home_preview.texture = home_stage.preview.get_texture()
	home_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	home_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	home_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	home_card.add_child(home_preview)
	home_title = label("",40,Color("232822"))
	home_card.add_child(home_title)
	home_description = label("",19,Color("4b554a"))
	home_card.add_child(home_description)
	home_enter = button("进入",_enter_home,true)
	home_card.add_child(home_enter)
	for index in range(3):
		var item = button(["查看棋局" if not app.game.result.is_empty() else "继续对局","人机对弈","同机对弈"][index],_choose_home.bind(index))
		item.add_theme_stylebox_override("normal",style(Color.TRANSPARENT,0))
		item.add_theme_stylebox_override("disabled",style(Color.TRANSPARENT,0))
		item.add_theme_stylebox_override("hover",style(Color(1,1,1,0.30),6))
		item.disabled = index == 0 and not app.has_game
		home_buttons.append(item)
		page.add_child(item)
	home_continue = home_buttons[0] if app.has_game else null
	home_settings = icon_button("settings","偏好设置",show_settings.bind(false))
	page.add_child(home_settings)
	home_selected = 0 if app.has_game else 1
	_update_home(false)
	refresh()
	layout()

func _choose_home(index: int) -> void:
	if index == 0 and not app.has_game:
		return
	if home_selected == index:
		_enter_home()
	else:
		home_selected = index
		_update_home()

func _update_home(animate: bool = true) -> void:
	home_stage.select(home_selected,animate)
	home_title.text = home_buttons[home_selected].text
	home_description.text = ["接着上一局，慢慢落下一子。" if app.game.result.is_empty() else "回到棋盘，重温这场对局。","选好执子与难度，和电脑下一局。","面对面，轮流执子。一个棋盘，两个人。"][home_selected]
	home_enter.text = "继续" if home_selected == 0 and app.game.result.is_empty() else "进入"
	for index in range(3):
		home_buttons[index].add_theme_color_override("font_color",Color("a43b30") if index == home_selected else INK)

func _enter_home() -> void:
	if home_selected == 0:
		app._resume_game()
	else:
		show_setup("ai" if home_selected == 1 else "local")

func show_setup(mode: String) -> void:
	page_name = "setup"
	setup_mode = mode
	var column = _home_base("人机对弈" if mode == "ai" else "同机对弈")
	if mode == "ai":
		column.add_child(label("执子",16,MUTED))
		column.add_child(_segments(["先手","后手","随机"],[1,-1,0],setup_side,func(value): setup_side = value))
		column.add_child(label("电脑难度",16,MUTED))
		column.add_child(_segments(["入门","标准"],[0,1],setup_difficulty,func(value): setup_difficulty = value))
	else:
		column.add_child(label("两个人，一张棋盘。",19))
		column.add_child(_toggle("落子后自动转向",app.preferences.auto_flip,func(value): app._preference("auto_flip",value)))
	var space = Control.new()
	space.custom_minimum_size.y = 8
	column.add_child(space)
	column.add_child(button("开始对局",_begin_configured_game,true))
	if app.has_game:
		column.add_child(label("开始后将替换当前对局",14,MUTED))

func _begin_configured_game() -> void:
	app._start_game(setup_mode,setup_side,setup_difficulty)

func _segments(names: Array, values: Array, selected: int, callback: Callable) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	var group = ButtonGroup.new()
	for index in range(names.size()):
		var choice = button(names[index],callback.bind(values[index]))
		choice.toggle_mode = true
		choice.button_group = group
		choice.button_pressed = values[index] == selected
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(choice)
	return row

func _toggle(title: String, value: bool, callback: Callable) -> HBoxContainer:
	var row = HBoxContainer.new()
	var text = label(title,18)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var toggle = CheckButton.new()
	toggle.button_pressed = value
	toggle.custom_minimum_size = Vector2(66,44)
	toggle.toggled.connect(callback)
	row.add_child(toggle)
	return row

func show_settings(in_game: bool = false) -> void:
	page_name = "settings"
	var column = dialog("偏好设置",440) if in_game else _home_base("偏好设置")
	column.add_child(_toggle("落子声音",app.preferences.sound,func(value): app._preference("sound",value)))
	var volume_row = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation",16)
	column.add_child(volume_row)
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = app.preferences.volume
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(200,48)
	slider.value_changed.connect(func(value): app._preference("volume",value))
	volume_row.add_child(slider)
	volume_row.add_child(button("试听",app._play_sound.bind(true)))
	column.add_child(_toggle("落点提示",app.preferences.hints,func(value): app._preference("hints",value)))
	column.add_child(_toggle("上一步标记",app.preferences.last_move,func(value): app._preference("last_move",value)))
	column.add_child(_toggle("棋盘坐标",app.preferences.coordinates,func(value): app._preference("coordinates",value)))
	var credit = button("书法与素材署名",show_artwork_credits)
	credit.custom_minimum_size.y = 32
	credit.add_theme_font_size_override("font_size",14)
	if in_game:
		var footer = HBoxContainer.new()
		footer.add_theme_constant_override("separation",12)
		credit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(credit)
		footer.add_child(button("完成",close_modal,true))
		column.add_child(footer)
	else:
		column.add_child(credit)

func show_artwork_credits() -> void:
	var column = dialog("书法与素材",510)
	var credits = RichTextLabel.new()
	credits.bbcode_enabled = true
	credits.custom_minimum_size = Vector2(450,240)
	credits.add_theme_font_size_override("normal_font_size",17)
	credits.add_theme_color_override("default_color",INK)
	credits.text = "菱湖体将棋字面：LuffyKudo\n[url=https://github.com/LuffyKudo/Shogi-Themes/tree/main/Ryoko]原始字面与作者[/url] · [url=https://creativecommons.org/licenses/by-sa/4.0/]CC BY-SA 4.0[/url]\n\n本作保留书法轮廓，移除插图木胎及底边铭文，重新排入三维棋子并合成木纹。衍生字面素材沿用 CC BY-SA 4.0。\n\n界面：Noto Sans SC；坐标：Yuji Syuku。两者采用 SIL OFL 1.1。"
	credits.meta_clicked.connect(func(link): OS.shell_open(str(link)))
	column.add_child(credits)

func show_game() -> void:
	close_modal()
	_clear_page()
	page_name = "game"
	refresh()
	layout()

func show_pause() -> void:
	if app.busy:
		return
	app._cancel_pointer()
	var column = dialog("对局",380)
	column.add_child(button("继续对局",close_modal,true))
	var undo = button("悔棋",func(): close_modal(); app._undo())
	undo.disabled = app.game.moves.is_empty()
	column.add_child(undo)
	column.add_child(button("翻转棋盘",func(): close_modal(); app._flip()))
	var replay = button("棋谱回放",show_record)
	replay.disabled = app.game.moves.is_empty()
	column.add_child(replay)
	column.add_child(button("偏好设置",show_settings.bind(true)))
	column.add_child(button("返回主页",show_home))
	var resign = button("认输",show_resign)
	resign.disabled = not app.game.result.is_empty() or app.replay_index >= 0 or app._is_ai_turn()
	column.add_child(resign)

func dialog(title: String, width: float = 440) -> VBoxContainer:
	close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade = ColorRect.new()
	shade.color = Color(0.11,0.16,0.13,0.32)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = width
	var box = style(PAPER,18)
	box.set_content_margin_all(24)
	box.shadow_color = Color(0,0,0,0.13)
	box.shadow_size = 24
	panel.add_theme_stylebox_override("panel",box)
	center.add_child(panel)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	panel.add_child(column)
	var heading = HBoxContainer.new()
	column.add_child(heading)
	var text = label(title,27)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(text)
	heading.add_child(icon_button("close","关闭",close_modal))
	return column

func close_modal() -> void:
	if modal != null:
		root.remove_child(modal)
		modal.queue_free()
		modal = null
	if app != null:
		app._cancel_pointer()

func show_promotion(candidates: Array[Dictionary]) -> void:
	var column = dialog("升变？",390)
	var choices = HBoxContainer.new()
	choices.add_theme_constant_override("separation",12)
	column.add_child(choices)
	for move in candidates:
		var choice = button("成" if move.promote else "不成",func(): close_modal(); app._commit(move),move.promote)
		choice.custom_minimum_size.y = 76
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.add_theme_font_size_override("font_size",28)
		choices.add_child(choice)

func show_resign() -> void:
	var column = dialog("确认认输？",390)
	column.add_child(button("认输",func(): close_modal(); app._resign(),true))
	column.add_child(button("继续对局",close_modal))

func show_result() -> void:
	var column = dialog("本局结束",460)
	var result = label(app.game.result,21)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size.x = 380
	column.add_child(result)
	column.add_child(button("回看棋谱",func(): close_modal(); app._set_replay(app.game.moves.size()),true))
	column.add_child(button("返回主页",show_home))

func show_record() -> void:
	var column = dialog("棋谱",400)
	var record = ItemList.new()
	record.custom_minimum_size = Vector2(340,320)
	for index in range(app.game.labels.size()):
		record.add_item("%03d   %s" % [index+1,app.game.labels[index]])
	record.item_selected.connect(func(index): close_modal(); app._set_replay(index+1))
	column.add_child(record)
	column.add_child(button("从头回放",func(): close_modal(); app._set_replay(0),true))

func refresh() -> void:
	if hud == null:
		return
	hud.visible = app.screen == "game"
	menu_button.disabled = app.busy
	replay_bar.visible = app.replay_index >= 0
	replay_label.text = "%d / %d" % [maxi(0,app.replay_index),app.game.moves.size()]
	replay_previous.disabled = app.busy or app.replay_index <= 0
	replay_next.disabled = app.busy or app.replay_index >= app.game.moves.size()
	check_label.visible = app.screen == "game" and app._display_position().in_check(app._display_position().turn)

func layout() -> void:
	if root == null:
		return
	var size = app.get_viewport().get_visible_rect().size
	menu_button.position = Vector2(28,28)
	check_label.position = Vector2(size.x-88,40)
	replay_bar.position = Vector2((size.x-344)/2,size.y-66)
	if page != null and page_name == "home":
		home_stage.position = Vector2.ZERO
		home_stage.size = size
		home_card.position = Vector2(size.x*0.07,size.y*0.105)
		home_card.size = Vector2(size.x*0.86,size.y*0.37)
		home_preview.position = Vector2(home_card.size.x*.065,home_card.size.y*.13)
		home_preview.size = Vector2(home_card.size.x*.245,home_card.size.y*.57)
		home_title.position = Vector2(home_card.size.x*.355,home_card.size.y*.12)
		home_description.position = Vector2(home_card.size.x*.355,home_card.size.y*.40)
		home_enter.position = Vector2(home_card.size.x*.80,home_card.size.y*.61)
		home_enter.size = Vector2(125,48)
		for index in range(3):
			home_buttons[index].position = Vector2(size.x*(float(index)+0.5)/3.0-115,size.y*.835)
			home_buttons[index].size = Vector2(230,54)
		home_settings.position = Vector2(size.x-84,24)
	elif page != null:
		var column = page.get_node("Content")
		column.position = Vector2((size.x-440)/2,60)
		column.size = Vector2(440,0)
		var backdrop = page.get_node_or_null("Backdrop")
		if backdrop != null:
			backdrop.position = Vector2((size.x-570)/2,32)
			backdrop.size = Vector2(570,size.y-64)
