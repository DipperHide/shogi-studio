extends "res://tests/chessis23_test.gd"

func navigation_fixture() -> void:
	app._start_match("local", 1, 2, "basic"); app.ui.close()
	for value in ["7g7f", "3c3d", "2g2f", "8c8d"]:
		check(app.game.play(app.Codec.parse_move(value, app.game.position)), "navigation fixture " + value)
	app._refresh()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/live-navigation")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records-" + str(Time.get_ticks_usec()))
	app.save_path = output.path_join("active.json")
	app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(150).timeout.connect(func(): app.get_tree().quit(2))
	await resize(Vector2i(393, 852))
	app.preferences.studio.animation = 0.12
	app.preferences.studio.autoplay = 0.15
	app.ui.toolbar.get_child(3).name = "Rewind"
	app.ui.toolbar.get_child(4).name = "Autoplay"
	app.ui.toolbar.get_child(5).name = "Forward"
	app.ui.toolbar.get_child(6).name = "Undo"
	for style in ["anime2d", "wood"]:
		navigation_fixture(); app.set_appearance(style)
		var original = app.game
		var signature = app.RecordChanges.game_signature(original)
		await press("Rewind"); await press("Rewind")
		check(app.replay_index == 2 and not app.ui.toolbar.get_child(6).disabled, "rewinding leaves undo available " + style)
		check(app.RecordChanges.game_signature(app.game) == signature, "rewinding is read-only " + style)
		await press("Forward"); await press("Forward")
		check(await until(func(): return app.motion_progress == 1), "forward animation settles " + style)
		check(app.replay_index == -1 and app.game == original and app._can_play(), "latest position immediately resumes live match " + style)
		check(not app.ui.continue_button.visible and not app.ui.toolbar.get_child(6).disabled, "latest position needs no continuation and allows undo " + style)
		var move = app.Codec.parse_move("7f7e", app.game.position)
		await tap(app.square_rect(move.from).get_center()); await tap(app.square_rect(move.to).get_center())
		check(await until(func(): return app.game.moves.size() == 5 and app.motion_progress == 1), "board touch plays immediately after returning to latest " + style)
		await press("Undo")
		check(app.game.moves.size() == 4, "undo works after rewind-forward-play " + style)
		app.ui.show_history(1); await settle(0.15)
		await press("Undo")
		check(await until(func(): return app.motion_progress == 1), "undo from history animation settles " + style)
		check(app.game.moves.size() == 3 and app.replay_index == -1 and app._can_play(), "undo in history retracts latest move and returns to live " + style)
		app.ui.show_history(0)
		await press("Autoplay")
		check(await until(func(): return app.replay_index == -1 and not app.ui.autoplay_on and app.motion_progress == 1, 5), "autoplay ends on live board without looping " + style)
		check(app._can_play() and app.game.moves.size() == 3, "autoplay never changes the record " + style)
		app.ui.show_history(0); app.ui.toggle_autoplay(); app.ui.seek(1)
		check(not app.ui.autoplay_on and app.replay_index == 1, "manual navigation pauses playback " + style)
		app._set_replay(app.game.moves.size())
		check(app.replay_index == -1, "direct latest cursor restores live state " + style)
	navigation_fixture()
	app.game.mode = "ai"; app.game.human_side = 1
	app.ui.show_history(2); app.ui.show_history(4)
	check(await until(func(): return app.motion_progress == 1), "AI match return animation settles")
	check(app._can_play() and app.game.human_side == 1, "returning to latest keeps original human side")
	app.ui.show_history(1); await press("Undo")
	check(app.game.moves.size() == 2 and app.game.human_side == 1, "history undo retains normal paired AI undo behavior")
	navigation_fixture()
	var imported = app.Game.from_data(app.game.to_data())
	app.review_game = imported
	app.ui.show_history(imported.moves.size()); await settle(0.2)
	check(app.replay_index == imported.moves.size() and not app._can_play(), "imported record end remains an independent replay")
	check(app.ui.toolbar.get_child(6).disabled, "imported replay cannot undo unrelated live match")
	app.ui.close()
	for style in ["anime2d", "minimal"]:
		app.set_appearance(style)
		for mode in ["light", "dark"]:
			app.set_preference("color_mode", mode)
			for dimensions in [Vector2i(393, 852), Vector2i(852, 393)]:
				await resize(dimensions)
				check(app.safe_rect().encloses(app.ui.toolbar.get_global_rect()), "flat toolbar fits " + str(dimensions))
				await capture(style + "-" + mode + "-" + str(dimensions.x))
	app.ui.live_enabled = false; app._pause_search()
	await finish()
