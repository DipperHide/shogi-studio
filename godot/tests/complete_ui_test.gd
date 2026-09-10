extends RefCounted

var app
var checks: int = 0
var failures: Array[String] = []
var output: String

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("COMPLETE UI FAIL: ", title)

func settle() -> void:
	for i in range(4):
		await app.get_tree().process_frame

func until(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await app.get_tree().process_frame
	return predicate.call()

func click_button(text: String) -> void:
	var buttons = app.ui.root.find_children("*", "Button", true, false)
	for button in buttons:
		if button.text == text and button.is_visible_in_tree():
			var parent = button.get_parent()
			while parent != null:
				if parent is ScrollContainer:
					parent.ensure_control_visible(button)
					await settle()
				parent = parent.get_parent()
			var point = button.get_global_rect().get_center()
			var motion = InputEventMouseMotion.new()
			motion.position = point
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
			await settle()
			for pressed in [true, false]:
				var event = InputEventMouseButton.new()
				event.position = point
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				Input.parse_input_event(event)
				Input.flush_buffered_events()
				await settle()
			return
	check(false, "visible button: " + text)

func capture(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	await app.get_tree().process_frame
	app.get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))

func run(instance) -> void:
	app = instance
	app.get_tree().create_timer(55).timeout.connect(func(): printerr("COMPLETE UI TIMEOUT"); app.get_tree().quit(1))
	output = ProjectSettings.globalize_path("res://../review/app/complete")
	DirAccess.make_dir_recursive_absolute(output)
	await settle()
	app.active = true
	await click_button("菜单")
	check(app.ui.page_name == "menu" and not app._can_play(), "menu opens and blocks board input")
	await capture("01-menu")
	await click_button("新开局")
	check(app.ui.page_name == "setup", "new game configuration opens")
	await capture("02-setup")
	var choices = app.ui.page.find_children("*", "OptionButton", true, false)
	check(choices.size() == 5 and choices[3].item_count == 6, "mode, seat, engine, difficulty and time options")
	choices[1].select(1)
	choices[3].select(0)
	await click_button("开始")
	app.active = true
	check(app.game.human_side == -1 and app.flipped and app.engine_level == 0, "human second seat and difficulty apply")
	check(await until(func(): return app.usi != null and app.usi.available()), "bundled engine starts from game configuration")
	app._request_engine("play", app.game.position, app.game.moves, false)
	check(await until(func(): return app.game.moves.size() == 1), "YaneuraOu commits actual first move for human second seat")
	check(await until(func(): return app.motion_progress >= 1.0), "computer move animation finishes")
	check(app.game.position.turn == -1 and app._can_play(), "human gets second turn")
	for square in [0, 10, 40, 70, 80]:
		check(app._square_at(app.square_rect(square).get_center()) == square, "flipped hit mapping %d" % square)
	await capture("03-engine-game")
	await click_button("菜单")
	await click_button("本局棋谱")
	check(app.replay_index == 1 and app.ui.page_name == "history", "record sheet shows played position")
	await click_button("上一手")
	check(app.replay_index == 0 and app._display_position().key() == app.Rules.new().key(), "record previous restores initial board without changing live game")
	check(app.game.moves.size() == 1 and not app._can_play(), "replay cannot mutate current game")
	await capture("04-history")
	await click_button("分析此局面")
	check(await until(func(): return app.analysis_lines.size() == 3), "analysis UI receives three actual engine variations")
	check(app.ui.analysis_label != null and "评分" in app.ui.analysis_label.text, "analysis shows scores and notation")
	check(app.board_rect.end.y < app.ui.page.position.y, "analysis controls do not cover replay board")
	await capture("05-analysis")
	await click_button("返回棋盘")
	check(app.replay_index == -1 and app.game.moves.size() == 1 and app.engine_context.is_empty(), "leaving analysis cancels search and restores current game")
	await click_button("菜单")
	await click_button("悔棋")
	check(app.game.moves.is_empty(), "menu undo reverts move")
	app._commit(app.Codec.parse_move("7g7f", app.game.position))
	app.game.human_side = 1
	app.game.mode = "ai"
	app._resign_game()
	check("后手获胜" in app.game.result, "human resignation during computer turn awards win to computer")
	var restored = app.Game.from_data(JSON.parse_string(JSON.stringify(app.game.to_data())))
	check(restored != null and restored.result == app.game.result, "resigning side persists when it is not their turn")
	app.ui.show_settings()
	await capture("06-settings")
	check(app.engine_level == 0, "difficulty survives play and menus")
	app.ui.close()
	app._start_match("local", 1, 0, "basic", 4)
	app.active = true
	await settle()
	check(app.game.clock.preset == 4 and not app.game.clock.paused, "timed game starts with chosen control")
	await capture("11-timed-game")
	app.ui.show_menu()
	await settle()
	var time_left: int = app.game.clock.period_left
	await app.get_tree().create_timer(.1).timeout
	check(app.game.clock.paused and app.game.clock.period_left == time_left, "local menu pauses clock")
	app.ui.close()
	await settle()
	check(not app.game.clock.paused, "return to board resumes clock")
	app.game.clock.period_left = 40
	app.game.clock.stamp = Time.get_ticks_msec()
	check(await until(func(): return not app.game.result.is_empty()), "app detects expired clock")
	check("后手获胜" in app.game.result and not app._can_play(), "timeout ends play for correct winner")
	await capture("12-timeout")
	app._start_match("local", 1, 0, "basic")
	app.ui.show_declaration()
	await settle()
	var declarations = app.ui.page.find_children("*", "Button", true, false)
	check(declarations.any(func(item): return item.text == "宣言获胜" and item.disabled), "initial position cannot declare a win through UI")
	app.ui.close()
	var file = FileAccess.open(output.path_join("ui-tests.json"), FileAccess.WRITE)
	var report = {"checks": checks, "failures": failures}
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("COMPLETE_UI_TESTS: ", JSON.stringify(report))
	app.get_tree().quit(0 if failures.is_empty() else 1)
