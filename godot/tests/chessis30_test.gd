extends "res://tests/chessis23_test.gd"
var importer
var original_review
var original_data: Dictionary
var clipboard: String
var motion_frames = []

class Picker extends RefCounted:
	signal analysis_record_imported(request: int, text: String, error: String)
	var request = 0
	func pickAnalysisRecord(id: int) -> void: request = id

func source_unchanged(label: String) -> void:
	preserve(label)
	check(app.review_game == original_review and app.replay_index == 2 and app.review_path == "original-review", label + " keeps original replay identity, path and cursor")
	check(original_review.to_data() == original_data, label + " keeps original comments and metadata")

func imported() -> void:
	check(await until(func(): return not importer.busy, 15), "background legality check completes")
	await settle()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis30/ui")
	if "--chessis31-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis31/chessis30")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records-" + str(Time.get_ticks_usec()))
	app.save_path = output.path_join("active.json"); app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(220).timeout.connect(func(): app.get_tree().quit(2))
	await resize(Vector2i(393,852))
	app._start_match("local",1,2,"basic"); app.ui.close()
	await play("7g7f"); await play("3c3d")
	practice = app.ui.practice; live = app.game; saved_live = live.to_data().duplicate(true)
	original_review = preload("res://scripts/shogi_openings.gd").game_for(preload("res://scripts/shogi_openings.gd").LINES[8])
	original_review.comments["2"] = "保留原局注释"; original_review.metadata["先手"] = "原棋手"
	original_data = original_review.to_data().duplicate(true)
	app.review_game = original_review; app.review_path = "original-review"; app.replay_index = 2; app._refresh()
	clipboard = DisplayServer.clipboard_get()
	DisplayServer.clipboard_set("private clipboard sentinel")
	app.ui.show_import_analysis(0); importer = app.ui.analysis_import
	check(importer.input.text.is_empty(), "opening importer does not read clipboard automatically")
	await press("AnalysisLoad")
	check(not importer.busy and importer.feedback.text.contains("先输入"), "empty input shows inline feedback")
	source_unchanged("empty input")
	await press("AnalysisPaste")
	check(importer.draft.source == "private clipboard sentinel", "explicit paste copies clipboard")
	await press("AnalysisLoad"); await imported()
	check(app.ui.page_name == "analysis-import" and not importer.feedback.text.is_empty(), "invalid input leaves editable dialog open")
	source_unchanged("invalid input")
	await press("AnalysisClear")
	check(importer.input.text.is_empty() and importer.draft.source.is_empty(), "clear removes full draft")
	importer.input.grab_focus()
	for character in "position startpos moves 7g7f 3c3d":
		var event = InputEventKey.new(); event.pressed = true; event.unicode = character.unicode_at(0)
		Input.parse_input_event(event); Input.flush_buffered_events()
	await settle()
	check(importer.draft.source == "position startpos moves 7g7f 3c3d", "native typing updates full draft")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode",mode)
		for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
			await resize(dimensions); await settle()
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()), "analysis dialog fits safe area " + str(dimensions))
			check(absf(app.ui.page.size.x - minf(420,app.safe_rect().size.x * 0.94)) < 1, "reference dialog width cap " + str(dimensions))
			check(importer.input.size.y == 120 and importer.paste_button.size.y == 46 and importer.file_button.size.y == 46, "reference input and action heights")
			check(app.ui.page.find_child("AnalysisSourceTabs",true,false).size.y == 40, "reference segmented source tabs")
			check(app.ui.page.find_child("AnalysisInputCard",true,false).get_theme_stylebox("panel").bg_color == app.palette().surface, "input card follows theme " + mode)
			check(importer.input.get_theme_color("font_color") == app.palette().ink and importer.input.get_theme_color("font_readonly_color") == app.palette().ink, "normal and long-preview text follows theme " + mode)
			await capture("analysis-input-%s-%d" % [mode,dimensions.x])
	await resize(Vector2i(393,852)); app.set_preference("color_mode","dark")
	await press("AnalysisTab1")
	check(app.ui.historic_count.text.begins_with("26"), "second source tab keeps current official tournament catalog")
	await press("OfflineTournaments")
	check(app.ui.historic_count.text.begins_with("195"), "offline historic collection still reachable")
	await capture("analysis-historic")
	await press("AnalysisTab0")
	check(importer.input.text.ends_with("7g7f 3c3d"), "switching source tabs retains typed input")
	await press("AnalysisImportHelp")
	check(app.ui.page_name == "analysis-help", "import help opens without a network account claim")
	app.ui.back(); await settle()
	check(importer.draft.source.ends_with("7g7f 3c3d"), "help back preserves draft")
	app.ui.keyboard_height = 280; importer.layout()
	check(app.ui.page.get_global_rect().end.y <= app.safe_rect().end.y - 280, "dialog stays above simulated mobile keyboard")
	app.ui.keyboard_height = 0; importer.layout()
	# Check both native picker cancellation and out-of-order replies without a device.
	var picker = Picker.new(); app.ui.platform = picker; importer.initialize(app.ui)
	await press("AnalysisChooseFile")
	var old_request: int = picker.request
	picker.analysis_record_imported.emit(old_request,"","")
	check(importer.picker_ticket == 0 and not importer.file_button.disabled and importer.draft.source.ends_with("7g7f 3c3d"), "picker cancel preserves draft and re-enables file action")
	await press("AnalysisChooseFile"); old_request = picker.request
	app.ui.back(); app.ui.show_import_analysis(0)
	picker.analysis_record_imported.emit(old_request,"position startpos moves 2g2f","")
	check(importer.draft.source.ends_with("7g7f 3c3d") and not importer.busy, "late picker result from dismissed flow is ignored")
	await press("AnalysisChooseFile")
	picker.analysis_record_imported.emit(picker.request,"","读取失败")
	check(importer.feedback.text == "读取失败", "picker error is distinct from cancel")
	source_unchanged("picker cancellation and failures")
	# Long input remains complete; parsing runs in an isolated worker.
	var long_record = FileAccess.get_file_as_string("res://../review/app/chessis31/long-record.json" if "--chessis31-regression" in OS.get_cmdline_user_args() else "res://../review/app/chessis30/long-record.json")
	DisplayServer.clipboard_set(long_record); await press("AnalysisPaste")
	check(importer.draft.locked() and not importer.input.editable and importer.input.text.length() < 16010, "large clipboard has bounded read-only preview")
	await capture("analysis-long-input")
	await press("AnalysisLoad"); await imported()
	check(app.ui.page == null and app.review_game.moves.size() == 5 and app.review_game.comments["5"] == "最終手の注釈", "load uses complete source beyond preview limit")
	check(app.review_game.comments["2"].length() > 16000 and app.replay_index == 0 and app.ui.live_enabled, "full comments preserved and main board enters live analysis")
	preserve("loaded analysis")
	if "--portable-import" not in OS.get_cmdline_user_args():
		check(await until(func(): return app.ui.live_details.has(1),12), "actual local engine evaluates newly loaded game")
		check(app.ui.live_key == app._display_position().key(), "candidate analysis root matches imported position")
	app.ui.show_history(3)
	var deadline = Time.get_ticks_msec()+4000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		motion_frames.append(app.motion_progress)
		if app.motion_progress == 1: break
	check(motion_frames.any(func(value): return value > 0 and value < 1), "imported replay shows real intermediate frames")
	check(app.ui.continue_button.visible, "imported position offers continuation")
	var saved_path: String = app.records.archive(app.review_game,"已导入测试棋谱")
	check(not saved_path.is_empty(), "test can archive a loaded game")
	app.ui.show_import_analysis(0); await press("AnalysisRecent")
	await capture("analysis-recent")
	check(importer.recent_entries.size() == 1, "recent picker lists saved games")
	await press("AnalysisSaved0"); await imported()
	check(app.ui.page == null and app.review_path == saved_path and app.review_game.comments["5"] == "最終手の注釈", "recent picker directly loads full saved game")
	app.ui.show_import_analysis(0); app.ui.platform = null
	await press("AnalysisChooseFile")
	check(app.ui.file_dialog.visible and app.ui.file_dialog.has_meta("analysis_import"), "desktop file selector is shown for this request")
	app.ui.back(); await settle()
	check(not app.ui.file_dialog.visible and importer.picker_ticket == 0 and not importer.file_button.disabled, "back cancels desktop selector and unlocks retry")
	await press("AnalysisChooseFile")
	app.ui.file_dialog.get_cancel_button().pressed.emit(); await settle()
	check(importer.picker_ticket == 0 and not importer.file_button.disabled, "desktop Cancel button unlocks retry")
	await press("AnalysisChooseFile")
	var path = ProjectSettings.globalize_path("res://../review/app/chessis31/source-cp932.kif" if "--chessis31-regression" in OS.get_cmdline_user_args() else "res://../review/app/chessis30/source-cp932.kif")
	app.ui.file_dialog.file_selected.emit(path); app.ui.file_dialog.hide()
	await imported()
	check(app.ui.page == null and app.review_game.moves.size() == 5 and app.review_game.comments["5"].strip_edges() == "最終手の注釈", "desktop CP932 file routes directly to complete analysis")
	# Invalid input keeps an active variation; a valid load ends it before replacement.
	var varied = app.review_game
	app.ui.start_variation_analysis(varied, 2)
	var varied_view = app.ui.study.view
	app.ui.show_import_analysis(0); importer.set_source("invalid shogi text"); importer.load_draft(); await imported()
	check(app.ui.study.active and app.review_game == varied_view and app.replay_index == 2, "invalid import preserves active variation and cursor")
	importer.set_source("position startpos moves 2g2f"); importer.load_draft(); await imported()
	check(not app.ui.study.active and app.review_game.moves.size() == 1 and app.Codec.move_name(app.review_game.moves[0]) == "2g2f", "valid import ends prior variation before installing new game")
	app.ui.start_variation_analysis(app.review_game, 0)
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	app.ui.show_import_analysis(1)
	app.ui.open_historic(historic.entries()[1])
	check(await until(func(): return not app.ui.tournament_view.local_busy,15), "historic validation worker finishes")
	await settle()
	check(not app.ui.study.active and app.ui.page == null and app.review_game.moves.size() > 60 and not app.review_game.result.is_empty(), "historic game replaces active variation and retains full result")
	preserve("historic import from variation")
	# A superseded parser result must not replace a later editor/page choice.
	app.ui.show_import_analysis(0)
	importer.set_source(long_record); importer.load_draft()
	check(importer.busy, "worker exposes running state")
	app.ui.show_openings("")
	var held_game = app.review_game
	await imported()
	check(app.ui.page_name == "openings" and app.review_game == held_game, "completed old parse cannot steal a different page")
	app.ui.back(); app.ui.live_enabled = false; app._pause_search()
	DisplayServer.clipboard_set(clipboard)
	FileAccess.open(output.path_join("motion-frames.json"),FileAccess.WRITE).store_string(JSON.stringify(motion_frames))
	await finish()
