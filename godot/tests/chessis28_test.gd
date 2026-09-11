extends "res://tests/chessis24_test.gd"
var samples = []
var baseline = false
var inject_after = -1.0
var injected = false
var frame_count = 0
var progress_reader: Callable

func inject_stall() -> void:
	var progress: float = progress_reader.call() if progress_reader.is_valid() else app.motion_progress
	if inject_after >= 0 and not injected and frame_count > 0 and progress >= inject_after and progress < 1:
		injected = true
		OS.delay_msec(400)

func sampled_move(label: String, action: Callable, stall: float = -1, reader: Callable = Callable()) -> void:
	await settle(0.15)
	injected = false
	inject_after = stall
	frame_count = 0
	progress_reader = reader
	var rows = []
	# Use the post-draw boundary which exposed the short cached-report motion.
	await RenderingServer.frame_post_draw
	var began = Time.get_ticks_usec()
	action.call()
	var requested = Time.get_ticks_usec()
	while Time.get_ticks_usec() - requested < 4000000:
		await RenderingServer.frame_post_draw
		var progress: float = reader.call() if reader.is_valid() else app.motion_progress
		rows.append({"ms": (Time.get_ticks_usec() - requested) / 1000.0, "progress": progress, "engine_delta": app.get_process_delta_time()})
		frame_count += 1
		if progress >= 1: break
	inject_after = -1
	var worst = 0.0
	var intermediate = 0
	for i in range(rows.size()):
		if rows[i].progress > 0 and rows[i].progress < 1: intermediate += 1
		if i > 0: worst = maxf(worst, rows[i].progress - rows[i - 1].progress)
	samples.append({"scenario": label, "duration_ms": app.preferences.studio.animation * 1000, "call_ms": (requested - began) / 1000.0, "injected_stall_ms": 400 if injected else 0, "frames": rows, "intermediate_frames": intermediate, "max_progress_step": worst})
	check(not rows.is_empty() and rows[-1].progress == 1, label + " finishes")
	if stall >= 0: check(injected, label + " actually exercised the requested render stall")
	if not baseline:
		check(rows[0].progress == 0, label + " first displayed frame is the installed start pose")
		check(intermediate >= 8, label + " preserves at least eight displayed intermediate poses")
		check(worst <= 0.30, label + " stalled rendering never skips most of the move")
	print("MOTION28 ", label, " frames=", rows.size(), " first=", rows[0].progress, " jump=", worst)

func run(instance) -> void:
	app = instance
	baseline = "--baseline28" in OS.get_cmdline_user_args()
	output = ProjectSettings.globalize_path("res://../review/app/chessis28/" + ("baseline" if baseline else "ui"))
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.get_tree().create_timer(150).timeout.connect(func(): app.get_tree().quit(2))
	RenderingServer.frame_pre_draw.connect(inject_stall)
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	app.preferences.studio.animation = 0.22
	await resize(Vector2i(393, 852))
	report = app.ui.report
	var actual = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/report-motion24.json"))
	report.cancel()
	report.game = app.Game.from_data(actual.source)
	report.samples = actual.samples
	report.rows = actual.rows
	report.index = report.samples.size()
	report.verification_cursor = report.rows.size()
	for appearance in ["minimal", "wood"]:
		app.set_appearance(appearance)
		app.flipped = false
		app.ui.open_report_position(3)
		await until(func(): return app.motion_progress >= 1)
		for stall in [-1.0, 0.0, 0.25]:
			await sampled_move(appearance + "-reverse-" + str(stall), func(): app.ui.show_history(2), stall)
			await sampled_move(appearance + "-capture-" + str(stall), func(): app.ui.show_history(3), stall)
		app.ui.close()
		app.game = app.Game.new()
		app.game.mode = "local"
		app._leave_review()
		app._refresh()
		for value in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]:
			await sampled_move(appearance + "-play-" + value, func(): app._commit(app.Codec.parse_move(value, app.game.position)), 0.0)
	RenderingServer.frame_pre_draw.disconnect(inject_stall)
	if not baseline: await extra_cases()
	FileAccess.open(output.path_join("motion-frames.json"), FileAccess.WRITE).store_string(JSON.stringify(samples, "  "))
	await finish()

func extra_cases() -> void:
	app.ui.open_report_position(3)
	await until(func(): return app.motion_progress >= 1)
	for speed in [0.12, 0.5]:
		app.preferences.studio.animation = speed
		await sampled_move("wood-speed-" + str(speed), func(): app.ui.show_history(2))
		app.ui.show_history(3)
		await until(func(): return app.motion_progress >= 1)
	app.preferences.studio.animation = 0
	app.ui.show_history(2)
	check(app.motion_progress == 1 and app.transition.is_empty(), "animation-off applies final pose synchronously")
	app.preferences.studio.animation = 0.22
	app.ui.show_history(3)
	app.motion_tween.pause()
	app.motion_tween.custom_step(0.08)
	var paused_progress: float = app.motion_progress
	await settle(0.3)
	check(app.motion_progress == paused_progress, "paused timeline never consumes presented frames")
	app.motion_tween.play()
	await until(func(): return app.motion_progress >= 1)
	check(app.transition.is_empty(), "resuming completes original capture")
	for i in range(24): app.ui.show_history(2 if i % 2 == 0 else 3)
	await settle(0.05)
	var drivers = app.get_children().filter(func(child): return child.get_script() == preload("res://scripts/shogi_rendered_tween.gd"))
	check(drivers.size() == 1, "rapid replay releases every superseded animation driver")
	app._cancel_motion()
	await settle(0.1)
	check(not is_instance_valid(app.motion_tween), "cancel releases the last animation driver")
	app.ui.show_history(2)
	app.motion_tween.pause()
	for phase in ["start", "quarter", "middle", "end"]:
		if phase != "start": app.motion_tween.custom_step(0.055 if phase != "end" else 0.2)
		await capture("wood-clock-" + phase)
	var tutorial = app.ui.tutorial
	tutorial._ensure_loaded()
	var book = tutorial.books[0]
	var lesson = tutorial._find_lesson(book.id, "intro-first-game")[1]
	var index = 0
	for i in range(lesson.steps.size()):
		if lesson.steps[i].kind in ["move", "sequence"]: index = i; break
	tutorial.open_lesson(book.id, lesson.id, index)
	var move = app.Codec.parse_move(tutorial.model.step.moves[0], tutorial.model.position)
	RenderingServer.frame_pre_draw.connect(inject_stall)
	await sampled_move("tutorial-answer", func(): tutorial._select_move([move]), 0.0, func(): return tutorial.board.motion)
	RenderingServer.frame_pre_draw.disconnect(inject_stall)
	var driver = tutorial.board.motion_tween
	check(not driver.active and not RenderingServer.frame_post_draw.is_connected(driver._after_draw), "finished lesson disconnects global draw callback")
	app.ui.close()
	await settle()
	check(not is_instance_valid(driver), "closing lesson releases its animation driver")
