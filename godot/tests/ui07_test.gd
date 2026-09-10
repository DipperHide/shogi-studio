extends "res://tests/unified_test.gd"

func capture(name: String) -> void:
	await settle(0.3)
	await super.capture(name)

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/ui07")
	if "--ui08-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/ui08/regression")
	DirAccess.make_dir_recursive_absolute(output)
	app.active = true
	check(not app.get_tree().quit_on_go_back, "Android Back is handled by the page stack")
	app.set_preference("language", "zh")
	app.set_preference("piece_font", "mincho")
	app.set_appearance("anime2d")
	for mode in ["light", "dark"]:
		app.set_preference("color_mode", mode)
		await resize(Vector2i(393, 852))
		app.ui.show_home()
		await capture("home-" + mode)
		app.ui.show_play()
		await capture("play-" + mode)
		app.ui.show_setup()
		await capture("setup-" + mode)
		app.ui.close()
		app._start_match("local", 1, 2, "basic")
		await capture("board-" + mode)
		app.ui.show_settings()
		await capture("settings-" + mode)
		var appearance = app.ui.page.find_children("*", "OptionButton", true, false)[0]
		appearance.show_popup()
		await settle()
		var popup = appearance.get_popup()
		var row_height = popup.get_theme_font("font").get_height(popup.get_theme_font_size("font_size")) + popup.get_theme_constant("v_separation")
		check(row_height >= 48, "dropdown touch height " + mode)
		await capture("settings-popup-" + mode)
		app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(not popup.visible and app.ui.page_name == "settings", "Back closes dropdown before page " + mode)
		app.ui.tutorial.show_catalog()
		await capture("learn-" + mode)
		app.ui.show_archives()
		await capture("archives-" + mode)
		app.ui.show_join()
		await click("连接")
		await capture("connection-error-" + mode)
		app.ui.close()
	for dimensions in [Vector2i(360, 800), Vector2i(393, 852), Vector2i(480, 960), Vector2i(852, 393), Vector2i(1100, 800)]:
		await resize(dimensions)
		check(app.board_rect.size.x == app.board_rect.size.y, "square board " + str(dimensions))
		if dimensions.x < dimensions.y:
			check(app.board_rect.size.x / dimensions.x >= 0.96, "full width " + str(dimensions))
		check(app.safe_rect().encloses(app.board_rect), "board fits " + str(dimensions))
		await capture("board-%dx%d" % [dimensions.x, dimensions.y])
	await resize(Vector2i(393, 852))
	app.set_preference("color_mode", "light")
	app.ui.close()
	app._new_game()
	app.game.mode = "local"
	app.preferences.confirm_move = true
	var key: String = app.game.position.key()
	await tap(app.square_rect(56).get_center())
	await tap(app.square_rect(47).get_center())
	check(app.ui.page_name == "confirm-move" and app.game.position.key() == key, "confirm defers mutation")
	await capture("move-confirmation")
	await click("取消")
	check(app.game.position.key() == key and app.pending_move.is_empty(), "cancel keeps position")
	await tap(app.square_rect(56).get_center())
	await tap(app.square_rect(47).get_center())
	await click("确认落子")
	await settle(0.3)
	check(app.game.moves.size() == 1, "confirm commits once")
	app.preferences.confirm_move = false
	await play("3c3d")
	await tap(app.square_rect(64).get_center())
	await tap(app.square_rect(16).get_center())
	check(app.ui.page_name == "promotion" and app.game.moves.size() == 2, "promotion waits for choice")
	await capture("promotion")
	app.set_preference("color_mode", "dark")
	app.ui.show_promotion()
	await capture("promotion-dark")
	app.set_preference("color_mode", "light")
	app.ui.show_promotion()
	await click("升变")
	await settle(0.3)
	check(app.game.moves.size() == 3 and app.game.moves[-1].promote, "promotion commits chosen move")
	await play("3a2b")
	await play("B*5e")
	await capture("capture-drop")
	app.ui.show_history(3)
	await capture("history")
	app.ui.show_analysis()
	await capture("analysis")
	app.set_preference("color_mode", "dark")
	app.ui.show_history(3)
	await capture("history-dark")
	app.ui.show_analysis()
	await capture("analysis-dark")
	app.set_preference("color_mode", "light")
	app.ui.close()
	for side in [1, -1]:
		app._new_game()
		app.game.mode = "local"
		app.game.position.board.fill(0)
		app.game.position.board[76] = 8
		app.game.position.board[4] = -8
		app.game.position.board[49 if side == 1 else 31] = -7 * side
		app.game.position.turn = side
		app.game.positions = [app.game.position.copy()]
		app._refresh()
		var king = 76 if side == 1 else 4
		check(app.checked_cells == [king], "check square for side " + str(side))
		for skin in ["anime2d", "minimal", "wood"]:
			app.set_appearance(skin)
			app.flipped = side == -1
			app._refresh()
			await capture("check-%s-%d" % [skin, side])
			app.set_preference("color_mode", "dark")
			await capture("check-%s-%d-dark" % [skin, side])
			app.set_preference("color_mode", "light")
		app.game.position.board[49 if side == 1 else 31] = 0
		app._refresh()
		check(app.checked_cells.is_empty(), "resolved check clears marker")
	app.set_appearance("anime2d")
	app._new_game()
	app.game.mode = "local"
	app._resign_game()
	await settle(0.3)
	await capture("result")
	for item in app.ui.page.find_children("*", "Label", true, false):
		if item.text == app.i18n.result(app.game): check(item.size.x >= 200, "result text keeps readable line width")
	app.set_preference("color_mode", "dark")
	app.ui.show_result()
	await capture("result-dark")
	app.set_preference("color_mode", "light")
	app.ui.show_home()
	await capture("home-resume")
	app.ui.close()
	for skin in ["anime2d", "wood"]:
		app._new_game()
		app.game.mode = "local"
		app.set_appearance(skin)
		await settle(0.3)
		for square in range(81): check(app._square_at(app.square_rect(square).get_center()) == square, "hit mapping " + skin + str(square))
		app.active = true
		app._pointer_down(-1, app.square_rect(56).get_center())
		app.pointer_moved = true
		app.pointer_current = app.square_rect(47).get_center()
		app._pointer_up(app.pointer_current, false)
		await settle(0.3)
		check(app.game.moves.size() == 1, "drag commits once " + skin)
		app._undo_move()
		await settle(0.3)
		check(app.game.moves.is_empty(), "undo restores " + skin)
		app._pointer_down(-1, app.square_rect(56).get_center())
		app.pointer_moved = true
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(app.drag_source == -1 and app.game.moves.is_empty(), "background cancels drag " + skin)
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var report = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "screenshots": screenshots}, "  "))
	print("UI07 RESULTS: ", checks, " checks; ", failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
