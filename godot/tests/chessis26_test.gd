extends "res://tests/chessis23_test.gd"
var bar

func inject(details: Dictionary) -> void:
	app.ui.live_key = app._display_position().key()
	app.ui.live_details = {1: details}
	bar.synchronize(0)

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis26/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	app.preferences.studio.bad_move_warning = false
	app.preferences.studio.win_rate = true
	bar = app.ui.evaluation_bar
	report = app.ui.report
	live = app.game
	saved_live = live.to_data().duplicate(true)
	var source = app.Game.new()
	for value in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]: source.play(app.Codec.parse_move(value, source.position))
	report.start(source, false, {"quick_mode": "depth", "quick_depth": 3})
	check(await until(func(): return not report.running, 30), "actual engine completes evaluation fixture")
	check(report.error.is_empty() and report.samples.size() == 6, "all six positions have actual engine samples")
	FileAccess.open(output.path_join("actual-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"samples": report.samples, "rows": report.rows}, "  "))
	app.ui.open_report_position(3)
	await settle()
	for appearance in ["minimal", "wood"]:
		app.set_appearance(appearance)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			for mode in ["bottom", "left", "left_on_game_report", "smart"]:
				app.ui.set_extra("eval_position", mode)
				await settle(0.1)
				var expected_side = mode in ["left", "left_on_game_report"] or (mode == "smart" and dimensions != Vector2i(393, 852) and dimensions != Vector2i(1100, 800))
				check(bar.side == expected_side, "position policy " + str([appearance, dimensions, mode]))
				check(bar.visible and app.safe_rect().encloses(bar.get_global_rect()), "evaluation bar fits viewport")
				check(not bar.get_global_rect().intersects(app.board_rect), "evaluation bar has dedicated space outside board")
				check(app.safe_rect().encloses(app.ui.engine_toggle.get_global_rect()), "engine control fits viewport")
				check(not app.ui.engine_toggle.get_global_rect().intersects(app.ui.toolbar.get_global_rect()), "engine control does not overlap toolbar")
				check(app.ui.continue_button.is_visible_in_tree() and app.safe_rect().encloses(app.ui.continue_button.get_global_rect()), "continue from position remains available")
				check(app.ui.analysis_scroll.size.y >= 30, "candidate panel keeps readable height")
				check(bar.state.depth == report.samples[3].depth, "depth matches current report position")
				if mode in ["bottom", "left"] and dimensions.x in [393, 852]: await capture(appearance + "-" + mode + "-" + str(dimensions.x))
	await resize(Vector2i(393, 852))
	app.set_appearance("minimal")
	app.ui.set_extra("eval_position", "left")
	await press("SideEngineOptions")
	check(app.ui.page_name == "evaluation-options" and not bar.visible, "actual side options touch opens settings and hides board overlay")
	var option = app.ui.page.find_child("EvaluationPosition", true, false)
	option.grab_focus()
	await key(KEY_SPACE)
	check(option.get_popup().visible, "keyboard opens the placement popup")
	# PopupMenu owns a separate native Window. Route subsequent input by its
	# window ID, matching hardware events rather than the main-window queue.
	for attempt_index in range(6):
		var code = KEY_ENTER if option.get_popup().get_focused_item() == 3 else KEY_DOWN
		for down in [true, false]:
			var event = InputEventKey.new()
			event.keycode = code; event.pressed = down
			event.window_id = option.get_popup().get_window_id()
			Input.parse_input_event(event); Input.flush_buffered_events()
			await settle(0.03)
		if code == KEY_ENTER: break
	check(app.preferences.studio.eval_position == "left_on_game_report", "keyboard selects and persists placement setting")
	app.ui.back()
	await settle()
	check(app.replay_index == 3 and app._view_game() == report.game and bar.side, "closing options restores exact report position")
	# Stop automated UI ticks while injecting scores, for exact animation timing.
	app.ui.set_process(false)
	app.ui.live_enabled = false
	app.preferences.studio.animation = 0.22
	inject({"score": 1000, "depth": 8})
	bar.synchronize(0.75)
	var start_progress: float = bar.progress
	inject({"score": -1000, "depth": 9})
	check(bar.progress == start_progress, "new score preserves currently drawn progress")
	bar.synchronize(0.3)
	var intermediate: float = bar.progress
	check(intermediate > minf(bar.start, bar.target) and intermediate < maxf(bar.start, bar.target), "750 ms transition has an intermediate frame")
	inject({"score": 500, "depth": 10})
	check(bar.progress == intermediate, "interrupted evaluation animation retains visible position")
	bar.synchronize(0.75)
	check(is_equal_approx(bar.progress, bar.target), "evaluation animation reaches latest target")
	app.flipped = false
	var normal = bar.fill_rect()
	app.flipped = true
	var flipped = bar.fill_rect()
	check(normal.size == flipped.size and normal.position.y > flipped.position.y, "flipping reverses vertical fill origin without changing evaluation")
	app.ui.set_extra("eval_position", "bottom")
	await settle()
	bar.layout_bar()
	var bottom_fill = bar.fill_rect()
	app.flipped = false
	check(bottom_fill == bar.fill_rect(), "horizontal white side remains left when board flips")
	check(app.ui.engine_toggle.get_index() == bar.engine_index and app.ui.continue_button.get_index() == bar.continue_index, "returning horizontal restores control order")
	app.ui.live_key = "stale-position"
	app.coach.cache.clear()
	var original_sample: Dictionary = report.samples[3].duplicate(true)
	report.samples[3] = {"score": -30000, "mate": true, "mate_distance": 7, "depth": 25}
	bar.synchronize(0)
	check(bar.state.text == "−詰7" and bar.state.depth == 25, "report fallback preserves mate distance and depth with gote to move")
	report.samples[3] = original_sample
	app.review_game = source
	app.replay_index = 0
	bar.synchronize(0)
	check(not bar.state.available and bar.progress == 0.5, "unscored unrelated position clears previous evaluation")
	source.resign(-1)
	bar.synchronize(0)
	check(not bar.state.terminal, "replaying an earlier position does not expose future final result")
	app.replay_index = source.moves.size()
	bar.synchronize(0.75)
	check(bar.state.terminal and bar.progress == 1, "last position displays actual terminal result")
	app.ui.set_extra("eval_bar", false)
	bar.synchronize(0)
	check(not bar.visible and app.ui.eval_label.visible, "disabled evaluation retains engine status and hides fill")
	app.ui.set_extra("eval_bar", true)
	app.ui.set_extra("eval_position", "smart")
	bar.synchronize(0)
	check(not bar.side, "smart uses bottom outside report replay")
	app.ui.pv_context = {"test": true}
	bar.synchronize(0)
	check(not bar.visible, "candidate preview hides unrelated evaluation")
	app.ui.pv_context.clear()
	app.review_game = report.game
	app.replay_index = 3
	app.ui.set_process(true)
	app.ui.set_extra("eval_position", "left")
	await settle()
	check(app.game == live and game_content(live.to_data()) == game_content(saved_live), "evaluation operations preserve live game")
	await press("ContinueFromPosition")
	check(app.game != live and app.game.moves.size() == 3 and app.game.position.key() == report.game.positions[3].key() and app.replay_index < 0, "side continue button starts a playable game from exact selected position")
	finish()
