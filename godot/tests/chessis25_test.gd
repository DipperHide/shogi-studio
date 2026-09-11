extends "res://tests/chessis23_test.gd"
var study
var source
var original_data: Dictionary
var saved_path = ""

func node_for(sequence: Array) -> int:
	var id = 0
	for move in sequence:
		var found = -1
		for child in study.tree.nodes[id].children:
			if app.Codec.move_name(study.tree.nodes[child].move) == move: found = child
		if found < 0: return -1
		id = found
	return id

func settled() -> void:
	check(await until(func(): return app.motion_progress >= 1), "study move animation finishes")
	app.active = true

func move(value: String) -> void:
	await settled()
	await attempt(value)
	if app.ui.page_name != "variation-policy": await settled()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis25/ui")
	if "--chessis26-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis26/variations")
	if "--chessis27-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis27/variations")
	if "--portable-variation" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis25/portable-ui")
	if "--chessis28-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis28/variations")
	if "--chessis29-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis29/chessis25")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	await play("9g9f")
	live = app.game
	saved_live = live.to_data().duplicate(true)
	practice = app.ui.practice
	report = app.ui.report
	app.preferences.studio.animation = 0.4
	app.preferences.studio.variation_policy_confirmed = false
	await resize(Vector2i(393, 852))
	source = app.Game.new()
	source.mode = "local"
	for value in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]: source.play(app.Codec.parse_move(value, source.position))
	source.metadata = {"先手": "先手", "后手": "后手", "棋战": "变化分析测试"}
	source.comments = {"3": "主线角交换"}
	source.annotations = {"3": [[64, 10]]}
	original_data = source.to_data().duplicate(true)
	app.ui.start_variation_analysis(source, 1)
	study = app.ui.study
	await settled()
	check(app._study_active() and app._can_play() and app.replay_index == 1, "analysis board accepts moves at the selected historical position")
	check(app.game == live and game_content(live.to_data()) == game_content(saved_live), "entering analysis preserves the live match")
	await move("8c8d")
	check(app.ui.page_name == "variation-policy" and study.tree.nodes.size() == 6, "first alternative asks policy before changing the record")
	await capture("variation-policy")
	await press("VariationPolicy_never")
	await settled()
	check(study.tree.main.size() == 5 and study.current.moves.size() == 2 and study.tree.nodes.size() == 7, "keep policy saves the alternative without replacing the main line")
	await move("2g2f")
	study.seek(2)
	await move("6g6f")
	await move("8d8e")
	await move("7f7e")
	var nested = node_for(["7g7f", "8c8d", "6g6f"])
	check(nested >= 0 and node_for(["7g7f", "8c8d", "2g2f"]) >= 0, "different continuations coexist inside a side variation")
	study.select(nested)
	await settled()
	app.ui.show_comment()
	var editor: TextEdit = app.ui.page.find_children("*", "TextEdit", true, false)[0]
	editor.text = "嵌套分支注释 [url=https://invalid.example]只是文字[/url]"
	await click("保存注释")
	check(study.tree.nodes[nested].comment == editor.text if is_instance_valid(editor) else study.tree.nodes[nested].comment.contains("嵌套分支注释"), "branch comment is attached to its own node")
	study.view.annotations[str(app.replay_index)] = [[0, 80]]
	app.ui.persist_viewed()
	check(study.tree.nodes[nested].annotations == [[0, 80]], "branch drawing is saved on its own node")
	saved_path = study.record_path
	var stored = app.records.read(saved_path)
	check(stored != null and stored.moves == source.moves and stored.comments == source.comments, "automatic record save preserves the original main moves and comments")
	check(stored.variation_tree.nodes.size() == study.tree.nodes.size(), "automatic save includes every nested branch")
	for appearance in ["minimal", "wood"]:
		app.set_appearance(appearance)
		for dimensions in [Vector2i(393, 852), Vector2i(852, 393)]:
			await resize(dimensions)
			study.select(nested)
			await settled()
			await capture(appearance + "-branch-" + str(dimensions.x))
			check(app.ui.move_scroll.get_global_rect().end.y <= app.top_player_rect.position.y if not app.wide_layout else app.ui.move_scroll.get_global_rect().end.y <= app.board_rect.position.y, "two-row ribbon does not overlap board or player panels")
			app.ui.show_variations()
			await capture(appearance + "-variations-" + str(dimensions.x))
			var lines = app.ui.page.find_children("VariationLine_*", "RichTextLabel", true, false)
			check(lines.size() == 3, "main, side and nested variations all have selectable rows")
			for line in lines:
				check(line.get_parsed_text().find("https://invalid.example") >= 0 if line.text.contains("invalid.example") else true, "comment markup remains literal text")
			app.ui._board_keep()
	await resize(Vector2i(393, 852))
	var before_remove: Dictionary = study.tree.to_data()
	app.ui.show_variations()
	await press("RemoveVariation_" + str(nested))
	check(node_for(["7g7f", "8c8d", "6g6f"]) < 0 and node_for(["7g7f", "8c8d", "2g2f"]) >= 0, "visible remove action removes only the selected subtree")
	await capture("variation-removed")
	await press("UndoVariationChange")
	check(study.tree.to_data() == before_remove, "visible undo restores nested comments, drawings, cursor and descendants")
	nested = node_for(["7g7f", "8c8d", "6g6f"])
	app.ui._board_keep()
	study.select(nested)
	await settled()
	await long_press("VariationMove_" + str(nested))
	check(app.ui.page_name == "variation-move" and study.tree.to_data() == before_remove, "long touch opens the move actions without selecting or deleting another move")
	await press("PromoteVariation")
	await settled()
	check(study.document().moves.size() == 5 and app.Codec.move_name(study.document().moves[1]) == "8c8d", "visible promotion makes the selected continuation the main line")
	check(node_for(["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]) >= 0, "manual promotion retains the old main as a variation")
	await capture("variation-promoted")
	study.undo()
	await settled()
	check(study.document().moves == source.moves, "undo promotion returns the old main")
	app.ui.show_export()
	var exported: TextEdit = app.ui.page.find_children("*", "TextEdit", true, false)[0]
	var decoded = app.ui.Exchange.new().parse(exported.text)
	check(decoded != null and decoded.variation_tree != null and decoded.variation_tree.to_data() == study.tree.to_data(), "default variation export is a complete JSON tree")
	app.ui._board_keep()
	check(app.ui.finish_study() and app.game == live and app.review_game == null and app.replay_index == -1, "leaving analysis returns to the same live match")
	check(game_content(live.to_data()) == game_content(saved_live) and source.to_data() == original_data, "analysis never changes the live match or source record")
	check(app._load_archive(saved_path) and app._study_active() and study.record_path == saved_path, "reopening a saved tree resumes the same editable record")
	nested = node_for(["7g7f", "8c8d", "6g6f"])
	study.select(nested)
	await settled()
	var expected: String = app._display_position().key()
	app.ui.branch_here()
	check(not app._study_active() and app.game.position.key() == expected and app.game.variation_tree != null, "continue from a nested variation creates the exact playable position and keeps its alternatives")
	check(app.Game.from_data(app.game.to_data()) != null, "continued branch is a valid persistent game")
	FileAccess.open(output.path_join("study-record.json"), FileAccess.WRITE).store_string(FileAccess.get_file_as_string(saved_path))
	await edge_cases()
	await finish()

func long_press(name: String) -> void:
	await settle()
	var control = app.ui.root.find_child(name, true, false)
	check(control != null, "long-press move is present")
	if control == null: return
	app.ui.move_scroll.ensure_control_visible(control)
	await RenderingServer.frame_post_draw
	var point: Vector2 = control.get_global_rect().get_center()
	var down = InputEventScreenTouch.new()
	down.index = 0; down.pressed = true; down.position = point
	Input.parse_input_event(down); Input.flush_buffered_events()
	check(await until(func(): return app.ui.page_name == "variation-move", 3), "holding a move opens its actions")
	var up = InputEventScreenTouch.new()
	up.index = 0; up.pressed = false; up.position = point
	Input.parse_input_event(up); Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	await app.get_tree().process_frame

func edge_cases() -> void:
	check(study.start(source, 1), "start independent policy fixture")
	await settled()
	app.preferences.studio.variation_policy_confirmed = true
	app.preferences.studio.variation_policy = "replace"
	var before: Dictionary = study.tree.to_data()
	check(study.commit(app.Codec.parse_move("8c8d", study.current.position)), "replace policy accepts the alternative")
	await settled()
	check(study.tree.nodes.size() == 3 and study.tree.main.size() == 2 and node_for(["7g7f", "3c3d"]) < 0, "replace policy removes the old continuation and its annotations")
	study.undo()
	await settled()
	check(study.tree.to_data() == before, "undo replace restores all old moves, comments and drawings")
	app.preferences.studio.variation_policy = "never"
	study.commit(app.Codec.parse_move("8c8d", study.current.position))
	await settled()
	study.seek(1)
	await settled()
	app.preferences.studio.variation_policy = "replace"
	study.commit(app.Codec.parse_move("8c8d", study.current.position))
	await settled()
	check(study.tree.nodes.size() == 3 and study.tree.main.size() == 2, "replace policy also promotes an already existing alternative")
	study.undo()
	await settled()
	study.select(node_for(["7g7f", "8c8d"]))
	await settled()
	study.commit(app.Codec.parse_move("2g2f", study.current.position))
	await settled()
	check(study.tree.main.size() == 3 and node_for(["7g7f", "3c3d"]) < 0, "replacing within a side branch removes the old main at the first divergence")
	study.undo()
	await settled()
	var record_path: String = study.record_path
	var blocker: String = output.path_join("read-only-fixture")
	FileAccess.open(blocker, FileAccess.WRITE).store_string("A file prevents creation of a child directory.")
	study.record_path = blocker.path_join("record.json")
	var in_memory: Dictionary = study.tree.to_data()
	check(not study.save() and study.dirty and not study.error.is_empty(), "failed save exposes retryable dirty state")
	check(not study.stop() and study.active and study.tree.to_data() == in_memory, "failed save prevents closing and preserves edits in memory")
	study.record_path = record_path
	check(study.save() and not study.dirty, "retry writes the same complete record")
	var backup = preload("res://scripts/shogi_backup.gd").new()
	var bundle: Dictionary = backup.collect(app, app.ui.tutorial)
	var records_root: String = app.records.root
	app.records.root = output.path_join("restored-records-" + str(Time.get_ticks_usec()))
	var count: int = backup.restore(app, app.ui.tutorial, JSON.parse_string(JSON.stringify(bundle)), false, false)
	check(count == bundle.records.size() + 1, "backup restores every record and the active game")
	var found = false
	for entry in app.records.list_all():
		var saved = app.records.read(entry.path)
		if saved.variation_tree != null and saved.variation_tree.to_data() == study.tree.to_data(): found = true
	check(found, "backup restore retains the full analysis tree and its selected node")
	app.records.root = records_root
	if "--portable-variation" not in OS.get_cmdline_user_args():
		app.preferences.report.quick_mode = "depth"
		app.preferences.report.quick_depth = 3
		app.ui.start_report(false)
		check(study.paused and not app._study_active(), "report temporarily pauses editable variation navigation")
		check(await until(func(): return not report.running, 30), "real engine completes a branch report")
		check(report.error.is_empty() and report.rows.size() == study.view.moves.size(), "real engine analyzes the selected variation instead of the live match")
		FileAccess.open(output.path_join("variation-engine-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"source": report.game.to_data(), "rows": report.rows, "samples": report.samples}, "  "))
		study.resume()
		await settled()
		check(app._study_active() and study.tree.to_data() == in_memory, "returning from a report restores the unchanged tree and cursor")
	# A deterministic legal line checks preview routing; report above uses the actual engine.
	var next_move: String = app.Codec.move_name(study.current.position.legal_moves()[0])
	app.ui.live_details = {1: {"pv": [next_move]}}
	app.ui.preview_pv(1)
	app.ui.autoplay_on = false
	check(not app._study_active() and not app.ui.pv_context.is_empty(), "candidate preview temporarily owns the replay board")
	app.ui.stop_pv(false)
	check(app._study_active() and study.tree.to_data() == in_memory, "candidate preview returns to the exact editable node")
	app.ui.live_details = {1: {"pv": [next_move]}}
	app.ui.preview_pv(1)
	app.ui.autoplay_on = false
	check(study.stop() and app.ui.pv_context.is_empty() and not study.active, "ending analysis during candidate preview clears the preview and restores the prior board")
