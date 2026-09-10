extends "res://tests/unified_test.gd"

func swipe(from: Vector2, to: Vector2) -> void:
	var down = InputEventScreenTouch.new()
	down.position = from
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	await settle(0.04)
	var previous = from
	for i in range(1, 16):
		var drag = InputEventScreenDrag.new()
		drag.position = from.lerp(to, i / 15.0)
		drag.relative = drag.position - previous
		drag.screen_relative = drag.relative
		previous = drag.position
		Input.parse_input_event(drag)
		Input.flush_buffered_events()
		await settle(0.03)
	var up = InputEventScreenTouch.new()
	up.position = to
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	await settle(0.4)

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/ui08")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("test-records")
	app.ui.tutorial.progress_path = output.path_join("test-progress.json")
	app.get_tree().create_timer(90).timeout.connect(func(): app.get_tree().quit(2))
	app.set_preference("language", "zh")
	app.set_preference("color_mode", "light")
	app.set_preference("piece_font", "mincho")
	app.set_appearance("anime2d")
	app._start_match("local", 1, 2, "basic")
	await play("7g7f")
	app.records.archive(app.game, "触摸与返回回归测试")
	for mode in ["light", "dark"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 800), Vector2i(393, 852), Vector2i(480, 960), Vector2i(1100, 800), Vector2i(852, 393)]:
			await resize(dimensions)
			app.ui.show_home()
			await settle(0.15)
			await capture("home-%s-%dx%d" % [mode, dimensions.x, dimensions.y])
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "page fits " + mode + str(dimensions))
			check(app.ui.home_columns.vertical == (dimensions.x < 760), "responsive home " + str(dimensions))
			check(app.ui.home_art.size.x > 250, "hero readable " + str(dimensions))
		await resize(Vector2i(393, 852))
		app.ui.show_play()
		await capture("play-" + mode)
		app.ui.show_settings()
		await capture("settings-" + mode)
	app.set_preference("color_mode", "light")
	# Force overflow to exercise a drag starting on the CTA, a nested card and a form.
	app.ui.show_home()
	for dimensions in [Vector2i(360, 800), Vector2i(800, 360), Vector2i(360, 800)]:
		await resize(dimensions)
		await settle(0.2)
		var cta = app.ui.page.find_child("HomeStart", true, false)
		check(cta.size.y >= 48 and cta.size.y <= 52, "rotation keeps CTA height " + str(dimensions))
		check(app.ui.home_art.get_global_rect().encloses(cta.get_global_rect()), "CTA stays in hero after rotation " + str(dimensions))
		check(app.ui.page_scroll.get_global_rect().encloses(cta.get_global_rect()), "CTA visible without scrolling after rotation " + str(dimensions))
		await capture("rotate-home-%dx%d" % [dimensions.x, dimensions.y])
	ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", true)
	Input.emulate_touch_from_mouse = true
	print("TOUCHSCROLL available: ", DisplayServer.is_touchscreen_available())
	await resize(Vector2i(360, 500))
	app.ui.show_home()
	await settle()
	var start = app.ui.page.find_child("HomeStart", true, false)
	var scroll = app.ui.page_scroll
	var point = start.get_global_rect().get_center()
	await swipe(point, point - Vector2(0, 110))
	check(app.ui.page_name == "home", "drag on CTA does not start a game")
	check(scroll.scroll_vertical > 35, "drag on nested CTA scrolls the home")
	await capture("scroll-from-cta")
	app.ui.show_home()
	await settle()
	await tap(app.ui.page.find_child("HomeStart", true, false).get_global_rect().get_center())
	check(app.ui.page_name == "play", "short tap still opens play")
	await click("人机对弈")
	check(app.ui.page_name == "setup", "action row is clickable")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.ui.page_name == "play", "setup back returns to play")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.ui.page_name == "home", "play back returns home")
	for i in range(3): app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.ui.page_name == "home", "repeated root Back stays home")
	app.ui.show_settings()
	await settle()
	var option = app.ui.page.find_children("*", "OptionButton", true, false)[0]
	scroll = app.ui.page_scroll
	point = option.get_global_rect().get_center()
	await swipe(point, point - Vector2(0, 90))
	check(scroll.scroll_vertical > 25 and not option.get_popup().visible, "drag from OptionButton scrolls without opening popup")
	app.ui.show_settings()
	await settle()
	option = app.ui.page.find_children("*", "OptionButton", true, false)[0]
	await tap(option.get_global_rect().get_center())
	check(option.get_popup().visible, "tap OptionButton opens popup")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not option.get_popup().visible and app.ui.page_name == "settings", "Back dismisses popup only")
	app.ui.back()
	check(app.ui.page_name == "home", "settings Back returns home")
	app.ui.close()
	app.active = true
	await tap(app.square_rect(20).get_center())
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.ui.page == null and app.selection == -1, "board Back cancels selection first")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app.ui.page_name == "home", "board Back returns home")
	app.ui.close()
	app._resign_game()
	await settle(0.4)
	app.ui.back()
	await settle(0.4)
	check(app.ui.page_name == "home", "finished game Back has no result loop")
	var escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	await settle()
	check(app.ui.page_name == "home", "Escape also stays at root")
	ProjectSettings.set_setting("input_devices/pointing/emulate_touch_from_mouse", false)
	Input.emulate_touch_from_mouse = false
	var report = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "screenshots": screenshots}, "  "))
	print("UI08 RESULTS: ", checks, " checks; ", failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
