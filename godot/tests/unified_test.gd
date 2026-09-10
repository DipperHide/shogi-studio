extends RefCounted
var app
var checks: int = 0
var failures: Array[String] = []
var output: String
var screenshots: Array[String] = []

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("UNIFIED FAIL: ", name)

func settle(seconds: float = 0.06) -> void:
	await app.get_tree().create_timer(seconds).timeout

func until(predicate: Callable, seconds: float = 12) -> bool:
	var deadline = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await app.get_tree().process_frame
	return predicate.call()

func capture(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	await app.get_tree().process_frame
	app.get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	screenshots.append(name)

func tap(point: Vector2) -> void:
	for pressed in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await settle(0.025)

func click(source: String) -> void:
	for button in app.ui.root.find_children("*", "Button", true, false):
		if button.text == app.t(source) and button.is_visible_in_tree():
			var parent = button.get_parent()
			while parent != null:
				if parent is ScrollContainer: parent.ensure_control_visible(button)
				parent = parent.get_parent()
			await settle()
			for pressed in [true, false]:
				var event = InputEventMouseButton.new()
				event.position = button.get_global_rect().get_center()
				event.button_index = MOUSE_BUTTON_LEFT
				event.pressed = pressed
				Input.parse_input_event(event)
				Input.flush_buffered_events()
				await settle(0.025)
			return
	check(false, "button available: " + source)

func play(value: String) -> void:
	var move = app.Codec.parse_move(value, app.game.position)
	check(not move.is_empty(), "legal fixture move " + value)
	app._commit(move)
	await settle(0.25)

func resize(dimensions: Vector2i) -> void:
	app.get_window().content_scale_size = dimensions
	app.get_window().size = dimensions
	await settle(0.12)
	app._layout()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/unified")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.get_tree().create_timer(150).timeout.connect(func(): check(false, "test deadline"); finish())
	await settle()
	check(app.ui.page == null, "launch enters board directly")
	check(app.wood_view == null and app.find_children("*", "Node3D").is_empty(), "minimal does not instantiate wooden geometry")
	check(not ProjectSettings.get_setting("application/boot_splash/show_image"), "Godot boot logo disabled")
	for style in ["minimal", "wood"]:
		app.set_appearance(style)
		app.game = app.Game.new()
		app.game.mode = "local"
		app._refresh()
		await settle()
		for square in range(81): check(app._square_at(app.square_rect(square).get_center()) == square, style + " hit mapping " + str(square))
		await tap(app.square_rect(56).get_center())
		check(app.selection == 56, style + " touch selects pawn")
		await tap(app.square_rect(47).get_center())
		check(app.game.moves.size() == 1, style + " touch commits once")
		check(app.motion_progress < 1, style + " visible move transition")
		await settle(0.25)
		var original = app.game
		app.set_appearance("wood" if style == "minimal" else "minimal")
		check(app.game == original and app.game.moves.size() == 1, "appearance preserves shared game")
		app.set_appearance(style)
		app._undo_move()
		await settle(0.25)
		check(app.game.moves.is_empty(), style + " undo")
		check(await until(func(): return app.motion_progress >= 1.0), style + " undo animation completes")
		app.active = true
		check(app._can_play(), style + " input ready for drag")
		app._pointer_down(-1, app.square_rect(56).get_center())
		app.pointer_moved = true
		app.pointer_current = app.square_rect(47).get_center()
		app._redraw()
		app._pointer_up(app.square_rect(47).get_center(), false)
		await settle(0.25)
		check(app.game.moves.size() == 1, style + " drag move")
		app._undo_move()
		await settle(0.25)
		await until(func(): return app.motion_progress >= 1.0)
		app.active = true
		app._pointer_down(-1, app.square_rect(56).get_center())
		app.pointer_moved = true
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(app.drag_source == -1 and app.drag_drop == 0 and not app.pointer_moved, style + " focus loss restores dragged piece")
		check(app.game.moves.is_empty(), style + " canceled drag keeps game")
		app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		app.flipped = true
		app._layout()
		var event = InputEventKey.new()
		event.keycode = KEY_LEFT
		app.keyboard_square = 40
		app._key(event)
		check(app.keyboard_square == 41, style + " flipped keyboard direction")
		app.flipped = false
		app.keyboard_visible = false
		app._refresh()
		# Promotion and drops are reached through legal history, never invented positions.
		for value in ["7g7f", "3c3d", "8h2b+", "3a2b"]: await play(value)
		check(app.game.position.hands[1][6] == 1 and app.game.position.hands[-1][6] == 1, style + " captured hands")
		await tap(app.hand_hit_rect(1, 6).get_center())
		check(app.selected_drop == 6, style + " select held bishop")
		await tap(app.square_rect(40).get_center())
		await settle(0.25)
		check(app.game.moves.back().drop == 6, style + " legal bishop drop")
		await capture(style + "-capture-drop")
		app.ui.show_history(2)
		await settle(0.25)
		check(app.game.moves.size() == 5 and app.replay_index == 2, style + " replay does not change game")
		app.set_appearance("wood" if style == "minimal" else "minimal")
		check(app.replay_index == 2 and app._display_position().board == app.game.positions[2].board, "appearance preserves replay")
		app.ui.close()
		app.set_appearance(style)
		for locale in ["zh", "ja", "en"]:
			for mode in ["light", "dark"]:
				app.set_preference("language", locale)
				app.set_preference("color_mode", mode)
				await resize(Vector2i(480, 800))
				await capture(style + "-" + locale + "-" + mode)
				await click("菜单")
				await click("设置")
				check(app.ui.page_name == "settings", "shared settings " + style + locale + mode)
				check(app.ui.root.theme.get_color("font_color", "Label") == app.palette().ink, "theme applies to all controls")
				await capture(style + "-" + locale + "-" + mode + "-settings")
				app.ui.close()
		app.set_preference("piece_font", "mincho")
		await capture(style + "-mincho")
		app.set_preference("piece_font", "ryoko")
		for dimensions in [Vector2i(360, 800), Vector2i(800, 480), Vector2i(1280, 720)]:
			await resize(dimensions)
			await capture(style + "-" + str(dimensions.x) + "x" + str(dimensions.y))
			for square in [0, 8, 40, 72, 80]:
				check(app._square_at(app.square_rect(square).get_center()) == square, "resized board hit")
			app.ui.show_history(3)
			await settle(0.25)
			await capture(style + "-replay-" + str(dimensions.x))
			check(not app.ui.page.get_global_rect().has_point(app.square_rect(40).get_center()), "replay does not cover board center")
			app.ui.close()
	await records_and_engine()
	await recovery_and_feedback()
	finish()

func recovery_and_feedback() -> void:
	app.ui.close()
	app._cancel_motion()
	app.game = app.Game.new()
	app.game.mode = "local"
	app.active = true
	app._refresh()
	var recovery = output.path_join("recovery.json")
	check(app.game.save_to(recovery) == OK, "create recoverable save")
	await play("7g7f")
	check(app.game.save_to(recovery) == OK, "previous valid save backed up")
	var corrupt = FileAccess.open(recovery, FileAccess.WRITE)
	corrupt.store_string("truncated"); corrupt.close()
	var restored = app.Game.load_from(recovery)
	check(restored != null and restored.moves.is_empty(), "corrupt save recovers backup")
	var before = app.game.position.key()
	app.engine_context = {"id": 909, "revision": app.revision - 1, "kind": "play", "key": before}
	app._engine_best(909, app.legal[0], "")
	check(app.game.position.key() == before and app.pending_ai.is_empty(), "expired engine result cannot apply")
	for pace in range(3):
		app.preferences.move_pace = pace
		var delay = [300, 800, 1500][pace]
		app.ai_started_at = Time.get_ticks_msec() - delay + 50
		check(not app._ai_delay_done(), "pace minimum enforced " + str(delay))
		app.ai_started_at = Time.get_ticks_msec() - delay
		check(app._ai_delay_done(), "pace releases at minimum " + str(delay))
	app.game.clock.configure(1)
	app.game.clock.remaining[app.game.position.turn] = 100
	app.game.clock.period_left = 0
	app.ai_started_at = Time.get_ticks_msec()
	check(app._ai_delay_done(), "urgent clock bypasses pacing")
	app.game.clock.configure(0)
	app.preferences.move_pace = 1
	# Full held-piece trays and promotion controls in each renderer.
	for style in ["minimal", "wood"]:
		app.set_appearance(style)
		app.set_preference("language", "en")
		app.set_preference("color_mode", "dark")
		app.game = app.Game.new()
		app.game.mode = "local"
		for side in [1, -1]:
			for kind in range(1, 8): app.game.position.hands[side][kind] = 2
		app.game.positions = [app.game.position.copy()]
		app._refresh()
		await resize(Vector2i(360, 800))
		for side in [1, -1]:
			for kind in range(1, 8):
				check(Rect2(Vector2.ZERO, app.size).encloses(app.hand_hit_rect(side, kind)), "full hand remains visible " + style)
		await capture(style + "-full-hands")
		app.game = app.Game.new()
		app.game.mode = "local"
		app._refresh()
		for value in ["7g7f", "3c3d"]: await play(value)
		app.active = true
		await tap(app.square_rect(app.Codec.parse_square("8h")).get_center())
		await tap(app.square_rect(app.Codec.parse_square("2b")).get_center())
		check(app.promotion_moves.size() == 2, style + " offers promotion")
		await capture(style + "-promotion")
		app.set_appearance("minimal" if style == "wood" else "wood")
		check(app.promotion_moves.size() == 2, "pending promotion survives skin switch")
		await tap(app.square_rect(app.promotion_cells[0]).get_center())
		await settle(0.25)
		check(app.game.moves.size() == 3 and app.game.moves.back().promote, "promotion selected once")
		app.set_appearance(style)
		app.ui.show_declaration()
		await capture(style + "-declaration")
		app.ui.close()
	app.game = app.Game.new()
	app._refresh()

func records_and_engine() -> void:
	app.set_appearance("minimal")
	app.set_preference("language", "en")
	await resize(Vector2i(480, 800))
	var original = app.game
	var saved = app.records.archive(app.game, "Test record")
	check(not saved.is_empty(), "archive writes record")
	check(app.records.rename_record(saved, "Renamed"), "rename record")
	check(app.records.read(saved).position.key() == app.game.position.key(), "record roundtrip")
	check(app._load_archive(saved), "open isolated record")
	app.ui.show_history(2)
	await settle(0.25)
	check(app.game == original and app.game.moves.size() == 5, "review keeps active game unchanged")
	app.ui.close()
	check(app.game == original and app.review_game == null, "close review restores current game")
	check(app._load_archive(saved), "reopen record")
	app._set_replay(2)
	await settle(0.25)
	check(app._continue_review() and app.game.moves.size() == 2, "explicit continue branches at viewed position")
	check(app.records.delete_record(saved), "delete record")
	check(not app.records.delete_record(output.path_join("outside.json")), "delete restricted to archive library")
	var invalid = output.path_join("bad.json")
	var f = FileAccess.open(invalid, FileAccess.WRITE)
	f.store_string("{invalid"); f.close()
	check(app.records.read(invalid) == null, "invalid import rejected")
	var old = output.path_join("legacy.json")
	check(app.game.save_to(old) == OK, "legacy save")
	var migrated = output.path_join("migrated-" + str(Time.get_ticks_usec()) + ".json")
	var result = app.records.migrate(migrated, [old])
	check(result != null and result.position.key() == app.game.position.key() and FileAccess.file_exists(old), "migration keeps original and restores game")
	var prefs = app.Preferences.new()
	prefs.language = "ja"; prefs.appearance = "wood"; prefs.color_mode = "dark"; prefs.piece_font = "mincho"; prefs.move_pace = 2
	var cfg = output.path_join("preferences.cfg")
	check(prefs.save_to(cfg) == OK, "save all preferences")
	var restored = app.Preferences.new(); restored.load_from(cfg)
	check(restored.language == "ja" and restored.appearance == "wood" and restored.color_mode == "dark" and restored.piece_font == "mincho" and restored.move_pace == 2, "preferences persist")
	app.testing = false
	app.save_path = output.path_join("missing-parent/game.json")
	app._save()
	check(app.save_failed and not app.notice.is_empty(), "save failure remains visible")
	app.save_path = output.path_join("retry.json"); app._save()
	check(not app.save_failed, "save retry succeeds")
	app.testing = true
	app.game = app.Game.new()
	app.game.mode = "ai"
	app.game.human_side = -1
	app.active = true
	app.ui.close()
	app.engine_level = 0
	app._refresh()
	app._load_engine()
	check(await until(func(): return app.usi.available()), "real USI engine starts")
	var response_observed = [false]
	var observe = func(_id, _move, _special):
		response_observed[0] = not app.pending_ai.is_empty() and app.game.moves.is_empty()
		app.set_preference("appearance", "wood")
	app.usi.best_move.connect(observe, CONNECT_ONE_SHOT)
	var requested_at = Time.get_ticks_msec()
	app._request_engine("play", app.game.position, app.game.moves, false)
	check(await until(func(): return app.game.moves.size() == 1), "queued engine result survives appearance change")
	check(response_observed[0], "real engine response queued before shared controller commits")
	check(Time.get_ticks_msec() - requested_at >= 800, "standard pace waits at least 800 ms")
	await settle(0.25)
	app.ui.show_analysis()
	check(await until(func(): return app.analysis_lines.size() == 3), "three real analysis candidates")
	await capture("wood-english-analysis")
	app.ui.close()
	check(app.engine_context.is_empty(), "analysis cancellation clears stale context")
	app.usi.shutdown()
	app.game.resign(-1)
	check(app.game.result_code == "resign" and app.game.winner == 1, "language-independent result")
	await capture("wood-english-result")

func finish() -> void:
	var report = {"checks": checks, "failures": failures, "screenshots": screenshots}
	var file = FileAccess.open(output.path_join("ui-tests.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("UNIFIED_TESTS: ", JSON.stringify(report))
	app.set_appearance("minimal")
	await settle(0.2)
	app.get_tree().quit(0 if failures.is_empty() else 1)
