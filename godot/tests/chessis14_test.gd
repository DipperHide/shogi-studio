extends "res://tests/chessis13_test.gd"

func use_actual(name: String) -> void:
	var path = ProjectSettings.globalize_path("res://../review/app/chessis14/engine/" + name + ".json")
	var actual = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(actual is Dictionary and actual.rows.size() > 0, "load this run's actual engine evidence " + name)
	report.cancel()
	report.game = app.Game.from_data(actual.source)
	report.samples = actual.samples
	report.rows = actual.rows
	report.verification_searches = actual.verification_searches
	report.index = report.samples.size()
	report.verification_cursor = report.rows.size()
	report.phase_cache_size = -1
	app.ui.report_selected_ply = -1
	app.ui.report_category = ""
	app.ui.report_category_side = 0
	app.ui.show_report()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis14/ui")
	if "--chessis15-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis15/classification-ui")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/classification-ui")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis14_test")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/classification-ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.ui.tutorial.progress_path = output.path_join("learning-" + str(Time.get_ticks_usec()) + ".json")
	app.get_tree().create_timer(110).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	await play("7g7f")
	live = app.game
	saved_live = live.to_data().duplicate(true)
	report = app.ui.report
	practice = app.ui.practice
	use_actual("actual-fork")
	check(report.rows[2].category == "锐利", "UI uses actual verified fork classification")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			app.ui.show_report()
			app.ui.select_report_move(3)
			await settle()
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "classification report fits " + mode + str(dimensions))
			check(app.ui.page.find_children("ClassificationCount*", "Button", true, false).size() == 20, "both players have all ten classification counts")
			check(app.ui.page.find_children("ClassificationName", "Label", true, false).all(func(item): return item.get_line_count() == 1 and item.get_global_rect().end.x <= app.ui.page.get_global_rect().end.x), "all category names stay on one readable line")
			await capture("report-" + mode + "-%dx%d" % [dimensions.x, dimensions.y])
	app.set_preference("color_mode", "dark")
	await resize(Vector2i(393, 852))
	app.ui.show_report()
	await press("ClassificationHelp")
	check(app.ui.page_name == "report-classifications", "classification legend opens from report")
	check(app.ui.page.find_children("*", "TextureRect", true, false).size() >= 11, "legend shows ten category icons plus forced move")
	await capture("classification-help")
	app.ui.back()
	check(app.ui.page_name == "report" and app.ui.report_selected_ply == 3, "legend returns to selected move")
	await press("ClassificationCount1_锐利")
	check(app.ui.report_category == "锐利" and app.ui.report_category_side == 1 and app.ui.report_move_list.get_child_count() == 2, "clicking category count filters to actual sharp move")
	await capture("sharp-filter")
	app.ui.show_report()
	app.ui.select_report_move(3)
	app.ui.review_mistake()
	check(app.ui.page.find_child("Retry错失胜机", true, false) != null and app.ui.page.find_child("Retry锐利", true, false) != null and app.ui.page.find_child("Retry妙手", true, false) != null, "practice includes lost wins and verified good moves")
	for category in ["漏着", "错失胜机", "失误", "不精确", "锐利", "妙手"]:
		app.ui.page.find_child("Retry" + category, true, false).button_pressed = category == "锐利"
	await capture("sharp-practice-settings")
	check(app.ui.page.find_child("RetryCount", true, false).text == "符合条件 1 手", "actual sharp move available as an exercise")
	await press("BeginMistakePractice")
	app.active = true
	check(practice.active and practice.entry().category == "锐利", "verified good move starts before played fork")
	await attempt("5e4d")
	check(practice.stage == "solved", "actual verified fork can be solved on shared board")
	await capture("sharp-practice-solved")
	await until(func(): return app.motion_progress >= 1)
	practice.stop()
	preserve("verified fork practice")
	use_actual("actual-lost-win")
	app.ui.select_report_move(1)
	await capture("lost-win-selected")
	check(report.summary(1).counts.get("错失胜机", 0) == 1, "lost win has its own actual count")
	app.review_game = report.game
	app.replay_index = 1
	app.ui._board_keep()
	app.ui.update_inline_report()
	await settle()
	var counts = app.ui.report_inline.find_child("InlineClassificationCounts", true, false)
	check(counts != null and counts.get_child(0).get_child_count() == 10, "inline strip retains every category in one scrollable row")
	if counts != null:
		check(counts.get_global_rect().end.y <= app.ui.report_buttons.get_global_rect().position.y, "inline classification labels avoid report action buttons")
		counts.scroll_horizontal = 10000
	await capture("inline-ten-categories")
	check(app.ui.report_inline.visible, "expanded inline report remains on shared board")
	app.ui.seek_mistake(-1)
	check(app.replay_index == 1, "mistake navigation includes lost win category")
	app.ui.close()
	preserve("all classification pages")
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "screenshots": screenshots}, "  "))
	print("CHESSIS 14 UI: ", checks, " checks; ", failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
