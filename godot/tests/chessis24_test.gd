extends "res://tests/chessis13_test.gd"
var measurements = []
var calls = []
var pre_draw_us = 0
var process_us = 0
var continuity = []

func record_pre_draw() -> void:
	pre_draw_us = Time.get_ticks_usec()

func record_process() -> void:
	process_us = Time.get_ticks_usec()

func finish_probe() -> void:
	# The global renderer outlives SceneTree teardown. Remove diagnostic
	# callbacks before releasing the script and its app reference.
	RenderingServer.frame_pre_draw.disconnect(record_pre_draw)
	app.get_tree().process_frame.disconnect(record_process)
	await app.get_tree().process_frame
	await finish()

func visible_poses() -> Dictionary:
	var poses = {}
	for track in app.transition:
		var pose = {"rect": app.board_view.motion_rect(track), "value": app.board_view.motion_value(track)}
		if app.wood_view != null and app.wood_view.animated_nodes.has(track.id):
			var node: Node3D = app.wood_view.animated_nodes[track.id]
			pose["model"] = node.transform
			pose["face"] = node.get_child(0).transform
		poses[track.id] = pose
	return poses

func interruption_probe() -> void:
	for appearance in ["minimal", "wood"]:
		app.set_appearance(appearance)
		for flipped in [false, true]:
			app.flipped = flipped
			app.ui.open_report_position(2)
			await until(func(): return app.motion_progress >= 1)
			check(app.flipped == flipped, "requested board orientation is active")
			app._set_replay(3)
			app.motion_tween.pause()
			# Drive the real replay tween deterministically; GPU stalls must not
			# turn a requested mid-capture sample into an already completed move.
			for ply in [2, 3, 4, 5, 0, 5, 5, 3, 2]:
				app.motion_tween.custom_step(0.18)
				check(app.motion_progress > 0 and app.motion_progress < 1, "replay interruption occurs within the animation")
				var poses = visible_poses()
				var camera = app.wood_view.camera.transform if app.wood_view != null else Transform3D()
				app.ui.show_history(ply)
				app.motion_tween.pause()
				var after = visible_poses()
				var max_rect_jump = 0.0
				var max_world_jump = 0.0
				for id in poses:
					check(after.has(id), "physical piece survives interrupted replay " + str(id))
					if not after.has(id): continue
					max_rect_jump = maxf(max_rect_jump, poses[id].rect.position.distance_to(after[id].rect.position))
					check(poses[id].rect.is_equal_approx(after[id].rect) and poses[id].value == after[id].value, "2D interrupted replay preserves position, size and face " + str(id))
					if poses[id].has("model"):
						check(after[id].has("model"), "interrupted capture retains its model " + str(id))
						if not after[id].has("model"): continue
						max_world_jump = maxf(max_world_jump, poses[id].model.origin.distance_to(after[id].model.origin))
						check(poses[id].model.is_equal_approx(after[id].model), "3D interrupted replay preserves position, scale and rotation " + str(id))
						check(poses[id].face.is_equal_approx(after[id].face), "promotion face remains continuous " + str(id))
				if app.wood_view != null:
					check(app.wood_view.camera.transform == camera, "replay interruption does not move the camera")
				continuity.append({"appearance": appearance, "flipped": flipped, "target": ply, "piece_count": poses.size(), "max_rect_jump_px": max_rect_jump, "max_world_jump": max_world_jump})
			app.motion_tween.custom_step(0.5)
			check(app.motion_progress == 1 and app.transition.is_empty(), "rapid replay settles at the selected position")
			check(app._display_position().key() == report.game.positions[2].key(), "final replay agrees with the legal game record")
			if app.wood_view != null:
				check(app.wood_view.animated_nodes.is_empty() and app.wood_view.piece_layer.visible, "finished replay releases temporary models")
			await capture(appearance + ("-flipped" if flipped else "-normal"))
	FileAccess.open(output.path_join("continuity.json"), FileAccess.WRITE).store_string(JSON.stringify(continuity, "  "))

func timed(label: String, action: Callable) -> void:
	var start = Time.get_ticks_usec()
	action.call()
	calls.append({"call": label, "ms": (Time.get_ticks_usec() - start) / 1000.0})

func motion(label: String, action: Callable) -> void:
	await settle(0.2)
	var begin = Time.get_ticks_usec()
	action.call()
	var input_ms = (Time.get_ticks_usec() - begin) / 1000.0
	var camera = app.wood_view.camera.transform if app.wood_view != null else Transform3D()
	var records = []
	var last = begin
	var tail = 0
	while Time.get_ticks_usec() - begin < 2000000:
		await RenderingServer.frame_post_draw
		var now = Time.get_ticks_usec()
		var entry = {"ms": (now - begin) / 1000.0, "gap_ms": (now - last) / 1000.0, "progress": app.motion_progress,
			"render_ms": (now - pre_draw_us) / 1000.0, "process_to_render_ms": (pre_draw_us - process_us) / 1000.0,
			"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
			"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}
		if app.wood_view != null:
			check(app.wood_view.camera.transform == camera, label + " camera remains still")
			entry.animated_nodes = app.wood_view.animated_nodes.size()
		records.append(entry)
		last = now
		if app.motion_progress >= 1: tail += 1
		if tail >= 4: break
	check(records.any(func(frame): return frame.progress > 0 and frame.progress < 1), label + " renders intermediate frames")
	check(app.motion_progress == 1, label + " animation completes")
	for index in range(1, records.size()):
		check(records[index].progress >= records[index - 1].progress, label + " animation never moves backwards")
	var gaps = records.map(func(frame): return frame.gap_ms)
	measurements.append({"scenario": label, "input_ms": input_ms, "max_gap": gaps.max(), "frame_budget_ms": 50, "within_frame_budget": gaps.max() <= 50, "frames": records})
	print("MOTION24 ", label, " input=", input_ms, " max_gap=", gaps.max(), " frames=", records.size())

func run(instance) -> void:
	app = instance
	RenderingServer.frame_pre_draw.connect(record_pre_draw)
	app.get_tree().process_frame.connect(record_process)
	var variant = "baseline" if "--baseline" in OS.get_cmdline_user_args() else "candidate"
	if "--isolate" in OS.get_cmdline_user_args(): variant = "isolation"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case24="): variant = arg.trim_prefix("--case24=")
	output = ProjectSettings.globalize_path("res://../review/app/chessis24/" + variant)
	if "--chessis26-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis26/animation")
	if "--chessis25-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis25/animation")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.get_tree().create_timer(150).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	app.preferences.studio.animation = 0.4
	await resize(Vector2i(393, 852))
	report = app.ui.report
	var actual = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/report-motion24.json"))
	report.cancel()
	report.game = app.Game.from_data(actual.source)
	report.samples = actual.samples
	report.rows = actual.rows
	report.index = report.samples.size()
	report.verification_cursor = report.rows.size()
	if "--interrupt-only" in OS.get_cmdline_user_args():
		await interruption_probe()
		await finish_probe()
		return
	if "--isolate" in OS.get_cmdline_user_args():
		app.ui.open_report_position(3)
		await until(func(): return app.motion_progress >= 1)
		timed("manual app process", func(): app._process(0.016))
		timed("manual UI process", func(): app.ui._process(0.016))
		for kind in ["all", "no_app_process", "no_ui_process", "no_board_draw"]:
			if kind == "no_app_process": app.set_process(false)
			if kind == "no_ui_process": app.ui.set_process(false)
			if kind == "no_board_draw": app.board_view.hide()
			for repeat in range(2):
				await motion(kind + str(repeat), func(): app._set_replay(2 if repeat == 0 else 3))
		FileAccess.open(output.path_join("timing.json"), FileAccess.WRITE).store_string(JSON.stringify({"measurements": measurements, "calls": calls}, "  "))
		print("MOTION24 CALLS ", JSON.stringify(calls))
		await finish_probe()
		return
	await interruption_probe()
	for appearance in ["minimal", "wood"]:
		app.set_appearance(appearance)
		app.flipped = false
		app.ui.open_report_position(3)
		await until(func(): return app.motion_progress >= 1)
		await settle(0.3)
		for repeat in range(3):
			await motion(appearance + "-report-reverse-" + str(repeat), func(): app.ui.show_history(2))
			await motion(appearance + "-report-capture-" + str(repeat), func(): app.ui.show_history(3))
		timed(appearance + " refresh saved lines", func(): app.ui.report_board_key = ""; app.ui.refresh_report_board())
		timed(appearance + " refresh inline stats", app.ui.update_inline_report)
		timed(appearance + " refresh scene", app._refresh)
		app.ui.close()
		app.game = app.Game.new()
		app.game.mode = "local"
		app._leave_review()
		app._refresh()
		await settle(0.5)
		for value in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]:
			await motion(appearance + "-play-" + value, func(): app._commit(app.Codec.parse_move(value, app.game.position)))
	FileAccess.open(output.path_join("timing.json"), FileAccess.WRITE).store_string(JSON.stringify({"measurements": measurements, "calls": calls, "checks": checks, "failures": failures}, "  "))
	print("MOTION24 CALLS ", JSON.stringify(calls))
	await finish_probe()
