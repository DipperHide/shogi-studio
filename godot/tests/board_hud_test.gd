extends "res://tests/chessis23_test.gd"
const Hud = preload("res://scripts/shogi_board_hud.gd")

func row_fits(row: Control, context: String) -> void:
	var previous = Rect2()
	for child in row.get_children():
		if not child is Control or not child.is_visible_in_tree(): continue
		var area: Rect2 = child.get_global_rect()
		check(app.safe_rect().grow(1).encloses(area), context + " fits screen: " + child.name)
		check(not previous.has_area() or not area.intersects(previous), context + " controls do not overlap: " + child.name)
		previous = area

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis34/visual")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records-" + str(Time.get_ticks_usec()))
	app.save_path = output.path_join("active.json")
	app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	await startup_menu()
	if "--startup-menu" in OS.get_cmdline_user_args():
		await finish()
		return
	app._start_match("local", 1, 2, "basic"); app.ui.close()
	for width in [108, 160, 209, 210, 360, 600]:
		var area = Rect2(20, 30, width, 42)
		var geo = Hud.player_layout(area)
		check(area.encloses(geo.name) and area.encloses(geo.clock), "player name and clock stay in panel width " + str(width))
		check(not geo.name.intersects(geo.clock) and (geo.compact or not geo.avatar.intersects(geo.clock)), "name, clock and avatar do not overlap at width " + str(width))
	var source = app.Game.new(); source.mode = "local"
	check(source.set_initial("4k4/9/9/9/9/9/9/9/4K4 b RB2G2S2N2L9Prb2g2s2n2l9p 1"), "all hand piece fixture is valid")
	source.metadata = {"先手": "Alexanderson / 藤井聡太", "後手": "International player / 永瀬拓矢"}
	app.review_game = source; app.replay_index = 0; app._refresh()
	for language in ["zh", "en", "ja"]:
		app.set_preference("language", language)
		for appearance in ["anime2d", "wood"]:
			app.set_appearance(appearance)
			for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393)]:
				await resize(dimensions)
				app.set_preference("color_mode", "dark")
				app.ui.close(); app.review_game = source; app.replay_index = 0; app._refresh()
				await settle(0.2)
				var context = language + "-" + appearance + "-" + str(dimensions.x)
				check(app.safe_rect().encloses(app.top_player_rect) and not app.top_player_rect.intersects(app.bottom_player_rect), context + " player panels do not overlap")
				for side in [1, -1]:
					for kind in range(1, 8):
						var rect: Rect2 = app.board_view.piece_rect(app.hand_slot(side, kind))
						check(is_equal_approx(rect.size.x, rect.size.y) and app.hand_slot(side, kind).encloses(rect), context + " hand piece keeps aspect ratio " + str(side * kind))
				row_fits(app.ui.eval_row, context + " analysis")
				row_fits(app.ui.report_buttons, context + " reports")
				check(app.ui.continue_button.text == app.t("从这里下"), context + " persistent continue button refreshes language")
				await capture(context)
				var board: Rect2 = app.board_rect
				app.ui.show_menu(); await settle(0.1)
				check(app.board_rect == board, context + " opening menu preserves board geometry")
				check(app.ui.backdrop.visible and app.ui.backdrop.color.a > 0.1, context + " overlay separates menu from board")
				if dimensions.x == 360: await capture(context + "-menu")
				app.ui.close()
		await resize(Vector2i(360, 760))
		app.ui.show_settings(); await capture(language + "-settings")
		var board_action: Button = app.ui.page.find_child("PageBoard", true, false)
		var text_width = board_action.get_theme_font("font").get_string_size(board_action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, board_action.get_theme_font_size("font_size")).x
		check(board_action.size.y <= 51 and text_width + board_action.get_theme_stylebox("normal").get_minimum_size().x <= board_action.size.x + 1, language + " Board header action fits one line")
		app.ui.show_board_settings(); await capture(language + "-board-settings")
		for item in app.ui.page.find_children("*", "Control", true, false):
			if item.has_meta("translation_source"):
				var source_text: String = item.get_meta("translation_source")
				if language != "zh" and app.i18n.CATALOG.data.has(source_text): check(app.t(source_text) != source_text or source_text in ["明暗", "日本語", "English", "‹", "棋盘坐标", "关闭", "自定义"], language + " board setting translated: " + source_text)
		check(app.ui.page_scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, language + " settings use a vertical page")
		app.ui.close(); app.review_game = source; app.replay_index = 0; app._refresh()
		app.set_preference("color_mode", "light")
		await capture(language + "-wood-light")
		app.ui.start_variation_analysis(source, 0)
		app.ui.study.view.comments["0"] = "Test unsaved comment"
		app.ui.study.persist_view(); await settle(0.2)
		row_fits(app.ui.study_bar, language + " variation actions")
		check(app.ui.analysis_scroll.size.y >= 38, language + " study leaves a full candidate row visible")
		await capture(language + "-study-space")
		app.ui.finish_study(); await settle(0.15)
		check(app.ui.page.size.y <= 441, language + " wrapped dialog settles to compact height")
		check(app.ui.root.find_child("SaveStudyChanges", true, false).text == app.t("保存"), language + " save choice translated")
		check(app.safe_rect().encloses(app.ui.page.get_global_rect()), language + " save dialog fits")
		await capture(language + "-save-choice")
		await press("DiscardStudyChanges")
	app.set_preference("language", "zh")
	app.ui.live_enabled = false; app._pause_search()
	await finish()

func startup_menu() -> void:
	await settle(0.5)
	app.ui.toolbar.get_child(0).name = "StartupMenu"
	var original = app.game.to_data().duplicate(true)
	original.erase("clock")
	check(not app.ui.live_panel.get_global_rect().intersects(app.ui.toolbar.get_global_rect()), "initial analysis area leaves toolbar unobstructed")
	await press("StartupMenu")
	check(app.ui.page_name == "drawer", "menu opens on untouched startup layout")
	app.ui.close()
	app.ui.toolbar.get_child(7).name = "StartupMore"
	await press("StartupMore")
	check(app.ui.page_name == "menu", "more opens without making a move")
	await touch_at(app.safe_rect().position + Vector2(10, 10))
	check(app.ui.page == null, "tapping outside more closes it")
	for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393)]:
		await resize(dimensions)
		for appearance in ["anime2d", "wood"]:
			app.set_appearance(appearance)
			app.ui.show_home()
			await settle(0.3)
			var menu = app.ui.toolbar.get_child(0)
			menu.name = "StartupMenu"
			check(not app.ui.live_panel.get_global_rect().intersects(app.ui.toolbar.get_global_rect()), "analysis area leaves toolbar unobstructed at " + str(dimensions))
			check(app.game.moves.is_empty(), "startup has no moves")
			await press("StartupMenu")
			check(app.ui.page_name == "drawer", "menu opens before any move at " + str(dimensions) + " " + appearance)
			if app.ui.page != null:
				await touch_at(app.ui.page.position + Vector2(app.ui.page.size.x * 0.6, 12))
				check(app.ui.page_name == "drawer", "tapping inside menu keeps it open")
				var outside = Vector2(app.safe_rect().end.x - 10, app.safe_rect().get_center().y)
				await touch_at(outside, true)
				check(app.ui.page_name == "drawer", "canceled outside touch keeps menu open")
				await touch_at(outside)
				check(app.ui.page == null and app.pointer_id == -2, "outside tap closes menu without starting a board gesture")
	var after = app.game.to_data().duplicate(true)
	after.erase("clock")
	check(after == original, "startup navigation leaves the game unchanged")

func touch_at(point: Vector2, canceled: bool = false) -> void:
	for down in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 0; event.pressed = down; event.position = point
		event.canceled = canceled and not down
		Input.parse_input_event(event); Input.flush_buffered_events()
		await RenderingServer.frame_post_draw
		await app.get_tree().process_frame
