extends "res://scripts/shogi_menu.gd"
## Chessis 20.9's board-first navigation adapted to shogi, with shared native game services.
const Exchange = preload("res://scripts/shogi_exchange.gd")
const Openings = preload("res://scripts/shogi_openings.gd")
const WOOD_REPORT_PAGES = ["report", "report-phase", "report-accuracy", "report-metric-info"]
var top_bar: HBoxContainer
var move_strip: HBoxContainer
var move_scroll: ScrollContainer
var live_panel: VBoxContainer
var live_text: Label
var eval_label: Label
var evaluation_bar
var eval_row: HBoxContainer
var score_slot: Control
var win_row: HBoxContainer
var report
var report_progress: Label
var report_chart
var report_phases
var report_accuracy_view
var report_selection: VBoxContainer
var report_move_from_report: bool = false
var report_board_active: bool = false
var report_board_key: String = ""
var report_board_game
var report_board_line_limit: int = 5
var report_story
var report_story_expanded: bool = false
var report_story_source
var report_selected_ply: int = -1
var report_moves_expanded: bool = false
var report_category: String = ""
var report_category_side: int = 0
var report_statistics
var report_statistics_source
var live_enabled: bool = false
var live_key: String = ""
var live_details: Dictionary = {}
var arrows: Array = []
var autoplay_on: bool = false
var autoplay_elapsed: float = 0
var ribbon_key: String = ""
var drawing: bool = false
var drawing_start: int = -1
var editor
var report_buttons: HBoxContainer
var report_filter: int = 0
var pending_backup: String = ""
var reading_backup: bool = false
var pv_rows: Dictionary = {}
var pv_column: VBoxContainer
var analysis_scroll: ScrollContainer
var engine_toggle: Button
var pv_context: Dictionary = {}
var return_line: Button
var report_inline: VBoxContainer
var report_side: int = 0
var report_expanded: bool = true
var archive_tab: int = 0
var historic_query: String = ""
var historic_event: String = "全部赛事"
var historic_year: String = "全部年份"
var historic_list: VBoxContainer
var historic_count: Label
var historic_offset: int = 0
var historic_recent: bool = true
var tournament_status: Label
var tournament_refresh: Button
var tournaments
const Historic = preload("res://scripts/shogi_historic_games.gd")
var reference_icons: Dictionary = {}
var continue_button: Button
var win_rate_label: Label
var coach_notice: Button
const Coach = preload("res://scripts/shogi_coach.gd")
var practice
var practice_scroll: ScrollContainer
var practice_panel: VBoxContainer
var retry_from_report: bool = false
var study
var variation_ui
var opening_view
var analysis_import
var tournament_view
var archive_view
var study_bar: HBoxContainer
var display_language = ""

func initialize(owner_node) -> void:
	super.initialize(owner_node)
	backdrop.gui_input.connect(_menu_backdrop_input)
	study = preload("res://scripts/shogi_variation_study.gd").new()
	study.app = app
	variation_ui = preload("res://scripts/shogi_variation_view.gd").new()
	variation_ui.ui = self
	opening_view = preload("res://scripts/shogi_opening_view.gd").new()
	opening_view.ui = self
	analysis_import = preload("res://scripts/shogi_analysis_import.gd").new()
	analysis_import.initialize(self)
	tournaments = preload("res://scripts/shogi_tournament_sync.gd").new()
	add_child(tournaments)
	tournaments.initialize(ProjectSettings.globalize_path("res://../.work/tournaments-ui-test") if app.testing else "user://tournaments", not app.testing)
	tournament_view = preload("res://scripts/shogi_tournament_view.gd").new()
	tournament_view.ui = self
	archive_view = preload("res://scripts/shogi_archive_view.gd").new()
	archive_view.ui = self
	tournaments.changed.connect(func():
		tournament_view.refresh()
	)
	tournaments.game_resolved.connect(tournament_view.resolved)
	for child in toolbar.get_children(): toolbar.remove_child(child); child.queue_free()
	toolbar.add_theme_constant_override("separation", 2)
	for entry in [["☰", "菜单", show_drawer], ["⇅", "翻转棋盘", func(): app.flipped = not app.flipped; app._layout()], ["⌕", "提示与分析", toggle_live], ["‹", "上一手", func(): seek(-1)], ["▷", "自动回放", toggle_autoplay], ["›", "下一手", func(): seek(1)], ["↶", "悔棋", undo_from_board], ["•••", "更多", show_menu]]:
		var item = button(entry[0], entry[2])
		item.tooltip_text = entry[1]
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.custom_minimum_size = Vector2(32, 50)
		item.add_theme_font_size_override("font_size", 23)
		toolbar.add_child(item)
	for i in range(8):
		set_reference_icon(toolbar.get_child(i), ["ic_baseline_menu_24", "ic_flip_board", "ic_search", "ic_nav_previous", "ic_nav_play", "ic_nav_next", "ic_undo", "ic_nav_more"][i])
	top_bar = HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 6)
	root.add_child(top_bar)
	var brand = button("将棋", show_drawer)
	brand.alignment = HORIZONTAL_ALIGNMENT_LEFT
	brand.icon = piece_icon("歩")
	brand.expand_icon = true
	brand.add_theme_constant_override("icon_max_width", 25)
	brand.add_theme_font_size_override("font_size", 20)
	brand.autowrap_mode = TextServer.AUTOWRAP_OFF
	brand.add_theme_stylebox_override("normal", Design.box(Color.TRANSPARENT, 0, 4))
	top_bar.add_child(brand)
	for entry in [["新对局", show_play], ["设置", show_settings]]:
		var item = button(entry[0], entry[1])
		item.size_flags_horizontal = Control.SIZE_SHRINK_END
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.custom_minimum_size = Vector2(58, 44)
		item.add_theme_stylebox_override("normal", Design.box(Color.TRANSPARENT, 5, 4))
		item.add_theme_font_size_override("font_size", 13)
		top_bar.add_child(item)
	move_scroll = ScrollContainer.new()
	move_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	move_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	root.add_child(move_scroll)
	move_strip = HBoxContainer.new()
	move_strip.add_theme_constant_override("separation", 3)
	move_scroll.add_child(move_strip)
	live_panel = VBoxContainer.new()
	live_panel.add_theme_constant_override("separation", 4)
	root.add_child(live_panel)
	# Initial text shaping can temporarily inflate this container. Refit when
	# its minimum settles so its invisible scroll area cannot cover the toolbar.
	live_panel.minimum_size_changed.connect(layout, CONNECT_DEFERRED)
	var row = HBoxContainer.new()
	eval_row = row
	live_panel.add_child(row)
	score_slot = Control.new()
	score_slot.custom_minimum_size = Vector2(60, 34)
	score_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(score_slot)
	study_bar = HBoxContainer.new()
	study_bar.name = "VariationControls"
	study_bar.add_theme_constant_override("separation", 4)
	live_panel.add_child(study_bar)
	study_bar.hide()
	win_rate_label = label("胜率估计 · 计算中…", 12)
	win_rate_label.name = "WinRate"
	win_rate_label.tooltip_text = "根据当前引擎评分换算的局面胜率估计，不是实际获胜保证。分数 s 按 1 / (1 + exp(-s/600)) 换算；先后手固定，翻转棋盘不会交换名称。"
	win_row = HBoxContainer.new()
	live_panel.add_child(win_row)
	win_row.add_child(win_rate_label)
	win_rate_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	win_rate_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coach_notice = compact_button("", review_coach, 30)
	coach_notice.name = "BadMoveNotice"
	coach_notice.add_theme_color_override("font_color", Color("ee984f"))
	coach_notice.hide()
	live_panel.add_child(coach_notice)
	eval_label = label("YaneuraOu", 13)
	eval_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(eval_label)
	continue_button = compact_button("从这里下", branch_here, 30)
	continue_button.name = "ContinueFromPosition"
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	continue_button.hide()
	row.add_child(continue_button)
	for entry in [["▷", toggle_live], ["−", func(): change_lines(-1)], ["+", func(): change_lines(1)]]:
		var item = button(entry[0], entry[1])
		item.custom_minimum_size = Vector2(48 if entry[0] == "分析" else 30, 30)
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.add_theme_stylebox_override("normal", Design.box(Color(0, 0, 0, 0.12), 5, 4))
		item.size_flags_horizontal = Control.SIZE_SHRINK_END
		item.add_theme_font_size_override("font_size", 12)
		row.add_child(item)
		if entry[0] == "▷": engine_toggle = item; item.tooltip_text = "开始 / 暂停引擎分析"
	analysis_scroll = ScrollContainer.new()
	analysis_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	analysis_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	live_panel.add_child(analysis_scroll)
	pv_column = VBoxContainer.new()
	pv_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv_column.add_theme_constant_override("separation", 1)
	analysis_scroll.add_child(pv_column)
	live_text = label("点击「分析」查看候选着手。", 13)
	live_text.clip_text = true
	pv_column.add_child(live_text)
	return_line = compact_button("↶ 返回原局", stop_pv, 30)
	return_line.hide()
	live_panel.add_child(return_line)
	report_inline = VBoxContainer.new()
	report_inline.add_theme_constant_override("separation", 3)
	pv_column.add_child(report_inline)
	var reports = HBoxContainer.new()
	report_buttons = reports
	live_panel.add_child(reports)
	for entry in [["快速报告", func(): start_report(false)], ["深度报告", func(): start_report(true)]]:
		var item = button(entry[0], entry[1])
		item.custom_minimum_size.y = 32
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.add_theme_stylebox_override("normal", Design.box(Color(0, 0, 0, 0.16), 5, 4))
		item.add_theme_font_size_override("font_size", 12)
		item.icon = reference_icon("ic_quick_report" if entry[0] == "快速报告" else "ic_deep_report")
		item.expand_icon = true
		item.add_theme_constant_override("icon_max_width", 18)
		item.add_theme_stylebox_override("normal", Design.box(app.palette().accent if entry[0] == "快速报告" else app.palette().soft, 18, 7))
		item.add_theme_color_override("font_color", Color.WHITE if entry[0] == "快速报告" else app.palette().ink)
		reports.add_child(item)
	reports.add_child(compact_button("⚙", show_report_settings, 32))
	var good_line = compact_button("好棋线路", show_good_line, 32)
	good_line.name = "BestLine"
	reports.add_child(good_line)
	report = preload("res://scripts/shogi_report.gd").new()
	add_child(report)
	report.changed.connect(report_changed)
	practice = preload("res://scripts/shogi_mistake_practice.gd").new()
	practice.initialize(app)
	practice_scroll = ScrollContainer.new()
	practice_scroll.name = "MistakePracticeScroll"
	practice_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	practice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	practice_scroll.hide()
	live_panel.add_child(practice_scroll)
	practice_panel = VBoxContainer.new()
	practice_panel.name = "MistakePractice"
	practice_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_panel.add_theme_constant_override("separation", 5)
	practice_scroll.add_child(practice_panel)
	evaluation_bar = preload("res://scripts/shogi_evaluation_bar.gd").new()
	root.add_child(evaluation_bar)
	evaluation_bar.setup(self)
	menu_button.hide()
	navigation.hide()
	apply_theme()
	layout()

func _page(title: String, name: String, use_sheet: bool = false) -> VBoxContainer:
	if archive_view != null: archive_view.leaving(name)
	if tournament_view != null: tournament_view.leaving(name)
	if analysis_import != null: analysis_import.leaving(name)
	if opening_view != null: opening_view.stop_preview()
	if practice_active() and name not in ["promotion", "confirm-move"]: practice.stop(false)
	if not pv_context.is_empty(): stop_pv(false)
	var column = super._page(title, name, use_sheet)
	if name in ["save-study", "replace-game", "analysis-import-choice"]:
		# Wrapped headings can temporarily increase the minimum while shaping.
		# Refit after that minimum settles, including a language change.
		page.minimum_size_changed.connect(func(): fit_decision.call_deferred())
	if use_sheet:
		backdrop.color = Color(0, 0, 0, 0.5)
		backdrop.show()
	navigation.hide()
	if top_bar != null: top_bar.hide(); move_scroll.hide(); live_panel.hide()
	layout()
	return column

func fit_decision() -> void:
	if page == null or page_name not in ["save-study", "replace-game", "analysis-import-choice"]: return
	var safe: Rect2 = app.safe_rect()
	page.size = Vector2(minf(440, safe.size.x - 24), minf(440, safe.size.y - 24))
	page.position = safe.position + (safe.size - page.size) / 2

func show_home() -> void:
	close()

func _menu_backdrop_input(event: InputEvent) -> void:
	if page_name not in ["drawer", "menu"]: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and not event.canceled:
		backdrop.accept_event()
		close()

func label(value: String, font_size: int = 18) -> Label:
	var item = super.label(value, font_size)
	if page_name in WOOD_REPORT_PAGES or page_name in ["report-settings", "report-value", "retry-settings", "report-classifications", "report-story-info", "report-move"]:
		item.add_theme_color_override("font_color", Color("f8f1e6") if page_name in WOOD_REPORT_PAGES else app.palette().ink)
	return item

func banner(parent: Control, _compact: bool = false) -> void:
	var strip = label("将棋 · 学习与复盘", 22)
	strip.custom_minimum_size.y = 56
	parent.add_child(strip)

func close() -> void:
	if archive_view != null: archive_view.leaving("")
	if tournament_view != null: tournament_view.leaving("")
	if analysis_import != null: analysis_import.leaving("")
	if opening_view != null: opening_view.stop_preview()
	var practicing = practice_active()
	var studying = study_active()
	var practice_view = app.review_game
	var practice_ply: int = app.replay_index
	super.close()
	if studying:
		app.review_game = study.view
		app.review_path = study.record_path
		app.replay_index = study.tree.nodes[study.tree.cursor].depth
		app._refresh()
	if practicing:
		app.review_game = practice_view
		app.replay_index = practice_ply
		app._refresh()
	autoplay_on = false
	drawing = false
	if top_bar != null: top_bar.show(); move_scroll.show(); live_panel.show()
	menu_button.hide()
	navigation.hide()
	live_key = ""
	ribbon_key = ""
	layout()
	if toolbar.get_child_count() == 8: toolbar.get_child(4).text = "▷"
	if practicing: update_practice()

func _board_keep() -> void:
	var keep_autoplay = autoplay_on
	var viewed = app.review_game
	var path: String = app.review_path
	var ply: int = app.replay_index
	close()
	app.review_game = viewed
	app.review_path = path
	app.replay_index = ply
	autoplay_on = keep_autoplay
	if toolbar.get_child_count() == 8: toolbar.get_child(4).text = "Ⅱ" if autoplay_on else "▷"
	app._refresh()

func layout() -> void:
	super.layout()
	if app == null or top_bar == null: return
	var safe: Rect2 = app.safe_rect()
	menu_button.hide()
	# Original activity_main starts with the move ribbon; actions live below.
	top_bar.hide()
	top_bar.position = safe.position + Vector2(10, 0)
	top_bar.size = Vector2(safe.size.x - 20, 48)
	move_scroll.position = safe.position + Vector2(10, 3)
	move_scroll.size = Vector2(safe.size.x - 20, 62 if study_active() else 32)
	toolbar.position = Vector2(safe.position.x + 5, safe.end.y - 55)
	toolbar.size = Vector2(safe.size.x - 10, 50)
	var x = app.bottom_player_rect.position.x
	var y = app.bottom_player_rect.end.y + (54 if app.wide_layout else 7)
	live_panel.position = Vector2(x, y)
	live_panel.size = Vector2(app.bottom_player_rect.size.x, maxf(40, safe.end.y - 65 - y))
	if report_buttons != null: report_buttons.visible = safe.size.y >= 480 and not practice_active()
	if analysis_scroll != null: analysis_scroll.visible = not practice_active()
	if practice_scroll != null: practice_scroll.visible = practice_active()
	if page_name == "drawer" and page != null:
		page.position = safe.position
		page.size = Vector2(minf(320, safe.size.x - 36), safe.size.y)
		backdrop.color = Color(0, 0, 0, 0.6)
		backdrop.show()
	if page != null and page_name in ["save-study", "replace-game", "analysis-import-choice"]:
		fit_decision()
		backdrop.color = Color(0, 0, 0, 0.6)
	if page != null and page_name == "report":
		page.position = safe.position
		page.size = safe.size
	if page != null and page_name == "editor":
		page.position = safe.position
		page.size = safe.size - Vector2(0, keyboard_height)
	if page != null and page_name == "openings":
		page.position = safe.position
		page.size = safe.size - Vector2(0, keyboard_height)
	if page != null and page_name == "opening-info":
		page.size = Vector2(safe.size.x if safe.size.x > safe.size.y else minf(560, safe.size.x), safe.size.y)
		page.position = safe.position + Vector2((safe.size.x - page.size.x) / 2, 0)
		if opening_view != null and is_instance_valid(opening_view.preview): opening_view.preview.layout_preview()
	if page != null and page_name in ["report-phase", "report-accuracy", "report-metric-info"]: fit_wood_dialog()
	if page != null and page_name in ["report-settings", "report-value", "retry-settings", "report-classifications", "report-story-info", "report-move"]:
		var available = safe
		available.size.y -= keyboard_height
		var dialog_height = 280 if page_name == "report-value" else 480 if page_name == "report-story-info" else 700
		var dialog_size = Vector2(minf(420, safe.size.x * 0.94), minf(dialog_height, maxf(180, available.size.y - 24)))
		page.size = dialog_size
		page.position = available.position + (available.size - dialog_size) / 2
		backdrop.color = Color(0, 0, 0, 0.6)
	if evaluation_bar != null: evaluation_bar.layout_bar()
	if analysis_import != null: analysis_import.layout()
	if tournament_view != null: tournament_view.layout()
	if archive_view != null: archive_view.layout()

func apply_theme() -> void:
	var report_colors: Dictionary = {}
	if page != null and page_name in WOOD_REPORT_PAGES:
		for item in page.find_children("*", "Label", true, false): report_colors[item] = item.get_theme_color("font_color")
	super.apply_theme()
	if continue_button != null:
		continue_button.add_theme_stylebox_override("normal", Design.box(app.palette().accent, 6, 4))
		continue_button.add_theme_stylebox_override("hover", Design.box(app.palette().accent.lightened(0.08), 6, 4))
		continue_button.add_theme_stylebox_override("pressed", Design.box(app.palette().accent.darkened(0.08), 6, 4))
		for state in ["font_color", "font_hover_color", "font_pressed_color"]: continue_button.add_theme_color_override(state, Color.WHITE)
	if display_language != app.preferences.language:
		display_language = app.preferences.language
		ribbon_key = ""
		if variation_ui != null: variation_ui.bar_key = ""
		if toolbar != null and toolbar.get_child_count() == 8:
			for i in range(8): toolbar.get_child(i).tooltip_text = app.t(["菜单", "翻转棋盘", "提示与分析", "上一手", "自动回放", "下一手", "悔棋", "更多"][i])
	for item in report_colors: item.add_theme_color_override("font_color", report_colors[item])
	if page_name == "editor" and is_instance_valid(editor): editor.apply_theme()
	if page_name in ["openings", "opening-info"] and opening_view != null: opening_view.apply_theme()
	if analysis_import != null: analysis_import.apply_theme()
	if tournament_view != null: tournament_view.apply_theme()
	if archive_view != null: archive_view.apply_theme()
	if toolbar == null: return
	for item in toolbar.get_children():
		item.add_theme_stylebox_override("normal", Design.box(Color(0, 0, 0, 0.12), 5, 4))
		item.add_theme_color_override("font_color", app.palette().ink)
	if app.preferences.appearance != "wood":
		var p = app.palette()
		for item in root.find_children("*", "Button", true, false):
			if not item.has_meta("reference_icon"): continue
			for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]: item.add_theme_color_override(state, p.ink)
			item.add_theme_color_override("icon_disabled_color", Color(p.muted, 0.35))
		for item in toolbar.get_children():
			for state in ["normal", "disabled"]: item.add_theme_stylebox_override(state, Design.box(Color.TRANSPARENT, 9, 4))
			for state in ["hover", "pressed"]: item.add_theme_stylebox_override(state, Design.box(p.soft, 9, 4))
		if report_buttons != null:
			for index in range(report_buttons.get_child_count()):
				var item = report_buttons.get_child(index)
				if not item is Button: continue
				item.add_theme_stylebox_override("normal", Design.box(p.accent if index == 0 else p.soft, 8, 4))
				item.add_theme_color_override("font_color", Color.WHITE if index == 0 else p.ink)
				item.add_theme_color_override("icon_normal_color", Color.WHITE if index == 0 else p.ink)
	if live_text != null: live_text.add_theme_color_override("font_color", app.palette().ink)

func handles_point(point: Vector2) -> bool:
	if super.handles_point(point): return true
	for control in [top_bar, move_scroll, live_panel, evaluation_bar, engine_toggle, evaluation_bar.options_button if evaluation_bar != null else null]:
		if control != null and control.is_visible_in_tree() and control.get_global_rect().has_point(point): return true
	return false

func _process(delta: float) -> void:
	super._process(delta)
	if top_bar == null: return
	if practice_active(): practice.tick(delta)
	if engine_toggle != null: set_reference_icon(engine_toggle, "ic_pause" if live_enabled else "ic_play")
	if toolbar.get_child_count() == 8:
		set_reference_icon(toolbar.get_child(4), "ic_nav_pause" if autoplay_on else "ic_nav_play")
		for index in [2, 3, 4, 5]: toolbar.get_child(index).disabled = practice_active() and (index == 2 or practice.stage != "preview")
		toolbar.get_child(6).disabled = practice.stage in ["wrong", "complete"] if practice_active() else app.game.moves.is_empty() or app.review_game != null or not pv_context.is_empty()
		if study_active(): toolbar.get_child(6).disabled = study.history.is_empty()
		if practice_active(): set_reference_icon(toolbar.get_child(4), "ic_nav_pause" if practice.preview_playing else "ic_nav_play")
	if continue_button != null: continue_button.visible = app.replay_index >= 0 and pv_context.is_empty() and app.session == null and not practice_active()
	update_coach_display()
	if variation_ui != null: variation_ui.update_bar()
	if page == null:
		update_ribbon()
		refresh_report_board()
		if live_enabled and pv_context.is_empty() and not app._ai_allowed() and not report.running:
			var key: String = app._display_position().key()
			if key != live_key:
				live_key = key
				live_details.clear()
				arrows.clear()
				clear_pv_rows()
				app._request_analysis()
		if autoplay_on:
			autoplay_elapsed += delta
			if autoplay_elapsed >= app.preferences.studio.autoplay and app.motion_progress >= 1:
				autoplay_elapsed = 0
				if app.replay_index >= app._view_game().moves.size(): autoplay_on = false
				else: seek(1, true)
	if evaluation_bar != null: evaluation_bar.synchronize(delta)

func update_ribbon() -> void:
	if practice_active(): return
	if study_active(): variation_ui.update_ribbon(); return
	var viewed = app._view_game()
	var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
	# Comment editing explicitly invalidates this key. Do not serialize the entire
	# annotated record every frame while the board is idle.
	var key = str([viewed.get_instance_id(), viewed.moves.size(), ply, viewed.comments.size()])
	if key == ribbon_key: return
	ribbon_key = key
	for child in move_strip.get_children(): move_strip.remove_child(child); child.queue_free()
	var start = maxi(0, ply - 8)
	for i in range(start, mini(viewed.moves.size() + 1, ply + 6)):
		var value = i
		var item = button("起局" if i == 0 else str(i) + ". " + viewed.labels[i - 1] + (" ▪" if viewed.comments.has(str(i)) else ""), func(): show_history(value))
		item.custom_minimum_size.y = 28
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.add_theme_font_size_override("font_size", 12)
		item.add_theme_stylebox_override("normal", Design.box(app.palette().accent if i == ply else Color.TRANSPARENT, 5, 5))
		if i == ply: item.add_theme_color_override("font_color", Color.WHITE)
		move_strip.add_child(item)
		if i == ply: reveal_ribbon.call_deferred(item.get_instance_id())
	if not live_enabled:
		live_text.text = str(viewed.comments.get(str(ply), app.t("点击「分析」查看候选着手。")))

func reveal_ribbon(instance_id: int) -> void:
	var control = instance_from_id(instance_id)
	if is_instance_valid(control) and move_scroll.is_ancestor_of(control): move_scroll.ensure_control_visible(control)

func show_history(ply: int) -> void:
	_show_history(ply, false)

func _show_history(ply: int, automatic: bool = false) -> void:
	if practice_active():
		if practice.stage == "preview": practice.seek(ply - app.replay_index)
		return
	if not automatic: autoplay_on = false; autoplay_elapsed = 0
	# Closing a dialog cancels motion. Close first, then start the replay transition.
	if page != null: _board_keep()
	# Retarget the visible animation immediately; the board preserves its pose.
	app._set_replay(ply)
	if app.replay_index < 0: autoplay_on = false
	update_inline_report()

func undo_from_board() -> void:
	if study_active(): study.undo(); return
	if practice_active(): practice.retry(); return
	if app.review_game != null or not pv_context.is_empty(): return
	autoplay_on = false
	if live_enabled: toggle_live()
	app._undo_move()

func seek(delta: int, automatic: bool = false) -> void:
	if practice_active(): practice.seek(delta); return
	var ply: int = app._view_game().moves.size() if app.replay_index < 0 else app.replay_index
	_show_history(clampi(ply + delta, 0, app._view_game().moves.size()), automatic)

func toggle_autoplay() -> void:
	if practice_active():
		if practice.stage == "preview": practice.preview_playing = not practice.preview_playing; update_practice()
		return
	autoplay_on = not autoplay_on
	autoplay_elapsed = 0
	if autoplay_on and (app.replay_index < 0 or app.replay_index == app._view_game().moves.size()): _show_history(0, true)
	toolbar.get_child(4).text = "Ⅱ" if autoplay_on else "▷"

func toggle_live() -> void:
	if practice_active(): practice.hint(); return
	live_enabled = not live_enabled
	live_key = ""
	if not live_enabled:
		app._pause_search()
		arrows.clear()
		live_details.clear()
		clear_pv_rows()
		live_text.text = app.t("分析已暂停")
		app._redraw()
	engine_toggle.text = "Ⅱ" if live_enabled else "▷"

func show_analysis() -> void:
	_board_keep()
	live_enabled = true
	live_key = ""

func show_good_line() -> void:
	if app.session != null: return
	if not pv_context.is_empty(): stop_pv(false)
	if page != null: _board_keep()
	toggle_live()
	if live_enabled:
		live_text.text = app.t("正在寻找好棋线路… 点击候选着手右侧播放按钮，可逐手查看。")
		live_text.show()

func evaluation() -> Dictionary:
	if practice_active(): return {}
	if app.session != null or not pv_context.is_empty(): return {}
	var viewed = app._view_game()
	var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
	if live_key == app._display_position().key() and live_details.has(1): return live_details[1]
	if app.coach != null:
		var cached: Dictionary = app.coach.cache.get(app.coach.key_for(viewed, ply), {})
		if not cached.is_empty(): return cached
	if report != null and report.game == viewed and ply < report.samples.size():
		var sample: Dictionary = report.samples[ply]
		return {"score": int(sample.get("mate_distance", 0)) if sample.mate else int(sample.score) * viewed.positions[ply].turn, "score_type": "mate" if sample.mate else "cp", "depth": int(sample.get("depth", 0))}
	return {}

func update_coach_display() -> void:
	if win_rate_label == null or app.coach == null: return
	if practice_active(): win_rate_label.hide(); coach_notice.hide(); return
	win_rate_label.visible = app.preferences.studio.win_rate and app.session == null and pv_context.is_empty()
	var details = evaluation()
	if details.has("score"):
		var chance = Coach.sente_chance(details, app._display_position().turn)
		win_rate_label.text = app.t("胜率估计  先手 %.0f%%  ·  后手 %.0f%%") % [chance * 100, (1 - chance) * 100]
	else:
		win_rate_label.text = app.t("胜率估计 · 计算中…" if app.coach.error.is_empty() else "胜率估计 · 引擎暂不可用")
	var warning: Dictionary = app.coach.warning
	coach_notice.visible = not warning.is_empty() and app.replay_index < 0 and app.review_game == null and app.session == null
	if coach_notice.visible:
		coach_notice.text = app.t("第 %d 手可能是失误 · 查看更好线路") % warning.ply
		coach_notice.tooltip_text = warning.label + app.t(" · 引擎评价损失 %d") % warning.loss

func review_coach() -> void:
	var warning: Dictionary = app.coach.warning
	if not app.coach.valid(warning): return
	show_history(warning.ply - 1)
	live_enabled = false
	live_key = app._display_position().key()
	live_details.clear()
	clear_pv_rows()
	receive_info(warning.best)
	live_text.text = app.t("这步的更好线路；可播放查看，或从这里重新下。")
	live_text.show()

func update_analysis(lines: String) -> void:
	super.update_analysis(lines)
	# Each PV has its own scroll position and controls; never wrap all PVs together.
	if live_details.is_empty() and live_text != null: live_text.text = lines

func receive_info(details: Dictionary, saved_report: bool = false) -> void:
	if not pv_context.is_empty(): return
	var index = int(details.get("multipv", 1))
	if not saved_report and index > app.preferences.studio.analysis_lines: return
	live_details[index] = details
	if not pv_rows.has(index):
		var pv = preload("res://scripts/shogi_pv_row.gd").new()
		pv.setup(index, self)
		pv.preview_requested.connect(preview_pv)
		pv.arrow_toggled.connect(func(_i, _on): update_pv_arrows())
		pv_column.add_child(pv)
		pv_rows[index] = pv
		var keys = pv_rows.keys(); keys.sort()
		for i in range(keys.size()): pv_column.move_child(pv_rows[keys[i]], i)
	pv_rows[index].update_line(details, app._display_position(), app.Codec)
	live_text.hide()
	update_pv_arrows()
	if int(details.get("multipv", 1)) == 1:
		eval_label.text = app.t("YaneuraOu · 深度 %d") % int(details.get("depth", 0))
	engine_toggle.text = "Ⅱ" if live_enabled else "▷"
	app._redraw()

func compact_button(value: String, action: Callable, height: int = 32) -> Button:
	var b = button(value, action)
	b.custom_minimum_size = Vector2(height, height)
	b.autowrap_mode = TextServer.AUTOWRAP_OFF
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_stylebox_override("normal", Design.box(Color(0, 0, 0, 0.16), 6, 4))
	var icons = {"▥": "ic_report", "‹": "ic_nav_previous", "›": "ic_nav_next", "⌃": "ic_arrow_drop_up", "⚙": "ic_settings", "▷": "ic_play"}
	if icons.has(value): set_reference_icon(b, icons[value])
	return b

func reference_icon(key: String) -> Texture2D:
	if not reference_icons.has(key): reference_icons[key] = load("res://assets/reference-ui/" + key + ".svg")
	return reference_icons[key]

func set_reference_icon(item: Button, key: String) -> void:
	item.text = ""
	if item.get_meta("reference_icon", "") == key: return
	item.icon = reference_icon(key)
	item.set_meta("reference_icon", key)
	item.expand_icon = true
	item.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.add_theme_constant_override("icon_max_width", 22)
	item.add_theme_color_override("icon_normal_color", app.palette().ink)

func change_lines(delta: int) -> void:
	if report_board_active and not live_enabled:
		report_board_line_limit = clampi(mini(report_board_line_limit, live_details.size()) + delta, 1, 5)
		report_board_key = ""
		refresh_report_board()
		return
	set_extra("analysis_lines", clampi(app.preferences.studio.analysis_lines + delta, 1, 5))
	live_key = ""
	clear_pv_rows()

func clear_pv_rows() -> void:
	for row in pv_rows.values(): pv_column.remove_child(row); row.queue_free()
	pv_rows.clear()
	live_text.show()

func update_pv_arrows() -> void:
	arrows.clear()
	for index in pv_rows:
		if not pv_rows[index].eye_button.button_pressed: continue
		var detail: Dictionary = live_details.get(index, {})
		if detail.get("pv", []).is_empty(): continue
		var move = app.Codec.parse_move(detail.pv[0], app._display_position())
		if not move.is_empty():
			move.hint_line = int(index)
			arrows.append(move)
	app._redraw()

func preview_pv(index: int) -> void:
	if not live_details.has(index) or not pv_context.is_empty(): return
	var next = app.Game.new()
	if not next.set_initial(app.Codec.sfen(app._display_position())): return
	next.mode = "local"
	for value in live_details[index].get("pv", []):
		var move = app.Codec.parse_move(value, next.position)
		if move.is_empty() or not next.play(move): break
	if next.moves.is_empty(): return
	pv_context = {"game": app.review_game, "path": app.review_path, "ply": app.replay_index, "live": live_enabled}
	app._pause_search()
	live_enabled = false
	app.review_game = next
	app.review_path = ""
	app.replay_index = 0
	app._cancel_motion()
	app._refresh()
	autoplay_on = true
	return_line.show()
	eval_label.text = app.t("候选线路预览")
	arrows.clear()

func stop_pv(return_report: bool = true) -> void:
	if pv_context.is_empty(): return
	var from_report: bool = pv_context.get("report", false)
	var from_details: bool = pv_context.get("details", false)
	app._cancel_motion()
	app.review_game = pv_context.game
	app.review_path = pv_context.path
	app.replay_index = pv_context.ply
	live_enabled = pv_context.live
	pv_context.clear()
	autoplay_on = false
	return_line.hide()
	localize(return_line, "↶ 返回原局")
	eval_label.text = "YaneuraOu"
	live_key = ""
	app._refresh()
	report_board_key = ""
	refresh_report_board()
	if from_report and return_report:
		if from_details: show_report_move_details.call_deferred(report_selected_ply, true)
		else: show_report.call_deferred()

func show_drawer() -> void:
	var column = _page("将棋", "drawer", true)
	column.add_child(label("对弈 · 分析 · 进步", 14))
	for entry in [["棋盘", close], ["开始对弈", show_play], ["分析棋谱", show_import_analysis], ["历史大赛对局", show_historic_games], ["局面编辑", show_editor], ["棋谱库", show_archives], ["开局与练习", show_openings], ["互动教程", tutorial.show_catalog], ["设置", show_settings], ["备份与恢复", show_backup], ["关于", show_about]]:
		var item = button(entry[0], entry[1])
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.custom_minimum_size.y = 46
		item.add_theme_font_size_override("font_size", 16)
		column.add_child(item)

func show_menu() -> void:
	var column = _page("更多选项", "menu", true)
	column.add_child(button("变化线路" if study_active() else "试下变化", show_variations if study_active() else start_variation_analysis))
	for entry in [["返回棋盘", _board_keep], ["悔棋", func(): close(); app._undo_move()], ["新对局", show_play], ["从此处继续", branch_here], ["整局分析报告", func(): start_report(false)], ["添加注释", show_comment], ["编辑棋谱信息", show_tags], ["画箭头与圆圈", start_drawing], ["清除本步标记", clear_annotations], ["保存棋谱", func():
		var saved: String = save_viewed_record()
		if saved.is_empty(): show_message(app.records.error)
		else: show_record_details(saved)
	], ["导出棋谱 / SFEN", show_export], ["入玉宣言", show_declaration], ["认输", show_resign]]:
		var item = button(entry[0], entry[1])
		item.alignment = HORIZONTAL_ALIGNMENT_LEFT
		column.add_child(item)
	if app.session != null: column.add_child(button("当前联机", show_connection))

func back() -> void:
	if page_name in archive_view.PAGES:
		for option in page.find_children("*","OptionButton",true,false):
			if option.get_popup().visible: option.get_popup().hide(); return
		if keyboard_height > 0:
			DisplayServer.virtual_keyboard_hide()
			var focus = root.get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus()
			return
		if page_name == "archive-filter": archive_view.close_filter(); return
		if page_name == "analysis-recent": archive_view.leave_archive(); return
		archive_view.show(); return
	if page_name == "tournament-filter":
		var options = page.find_child("HistoricYear",true,false)
		if options != null and options.get_popup().visible: options.get_popup().hide(); return
		if keyboard_height > 0:
			DisplayServer.virtual_keyboard_hide()
			var focus = root.get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus()
			return
		tournament_view.close_filter("cancel"); return
	if page_name == "tournament-archive": archive_view.leave_archive(); return
	if page_name in ["analysis-import", "analysis-help", "analysis-import-choice"]:
		if file_dialog != null and is_instance_valid(file_dialog) and file_dialog.visible:
			file_dialog.hide()
			if file_dialog.has_meta("analysis_import"): analysis_import.file_received(analysis_import.picker_ticket, "", "")
			return
		if keyboard_height > 0:
			DisplayServer.virtual_keyboard_hide()
			var focus = root.get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus()
			return
		if page_name != "analysis-import": analysis_import.show(0); return
	if page_name == "opening-info": opening_view.show_list(); return
	if page_name == "editor" and is_instance_valid(editor) and editor.interaction.pointer_id != -2: editor.interaction.cancel(); return
	if page_name == "evaluation-options": _board_keep(); return
	if page_name in ["save-study", "replace-game"]: _board_keep(); return
	if page_name in ["variations", "variation-move", "variation-policy"]: _board_keep(); return
	if page == null and study_active(): finish_study(); return
	if page_name == "report-move":
		if report_move_from_report: show_report()
		else: open_report_position(report_selected_ply)
		return
	if practice_active() and page == null:
		if practice.stage == "preview": practice.end_preview()
		else: practice.stop()
		return
	if page_name == "retry-settings":
		if retry_from_report: show_report()
		else: _board_keep()
		return
	if page_name in ["report-phase", "report-classifications", "report-story-info", "report-move", "report-accuracy", "report-metric-info"]: show_report(); return
	if page_name == "report-value": show_report_settings(); return
	if page_name == "report-settings": _board_keep(); return
	if page == null and not pv_context.is_empty(): stop_pv(); return
	if page_name in ["drawer", "menu", "report", "editor", "openings", "comment", "tags", "export", "backup", "about", "analysis-import", "board-settings", "engine-settings", "sound-settings", "bot-picker"]:
		_board_keep()
		return
	if page == null and drawing: drawing = false; live_text.text = app.t("标记已保存"); return
	if page == null and app.replay_index >= 0: close(); return
	super.back()

func show_play() -> void:
	var column = _page("开始对弈", "play")
	for entry in [["与电脑对弈", "选择难度与先后手", show_bots], ["同机双人", "与朋友共用棋盘", func(): show_setup(1)], ["电脑对电脑", "观看引擎双方对弈", func(): show_setup(2)], ["网络对战", "IP 直连对局", show_network], ["蓝牙对战", "连接附近的 Android 设备", show_bluetooth]]:
		column.add_child(action_row(entry[0], entry[1], "play", entry[2], true))

func show_bots() -> void:
	var column = _page("选择电脑", "bot-picker")
	column.add_child(label("选择练习搭档", 22))
	var names = ["小步", "桂风", "银月", "金城", "龙马", "王将"]
	var hints = ["熟悉每一枚棋子的走法", "练习吃子与持驹打入", "留意对方的下一步", "制定完整的攻守计划", "寻找局面中的关键着手", "挑战完整搜索强度"]
	for i in range(6):
		var level = i
		column.add_child(action_row(names[i] + "  ·  " + app.USI.LEVELS[i].name, hints[i], "play", func(): app.engine_level = level; show_setup(0), true))

func show_setup(initial_mode: int = 0) -> void:
	var column = _page("新对局", "setup")
	var mode = choice(column, "对弈方式", ["人机对弈", "同机双人", "电脑对电脑"], initial_mode)
	var side = choice(column, "我的先后手", ["先手", "后手", "随机"], 0)
	var engine = choice(column, "电脑", ["YaneuraOu", "基础电脑"], 0 if app.engine_provider == "yaneuraou" else 1)
	var levels: Array[String] = []
	for entry in app.USI.LEVELS: levels.append(entry.name)
	var level = choice(column, "难度", levels, app.engine_level)
	var clocks: Array[String] = []
	for entry in app.Game.Clock.PRESETS: clocks.append(entry.name)
	var clock_option = choice(column, "用时", clocks, 0)
	column.add_child(label("本地对局打开菜单时暂停计时。开始前可选择是否保存当前棋谱。", 14))
	column.add_child(button("开始", func():
		var mode_index = mode.selected
		var human = (1 if randi() % 2 == 0 else -1) if side.selected == 2 else (1 if side.selected == 0 else -1)
		var level_index = level.selected
		var provider = "yaneuraou" if engine.selected == 0 else "basic"
		var clock_index = clock_option.selected
		replace_game(func():
			app._start_match("local" if mode_index == 1 else "ai", human, level_index, provider, clock_index)
			app.game.engine_match = mode_index == 2
			app._save()
			close()
		)
	))

func show_editor() -> void:
	if app.session != null: show_message("请先结束或退出联机对局。"); return
	var source = app._display_position().copy()
	var column = _page("局面编辑", "editor")
	editor = preload("res://scripts/shogi_position_editor.gd").new()
	column.add_child(editor)
	editor.build(self, source)
	editor.submitted.connect(func(sfen):
		var orientation: bool = editor.flipped
		var next = app.Game.new()
		if not next.set_initial(sfen): return
		next.update_result()
		next.mode = "local"
		adopt_game(next, orientation)
	)

func adopt_game(next, orientation: Variant = null) -> void:
	replace_game(func(): _adopt_game(next, orientation))

func _adopt_game(next, orientation: Variant = null) -> void:
	if app.coach != null: app.coach.clear()
	if not app._leave_network(): return
	app._pause_search()
	app._leave_review()
	app._cancel_motion()
	app.game = next
	app.archive_baseline = app.RecordChanges.game_signature(next)
	app.engine_level = next.engine_level
	app.engine_provider = next.engine_provider
	if orientation is bool: app.flipped = orientation
	app._save()
	close()

func branch_here() -> void:
	if app.session != null: show_message("联机中不能从历史局面创建分支。"); return
	autoplay_on = false
	var data: Dictionary = (study.fork_at_cursor(app.replay_index).to_data() if study != null and study.active and app.review_game == study.view else app._view_game().to_data()).duplicate(true)
	if app.replay_index >= 0: app.Game.truncate_data(data, app.replay_index)
	for key in ["resigned", "resigned_side", "agreed_draw", "declared_side", "clock"]: data.erase(key)
	data.mode = app.game.mode
	data.human_side = app._display_position().turn
	data.engine_provider = app.engine_provider
	data.engine_level = app.engine_level
	data.comments = data.comments.duplicate()
	data.annotations = data.annotations.duplicate()
	for key in data.comments.keys():
		if int(key) > data.moves.size(): data.comments.erase(key)
	for key in data.annotations.keys():
		if int(key) > data.moves.size(): data.annotations.erase(key)
	data.engine_match = false
	var next = app.Game.from_data(data)
	if next != null: replace_game(func(): _adopt_game(next), true)

func show_import_analysis(tab: int = -1) -> void:
	analysis_import.show(tab)

func show_historic_games() -> void:
	show_import_analysis(1)

func refresh_historic_list() -> void:
	tournament_view.refresh()

func open_historic(entry: Dictionary) -> void:
	tournament_view.open_entry(entry)

func _open_tournament_game(next) -> void:
	if not finish_study(true, func(): _open_tournament_game(next)): return
	if not analysis_import.open_game(next): return
	live_enabled = false
	live_details.clear()
	clear_pv_rows()
	live_text.text = next.metadata["棋战"] + "\n" + next.metadata["先手"] + "  —  " + next.metadata["后手"]
	eval_label.text = app.t("历史大赛 · %d 手") % next.moves.size()
	update_inline_report()

func show_paste() -> void:
	var column = _page("粘贴棋谱 / SFEN", "paste-record")
	column.add_child(label("JSON · KIF · CSA · USI · SFEN", 14))
	var input = TextEdit.new()
	input.custom_minimum_size.y = 240
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.text = DisplayServer.clipboard_get().left(2097152)
	column.add_child(input)
	column.add_child(button("导入", func(): _import_text(input.text)))

func _import_text(value: String) -> void:
	if reading_backup:
		reading_backup = false
		show_restore(value)
		return
	var codec = Exchange.new()
	var imported = codec.parse(value)
	if imported == null: show_message(codec.error); return
	var saved: String = app.records.archive(imported)
	if saved.is_empty(): show_message(app.records.error)
	else: show_record_details(saved)

func import_record() -> void:
	if platform != null and platform.has_method("pickRecord"): platform.pickRecord(); return
	_open_file(false, func(path):
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 2097152: show_message("棋谱无法读取。"); return
		_import_text(file.get_as_text())
	)
	file_dialog.clear_filters()
	file_dialog.add_filter("*.json,*.kif,*.kifu,*.csa,*.usi,*.sfen,*.txt", "将棋棋谱")

func show_export() -> void:
	var viewed = record_game()
	var column = _page("导出棋谱", "export")
	var selector = choice(column, "格式", ["KIF", "CSA", "USI", "SFEN", "JSON"], 4 if viewed.variation_tree != null else 0)
	if viewed.variation_tree != null: column.add_child(label("JSON 保存全部变化、注释和标记；KIF、CSA、USI 仅导出主线。", 13))
	var text = TextEdit.new()
	text.custom_minimum_size.y = 220
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.text = Exchange.export_game(viewed, "JSON" if viewed.variation_tree != null else "KIF")
	column.add_child(text)
	selector.item_selected.connect(func(index):
		text.text = Exchange.export_game(viewed, ["KIF", "CSA", "USI", "SFEN", "JSON"][index])
		if index == 3: text.text = app.Codec.sfen(app._display_position())
	)
	column.add_child(button("复制", func(): DisplayServer.clipboard_set(text.text); show_message("已复制")))
	column.add_child(button("保存文件", func(): save_text(text.text, "shogi." + selector.get_item_text(selector.selected).to_lower())))

func save_text(value: String, filename: String) -> void:
	if platform != null and platform.has_method("exportText"): platform.exportText(value, filename); return
	_open_file(true, func(path):
		var file = FileAccess.open(path, FileAccess.WRITE)
		if file == null: show_message("保存失败"); return
		file.store_string(value)
		file.flush()
		show_message("已保存" if file.get_error() == OK else "保存失败")
	)
	file_dialog.clear_filters()
	file_dialog.current_file = filename

func show_comment() -> void:
	if not prepare_review_edit(): return
	var viewed = app._view_game()
	var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
	var column = _page("第 %d 手 · 注释" % ply, "comment")
	var input = TextEdit.new()
	input.custom_minimum_size.y = 200
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.text = str(viewed.comments.get(str(ply), ""))
	column.add_child(input)
	column.add_child(button("保存注释", func():
		viewed.comments[str(ply)] = input.text.left(20000)
		persist_viewed()
		_board_keep()
	))

func show_tags() -> void:
	if not prepare_review_edit(): return
	var viewed = app._view_game()
	var column = _page("棋谱信息", "tags")
	var fields: Dictionary = {}
	for key in ["先手", "后手", "棋战", "开始日時", "场所"]: fields[key] = field(column, key, str(viewed.metadata.get(key, "")))
	column.add_child(button("保存", func():
		for key in fields:
			if viewed.metadata.has(key) or not fields[key].text.is_empty(): viewed.metadata[key] = fields[key].text.left(200)
		persist_viewed()
		_board_keep()
	))

func prepare_review_edit() -> bool:
	if app.review_game != null and not study_active(): start_variation_analysis()
	return app.review_game == null or study_active()

func save_viewed_record() -> String:
	if study_active(): return study.record_path if study.save() else ""
	var viewed = record_game()
	var path: String = app.records.archive(viewed)
	if not path.is_empty() and viewed == app.game: app.archive_baseline = app.RecordChanges.game_signature(app.game)
	return path

func persist_viewed() -> void:
	ribbon_key = ""
	if study_active():
		study.persist_view()
		if not study.error.is_empty(): show_message(study.error)
		return
	if app.review_game == null: app._save()

func start_drawing() -> void:
	if not prepare_review_edit(): return
	_board_keep()
	drawing = true
	live_enabled = false
	app._pause_search()
	live_text.text = app.t("拖动两个格子画箭头，点格子画圆。返回键结束。")

func clear_annotations() -> void:
	if not prepare_review_edit(): return
	var viewed = app._view_game()
	var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
	viewed.annotations.erase(str(ply))
	persist_viewed()
	_board_keep()

func consume_board_input(event: InputEvent) -> bool:
	if not drawing or page != null: return false
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION: return true
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		if handles_point(event.position): return false
		var square: int = app._square_at(event.position)
		if event.pressed: drawing_start = square
		elif drawing_start >= 0 and square >= 0:
			var viewed = app._view_game()
			var ply: int = viewed.moves.size() if app.replay_index < 0 else app.replay_index
			var marks: Array = viewed.annotations.get(str(ply), [])
			var mark = [drawing_start, square]
			if mark in marks: marks.erase(mark)
			elif marks.size() < 64: marks.append(mark)
			viewed.annotations[str(ply)] = marks
			persist_viewed()
			app._redraw()
		return true
	return event is InputEventMouseMotion or event is InputEventScreenDrag

func show_openings(query: Variant = null) -> void:
	opening_view.show_list(query)

func start_report(deep: bool) -> void:
	if not pv_context.is_empty(): stop_pv(false)
	var source = app._view_game()
	if study_active(): study.paused = true
	_board_keep()
	live_enabled = false
	app._pause_search()
	clear_pv_rows()
	report_selected_ply = -1
	report_story_expanded = false
	report_category = ""
	report_category_side = 0
	report.start(source, deep, app.preferences.report, app.preferences.studio)
	report_filter = 0
	report_expanded = true
	eval_label.text = "整局分析 · " + ("深度报告" if deep else "快速报告")
	engine_toggle.text = "▷"
	update_inline_report()

func show_report_settings() -> void:
	var column = report_dialog("分析设置", "report-settings", "选择整局分析的精细程度", "ic_tune")
	var controls = preload("res://scripts/shogi_report_settings_view.gd").new()
	column.add_child(controls)
	controls.build(self)
	extra_toggle(column, "报告显示平均评价损失（ACPL）", "report_cpl")

func report_dialog(title: String, name: String, subtitle: String, icon: String = "ic_report") -> VBoxContainer:
	var column = _page(title, name)
	var panel_style = Design.box(app.palette().background, 20, 16)
	panel_style.border_color = Color(1, 1, 1, 0.15) if app.preferences.is_dark() else Color(0, 0, 0, 0.08)
	panel_style.set_border_width_all(1)
	page.add_theme_stylebox_override("panel", panel_style)
	var outer = page.get_child(0)
	outer.add_theme_constant_override("separation", 14)
	var header = outer.get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	header.add_theme_constant_override("separation", 12)
	if name in WOOD_REPORT_PAGES:
		var wood = StyleBoxTexture.new()
		wood.texture = load("res://assets/reference-ui/wood_dark.png")
		wood.content_margin_left = 12
		wood.content_margin_right = 12
		wood.content_margin_top = 5
		wood.content_margin_bottom = 18
		page.add_theme_stylebox_override("panel", wood)
		if name != "report": round_wood_dialog()
		if name == "report":
			var spacer = Control.new()
			spacer.custom_minimum_size.x = 44
			header.add_child(spacer)
		var heading = label(title, 16 if name == "report" else 18)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if name == "report" else HORIZONTAL_ALIGNMENT_LEFT
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(heading)
		var dismiss_report = compact_button("×", back, 44)
		dismiss_report.custom_minimum_size.x = 44
		dismiss_report.size_flags_horizontal = Control.SIZE_SHRINK_END
		set_reference_icon(dismiss_report, "ic_close")
		dismiss_report.add_theme_color_override("icon_normal_color", Color("f8f1e6"))
		dismiss_report.add_theme_stylebox_override("normal", Design.box(Color.TRANSPARENT, 0, 10))
		header.add_child(dismiss_report)
		return column
	var icon_panel = PanelContainer.new()
	icon_panel.add_theme_stylebox_override("panel", Design.box(Color(app.palette().accent, 0.12), 10, 8))
	icon_panel.custom_minimum_size = Vector2(40, 40)
	header.add_child(icon_panel)
	var badge = TextureRect.new()
	badge.texture = reference_icon(icon)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.custom_minimum_size = Vector2(24, 24)
	badge.modulate = app.palette().accent
	icon_panel.add_child(badge)
	var titles = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	titles.add_child(label(title, 18))
	var caption = label(subtitle, 12)
	caption.add_theme_color_override("font_color", app.palette().muted)
	titles.add_child(caption)
	header.add_child(titles)
	var dismiss = compact_button("×", back, 40)
	dismiss.custom_minimum_size.x = 40
	dismiss.size_flags_horizontal = Control.SIZE_SHRINK_END
	set_reference_icon(dismiss, "ic_close")
	dismiss.add_theme_stylebox_override("normal", Design.box(Color.TRANSPARENT, 0, 8))
	header.add_child(dismiss)
	return column

func set_report_option(key: String, value: Variant) -> void:
	app.preferences.report[key] = value
	app.preferences.report = preload("res://scripts/shogi_report_settings.gd").normalized(app.preferences.report)
	if not app.testing and app.preferences.save_to() != OK: show_message("分析设置保存失败。")

func show_report_value(prefix: String) -> void:
	var is_time: bool = app.preferences.report[prefix + "_mode"] == "time"
	var key = prefix + ("_time" if is_time else "_depth")
	var column = report_dialog(("快速报告" if prefix == "quick" else "深度报告") + ("时间" if is_time else "深度"), "report-value", "0.1–10 秒" if is_time else "1–30 层", "ic_settings")
	var input = SpinBox.new()
	input.name = "ReportValueInput"
	input.min_value = 0.1 if is_time else 1
	input.max_value = 10 if is_time else 30
	input.step = 0.1 if is_time else 1
	input.value = app.preferences.report[key]
	input.suffix = "秒" if is_time else "层"
	input.custom_minimum_size.y = 48
	column.add_child(input)
	column.add_child(button("确定", func(): input.apply(); set_report_option(key, input.value); show_report_settings()))

func update_inline_report() -> void:
	if report_inline == null: return
	for child in report_inline.get_children(): report_inline.remove_child(child); child.queue_free()
	if report.game == null or practice_active() or study_active(): report_inline.hide(); return
	var viewed = app._view_game()
	report_inline.visible = viewed.initial_sfen == report.game.initial_sfen and viewed.moves == report.game.moves
	if not report_inline.visible: return
	live_text.hide()
	var header = HBoxContainer.new()
	report_inline.add_child(header)
	for entry in [["双方", 0], ["先手", 1], ["后手", -1]]:
		var side: int = entry[1]
		var b = compact_button(entry[0], func(): report_side = side; update_inline_report())
		b.add_theme_stylebox_override("normal", Design.box(app.palette().accent if report_side == side else Color(0, 0, 0, 0.18), 16, 4))
		if report_side == side: b.add_theme_color_override("font_color", Color.WHITE)
		header.add_child(b)
	for entry in [["▥", "打开详细报告", show_report], ["‹", "上一个失误", func(): seek_mistake(-1)], ["›", "下一个失误", func(): seek_mistake(1)], ["⌃" if report_expanded else "⌄", "收起 / 展开报告", func(): report_expanded = not report_expanded; update_inline_report()]]:
		var b = compact_button(entry[0], entry[2], 28)
		b.tooltip_text = entry[1]
		header.add_child(b)
	if report.running:
		var progress = ProgressBar.new()
		progress.custom_minimum_size.y = 8
		progress.max_value = report.game.positions.size()
		progress.value = report.samples.size()
		progress.show_percentage = false
		report_inline.add_child(progress)
		report_inline.add_child(label(report.progress_text(), 12))
		report_inline.add_child(compact_button("停止分析", func(): report.cancel(); update_inline_report()))
	elif not report.error.is_empty():
		report_inline.add_child(label(report.error, 13))
	elif report_expanded:
		var counts_scroll = ScrollContainer.new()
		counts_scroll.name = "InlineClassificationCounts"
		counts_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		counts_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		counts_scroll.custom_minimum_size.y = 44
		report_inline.add_child(counts_scroll)
		var counts = HBoxContainer.new()
		counts.add_theme_constant_override("separation", 9)
		counts_scroll.add_child(counts)
		for category in report.CATEGORIES:
			var total = 0
			for result in report.rows:
				if (report_side == 0 or report_side == result.side) and result.category == category: total += 1
			var item = compact_button(str(total) + "\n" + category, func(): select_report_category(report_side, category), 36)
			item.name = "InlineCategory_" + category
			item.disabled = total == 0
			item.add_theme_font_size_override("font_size", 11)
			item.custom_minimum_size.x = 35 if category != "错失胜机" else 52
			item.alignment = HORIZONTAL_ALIGNMENT_CENTER
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			counts.add_child(item)
		var viewed_ply: int = app._view_game().moves.size() if app.replay_index < 0 else app.replay_index
		for result in report.rows:
			if result.ply == viewed_ply:
				report_inline.add_child(label("%d. %s · %s · 评价损失 %d" % [result.ply, result.label, result.category, result.loss], 12))
				break
		var actions = HBoxContainer.new()
		report_inline.add_child(actions)
		actions.add_child(compact_button("复习失误", review_mistake, 32))
		var detail_ply = viewed_ply
		var more = compact_button("本手解析", func(): show_report_move_details(detail_ply), 32)
		more.name = "ReportMoveDetails"
		more.disabled = app._view_game() != report.game or detail_ply <= 0 or detail_ply > report.rows.size()
		actions.add_child(more)
	if report.can_resume(): report_inline.add_child(compact_button("继续分析 · %d / %d" % [report.samples.size(), report.game.positions.size()], report.resume))

func seek_mistake(direction: int) -> void:
	if report.game == null: return
	var current: int = app._view_game().moves.size() if app.replay_index < 0 else app.replay_index
	var eligible = report.rows.filter(func(r): return r.category in ["失误", "漏着", "错失胜机"] and (report_side == 0 or r.side == report_side))
	if eligible.is_empty(): show_message("所选棋手没有失误。 "); return
	if direction < 0: eligible.reverse()
	var target: int = eligible[0].ply
	for r in eligible:
		if (r.ply - current) * direction > 0: target = r.ply; break
	app.review_game = report.game
	app.review_path = ""
	show_history(target)
	update_inline_report()

func show_report() -> void:
	if report_statistics_source != report.game: report_statistics_source = report.game; report_moves_expanded = false
	var column = report_dialog("整局分析报告", "report", "快速报告" if not report.deep_report else "深度报告")
	if report_story_source != report.game: report_story_source = report.game; report_story_expanded = false
	report_story = preload("res://scripts/shogi_report_story_view.gd").new()
	column.add_child(report_story)
	report_story.setup(self)
	report_progress = label("", 15)
	column.add_child(report_progress)
	var graph_panel = report_panel(column, Color("101215f2"), Color("58a6ff66"), 8)
	report_selection = VBoxContainer.new()
	report_selection.name = "SelectedMoveSummary"
	graph_panel.add_child(report_selection)
	report_chart = preload("res://scripts/shogi_report_chart.gd").new()
	report_chart.samples = report.samples
	report_chart.rows = report.rows
	report_chart.phases = report.phases()
	report_chart.total_plies = report.game.moves.size() if report.game != null else 0
	report_chart.selected.connect(select_report_move)
	graph_panel.add_child(report_chart)
	report_chart.custom_minimum_size.y = 168
	report_phases = preload("res://scripts/shogi_report_phases.gd").new()
	report_phases.name = "PhaseRibbon"
	report_phases.ui = self
	report_phases.report = report
	report_phases.show_cpl = app.preferences.studio.report_cpl
	report_phases.selected.connect(show_phase_accuracy)
	report_phases.accuracy_selected.connect(show_accuracy_insight)
	report_phases.acpl_selected.connect(show_acpl_info)
	report_phases.rating_selected.connect(show_rating_info)
	graph_panel.add_child(report_phases)
	if report.game != null:
		var opening = ""
		var longest = 0
		var played = PackedStringArray()
		for move in report.game.moves: played.append(app.Codec.move_name(move))
		var sequence = " ".join(played) + " "
		if report.game.initial_sfen.is_empty():
			for line in Openings.LINES:
				if sequence.begins_with(line.moves + " ") and line.moves.length() > longest: opening = line.name; longest = line.moves.length()
		if not opening.is_empty(): column.add_child(label("开局 · " + opening, 14))
	if report.running:
		column.add_child(button("停止分析", func(): report.cancel(); show_report()))
		column.add_child(button("后台分析 / 返回棋盘", _board_keep))
	else:
		if report.game == null: report_changed(); return
		if report.can_resume(): column.add_child(button("继续分析", func(): report.resume(); show_report()))
		var statistics = report_panel(column, Color("1f252ce6"), Color("58a6ff66"), 8)
		report_statistics = preload("res://scripts/shogi_report_statistics.gd").new()
		statistics.add_child(report_statistics)
		report_statistics.setup(self)
		column.add_child(label("准确率与阶段划分为将棋分析估计。点击评分查看依据。正分有利先手，负分有利后手。", 12))
		column.add_child(button("复习失误", review_mistake))
		column.add_child(button("保存分析报告", func(): save_text(JSON.stringify({"game": report.game.to_data(), "settings": report.settings, "deep": report.deep_report, "samples": report.samples, "moves": report.rows, "phases": report.phases(), "sente": report.summary(1), "gote": report.summary(-1), "metrics_model": "shogi-report-12-estimate", "classification_model": report.Classification.MODEL, "story": report.story(), "verification_searches": report.verification_searches}, "  "), "shogi-analysis.json")))
	if report_selected_ply >= 0: select_report_move(report_selected_ply)
	style_report_buttons()
	report_changed()

func accuracy_text(stats: Dictionary) -> String:
	return "%.1f" % stats.accuracy if stats.has_accuracy else "—"

func classification_icon(category: String, pixels: int = 24, forced: bool = false) -> TextureRect:
	var item = TextureRect.new()
	var index: int = report.Classification.NAMES.find(category)
	item.texture = reference_icon("ic_forced_move" if forced else report.Classification.ICONS[index] if index > 0 else "ic_bestmove")
	item.custom_minimum_size = Vector2(pixels, pixels)
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func show_classifications() -> void:
	var column = report_dialog("着手分类", "report-classifications", "每类着手的判定依据", "ic_report")
	for category in report.CATEGORIES:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(classification_icon(category))
		var detail = label(category + "：" + report.Classification.EXPLANATIONS[category], 14)
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(detail)
		column.add_child(row)
		if category == "最佳":
			var forced = HBoxContainer.new()
			forced.add_child(classification_icon(category, 24, true))
			var note = label("唯一合法着：只有这一手可下。计数包含在最佳中，不计入准确率。", 14)
			note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			forced.add_child(note)
			column.add_child(forced)
	column.add_child(label("分类是本次引擎分析的估计，会随搜索深度变化。妙手／锐利目前识别子力牺牲与多子攻击；其他复杂战术可能仍显示为最佳。", 12))
	column.add_child(compact_button("返回分析报告", show_report, 40))

func show_story_info() -> void:
	var column = report_dialog("关键时刻", "report-story-info", "哪些着手改变了这盘棋", "ic_report")
	column.add_child(label("关键时刻是改变优势归属或让较大优势流失的转折。经复核的妙手也可能成为亮点。点击卡片可在报告中选中该手，再查看棋盘或从这里继续下。", 15))
	column.add_child(label("默认展示最关键的一手，可展开最多十条。每张卡片显示实际着手、分类、行棋前后评分及变化原因；正分有利先手，负分有利后手。", 15))
	column.add_child(label("摘要只使用已分析局面。分析未完成时不会用最终胜负概括全局；评分和关键时刻会随搜索深度改变。", 15))
	column.add_child(compact_button("返回分析报告", show_report, 40))

func show_phase_accuracy(side: int, _focus_phase: int = 0) -> void:
	if report.game == null or side not in [1,-1]: return
	var column = report_dialog("阶段准确率", "report-phase", "")
	var view = preload("res://scripts/shogi_phase_accuracy_view.gd").new()
	column.add_child(view)
	view.build(self,side)

func fit_wood_dialog() -> void:
	if page == null or page_name not in ["report-phase", "report-accuracy", "report-metric-info"]: return
	var content = page_scroll.get_child(0)
	if not content.minimum_size_changed.is_connected(fit_wood_dialog): content.minimum_size_changed.connect(fit_wood_dialog, CONNECT_DEFERRED)
	var safe = app.safe_rect()
	safe.size.y -= keyboard_height
	var desired = content.get_combined_minimum_size().y + 92
	var dimensions = Vector2(minf(440, safe.size.x * 0.92), minf(maxf(200, desired), maxf(180, safe.size.y - 24)))
	page.size = dimensions
	page.position = safe.position + (safe.size - dimensions) / 2
	backdrop.color = Color(0, 0, 0, 0.6)

func round_wood_dialog() -> void:
	# The reference clips the wood background to a rounded dialog outline.
	# Material applies only to the panel itself, leaving child text sharp.
	var shader = Shader.new()
	shader.code = """shader_type canvas_item;
uniform vec2 panel_size;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
    vec4 sampled = COLOR;
    float radius = 14.0;
    vec2 q = abs(local_position - panel_size * 0.5) - (panel_size * 0.5 - vec2(radius));
    float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    COLOR = vec4(sampled.rgb, sampled.a * (1.0 - smoothstep(-0.6, 0.6, distance)));
}"""
	var material = ShaderMaterial.new()
	material.shader = shader
	var panel = page
	panel.material = material
	panel.resized.connect(func(): material.set_shader_parameter("panel_size", panel.size))
	material.set_shader_parameter("panel_size", panel.size)

func show_accuracy_insight(side: int) -> void:
	if report.game == null or side not in [1, -1]: return
	var column = report_dialog("准确率", "report-accuracy", "")
	report_accuracy_view = preload("res://scripts/shogi_accuracy_insight_view.gd").new()
	column.add_child(report_accuracy_view)
	report_accuracy_view.build(self, side)

func show_rating_info(side: int) -> void:
	if report.game == null or side not in [1, -1]: return
	var column = report_dialog("估计等级分", "report-metric-info", "")
	column.add_child(label(("先手" if side == 1 else "后手") + " · " + report.player_name(side), 15))
	column.add_child(label("暂无等级分估计", 23))
	column.add_child(label("当前报告未提供将棋等级分估计。单局表现受对手、用时和局面影响，不能视为正式等级分或段位。", 15))
	column.add_child(label("你仍可查看准确率、阶段表现和每一步的引擎线路。", 13))
	column.add_child(compact_button("返回分析报告", show_report, 40))
	style_report_buttons()
	fit_wood_dialog()

func show_acpl_info(side: int) -> void:
	if report.game == null: return
	var column = report_dialog("平均评价损失", "report-metric-info", "")
	var stats = report.summary(side)
	column.add_child(label(report.player_name(side) + (" · ACPL %d" % roundi(stats.average_loss) if stats.has_accuracy else " · ACPL —"), 18))
	column.add_child(label("ACPL 表示每手相对引擎最佳选择损失的平均评价值，数值越低，平均损失越小。这里使用将棋引擎的评分单位；定式与唯一合法着不计入。", 14))
	column.add_child(label("它与准确率的含义不同：相同的评价损失，在均势、明显占优或明显落败时，对取胜机会的影响可以不同。", 14))
	column.add_child(compact_button("返回分析报告", show_report, 36))
	style_report_buttons()
	fit_wood_dialog()

func report_panel(parent: Control, fill: Color, border: Color, margin: int) -> VBoxContainer:
	var panel = PanelContainer.new()
	var style = Design.box(fill, 8, margin)
	style.border_color = border
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	panel.add_child(content)
	return content

func style_report_buttons() -> void:
	for item in page.find_children("*", "Button", true, false):
		if str(item.name).begins_with("ClassificationCount") or item.has_meta("phase_ribbon_control") or item.has_meta("report_statistics_control"): continue
		if item.name in ["ToggleStoryMoments","StoryMomentsHelp"]: continue
		item.add_theme_color_override("font_color", Color("f8f1e6"))
		item.add_theme_color_override("icon_normal_color", Color("f8f1e6"))

func clear_report_selection() -> void:
	report_selected_ply = -1
	if is_instance_valid(report_chart): report_chart.active = -1; report_chart.queue_redraw()
	if is_instance_valid(report_selection):
		for child in report_selection.get_children(): report_selection.remove_child(child); child.queue_free()

func select_report_move(ply: int) -> void:
	if not is_instance_valid(report_selection) or ply < 0 or ply >= report.samples.size(): return
	if ply == 0: clear_report_selection(); return
	report_selected_ply = ply
	report_chart.active = ply
	report_chart.queue_redraw()
	for child in report_selection.get_children(): report_selection.remove_child(child); child.queue_free()
	var card = preload("res://scripts/shogi_report_move_card.gd").new()
	report_selection.add_child(card)
	card.setup(self, ply)

func open_report_position(ply: int) -> void:
	if report.game == null or ply < 0 or ply >= report.samples.size(): return
	if not pv_context.is_empty(): stop_pv(false)
	var before = app._view_tokens()
	if page != null: _board_keep()
	app._pause_search()
	live_enabled = false
	autoplay_on = false
	app.review_game = report.game
	app.review_path = ""
	app.replay_index = ply
	report_selected_ply = ply
	report_board_active = true
	report_board_game = report.game
	report_board_key = ""
	report_board_line_limit = 5
	app._refresh()
	app._present_transition(before, false)
	update_inline_report()
	refresh_report_board()

func refresh_report_board() -> void:
	if not report_board_active or not pv_context.is_empty() or page != null: return
	if report.game != report_board_game or app.review_game != report_board_game or practice_active() or live_enabled:
		report_board_active = false
		report_board_key = ""
		if not live_enabled: live_details.clear(); clear_pv_rows(); arrows.clear(); app._redraw()
		return
	var ply: int = app.replay_index
	var key = str([ply, report.samples.size(), report_board_line_limit])
	if key == report_board_key: return
	report_board_key = key
	live_details.clear()
	clear_pv_rows()
	arrows.clear()
	live_key = app._display_position().key()
	if ply >= 0 and ply < report.samples.size():
		var limit = report_board_line_limit
		for candidate in report.samples[ply].get("candidates", []):
			if int(candidate.get("multipv", 1)) <= limit: receive_info(candidate, true)
		eval_label.text = app.t("报告快照 · 第 %d 手 · 深度 %d") % [ply, report.samples[ply].depth]
		if live_details.is_empty(): live_text.text = app.t("该局面没有保存的候选线路。")
	else:
		eval_label.text = app.t("此局面尚未分析")
		live_text.text = app.t("点击播放分析可继续搜索。")
	app._redraw()

func show_report_move_details(ply: int, restore_context: bool = false) -> void:
	if report.game == null or ply <= 0 or ply > report.rows.size(): return
	if not restore_context: report_move_from_report = page_name == "report"
	report_selected_ply = ply
	var column = report_dialog("第 %d 手解析" % ply, "report-move", "原着与保存的最佳线路", "ic_report")
	column.add_child(label(report.rows[ply - 1].label, 17))
	var detail = label(report.score_text(ply) if ply == 0 else report.rows[ply - 1].category + "    " + report.score_text(ply - 1) + " → " + report.score_text(ply), 14)
	if ply > 0 and app.preferences.is_dark(): detail.add_theme_color_override("font_color", report.category_color(report.rows[ply - 1].category))
	column.add_child(detail)
	if ply > 0:
		var selected_row: Dictionary = report.rows[ply - 1]
		var reason = "唯一合法着：当时只有这一手可下，不计入准确率。" if selected_row.get("forced", false) else report.Classification.EXPLANATIONS.get(selected_row.category, "")
		var verification: Dictionary = selected_row.get("classification", {}).get("verification", {})
		if verification.get("accepted", false): reason += "\n复核候选差距 %.2f；搜索深度 %d。" % [verification.gap_cp * report.Metrics.CP_SCALE / 100, int(verification.candidates[0].get("depth", 0))]
		var explanation = label(reason, 12)
		explanation.name = "ReportMoveExplanation"
		column.add_child(explanation)
	column.add_child(compact_button("在棋盘查看", func(): open_report_position(ply), 36))
	column.add_child(compact_button("从这里下", func():
		open_report_position(ply)
		branch_here()
	, 36))
	var analyzed_ply = maxi(0, ply - 1)
	column.add_child(label("行棋前 · 第 %d 手后的局面（评分以先手为正）" % analyzed_ply, 13))
	var alternatives: Array = report.samples[analyzed_ply].get("candidates", [])
	for entry in alternatives:
		var candidate: Dictionary = entry
		var row = HBoxContainer.new()
		column.add_child(row)
		var absolute_score = {"score": float(candidate.score) * report.game.positions[analyzed_ply].turn, "mate": candidate.get("score_type") == "mate", "mate_distance": int(candidate.score)}
		var score = label(preload("res://scripts/shogi_report_move.gd").score_label(absolute_score), 13)
		score.custom_minimum_size.x = 44
		row.add_child(score)
		var scroll = ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		row.add_child(scroll)
		var moves = label(report_line_text(analyzed_ply, candidate), 13)
		moves.autowrap_mode = TextServer.AUTOWRAP_OFF
		scroll.add_child(moves)
		var preview = compact_button("▷", func(): preview_report_line(analyzed_ply, candidate, true), 28)
		preview.name = "ReportCandidatePreview%d" % int(candidate.get("multipv", 1))
		preview.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(preview)

	column.add_child(compact_button("返回分析报告", show_report, 36))

func report_line_text(ply: int, details: Dictionary) -> String:
	var position = report.game.positions[ply].copy()
	var names = PackedStringArray()
	for value in details.get("pv", []):
		var move = app.Codec.parse_move(value, position)
		if move.is_empty(): break
		names.append(position.notation(move))
		position = position.after(move)
	return "  ".join(names)

func preview_report_line(ply: int, details: Dictionary, return_details: bool = false) -> void:
	_board_keep()
	app.review_game = report.game
	app.review_path = ""
	app.replay_index = ply
	live_enabled = false
	live_details = {1: details}
	app._refresh()
	preview_pv(1)
	if not pv_context.is_empty():
		pv_context.report = true
		pv_context.details = return_details
		return_line.text = app.t("↶ 返回分析报告")

func select_report_category(side: int, category: String) -> void:
	if report.game == null: return
	var current: int = app.replay_index if app.review_game == report.game else -1
	var target: int = preload("res://scripts/shogi_report_quality.gd").next_ply(report.rows, category, side, current)
	if target < 0: return
	report_category = category
	report_category_side = side
	report_side = side
	report_expanded = true
	app.review_game = report.game
	app.review_path = ""
	show_history(target)
	update_inline_report()

func report_changed() -> void:
	update_inline_report()
	if page_name != "report": return
	if is_instance_valid(report_story): report_story.refresh()
	if report_progress != null and is_instance_valid(report_progress):
		report_progress.text = report.progress_text()
	if report_chart != null and is_instance_valid(report_chart):
		report_chart.samples = report.samples
		report_chart.rows = report.rows
		report_chart.phases = report.phases()
		report_chart.refresh()
	if report_phases != null and is_instance_valid(report_phases): report_phases.refresh()
	if not report.running and report_progress != null and not report_progress.has_meta("finished"):
		report_progress.set_meta("finished", true)
		# Defer one rebuild when a running report reaches completion.
		if page.find_children("*", "Button", true, false).any(func(b): return b.text == "停止分析"): show_report.call_deferred()

func review_mistake() -> void:
	if app.session != null: show_message("请结束联机对局后再练习。"); return
	if report.game == null or report.rows.is_empty(): show_message("请先分析一份棋谱。"); return
	retry_from_report = page_name in ["report", "report-phase"]
	var column = report_dialog("复习失误", "retry-settings", "在棋盘上重新找出最佳着", "ic_hint_up")
	var options: Dictionary = practice.options.duplicate(true)
	if report_side != 0: options.side = report_side
	var skipped = CheckButton.new()
	skipped.name = "SkipTriedMistakes"
	skipped.text = "跳过已尝试的着手"
	skipped.button_pressed = options.skip_tried
	skipped.custom_minimum_size.y = 42
	column.add_child(skipped)
	column.add_child(label("棋手", 12))
	var group = ButtonGroup.new()
	var radios = VBoxContainer.new()
	column.add_child(radios)
	for entry in [["双方", 0], [report.player_name(1) + (" · 先手" if report.player_name(1) != "先手" else ""), 1], [report.player_name(-1) + (" · 后手" if report.player_name(-1) != "后手" else ""), -1]]:
		var side: int = entry[1]
		var radio = CheckBox.new()
		radio.name = "RetrySide" + str(side)
		radio.text = entry[0]
		radio.button_group = group
		radio.button_pressed = options.side == side
		radio.custom_minimum_size.y = 42
		radios.add_child(radio)
	column.add_child(label("着手类型", 12))
	var categories: Array = []
	for category in ["漏着", "错失胜机", "失误", "不精确", "锐利", "妙手"]:
		var item = CheckBox.new()
		item.name = "Retry" + category
		item.text = category
		item.button_pressed = category in options.categories
		item.custom_minimum_size.y = 42
		item.add_theme_color_override("font_color", report.category_color(category))
		column.add_child(item)
		categories.append(item)
	var count = label("", 13)
	count.name = "RetryCount"
	column.add_child(count)
	var begin = button("开始练习", func():
		if not practice.start(report, options): show_message(practice.error)
	)
	begin.name = "BeginMistakePractice"
	column.add_child(begin)
	var refresh = func():
		options.skip_tried = skipped.button_pressed
		options.categories = []
		for item in categories:
			if item.button_pressed: options.categories.append(item.text)
		for i in range(radios.get_child_count()):
			if radios.get_child(i).button_pressed: options.side = [0, 1, -1][i]
		var total: int = practice.eligible(report, options).size()
		count.text = "符合条件 %d 手" % total
		begin.disabled = total == 0
	for item in categories + radios.get_children() + [skipped]: item.toggled.connect(func(_value): refresh.call())
	refresh.call()
	if report.running: column.add_child(label("将练习已完成分析的着手；后台报告可以继续。", 12))
	column.add_child(label("提示先指出棋子，再给出完整着手。退出练习后返回原棋局。", 12))

func practice_active() -> bool:
	return practice != null and practice.active

func update_practice() -> void:
	if practice_panel == null: return
	var running = practice_active()
	practice_scroll.visible = running
	analysis_scroll.visible = not running
	engine_toggle.get_parent().visible = not running
	report_buttons.visible = not running and app.safe_rect().size.y >= 480
	if not running:
		ribbon_key = ""
		return
	win_rate_label.hide()
	coach_notice.hide()
	return_line.hide()
	report_inline.hide()
	for child in practice_panel.get_children(): practice_panel.remove_child(child); child.queue_free()
	for child in move_strip.get_children(): move_strip.remove_child(child); child.queue_free()
	var description = "复习失误 · %d / %d" % [mini(practice.index + 1, practice.entries.size()), practice.entries.size()]
	if practice.stage != "complete": description += " · 原局第 %d 手" % practice.entry().ply
	var ribbon_label = label(description, 13)
	ribbon_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	move_strip.add_child(ribbon_label)
	var heading = HBoxContainer.new()
	practice_panel.add_child(heading)
	var title = label("练习结束" if practice.stage == "complete" else ("先手" if practice.entry().side == 1 else "后手") + " · " + practice.entry().category, 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var leave = compact_button("退出练习", func(): practice.stop(), 28)
	leave.name = "ExitMistakePractice"
	leave.size_flags_horizontal = Control.SIZE_SHRINK_END
	heading.add_child(leave)
	var feedback = label(practice.message, 14)
	feedback.name = "PracticeFeedback"
	feedback.add_theme_color_override("font_color", app.palette().danger if practice.stage == "wrong" else Color("85c975") if practice.stage == "solved" else app.palette().ink)
	practice_panel.add_child(feedback)
	if practice.stage == "complete":
		var totals: Dictionary = practice.totals()
		practice_panel.add_child(label("独立答对 %d · 辅助完成 %d\n查看答案 %d · 跳过 %d" % [totals.solved, totals.assisted, totals.revealed, totals.skipped], 14))
		practice_panel.add_child(compact_button("返回分析报告" if practice.context.report else "返回原棋局", func(): practice.stop(), 40))
	else:
		var actions = HBoxContainer.new()
		practice_panel.add_child(actions)
		var buttons: Array = []
		if practice.stage == "preview":
			buttons = [["返回练习", practice.end_preview, "ReturnToPractice"], ["暂停" if practice.preview_playing else "播放", toggle_autoplay, "PracticeAutoplay"], ["下一题", practice.next, "NextPractice"]]
		elif practice.stage in ["solved", "revealed"]:
			buttons = [["重试", practice.retry, "RetryPractice"], ["答案线路", practice.show_line, "PracticeLine"], ["下一题", practice.next, "NextPractice"]]
		else:
			buttons = [["提示" if practice.hint_level == 0 else "完整提示", practice.hint, "PracticeHint"], ["显示答案", practice.reveal, "RevealPractice"], ["跳过", practice.next, "NextPractice"]]
		for entry in buttons:
			var item = compact_button(entry[0], entry[1], 42)
			item.name = entry[2]
			item.disabled = practice.stage == "wrong"
			actions.add_child(item)
		if practice.stage != "preview":
			practice_panel.add_child(label("原着：第 %d 手 %s" % [practice.entry().ply, practice.entry().label], 12))
	if not practice.error.is_empty(): practice_panel.add_child(label(practice.error, 12))

func set_extra(key: String, value: Variant) -> void:
	app.preferences.studio[key] = value
	if not app.testing and app.preferences.save_to() != OK: show_message("设置保存失败。")
	if app.usi != null: app.usi.analysis_count = app.preferences.studio.analysis_lines
	if key in ["eval_bar", "eval_position"]: app._layout()
	app._redraw()

func evaluation_position_choice(column: VBoxContainer) -> void:
	var modes = ["smart", "left", "bottom", "left_on_game_report"]
	var option = choice(column, "评价条位置", ["智能", "左侧", "底部", "仅报告回放时在左侧"], modes.find(app.preferences.studio.eval_position))
	option.name = "EvaluationPosition"
	option.tooltip_text = "智能模式在报告回放空间不足时移到左侧。正分表示先手优势；评价条使用线性评分刻度，胜率另行显示。"
	option.item_selected.connect(func(index): set_extra("eval_position", modes[index]))

func show_evaluation_options() -> void:
	var column = _page("引擎与评价条", "evaluation-options")
	evaluation_position_choice(column)
	extra_toggle(column, "显示评价条", "eval_bar")
	column.add_child(button("暂停分析" if live_enabled else "开始分析", func(): _board_keep(); toggle_live()))
	for entry in [["增加候选着手", 1], ["减少候选着手", -1]]:
		var delta: int = entry[1]
		column.add_child(button(entry[0], func(): change_lines(delta); _board_keep()))
	column.add_child(button("引擎设置", show_engine_settings))

func extra_toggle(column: VBoxContainer, title: String, key: String) -> void:
	var item = CheckButton.new()
	localize(item, title)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.button_pressed = app.preferences.studio[key]
	item.custom_minimum_size.y = 48
	item.toggled.connect(func(value): set_extra(key, value))
	column.add_child(item)

func show_settings() -> void:
	var column = _page("设置", "settings")
	for entry in [["声音", "音效、音量与试听", show_sound_settings], ["棋盘与棋子", "主题、棋字、坐标与动画", show_board_settings], ["对弈设置", "确认落子、提示与自动转向", show_play_settings], ["引擎与分析", "线程、内存与候选着手", show_engine_settings], ["备份与恢复", "导出和恢复本地数据", show_backup]]:
		column.add_child(action_row(entry[0], entry[1], "settings", entry[2]))
	var colors = choice(column, "明暗", ["深色", "浅色", "跟随系统"], ["dark", "light", "system"].find(app.preferences.color_mode), true)
	colors.item_selected.connect(func(index): app.set_preference("color_mode", ["dark", "light", "system"][index]); show_settings.call_deferred())
	var language = choice(column, "界面语言", ["简体中文", "日本語", "English"], ["zh", "ja", "en"].find(app.preferences.language), true)
	language.item_selected.connect(func(index): app.set_preference("language", ["zh", "ja", "en"][index]); show_settings.call_deferred())
	column.add_child(button("引擎与署名", show_engine))

func show_board_settings() -> void:
	var column = _page("棋盘与棋子", "board-settings")
	var theme_names: Array[String] = ["经典木纹", "胡桃木", "青绿", "蓝色", "石板", "自定义"]
	var keys = ["classic", "walnut", "green", "blue", "slate", "custom"]
	var themes = choice(column, "棋盘主题", theme_names, maxi(0, keys.find(app.preferences.studio.board_theme)))
	themes.item_selected.connect(func(index): set_extra("board_theme", keys[index]); app._redraw())
	var custom = ColorPickerButton.new()
	custom.text = app.t("自定义棋盘颜色")
	custom.color = Color(app.preferences.studio.get("custom_color", "ddbc8b"))
	custom.custom_minimum_size.y = 48
	custom.color_changed.connect(func(value): set_extra("custom_color", value.to_html(false)); set_extra("board_theme", "custom"))
	column.add_child(custom)
	var appearance = choice(column, "棋子外观", ["二维将棋", "书法平面", "立体木制"], ["anime2d", "minimal", "wood"].find(app.preferences.appearance))
	appearance.item_selected.connect(func(index): app.set_preference("appearance", ["anime2d", "minimal", "wood"][index]))
	var fonts = choice(column, "棋字", ["日文明朝", "菱湖书法"], 1 if app.preferences.piece_font == "ryoko" else 0)
	fonts.item_selected.connect(func(index): app.set_preference("piece_font", "ryoko" if index == 1 else "mincho"))
	for entry in [["棋盘坐标", "coordinates"], ["上一步标记", "last_move"]]: preference_toggle(column, entry[0], entry[1])
	extra_toggle(column, "显示引擎箭头", "arrows")
	extra_toggle(column, "显示评价条", "eval_bar")
	evaluation_position_choice(column)
	extra_toggle(column, "局面编辑器显示实时评分", "editor_eval_bar")
	extra_toggle(column, "显示受攻击的棋子", "threats")
	var speed = choice(column, "棋子动画", ["关闭", "快速", "标准", "慢速"], 2)
	speed.item_selected.connect(func(index): set_extra("animation", [0.0, 0.12, 0.22, 0.5][index]))
	var replay = choice(column, "自动回放间隔", ["0.5 秒", "1 秒", "2 秒", "3 秒"], 1)
	replay.item_selected.connect(func(index): set_extra("autoplay", [0.5, 1.0, 2.0, 3.0][index]))
	var policy = choice(column, "分析棋盘的新变化", ["替换后续主线", "保留主线，另存为变化"], 1 if app.preferences.studio.variation_policy == "never" else 0)
	policy.item_selected.connect(func(index): set_extra("variation_policy", "never" if index == 1 else "replace"); set_extra("variation_policy_confirmed", true))

func study_active() -> bool:
	return study != null and study.effective()

func start_variation_analysis(source = null, ply: int = -2, path: String = "") -> void:
	if not pv_context.is_empty(): stop_pv(false)
	if source == null and study.active and app.review_game == study.view: study.resume(); return
	if source == null:
		source = app._view_game()
		path = app.review_path
	if ply == -2: ply = app.replay_index if app.replay_index >= 0 else source.moves.size()
	if not finish_study(false, func(): start_variation_analysis(source, ply, path)): return
	if not study.start(source, ply, path): show_message(study.error)

func finish_study(restore: bool = true, continuation: Callable = Callable()) -> bool:
	if study == null or not study.active: return true
	if not study.dirty: return study.stop(restore)
	var column = _page("保存这次修改？", "save-study")
	column.add_child(label("已修改走法、变化或注释。保存会写入棋谱库；不保存会放弃本次未保存的修改。", 15))
	var problem = label(study.error, 14)
	problem.visible = not study.error.is_empty()
	problem.name = "StudySaveError"
	column.add_child(problem)
	var save = button("保存", func():
		if not study.save(): problem.text = study.error; problem.show(); return
		study.stop(restore)
		if continuation.is_valid(): continuation.call()
	)
	save.name = "SaveStudyChanges"; column.add_child(save)
	var discard = button("不保存", func():
		study.stop(restore, true)
		if continuation.is_valid(): continuation.call()
	)
	discard.name = "DiscardStudyChanges"; column.add_child(discard)
	var cancel = button("继续编辑", func(): _board_keep())
	cancel.name = "CancelStudyExit"; column.add_child(cancel)
	return false

func record_game():
	return study.document() if study != null and study.active and app.review_game == study.view else app._view_game()

func show_variations() -> void:
	variation_ui.show_lines()

func show_variation_policy(move: Dictionary, key: String, parent: int) -> void:
	variation_ui.show_policy(move, key, parent)

func preference_toggle(column: VBoxContainer, title: String, key: String) -> void:
	var item = CheckButton.new()
	item.text = app.t(title)
	item.button_pressed = app.preferences.get(key)
	item.custom_minimum_size.y = 48
	item.toggled.connect(func(value): app.set_preference(key, value))
	column.add_child(item)

func show_play_settings() -> void:
	var column = _page("对弈设置", "play-settings")
	for entry in [["落子前确认", "confirm_move"], ["落点提示", "hints"], ["同机自动转向", "auto_flip"]]: preference_toggle(column, entry[0], entry[1])
	extra_toggle(column, "拖动落子", "drag")
	extra_toggle(column, "坏棋提醒", "bad_move_warning")
	extra_toggle(column, "显示胜率估计", "win_rate")
	var pace = choice(column, "落子节奏", ["快", "标准", "慢"], app.preferences.move_pace)
	pace.item_selected.connect(func(index): app.set_preference("move_pace", index))
	var username = field(column, "玩家名称", app.preferences.studio.username)
	column.add_child(button("保存名称", func(): set_extra("username", username.text.strip_edges().left(30))))

func show_sound_settings() -> void:
	var column = _page("声音", "sound-settings")
	preference_toggle(column, "落子声音", "sound")
	var volume = HSlider.new()
	volume.max_value = 1
	volume.step = 0.05
	volume.value = app.preferences.volume
	volume.custom_minimum_size.y = 50
	volume.value_changed.connect(func(value): app.set_preference("volume", value))
	column.add_child(volume)
	column.add_child(button("试听", func(): app._play_sound(true)))

func show_engine_settings() -> void:
	var column = _page("引擎与分析", "engine-settings")
	column.add_child(label("YaneuraOu · NNUE", 21))
	for entry in [["线程数", "threads", [1, 2, 4, 8]], ["Hash 内存 (MB)", "hash", [16, 32, 64, 128, 256]], ["候选着手数", "analysis_lines", [1, 2, 3, 4, 5]]]:
		var values: Array[String] = []
		for value in entry[2]: values.append(str(value))
		var key: String = entry[1]
		var numbers: Array = entry[2]
		var option = choice(column, entry[0], values, maxi(0, numbers.find(app.preferences.studio[key])), true)
		option.item_selected.connect(func(index): set_extra(key, numbers[index]))
	column.add_child(button("应用并重启引擎", func(): app._load_engine(); show_message("已重新加载引擎。")))
	column.add_child(button("引擎与署名", show_engine))

func show_archives() -> void:
	archive_view.enter(true)

func show_backup() -> void:
	var column = _page("备份与恢复", "backup")
	column.add_child(label("备份当前棋局、棋谱库、偏好设置和学习进度。", 15))
	column.add_child(button("创建备份文件", func():
		var service = preload("res://scripts/shogi_backup.gd").new()
		save_text(JSON.stringify(service.collect(app, tutorial), "  "), "shogi-backup.json")
	))
	column.add_child(button("打开备份文件", func():
		if platform != null and platform.has_method("pickRecord"):
			reading_backup = true
			platform.pickRecord()
			return
		_open_file(false, func(path):
			var file = FileAccess.open(path, FileAccess.READ)
			if file == null or file.get_length() > 20000000: show_message("备份无法读取。"); return
			show_restore(file.get_as_text())
		)
	))
	column.add_child(button("粘贴备份", func(): show_restore(DisplayServer.clipboard_get().left(20000000))))

func show_restore(value: String) -> void:
	var form = _page("恢复备份", "backup")
	form.add_child(label("棋局恢复为新的棋谱条目。恢复设置和进度前会保存现有数据的备份。", 14))
	var input = TextEdit.new()
	input.custom_minimum_size.y = 190
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.text = value
	form.add_child(input)
	var settings = CheckButton.new()
	settings.text = "恢复偏好设置"
	settings.custom_minimum_size.y = 48
	form.add_child(settings)
	var learning = CheckButton.new()
	learning.text = "恢复学习进度"
	learning.custom_minimum_size.y = 48
	form.add_child(learning)
	form.add_child(button("恢复", func():
		var service = preload("res://scripts/shogi_backup.gd").new()
		var count = service.restore(app, tutorial, JSON.parse_string(input.text), settings.button_pressed, learning.button_pressed)
		show_message(service.error if count < 0 else "已恢复 %d 份棋谱。" % count)
	))

func show_about() -> void:
	var column = _page("关于将棋", "about")
	column.add_child(label("将棋 " + str(ProjectSettings.get_setting("application/config/version")), 26))
	column.add_child(label("将棋对弈与复盘工具。界面依据所提供的 Chessis 20.9 APK 资源结构重新实现。", 16))
	column.add_child(label("棋盘、持驹打入、升变、千日手与入玉宣言使用将棋规则；分析使用 YaneuraOu。", 15))
	column.add_child(button("引擎与署名", show_engine))
	column.add_child(button("课程来源", func():
		var credits = _page("课程来源", "about")
		tutorial._ensure_loaded()
		for source in tutorial.books: credits.add_child(label(str(source.title), 15))
	))

func show_result() -> void:
	if app.game.result.is_empty(): return
	result_shown = str([app.game.moves, app.game.result])
	var column = _page("对局结束", "result")
	column.add_child(label(app.i18n.result(app.game), 26))
	column.add_child(label("%d 手" % app.game.moves.size(), 16))
	column.add_child(button("分析本局", func(): start_report(false)))
	column.add_child(button("回放棋谱", func(): show_history(0)))
	column.add_child(button("保存棋谱", func():
		var saved: String = app.records.archive(app.game)
		if not saved.is_empty(): app.archive_baseline = app.RecordChanges.game_signature(app.game)
		if saved.is_empty(): show_message(app.records.error)
		else: show_record_details(saved)
	))
	column.add_child(button("再来一局", show_play))
	column.add_child(button("返回棋盘", close))
