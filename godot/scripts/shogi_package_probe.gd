extends RefCounted
## Optional CLI diagnostic for testing a packaged build without changing saves.
var app
var report: Dictionary = {}
var done: bool = false
var answer: Dictionary = {}
var course_probe_path: String = ""

func run(owner_node) -> void:
	if "--peer-probe" in OS.get_cmdline_user_args():
		await load("res://scripts/shogi_peer_probe.gd").new().run(owner_node)
		return
	app = owner_node
	course_probe_path = "user://package-probe-tutorial-" + str(Time.get_ticks_usec()) + ".json"
	app.ui.tutorial.progress_path = course_probe_path
	report = {"platform": OS.get_name(), "failures": [], "checks": 0, "bluetooth_pair_tested": false}
	report.viewport = {"logical_size": [app.size.x, app.size.y], "window_size": [app.get_window().size.x, app.get_window().size.y], "density_dpi": DisplayServer.screen_get_dpi()}
	if OS.get_name() == "Windows": report.executable_sha256 = FileAccess.get_sha256(OS.get_executable_path())
	app.get_tree().create_timer(40).timeout.connect(func(): verify(false, "package probe timeout"); finish())
	for i in range(4): await app.get_tree().process_frame
	verify(app.first_board_frame_ms >= 0 and app.engine_start_ms == -1, "board is drawn before engine initialization")
	verify(app.ui.page == null and app.wood_view == null, "isolated probe starts renderer without 3D models")
	verify(not ProjectSettings.get_setting("application/boot_splash/show_image"), "Godot startup logo disabled")
	report.first_board_frame_ms = app.first_board_frame_ms
	await capture("startup-board")
	app.ui.show_home()
	verify(app.ui.page == null and app.ui.toolbar.get_child_count() == 8 and app.ui.move_scroll.visible, "board workbench and eight navigation controls including undo available")
	verify(not FileAccess.file_exists("res://config/membership.json") and not app.ui.has_method("show_membership"), "no payment configuration or membership page in package")
	verify(app.preferences.studio.bad_move_warning and app.preferences.studio.win_rate and app.coach != null, "coach and win estimate available in packaged app")
	await capture("workbench")
	app.ui.show_drawer()
	verify(app.ui.page_name == "drawer", "packaged side drawer opens")
	await capture("drawer")
	var exchange = preload("res://scripts/shogi_exchange.gd").new()
	verify(exchange.parse("position startpos moves 7g7f 3c3d") != null, "packaged interchange parser available")
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	verify(historic.entries().size() == 195, "195 complete tournament records packaged")
	var historic_game = historic.game_for(historic.entries()[1])
	verify(historic_game != null and historic_game.moves.size() > 60 and not historic_game.result.is_empty(), "packaged historic game replays to a verified result")
	app.ui.close()
	var frame_times: Array[float] = []
	for frame in range(90):
		var tick = Time.get_ticks_usec()
		await app.get_tree().process_frame
		frame_times.append((Time.get_ticks_usec() - tick) / 1000.0)
	frame_times.sort()
	report.frame_ms_p50 = frame_times[45]
	report.frame_ms_p95 = frame_times[85]
	verify(app.board_rect.size.x > 100 and app.board_rect.size.x == app.board_rect.size.y, "square board rendered")
	verify(app.game.position.legal_moves().size() == 30, "initial rules available")
	var courses = JSON.parse_string(FileAccess.get_file_as_string("res://courses/manifest.json"))
	verify(courses is Dictionary and courses.get("books", []).size() == 2, "both course manifests packaged")
	report.courses = []
	if courses is Dictionary:
		for course in courses.get("books", []):
			var path = "res://courses/" + str(course.file)
			verify(FileAccess.get_sha256(path) == course.sha256, "packaged course matches validated source: " + str(course.id))
			report.courses.append(course)
	if OS.get_name() == "Android":
		verify(Engine.has_singleton("ShogiPlatform"), "Android platform plugin registered")
		if Engine.has_singleton("ShogiPlatform"):
			var platform = Engine.get_singleton("ShogiPlatform")
			report.native_engine_path = platform.enginePath()
			report.native_engine_visible_to_file_access = FileAccess.file_exists(report.native_engine_path)
			report.bluetooth_adapter = platform.bluetoothSupported()
			report.bluetooth_permission = platform.bluetoothPermissionsGranted()
			verify(not report.native_engine_path.is_empty(), "native engine installed in read-only library directory")
	app._load_engine()
	app.usi.best_move.connect(func(id, move, special): answer = {"id": id, "move": move, "special": special})
	var deadline = Time.get_ticks_msec() + 30000
	while not app.usi.available() and app.usi.phase != "error" and Time.get_ticks_msec() < deadline:
		await app.get_tree().process_frame
	verify(app.usi.available(), "packaged engine and NNUE ready")
	report.engine = app.usi.engine_name
	report.error = app.usi.last_error
	if app.usi.available():
		verify(app.usi.search(app.game.position, [], 9101, 0), "packaged search starts")
		deadline = Time.get_ticks_msec() + 5000
		while answer.is_empty() and Time.get_ticks_msec() < deadline:
			await app.get_tree().process_frame
		verify(not answer.is_empty() and answer.get("move", {}) in app.game.position.legal_moves(), "packaged engine returns legal move")
		report.move = app.Codec.move_name(answer.move) if not answer.is_empty() and not answer.move.is_empty() else ""
	report.transcript = app.usi.transcript
	app.ui.show_report_settings()
	verify(app.ui.page.find_child("SmartAnalysis", true, false) != null and app.ui.page.find_child("QuickDepth", true, false) != null, "packaged report settings controls and icons open")
	await capture("report-settings")
	app.ui.report.start(exchange.parse("position startpos moves 7g7f 3c3d"), true, {"deep_mode": "depth", "deep_depth": 4, "deep_lines": 2})
	deadline = Time.get_ticks_msec() + 10000
	while app.ui.report.running and Time.get_ticks_msec() < deadline: await app.get_tree().process_frame
	verify(not app.ui.report.running and app.ui.report.error.is_empty() and app.ui.report.rows.size() == 2, "packaged depth report evaluates all moves")
	verify(app.ui.report.samples.size() == 3 and app.ui.report.samples.all(func(s): return s.candidates.size() == 2), "packaged report retains two real engine alternatives")
	app.ui.show_report()
	app.ui.select_report_move(2)
	verify(app.ui.page_name == "report" and app.ui.report_selected_ply == 2 and app.game.moves.is_empty(), "packaged report selection preserves live board")
	verify(app.ui.report.rows.all(func(row): return row.has("metrics")) and app.ui.report.phases().size() == 1, "packaged report includes actual move metrics and opening phase")
	verify(not app.ui.report.summary(1).has_accuracy and app.ui.report.summary(1).book == 1, "packaged book-only report does not invent perfect accuracy")
	await capture("report-selected")
	app.ui.show_phase_accuracy(-1)
	verify(app.ui.page_name == "report-phase" and app.ui.page.find_child("Phase1", true, false) != null, "packaged phase accuracy detail opens")
	verify(app.ui.page.find_child("PhaseTitle1",true,false).text=="开局（1 手）" and app.ui.page.find_child("PhaseScore1",true,false).text=="定式", "packaged phase uses player hand count and real book label")
	verify(app.ui.page.find_child("PhaseOverallScore",true,false).text=="—" and app.ui.page.find_child("PhaseErrors1",true,false)==null, "packaged unscored phase does not invent perfect score or clean state")
	await capture("report-phase")
	app.ui.back()
	verify(app.ui.page_name == "report" and app.ui.report_selected_ply == 2, "packaged phase detail returns to the same selected report move")
	var original = app.game
	app.review_game = app.ui.report.game
	app.replay_index = 2
	app.ui._board_keep()
	app.ui.show_history(1)
	await app.get_tree().create_timer(0.06).timeout
	verify(app.motion_progress > 0 and app.motion_progress < 1, "packaged replay contains intermediate movement")
	await app.get_tree().create_timer(0.3).timeout
	verify(app.ui.continue_button.visible and app.game == original, "packaged replay exposes direct continuation without changing live game")
	app.ui.close()
	await probe_mistake_practice()
	await probe_classification_verification()
	app.set_preference("language", "ja")
	app.set_preference("color_mode", "dark")
	app.set_appearance("wood")
	verify(app.wood_view != null and app.wood_view.pieces.size() == 40, "packaged wooden resources available")
	await capture("startup-wood-ja")
	app.set_appearance("minimal")
	await app.get_tree().process_frame
	app.set_preference("language", "zh")
	var tutorial = app.ui.tutorial
	tutorial.progress_path = course_probe_path
	tutorial.show_catalog()
	verify(tutorial.books.size() == 2 and tutorial.load_errors.is_empty(), "packaged tutorial catalog opens")
	await capture("tutorial-catalog")
	var before = app.game.to_data().duplicate(true)
	for source in tutorial.books:
		await probe_course(tutorial, source)
	verify(app.game.to_data() == before, "packaged lessons preserve the active game")
	verify(tutorial.progress.error.is_empty() and FileAccess.file_exists(course_probe_path), "packaged tutorial progress writes successfully")
	app.ui.close()
	finish()

func probe_mistake_practice() -> void:
	var original = app.game
	var balance: Dictionary = original.clock.remaining.duplicate()
	var source = app.Game.new()
	source.set_initial("8k/9/4p4/9/4R4/9/9/9/K8 b - 1")
	source.play(app.Codec.parse_move("5e5d", source.position))
	app.ui.report.start(source, true, {"deep_mode": "time", "deep_time": 0.5, "deep_lines": 2})
	var deadline = Time.get_ticks_msec() + 10000
	while app.ui.report.running and Time.get_ticks_msec() < deadline: await app.get_tree().process_frame
	var practice = app.ui.practice
	var ready: bool = not app.ui.report.running and app.ui.report.error.is_empty() and app.ui.report.rows.size() == 1
	verify(ready, "packaged engine produces real mistake exercise")
	if not ready: return
	verify(app.ui.report.rows[0].category == "错失胜机", "packaged report distinguishes a lost winning advantage")
	app.ui.show_report()
	app.ui.select_report_move(1)
	app.ui.review_mistake()
	var begin = app.ui.page.find_child("BeginMistakePractice", true, false)
	verify(begin != null and not begin.disabled, "packaged retry settings includes actual engine mistake")
	if begin == null or begin.disabled: return
	begin.pressed.emit()
	app.active = true
	verify(practice.active and app._can_play() and not app._ai_allowed(), "packaged practice uses playable independent board")
	if not practice.active: return
	verify(app.review_game == practice.exercise and practice.exercise.moves.is_empty() and app.game == original, "packaged practice starts before mistake without replacing live game")
	await capture("mistake-practice")
	practice.submit(practice.entry().best)
	await app.get_tree().create_timer(0.05).timeout
	verify(practice.stage == "solved" and app.motion_progress > 0 and app.motion_progress < 1, "packaged practice animates accepted engine answer")
	verify(practice.progress().state("mistakes", practice.entry().key, 0).mastered, "packaged independent correct answer persists as mastered")
	await app.get_tree().create_timer(0.5).timeout
	practice.show_line()
	verify(practice.stage == "preview" and app.review_game.moves.size() > 0, "packaged best line replays on shared board")
	await capture("mistake-answer-line")
	practice.stop()
	verify(app.ui.page_name == "report" and app.ui.report_selected_ply == 1, "packaged practice exit restores selected report move")
	verify(app.game == original and original.moves.is_empty() and original.clock.remaining == balance, "packaged practice preserves live game and clock balance")
	app.ui.close()

func probe_classification_verification() -> void:
	var original = app.game
	var source = app.Game.new()
	source.set_initial("9/9/4r1k1p/9/4SP3/9/9/9/K8 b - 1")
	for value in ["9i9h", "1c1d", "5e4d"]: source.play(app.Codec.parse_move(value, source.position))
	app.ui.report.start(source, true, {"deep_mode": "time", "deep_time": 0.5, "deep_lines": 2})
	var deadline = Time.get_ticks_msec() + 10000
	while app.ui.report.running and Time.get_ticks_msec() < deadline: await app.get_tree().process_frame
	var complete: bool = not app.ui.report.running and app.ui.report.error.is_empty() and app.ui.report.rows.size() == 3
	verify(complete, "packaged report completes main search and tactical verification")
	if not complete: return
	var row: Dictionary = app.ui.report.rows[2]
	verify(row.category == "锐利" and row.best == "5e4d", "packaged engine verifies an actual silver fork")
	var proof: Dictionary = row.classification.verification
	verify(proof.get("accepted", false) and proof.get("candidates", []).size() == 2, "packaged rare category has real alternative evidence")
	app.ui.show_report()
	app.ui.select_report_move(3)
	verify(app.ui.page.find_children("ClassificationCount*", "Button", true, false).size() == 20, "packaged report displays all ten categories for both players")
	var story: Dictionary = app.ui.report.story()
	verify(story.complete and not story.closed and not story.summary.is_empty(), "packaged narrative distinguishes unfinished game from completed analysis")
	verify(story.model=="shogi-story-19-reference-adapted" and story.phase_context.sample_count==app.ui.report.samples.size(), "packaged narrative contains phase context from actual analyzed samples")
	verify(story.phase_context.sides["1"].overall==app.ui.report.summary(1), "packaged phase narrative shares actual overall aggregation")
	verify(story.moments.size() > 0 and app.ui.report_story.find_child("StoryMoments", true, false).get_child_count() == 1, "packaged reference story defaults to one real turning point")
	verify(app.ui.report_story.find_child("StoryMomentsHelp",true,false).get_theme_color("font_color")==Color("d9cab4"), "packaged report preserves reference story caption color")
	var target: int = story.moments[0].ply
	app.ui.report_story.find_child("StoryMoment%d" % target, true, false).pressed.emit()
	verify(app.ui.report_selected_ply == target and app.ui.report_chart.active == target, "packaged story card selects matching actual report move")
	app.ui.show_story_info()
	verify(app.ui.page_name == "report-story-info", "packaged key moment explanation opens")
	app.ui.back()
	verify(app.ui.report_selected_ply == target and app.ui.page_name == "report", "packaged key moment help restores selected report")
	app.ui.select_report_move(3)
	await capture("verified-sharp-move")
	verify(app.ui.report_story.find_child("StoryMoveSide",true,false).size==Vector2(12,12), "packaged story card keeps reference square player marker")
	verify(app.ui.report_story.find_child("StoryMoveReason",true,false).get_parent().get_theme_constant("margin_left")==24, "packaged story reason uses original text inset")
	var card = app.ui.page.find_child("ReportMoveCard", true, false)
	verify(card != null and card.size.y >= 82 and card.size.y <= 170, "packaged selected move uses compact reference card")
	app.ui.page.find_child("OpenReportMoveBoard", true, false).pressed.emit()
	verify(app.ui.page == null and app.review_game == app.ui.report.game and app.replay_index == 3, "packaged card opens exact analyzed position")
	verify(not app.ui.live_enabled and app.ui.live_details[1].pv == app.ui.report.samples[3].candidates[0].pv and app.ui.live_key == app._display_position().key(), "packaged board uses saved candidate lines for current root")
	await capture("report-board-snapshot")
	var animation_deadline = Time.get_ticks_msec() + 3000
	while app.motion_progress < 1 and Time.get_ticks_msec() < animation_deadline: await app.get_tree().process_frame
	app.ui.show_history(2)
	await app.get_tree().create_timer(0.05).timeout
	verify(app.motion_progress > 0 and app.motion_progress < 1, "packaged cached report replay displays intermediate motion")
	verify(app.ui.live_details[1].pv == app.ui.report.samples[2].candidates[0].pv and app.ui.live_key == app._display_position().key(), "packaged replay updates candidate root alongside animation")
	app.ui.show_report_move_details(2)
	verify(app.ui.page_name == "report-move" and app.ui.page.find_child("ReportMoveExplanation", true, false) != null, "packaged move details retains full explanation and alternatives")
	app.ui.page.find_child("ReportCandidatePreview1", true, false).pressed.emit()
	verify(app.ui.pv_context.get("details", false) and app.review_game.initial_sfen == app.Codec.sfen(app.ui.report.game.positions[1]), "packaged detailed line starts before selected move")
	app.ui.stop_pv()
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	verify(app.ui.page_name == "report-move" and app.ui.report_selected_ply == 2, "packaged candidate returns to the same move details")
	app.ui.show_report()
	app.ui.select_report_move(3)
	app.ui.show_classifications()
	verify(app.ui.page_name == "report-classifications" and app.ui.page.find_children("*", "TextureRect", true, false).size() >= 11, "packaged classification legend includes colored icons and forced move")
	await capture("classification-help")
	app.ui.back()
	verify(app.ui.report_selected_ply == 3 and app.game == original and app.game.moves.is_empty(), "packaged classification detail preserves report selection and live game")
	await probe_accuracy_insight()
	app.ui.close()

func probe_accuracy_insight() -> void:
	app.ui.show_accuracy_insight(1)
	await capture("accuracy-insight")
	var view = app.ui.report_accuracy_view
	verify(app.ui.page_name == "report-accuracy" and app.ui.page.size.x <= 440.1, "packaged accuracy opens its own reference-sized dialog")
	verify(view.model.points.size() == app.ui.report.summary(1).evaluated and view.model.points.size() > 0, "packaged chart includes actual scored sente moves")
	if view.chart == null: return
	verify(view.find_child("AccuracyInsightValue", true, false).text == app.ui.accuracy_text(app.ui.report.summary(1)), "packaged accuracy hero matches report aggregate")
	view.chart.choose(0)
	var point: Dictionary = view.model.points[0]
	verify(view.find_child("AccuracyMoveEngine", true, false).text == preload("res://scripts/shogi_accuracy_insight.gd").engine_label(point), "packaged point detail retains adjacent actual evaluations")
	await capture("accuracy-selected-move")
	view.find_child("OpenAccuracyMoveBoard", true, false).pressed.emit()
	verify(app.ui.page == null and app.review_game == app.ui.report.game and app.replay_index == point.ply, "packaged accuracy card returns to the correct report position")
	verify(app.ui.report_board_active and app.ui.live_key == app._display_position().key(), "packaged accuracy board shows candidates from matching root")
	app.ui.show_phase_accuracy(1)
	await app.get_tree().process_frame
	verify(app.ui.page_name == "report-phase" and app.ui.page.size.x <= 440.1, "packaged phase statistics retain separate bounded dialog")
	var phase_view=app.ui.page.find_child("PhaseAccuracyView",true,false)
	verify(phase_view!=null and not phase_view.model.phases.is_empty(), "packaged compact phase view and model are available")
	var phase_entry: Dictionary=phase_view.model.phases[0]
	var phase_card=phase_view.find_child("Phase"+str(phase_entry.type),true,false)
	verify(phase_card.find_children("*","BaseButton",true,false).is_empty(), "packaged phase card has no extra review action")
	verify(phase_card.find_child("PhaseScore"+str(phase_entry.type),true,false).size.y<35, "packaged measured phase uses compact score pill")
	await capture("compact-phase")
	app.ui.show_acpl_info(1)
	verify(app.ui.page_name == "report-metric-info", "packaged ACPL explanation opens independently")
	app.ui.back()
	verify(app.ui.page_name == "report" and app.ui.report_selected_ply == point.ply, "packaged statistics return preserves selected report move")

func probe_course(tutorial, source: Dictionary) -> void:
	for chapter in source.chapters:
		for lesson in chapter.lessons:
			for index in range(lesson.steps.size()):
				if lesson.steps[index].kind != "move": continue
				tutorial.open_lesson(source.id, lesson.id, index)
				verify(tutorial.model.error.is_empty() and tutorial.board != null, "packaged interactive lesson opens: " + source.id)
				if not tutorial.model.error.is_empty(): return
				tutorial.model.reveal()
				tutorial._refresh_answer()
				verify(tutorial.model.solved and not tutorial.model.mastered() and tutorial.replay_positions.size() > 1, "packaged answer replay available without granting mastery: " + source.id)
				await capture("tutorial-" + source.id)
				tutorial._show_replay(tutorial.replay_positions.size() - 1)
				return
	verify(false, "packaged book has no move exercise: " + source.id)

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for i in range(3): await app.get_tree().process_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="):
			var directory = arg.trim_prefix("--probe-output=").get_base_dir()
			app.get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))

func verify(value: bool, title: String) -> void:
	report.checks += 1
	if not value:
		report.failures.append(title)
		printerr("PACKAGE PROBE FAIL: ", title)

func finish() -> void:
	if done: return
	done = true
	if not course_probe_path.is_empty():
		for temporary in [course_probe_path, course_probe_path + ".tmp"]:
			if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	var path = "user://package-probe.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="): path = arg.trim_prefix("--probe-output=")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("PACKAGE_PROBE: ", JSON.stringify(report))
	app.get_tree().quit(0 if report.failures.is_empty() else 1)
