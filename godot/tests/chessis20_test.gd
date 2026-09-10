extends "res://tests/unified_test.gd"
const Scene = preload("res://scripts/shogi_scene_layout.gd")
var measurements = []

func board_luminance() -> float:
	await app.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image = app.get_viewport().get_texture().get_image()
	var sum = 0.0
	var count = 0
	for square in range(27, 54):
		var point = app.square_rect(square).get_center()
		for offset in [Vector2(2, 2), Vector2(-2, -2)]:
			sum += image.get_pixelv(Vector2i(point + offset)).get_luminance()
			count += 1
	return sum / count

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis20/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.get_tree().create_timer(150).timeout.connect(func(): check(false, "test timeout"); finish())
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	app.set_appearance("wood")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			for flipped in [false, true]:
				app.flipped = flipped
				app._layout()
				await settle()
				for square in range(81): check(app._square_at(app.square_rect(square).get_center()) == square, "3D hit mapping %s %s %s %d" % [mode, dimensions, flipped, square])
				var rect = app.wood_view.projected_rect(Vector3(-4.8, Scene.BOARD_Y, -5.3), Vector3(4.8, Scene.BOARD_Y, 5.3))
				check(rect.size.x / app.board_rect.size.x >= 0.97, "3D board fills at least 97% of allotted width")
				check(rect.size.x / rect.size.y >= 0.99, "projected board no longer tall and narrow")
				check(app.board_rect.grow(1).encloses(rect), "board top stays inside assigned area")
				measurements.append({"mode": mode, "size": str(dimensions), "flipped": flipped, "width_fraction": rect.size.x / app.board_rect.size.x, "aspect": rect.size.x / rect.size.y})
			app.flipped = false; app._layout()
			await capture("wood-%s-%dx%d" % [mode, dimensions.x, dimensions.y])
	await resize(Vector2i(393, 852))
	app.set_preference("color_mode", "dark")
	var after = await board_luminance()
	await capture("wood-after")
	# Recreate the previous lighting and camera only inside this isolated test.
	var camera = app.wood_view.camera
	app.wood_view.world_env.environment.ambient_light_energy = 0.24
	app.wood_view.sunlight.light_energy = 0.42
	app.wood_view.sunlight.light_color = Color("e2dcc9")
	camera.size = maxf(10.0 * app.size.y / app.board_rect.size.x, 10.7 * app.size.y / app.board_rect.size.y)
	var target = Vector3(0, Scene.BOARD_Y, 0)
	camera.transform = Transform3D(Basis.IDENTITY, target + Vector3(0, 30, 6.4)).looking_at(target, Vector3(0, 0, -1))
	camera.position += camera.basis.y * ((app.board_rect.get_center().y - app.size.y / 2) * camera.size / app.size.y)
	camera.position -= camera.basis.x * ((app.board_rect.get_center().x - app.size.x / 2) * camera.size / app.size.y)
	var before = await board_luminance()
	await capture("wood-before")
	check(after > before * 1.3 and after < 0.94, "rendered board is brighter with wood texture below white clipping")
	measurements.append({"luminance_before": before, "luminance_after": after})
	app.wood_view.apply_lighting(); app._layout()
	app.ui.show_drawer()
	var buttons = ""
	for node in app.ui.page.find_children("*", "Button", true, false): buttons += node.text
	check(not buttons.contains("会员") and not buttons.contains("购买") and not app.ui.has_method("show_membership"), "drawer and runtime contain no purchase flow")
	app.ui.set_extra("analysis_lines", 5)
	app.ui.set_extra("board_theme", "custom")
	check(app.preferences.studio.analysis_lines == 5 and app.preferences.studio.board_theme == "custom", "five lines and custom board available without membership")
	app.ui.show_historic_games()
	await settle()
	check(app.ui.historic_recent and app.ui.historic_count.text.begins_with("26"), "recent tournament catalog opens by default")
	var years = app.ui.page.find_child("HistoricYear", true, false)
	check(years.item_count >= 3 and years.get_item_text(1) == "2026", "recent year choices follow catalog")
	check(app.ui.page.find_child("RefreshTournaments", true, false) != null, "manual tournament refresh available")
	await capture("recent-tournaments")
	await click("离线历史")
	check(not app.ui.historic_recent and app.ui.historic_count.text.begins_with("195"), "offline historical collection remains accessible")
	await capture("offline-tournaments")
	if "--tournament-ui-network" in OS.get_cmdline_user_args():
		await click("近期赛事")
		var original = app.game
		var expected = app.ui.tournaments.entries()[0]
		app.ui.tournaments.storage = output.path_join("download-test-" + str(Time.get_ticks_usec()))
		app.ui.tournaments.open_game(expected)
		check(await until(func(): return not app.ui.tournaments.downloading, 40), "official UI download finishes")
		check(app.ui.page == null and app.review_game != null and app.review_game.moves.size() == int(expected.plies), "official download opens full game on board")
		check(app.game == original and app.replay_index == 0, "downloaded replay preserves original match")
		app.ui.show_history(10)
		await settle(0.04)
		check(not app.transition.is_empty(), "latest downloaded game replays with movement animation")
		await until(func(): return app.motion_progress >= 1)
		await capture("latest-downloaded-board")
		check(app.ui.tournaments.cached_game(expected) != null, "official UI download remains available offline")
	FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE).store_string(JSON.stringify(measurements, "  "))
	await finish()
