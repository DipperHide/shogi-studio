extends RefCounted
const Filter = preload("res://scripts/shogi_tournament_filter.gd")
const Historic = preload("res://scripts/shogi_historic_games.gd")
const Job = preload("res://scripts/shogi_tournament_job.gd")
const Motion = preload("res://scripts/shogi_rendered_tween.gd")
const PAGES = ["tournament-archive", "tournament-filter"]
var ui
var states = [{"query":"", "events":[], "year":"", "limit":20, "scroll":0}, {"query":"", "events":[], "year":"", "limit":20, "scroll":0}]
var rows: Array = []
var serial = 0
var pending = 0
var pending_id = ""
var selected_id = ""
var local_busy = false
var draft: Dictionary = {}
var filter_search: LineEdit
var reveal = 1.0
var sheet_motion
var closing = false
var checkbox_icons = {}

func state() -> Dictionary: return states[0 if ui.historic_recent else 1]
func entries() -> Array: return ui.tournaments.entries() if ui.historic_recent else Historic.entries()
func active() -> bool: return ui.page_name == "tournament-archive"

func leaving(name: String) -> void:
	if active() and is_instance_valid(ui.page_scroll): state().scroll = ui.page_scroll.scroll_vertical
	if name not in PAGES:
		serial += 1; pending = 0; pending_id = ""

func action(caption: String, callback: Callable, id: String, icon: String = "", height: int = 44) -> Button:
	var item = ui.compact_button(caption, callback, height); item.name = id
	item.accessibility_name = caption; item.tooltip_text = caption
	if not icon.is_empty():
		ui.set_reference_icon(item, icon)
		item.text = caption; item.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if ui.page_name == "tournament-archive":
		for key in ["font_color","font_hover_color","font_pressed_color","icon_normal_color","icon_hover_color","icon_pressed_color"]: item.add_theme_color_override(key, Color("f8f1e6"))
		for key in ["normal","hover","pressed"]: item.add_theme_stylebox_override(key, ui.Design.box(Color("493c29"), 4, 6))
	return item

func text(value: String, font_size: int = 14) -> Label:
	var item = ui.label(value, font_size)
	item.add_theme_color_override("font_color", Color("f8f1e6") if font_size >= 16 else Color("d4c8b5"))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func show() -> void:
	ui.archive_tab = 1
	var content = ui._page("历史大赛", "tournament-archive")
	var outer = ui.page.get_child(0)
	outer.add_theme_constant_override("separation", 4)
	var header = outer.get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var title = text("历史大赛", 18); title.add_theme_font_override("font", ui.Design.heading_font(ui.app.text_font))
	title.name = "HistoricTitle"; title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var filter = action("筛选", show_filter, "HistoricFilter", "ic_filter")
	filter.text = ""; filter.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; filter.size_flags_horizontal = Control.SIZE_SHRINK_END
	header.add_child(filter)
	var close = action("关闭", ui.back, "HistoricClose", "ic_close")
	close.text = ""; close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.size_flags_horizontal = Control.SIZE_SHRINK_END; close.custom_minimum_size.x = 44; header.add_child(close)
	var fixed = VBoxContainer.new(); fixed.add_theme_constant_override("separation", 4)
	outer.add_child(fixed); outer.move_child(fixed, 1)
	var tabs = HBoxContainer.new(); fixed.add_child(tabs)
	tabs.add_child(action("棋谱文字 / 文件", func(): ui.analysis_import.select_tab(0), "AnalysisTab0", "", 40))
	var selected = action("历史大赛", func(): pass, "AnalysisTab1", "", 40)
	selected.add_theme_stylebox_override("normal", ui.Design.box(Color("3d82f4"), 4, 4)); tabs.add_child(selected)
	var sources = HBoxContainer.new(); fixed.add_child(sources)
	for recent in [true, false]:
		var item = action("近期赛事" if recent else "离线历史", func(): switch_source(recent), "LatestTournaments" if recent else "OfflineTournaments", "", 38)
		if recent == ui.historic_recent: item.add_theme_stylebox_override("normal", ui.Design.box(Color("736044"), 4, 4))
		sources.add_child(item)
	if ui.historic_recent:
		ui.tournament_refresh = action("刷新", func(): ui.tournaments.refresh(true), "RefreshTournaments", "ic_refresh", 38)
		sources.add_child(ui.tournament_refresh)
	ui.tournament_status = text("", 12); ui.tournament_status.name = "TournamentStatus"; fixed.add_child(ui.tournament_status)
	ui.historic_count = text("", 12); ui.historic_count.name = "HistoricCount"; fixed.add_child(ui.historic_count)
	ui.historic_list = content; ui.historic_list.add_theme_constant_override("separation", 0)
	refresh(); apply_theme(); layout()
	ui.page_scroll.set_deferred("scroll_vertical", state().scroll)
	if ui.historic_recent: ui.tournaments.refresh.call_deferred()

func switch_source(recent: bool) -> void:
	state().scroll = ui.page_scroll.scroll_vertical
	serial += 1; pending = 0; pending_id = ""
	# Save before changing which state leaving() observes.
	ui.historic_recent = recent
	var remembered: int = state().scroll
	show(); state().scroll = remembered; ui.page_scroll.set_deferred("scroll_vertical", remembered)

func apply_theme() -> void:
	if ui.page == null or ui.page_name not in PAGES: return
	if active():
		var wood = StyleBoxTexture.new(); wood.texture = load("res://assets/reference-ui/wood_dark.png"); wood.set_content_margin_all(10)
		ui.page.add_theme_stylebox_override("panel", wood)
		for label in ui.page.find_children("*", "Label", true, false): label.add_theme_color_override("font_color", Color("f8f1e6") if label.get_theme_font_size("font_size") >= 16 else Color("d4c8b5"))
		for item in ui.page.find_children("*", "Button", true, false):
			for key in ["font_color","font_hover_color","font_pressed_color","icon_normal_color","icon_hover_color","icon_pressed_color"]: item.add_theme_color_override(key, Color("f8f1e6"))
			var fill = Color("3d82f4") if item.name == "AnalysisTab1" else Color("736044") if item.name == ("LatestTournaments" if ui.historic_recent else "OfflineTournaments") else Color("493c29")
			if str(item.name).begins_with("HistoricLoad_"): fill = Color.TRANSPARENT
			item.add_theme_stylebox_override("normal", ui.Design.box(fill,4,0 if fill == Color.TRANSPARENT else 6))
	else:
		ui.page.add_theme_stylebox_override("panel", ui.Design.box(ui.app.palette().background, 0, 10))
		for check in ui.page.find_children("HistoricEvent_*", "CheckBox", true, false):
			check.add_theme_font_size_override("font_size",14)
			check.add_theme_color_override("font_color", ui.app.palette().ink)
			for key in ["normal","hover","pressed","hover_pressed"]: check.add_theme_stylebox_override(key,ui.Design.box(Color.TRANSPARENT,0,8))
			for marked in [false,true]: check.add_theme_icon_override("checked" if marked else "unchecked", checkbox_icon(marked))

func checkbox_icon(marked: bool) -> Texture2D:
	var color: Color = ui.app.palette().accent if marked else ui.app.palette().muted
	var key = str(marked)+color.to_html()
	if not checkbox_icons.has(key):
		var picture = Image.new()
		var shape = "<rect x='1.5' y='1.5' width='15' height='15' rx='2' fill='%s' stroke='#%s' stroke-width='2'/>" % ["#"+color.to_html(false) if marked else "none", color.to_html(false)]
		if marked: shape += "<path d='m4 9 3 3 7-7' fill='none' stroke='white' stroke-width='2'/>"
		picture.load_svg_from_string("<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18' viewBox='0 0 18 18'>"+shape+"</svg>")
		checkbox_icons[key] = ImageTexture.create_from_image(picture)
	return checkbox_icons[key]

func layout() -> void:
	if ui.page == null or ui.page_name not in PAGES: return
	var safe: Rect2 = ui.app.safe_rect(); safe.size.y = maxf(160, safe.size.y - ui.keyboard_height)
	if active(): ui.page.position = safe.position; ui.page.size = safe.size
	else:
		ui.page.size = Vector2(safe.size.x, minf(530, safe.size.y * 0.94))
		ui.page.position = Vector2(safe.position.x, safe.end.y - ui.page.size.y * reveal)
	ui.backdrop.show(); ui.backdrop.color = Color(0,0,0,0.6)

func refresh() -> void:
	if not active() or not is_instance_valid(ui.historic_list): return
	for child in ui.historic_list.get_children(): ui.historic_list.remove_child(child); child.queue_free()
	var current = state()
	rows = Filter.select(entries(), current.query, current.events, current.year)
	ui.historic_count.text = "%d 局 · %s" % [rows.size(), "官方已结束对局" if ui.historic_recent else "完整棋谱 · 离线可用"]
	if not current.query.is_empty() or not current.events.is_empty() or not current.year.is_empty(): ui.historic_count.text += " · 已筛选"
	ui.tournament_status.text = "正在校验完整棋谱…" if local_busy else ui.tournaments.status_text() if ui.historic_recent else "选择整行载入棋盘，可回放、分析或从选中局面续下。"
	if ui.historic_recent and is_instance_valid(ui.tournament_refresh): ui.tournament_refresh.disabled = ui.tournaments.refreshing
	if rows.is_empty():
		var empty = text("没有符合条件的对局，请调整筛选。", 14); empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size.y = 90; ui.historic_list.add_child(empty)
	for entry in rows.slice(0, current.limit): build_row(entry)
	if rows.size() > current.limit:
		ui.historic_list.add_child(action("显示更多对局", func(): current.limit += 20; refresh(), "HistoricMore", "", 44))

func build_row(entry: Dictionary) -> void:
	var panel = PanelContainer.new(); panel.name = "HistoricGame_" + entry.id
	panel.add_theme_stylebox_override("panel", ui.Design.box(Color("29442e") if entry.id == selected_id else Color.TRANSPARENT, 0, 0))
	ui.historic_list.add_child(panel)
	var load = action("载入 " + str(entry.tags.get("先手","")) + " 对 " + str(entry.tags.get("後手","")), func(): open_entry(entry), "HistoricLoad_" + entry.id)
	load.text = ""; load.disabled = local_busy or (ui.historic_recent and ui.tournaments.downloading)
	for key in ["normal","disabled"]: load.add_theme_stylebox_override(key, ui.Design.box(Color.TRANSPARENT,0,0))
	panel.add_child(load)
	var margin = MarginContainer.new(); margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in [["left",15],["right",10],["top",12],["bottom",12]]: margin.add_theme_constant_override("margin_" + pair[0], pair[1])
	panel.add_child(margin)
	var line = HBoxContainer.new(); line.mouse_filter = Control.MOUSE_FILTER_IGNORE; margin.add_child(line)
	var body = VBoxContainer.new(); body.mouse_filter = Control.MOUSE_FILTER_IGNORE; body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",2); line.add_child(body)
	var title = text("%s vs %s（%s）" % [entry.tags.get("先手",""),entry.tags.get("後手",""),Filter.outcome(entry)],16)
	title.add_theme_font_override("font", ui.Design.heading_font(ui.app.text_font)); body.add_child(title)
	body.add_child(text(str(entry.tags.get("開始日時", "")).left(10) + " | " + str(entry.tags.get("棋戦","")), 13))
	body.add_child(text("%d 手" % int(entry.plies) + (" · " + str(entry.tags["戦型"]) if entry.tags.has("戦型") else ""),12))
	var status = preload("res://scripts/shogi_tournament_status.gd").new()
	status.name = "HistoricState_" + entry.id
	status.busy = (local_busy and pending_id == entry.id) or ui.tournaments.download_id == entry.id
	status.cached = entry.has("kif") or not ui.tournaments.cache_data(entry).is_empty()
	status.icon = ui.reference_icon("ic_check_black_24dp"); status.size_flags_vertical = Control.SIZE_SHRINK_CENTER; line.add_child(status)
	var source = action("官方来源", func(): OS.shell_open(entry.source), "HistoricSource_" + entry.id, "", 32)
	source.text = "↗"; source.custom_minimum_size.x = 32; source.size_flags_horizontal = Control.SIZE_SHRINK_END; source.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(source)
	ui.historic_list.add_child(HSeparator.new())

func open_entry(entry: Dictionary) -> void:
	if local_busy or (not entry.has("kif") and ui.tournaments.downloading): return
	if ui.app.session != null: ui.show_message("请先退出联机对局，再载入其他棋谱。"); return
	serial += 1; pending = serial; pending_id = entry.id
	var request = pending
	state().scroll = ui.page_scroll.scroll_vertical if active() else state().scroll
	if not entry.has("kif"): ui.tournaments.open_game(entry, request); return
	local_busy = true; refresh()
	var job = Job.new(); ui.add_child(job)
	job.completed.connect(func(result):
		local_busy = false; refresh()
		if result.game != null: resolved(request, entry.id, result.game)
		elif request == pending and active(): ui.tournament_status.text = "棋谱校验失败，原棋局已保留。"
	)
	if job.begin_record(entry, ui.tournaments.Download.normalize(entry.kif.to_utf8_buffer())) != OK:
		job.queue_free(); local_busy = false; refresh()
		ui.tournament_status.text = "暂时无法校验棋谱，请重试。"

func resolved(request: int, id: String, game) -> void:
	if request == 0 or request != pending or id != pending_id or not active(): return
	selected_id = id
	ui._open_tournament_game(game)

func show_filter() -> void:
	serial += 1; pending = 0; pending_id = ""
	draft = state().duplicate(true); closing = false
	var choices = Filter.options(entries())
	var content = ui._page("筛选大师棋谱", "tournament-filter")
	var outer = ui.page.get_child(0); outer.add_theme_constant_override("separation", 10)
	var header = outer.get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var title = ui.label("筛选大赛棋谱",16); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; title.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font)); title.add_theme_color_override("font_color",ui.app.palette().ink); header.add_child(title)
	var close = action("关闭筛选", func(): close_filter("cancel"), "HistoricFilterClose", "ic_close")
	close.text = ""; close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.custom_minimum_size.x = 44; close.size_flags_horizontal = Control.SIZE_SHRINK_END; header.add_child(close)
	filter_search = LineEdit.new(); filter_search.name = "HistoricSearch"; filter_search.placeholder_text = "棋手、赛事或战型"; filter_search.text = draft.query
	filter_search.max_length = 120; filter_search.custom_minimum_size.y = 46; content.add_child(filter_search)
	filter_search.text_changed.connect(func(value): draft.query = value)
	content.add_child(ui.label("赛事（可多选，未勾选表示全部）",14))
	var events = HFlowContainer.new(); events.name = "HistoricEvents"; content.add_child(events)
	for event in choices.events:
		var check = CheckBox.new(); check.name = "HistoricEvent_" + event; check.text = event; check.custom_minimum_size.y = 44
		check.button_pressed = event in draft.events; events.add_child(check)
		check.toggled.connect(func(value):
			if value: draft.events.append(event)
			else: draft.events.erase(event)
		)
	content.add_child(ui.label("年份",14))
	var years = OptionButton.new(); years.name = "HistoricYear"; years.custom_minimum_size.y = 44; years.add_item("全部年份")
	for year in choices.years: years.add_item(year)
	years.select(choices.years.find(draft.year)+1); content.add_child(years)
	years.item_selected.connect(func(index): draft.year = "" if index == 0 else years.get_item_text(index))
	var footer = HBoxContainer.new(); outer.add_child(footer)
	footer.add_child(action("重置筛选", func(): close_filter("reset"), "HistoricFilterReset", "ic_clear_black_24dp",46))
	footer.add_child(action("显示结果", func(): close_filter("apply"), "HistoricFilterApply", "ic_search",46))
	apply_theme(); reveal = 0; layout(); animate_sheet(1.0)

func animate_sheet(target: float, completion: Callable = Callable()) -> void:
	if is_instance_valid(sheet_motion): sheet_motion.kill()
	var start = reveal
	sheet_motion = Motion.new(); ui.page.add_child(sheet_motion)
	sheet_motion.begin(ui.page, 0.18 if ui.app.preferences.studio.animation > 0 else 0, func(value): reveal = lerpf(start,target,value); layout(), completion)

func close_filter(mode: String) -> void:
	if closing: return
	closing = true
	var chosen = draft.duplicate(true)
	animate_sheet(0.0, func():
		if mode != "cancel":
			var current = state()
			current.query = chosen.query.strip_edges() if mode == "apply" else ""
			current.events = chosen.events.duplicate() if mode == "apply" else []
			current.year = chosen.year if mode == "apply" else ""
			current.limit = 20; current.scroll = 0
		show()
	)
