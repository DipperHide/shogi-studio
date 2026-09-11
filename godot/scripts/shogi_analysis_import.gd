extends RefCounted
const Draft = preload("res://scripts/shogi_import_draft.gd")
const FLOW = ["analysis-import", "analysis-help"]
var ui
var draft = Draft.new()
var input: TextEdit
var feedback: Label
var description: Label
var load_button: Button
var paste_button: Button
var file_button: Button
var busy = false
var ticket = 0
var picker_ticket = 0
var job
var changing = false
var archive_file = false

func initialize(menu) -> void:
	ui = menu
	if ui.platform != null and ui.platform.has_signal("analysis_record_imported"):
		ui.platform.analysis_record_imported.connect(file_received)

func leaving(name: String) -> void:
	if name in FLOW: return
	ticket += 1; picker_ticket = 0
	if is_instance_valid(ui.file_dialog) and ui.file_dialog.has_meta("analysis_import"):
		ui.file_dialog.hide()
		ui.file_dialog.queue_free(); ui.file_dialog = null

func action(caption: String, callback: Callable, id: String, icon: String = "", height: int = 46) -> Button:
	var item = ui.compact_button(caption, callback, height)
	item.name = id; item.tooltip_text = caption; item.accessibility_name = caption
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not icon.is_empty():
		item.icon = ui.reference_icon(icon); item.expand_icon = true
		item.add_theme_constant_override("icon_max_width", 21)
		item.add_theme_constant_override("h_separation", 12)
	item.add_theme_stylebox_override("normal", ui.Design.box(Color.TRANSPARENT, 10, 12))
	return item

func show(tab: int = -1) -> void:
	if tab == 2: show_recent(); return
	if tab < 0: tab = int(ui.app.preferences.studio.get("analysis_tab", 0))
	if tab == 1: ui.archive_view.enter(false); return
	ui.archive_tab = clampi(tab, 0, 1)
	var content = ui.report_dialog("分析棋谱", "analysis-import", "载入棋谱，查看局面与候选着手", "ic_drawer_analyze_outline")
	var outer = ui.page.get_child(0)
	var track = PanelContainer.new()
	track.name = "AnalysisSourceTabs"
	track.add_theme_stylebox_override("panel", ui.Design.box(ui.app.palette().soft, 20, 3))
	outer.add_child(track); outer.move_child(track, 1)
	var tabs = HBoxContainer.new(); tabs.add_theme_constant_override("separation", 0); track.add_child(tabs)
	for index in range(2):
		var choice = index
		var item = action(["棋谱文字 / 文件", "历史大赛"][index], func(): select_tab(choice), "AnalysisTab" + str(index), "", 34)
		item.alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.add_theme_font_size_override("font_size", 13)
		item.add_theme_stylebox_override("normal", ui.Design.box(ui.app.palette().accent if index == ui.archive_tab else Color.TRANSPARENT, 17, 4))
		if index == ui.archive_tab: item.add_theme_color_override("font_color", Color.WHITE)
		tabs.add_child(item)
	build_input(content)
	apply_theme()
	layout()

func apply_theme() -> void:
	if ui.page == null or ui.page_name not in FLOW: return
	var colors: Dictionary = ui.app.palette()
	for item in ui.page.find_children("*", "Button", true, false):
		for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]: item.add_theme_color_override(state, colors.ink)
		if str(item.name).begins_with("AnalysisTab"):
			var selected = item.name == "AnalysisTab" + str(ui.archive_tab)
			item.add_theme_stylebox_override("normal", ui.Design.box(colors.accent if selected else Color.TRANSPARENT, 17, 4))
			item.add_theme_color_override("font_color", Color.WHITE if selected else colors.muted)
	var card = ui.page.find_child("AnalysisInputCard", true, false)
	if card != null:
		var style = card.get_theme_stylebox("panel")
		style.bg_color = colors.surface; style.border_color = colors.line
	var tabs = ui.page.find_child("AnalysisSourceTabs", true, false)
	if tabs != null: tabs.get_theme_stylebox("panel").bg_color = colors.soft
	if ui.page_name == "analysis-import" and ui.archive_tab == 0 and is_instance_valid(input):
		input.add_theme_color_override("font_color", colors.ink)
		input.add_theme_color_override("font_readonly_color", colors.ink)
		input.add_theme_color_override("font_placeholder_color", colors.muted)

func select_tab(index: int) -> void:
	ui.app.preferences.studio.analysis_tab = clampi(index, 0, 1)
	if not ui.app.testing: ui.app.preferences.save_to()
	show(index)

func build_input(content: VBoxContainer) -> void:
	var card = PanelContainer.new()
	card.name = "AnalysisInputCard"
	var style = ui.Design.box(ui.app.palette().surface, 14, 0)
	style.border_color = ui.app.palette().line; style.set_border_width_all(1)
	card.add_theme_stylebox_override("panel", style)
	content.add_child(card)
	var column = VBoxContainer.new(); column.add_theme_constant_override("separation", 0); card.add_child(column)
	input = TextEdit.new()
	input.name = "AnalysisInput"
	input.custom_minimum_size.y = 120
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.placeholder_text = "在此输入棋谱或 SFEN 局面"
	var mono = SystemFont.new(); mono.font_names = PackedStringArray(["monospace"])
	input.add_theme_font_override("font", mono); input.add_theme_font_size_override("font_size", 13)
	for state in ["normal", "read_only", "focus"]: input.add_theme_stylebox_override(state, ui.Design.box(Color.TRANSPARENT, 14, 12))
	column.add_child(input)
	input.text_changed.connect(edited)
	column.add_child(HSeparator.new())
	paste_button = action("粘贴已复制的棋谱", paste, "AnalysisPaste", "ic_paste")
	column.add_child(paste_button)
	column.add_child(HSeparator.new())
	file_button = action("选择棋谱文件", choose_file, "AnalysisChooseFile", "ic_file")
	column.add_child(file_button)
	var info = HBoxContainer.new(); content.add_child(info)
	description = ui.label("", 12); description.size_flags_horizontal = Control.SIZE_EXPAND_FILL; info.add_child(description)
	var clear = action("清空", func(): set_source(""), "AnalysisClear", "", 32)
	clear.size_flags_horizontal = Control.SIZE_SHRINK_END; info.add_child(clear)
	load_button = action("载入棋谱", load_draft, "AnalysisLoad", "", 48)
	load_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_button.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed"]: load_button.add_theme_stylebox_override(state, ui.Design.box(ui.app.palette().accent, 14, 12))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]: load_button.add_theme_color_override(state, Color.WHITE)
	content.add_child(load_button)
	feedback = ui.label("", 13); feedback.name = "AnalysisImportStatus"; content.add_child(feedback)
	content.add_child(action("从最近棋谱中载入", show_recent, "AnalysisRecent", "ic_history", 50))
	content.add_child(action("分析当前棋局", func(): ui.start_report(false), "AnalysisCurrent", "ic_report", 44))
	var help = action("如何从其他将棋应用导入？", show_help, "AnalysisImportHelp", "", 36)
	help.add_theme_color_override("font_color", ui.app.palette().accent); content.add_child(help)
	refresh_input()

func layout() -> void:
	if ui.page == null or ui.page_name not in FLOW: return
	var safe: Rect2 = ui.app.safe_rect()
	safe.size.y = maxf(160, safe.size.y - ui.keyboard_height)
	var width = minf(420, safe.size.x * 0.94)
	var wanted = 660 if ui.page_name == "analysis-import" else 470
	ui.page.size = Vector2(width, minf(wanted, safe.size.y - 24))
	ui.page.position = safe.position + (safe.size - ui.page.size) / 2
	ui.backdrop.color = Color(0, 0, 0, 0.6)

func refresh_input() -> void:
	if ui.page_name != "analysis-import" or ui.archive_tab != 0 or not is_instance_valid(input): return
	changing = true
	input.text = draft.preview(); input.editable = not draft.locked() and not busy
	changing = false
	description.text = draft.description()
	feedback.text = "正在校验棋谱…" if busy else draft.error
	feedback.visible = not feedback.text.is_empty()
	load_button.disabled = busy or picker_ticket != 0
	paste_button.disabled = busy; file_button.disabled = picker_ticket != 0 or busy

func edited() -> void:
	if changing: return
	if draft.replace(input.text):
		ticket += 1; picker_ticket = 0
		if draft.locked(): refresh_input()
		else: description.text = draft.description(); feedback.hide()
	else: refresh_input()

func set_source(value: String, name: String = "") -> bool:
	var accepted = draft.replace(value, name)
	if accepted: ticket += 1; picker_ticket = 0
	refresh_input()
	return accepted

func paste() -> void:
	var value = DisplayServer.clipboard_get()
	if value.is_empty(): draft.error = "剪贴板没有可读取的棋谱。"; refresh_input(); return
	set_source(value)

func choose_file(save_in_archive: bool = false) -> void:
	if busy or picker_ticket != 0: return
	archive_file = save_in_archive
	ticket += 1; picker_ticket = ticket
	var request = picker_ticket
	refresh_input()
	if ui.platform != null and ui.platform.has_method("pickAnalysisRecord"):
		ui.platform.pickAnalysisRecord(request)
		return
	ui._open_file(false, func(path): read_file(request, path))
	ui.file_dialog.set_meta("analysis_import", true)
	ui.file_dialog.clear_filters()
	ui.file_dialog.add_filter("*.json,*.kif,*.kifu,*.csa,*.usi,*.sfen,*.txt", "将棋棋谱")
	ui.file_dialog.canceled.connect(func(): file_received(request, "", ""))

func read_file(request: int, path: String) -> void:
	if request != picker_ticket or ui.page_name not in FLOW: return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: file_received(request, "", "棋谱文件无法读取。"); return
	if file.get_length() > Draft.MAX_BYTES: file_received(request, "", "棋谱超过 2 MiB，已保留原输入。"); return
	var raw = file.get_buffer(file.get_length())
	var value = Draft.Decoder.decode(raw)
	if value.is_empty(): file_received(request, "", "棋谱为空，或文字编码无法读取。"); return
	file_received(request, value, "", path.get_file())

func file_received(request: int, value: String, error: String, name: String = "") -> void:
	if request != picker_ticket or picker_ticket == 0 or ui.page_name not in FLOW: return
	var save_in_archive = archive_file
	archive_file = false
	picker_ticket = 0
	if not error.is_empty(): draft.error = error; refresh_input(); return
	if value.is_empty(): refresh_input(); return
	if set_source(value, name):
		if ui.app.session != null: draft.error = "请先退出联机对局，再载入其他棋谱。"; refresh_input(); return
		start_parse(draft.source,"",save_in_archive)

func load_draft() -> void:
	if busy: return
	if ui.app.session != null: draft.error = "请先退出联机对局，再载入其他棋谱。"; refresh_input(); return
	if draft.source.strip_edges().is_empty(): draft.error = "请先输入、粘贴或选择棋谱。"; refresh_input(); return
	start_parse(draft.source)

func start_parse(source: String, path: String = "", save_in_archive: bool = false) -> void:
	if busy: return
	ticket += 1
	var request = ticket
	var revision: int = draft.revision
	job = preload("res://scripts/shogi_import_job.gd").new()
	ui.add_child(job)
	job.completed.connect(func(result): parsed(request, revision, result, path, save_in_archive))
	busy = true; refresh_input()
	var error: Error = job.begin(source)
	if error != OK:
		job.queue_free(); job = null; busy = false
		draft.error = "无法启动棋谱校验，请重试。"; refresh_input()

func parsed(request: int, revision: int, result: Dictionary, path: String = "", save_in_archive: bool = false) -> void:
	busy = false; job = null
	if request != ticket or revision != draft.revision or ui.page_name not in FLOW: refresh_input(); return
	if result.game == null:
		draft.error = result.error
		refresh_input()
		return
	if save_in_archive:
		if ui.app.session != null: draft.error = "请先退出联机对局，再载入其他棋谱。"; refresh_input(); return
		path = ui.app.records.archive(result.game,draft.source_name.get_basename())
		if path.is_empty(): draft.error = ui.app.records.error; refresh_input(); return
	open_game(result.game, path)

func open_game(game, path: String = "") -> bool:
	if ui.app.session != null: draft.error = "请先退出联机对局，再载入其他棋谱。"; refresh_input(); return false
	if not ui.finish_study(): return false
	ui.app._pause_search(); ui.report.cancel()
	ui.autoplay_on = false; ui.live_enabled = false
	ui.clear_pv_rows(); ui.live_details.clear(); ui.arrows.clear()
	ui.app.review_game = game; ui.app.review_path = path
	ui.app.replay_index = 0
	ui.report_selected_ply = -1
	ui._board_keep()
	ui.update_inline_report()
	ui.live_key = ""; ui.live_enabled = true
	ui.live_text.text = "棋谱已载入，可逐手回放、分析或从这里继续。"
	return true

func show_recent() -> void:
	ui.archive_view.enter(true)

func show_help() -> void:
	var content = ui.report_dialog("导入将棋棋谱", "analysis-help", "从文字或文件载入", "ic_file")
	content.add_child(ui.label("在原应用的棋谱页面选择导出或复制，使用 KIF、CSA、USI、SFEN 或本应用的 JSON 格式。", 15))
	content.add_child(ui.label("返回这里后，点击“粘贴已复制的棋谱”再载入，或直接选择导出的文件。KIF 支持 UTF-8 与 Shift JIS；不会自动读取剪贴板。", 14))
	content.add_child(ui.label("SFEN 是单一局面；完整棋谱保留逐手回放。每份文件最多 2 MiB，超过 16,000 字只缩短屏幕预览，载入仍使用完整文本。", 14))
	content.add_child(ui.label("国际象棋 PGN 和 Chess.com／Lichess 对局不能直接转成将棋。日本职业棋谱可从“历史大赛”进入官方公开目录。", 14))
	content.add_child(action("返回载入棋谱", func(): show(0), "AnalysisHelpBack", "", 44))
	apply_theme()
	layout()
