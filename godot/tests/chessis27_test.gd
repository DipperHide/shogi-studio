extends "res://tests/chessis23_test.gd"
var editor

func position_key() -> String:
	return app.Codec.sfen(editor.pos)

func evaluated() -> void:
	check(await until(func(): return not editor.analysis.details.is_empty() and not editor.analysis.searching, 12), "current editor setup receives actual local-engine evaluation")
	check(editor.analysis.key == position_key(), "evaluation root matches exact edited board, turn and hands")

func drag(source: Vector2, target: Vector2, canceled: bool = false, screenshot: String = "") -> void:
	var down = InputEventScreenTouch.new()
	down.index = 0; down.pressed = true; down.position = source
	Input.parse_input_event(down); Input.flush_buffered_events()
	await app.get_tree().process_frame
	for weight in [0.2, 0.5, 0.8, 1.0]:
		var move = InputEventScreenDrag.new()
		move.index = 0; move.position = source.lerp(target, weight)
		Input.parse_input_event(move); Input.flush_buffered_events()
		await app.get_tree().process_frame
	check(editor.interaction.dragging and editor.interaction.preview != null, "native touch drag displays a piece preview")
	if editor.interaction.preview != null: check(editor.interaction.preview.size.x == editor.interaction.preview.size.y, "drag preview preserves square geometry")
	await capture(screenshot if not screenshot.is_empty() else "editor-drag-canceled" if canceled else "editor-drag")
	var up = InputEventScreenTouch.new()
	up.index = 0; up.position = target; up.pressed = false; up.canceled = canceled
	Input.parse_input_event(up); Input.flush_buffered_events()
	await settle()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis27/ui")
	if "--editor-controls-only" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis27/controls")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active-test.json")
	app.ui.tutorial.progress_path = output.path_join("learning-test.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	await play("7g7f")
	await play("3c3d")
	live = app.game
	saved_live = live.to_data().duplicate(true)
	app.preferences.studio.editor_positions = []
	app.preferences.studio.editor_eval_bar = true
	app.preferences.studio.editor_eval_running = true
	app.ui.show_editor()
	editor = app.ui.editor
	var source_key = position_key()
	await evaluated()
	check(editor.analysis.engine != app.usi and editor.analysis.requests[0].milliseconds == 500, "editor has a private bounded search session")
	for mode in ["dark", "light"]:
		app.set_preference("color_mode", mode)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			if "--editor-controls-only" in OS.get_cmdline_user_args(): continue
			await resize(dimensions)
			await settle()
			var area = editor.board_rect
			check(area.size.x == area.size.y and editor.cells[0].size.x == editor.cells[0].size.y, "editor cells and board stay square " + str(dimensions))
			check(area.position.x >= 20 and area.end.x <= editor.size.x + 0.1, "editor board fits beside its evaluation column")
			check(app.safe_rect().encloses(editor.footer.get_global_rect()), "fixed Cancel and Done remain on screen")
			check(not editor.footer.get_global_rect().intersects(app.ui.page_scroll.get_global_rect()), "footer stays outside scrollable content")
			check(editor.feedback.get_theme_color("font_color").get_luminance() > 0.8, "wooden editor text remains readable in either global theme")
			app.ui.page_scroll.scroll_vertical = 0
			await settle()
			check(editor.cells[80].get_global_rect().end.y <= editor.footer.global_position.y, "full board is visible above fixed footer")
			await capture("editor-" + mode + "-" + str(dimensions.x))
	await resize(Vector2i(393, 852))
	app.set_preference("color_mode", "dark")
	app.ui.page_scroll.scroll_vertical = 0
	await settle()
	var initial_requests: int = editor.analysis.requests.size()
	await press("EditorPiece4")
	await press("EditorPromotion")
	check(editor.brush == 12 and editor.promote_button.button_pressed, "palette promotion selects promoted silver")
	check(editor.analysis.requests.size() == initial_requests, "selecting brush does not restart unchanged analysis")
	await drag(editor.palette[4].get_global_rect().get_center(), editor.cells[40].get_global_rect().get_center(), false, "editor-palette-drag")
	check(editor.pos.board[40] == 12, "dragging the displayed promoted palette piece preserves promotion")
	await press("EditorUndo")
	check(position_key() == source_key, "palette drag participates in exact setup undo")
	await press("EditorSquare40")
	check(editor.pos.board[40] == 12 and editor.analysis.details.is_empty() and editor.analysis.due == -1, "invalid extra piece immediately clears score and schedules no search")
	await press("EditorUndo")
	check(position_key() == source_key and editor.redo_button.disabled == false, "actual Undo restores exact setup and enables Redo")
	await press("EditorRedo")
	check(editor.pos.board[40] == 12, "actual Redo restores promoted piece")
	await press("EditorUndo")
	app.ui.page_scroll.scroll_vertical = 0
	await settle()
	await drag(editor.cells[54].get_global_rect().get_center(), editor.cells[45].get_global_rect().get_center())
	check(editor.pos.board[54] == 0 and editor.pos.board[45] == 1 and editor.pos.turn == 1, "drag repositions exactly one piece without playing a game move")
	var moved_key = position_key()
	await evaluated()
	var pid: int = editor.analysis.engine.process.pid
	await press("EditorEvaluation")
	check(not app.preferences.studio.editor_eval_running and editor.analysis.engine == null and not OS.is_process_running(pid), "pausing evaluation releases its owned engine process")
	await press("EditorEvaluation")
	await evaluated()
	check(editor.analysis.launches == 2, "resuming launches one replacement evaluator")
	var before_failure: int = editor.analysis.generation
	pid = editor.analysis.engine.process.pid
	editor.analysis.engine._fail("test: editor engine process failed")
	check(editor.analysis.engine == null and not OS.is_process_running(pid) and editor.analysis.details.is_empty(), "engine failure clears score and releases its process")
	check(editor.analysis.due >= Time.get_ticks_msec() + 450, "private engine recovery waits before restarting")
	editor.analysis.receive(before_failure, {"score": 3000})
	check(editor.analysis.details.is_empty(), "failed session cannot overwrite retry state")
	await evaluated()
	check(editor.analysis.launches == 3 and editor.analysis.retries == 1, "one injected process failure recovers to actual analysis")
	await press("EditorFlip")
	check(editor.flipped and editor.square_at(editor.cells[45].get_global_rect().get_center()) == 45 and position_key() == moved_key, "board flip changes hit mapping without changing setup")
	app.ui.page_scroll.scroll_vertical = 0
	await settle()
	await drag(editor.cells[45].get_global_rect().get_center(), editor.cells[36].get_global_rect().get_center(), true)
	check(position_key() == moved_key and editor.interaction.pointer_id == -2, "canceled touch drag preserves source and target")
	await press("EditorFlip")
	await press("EditorSave")
	check(editor.history.entries.size() == 2 and editor.history.index == 1, "explicit save adds a loaded setup")
	var records = app.records.list_all()
	check(records.size() >= 1 and app.records.read(records[0].path).initial_sfen == moved_key, "saved setup appears as a valid independent archive record")
	await press("EditorPrevious")
	check(editor.undo_button.disabled == false, "previous setup retains its separate edit history")
	await press("EditorUndo")
	check(position_key() == source_key, "undo on previous setup returns to its original source")
	await press("EditorNext")
	check(position_key() == moved_key, "next saved setup remains independent of previous undo")
	await press("EditorHands")
	await settle()
	for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
		await resize(dimensions)
		await settle()
		check(app.ui.page_scroll.get_global_rect().end.x <= app.safe_rect().end.x, "expanded hands cannot widen editor beyond actual screen " + str(dimensions))
		check(editor.footer.get_global_rect().end.x <= app.safe_rect().end.x, "expanded hands keep Done inside actual screen")
	await resize(Vector2i(393, 852))
	await settle()
	for counter in editor.counters.values(): check(counter.get_global_rect().end.x <= app.safe_rect().end.x + 1, "hand counter fits actual narrow viewport")
	var counts = editor.counters["1/1"]
	app.ui.page_scroll.ensure_control_visible(counts)
	await settle()
	counts.get_line_edit().grab_focus()
	counts.get_line_edit().text = "1"
	await key(KEY_ENTER)
	check(editor.pos.hands[1][1] == 1 and not editor.Game.position_error(editor.pos).is_empty(), "keyboard hand count is applied and excess inventory is reported")
	var before_hand_undo = {"sfen": position_key(), "history": editor.history.histories.duplicate(true), "text": counts.get_line_edit().text, "value": counts.value}
	var hand_events = []
	editor.undo_button.button_down.connect(func(): hand_events.append({"event": "down", "sfen": position_key()}))
	editor.undo_button.pressed.connect(func(): hand_events.append({"event": "pressed", "sfen": position_key()}))
	counts.value_changed.connect(func(value): hand_events.append({"event": "value", "value": value, "sfen": position_key()}))
	counts.get_line_edit().focus_exited.connect(func(): hand_events.append({"event": "blur", "sfen": position_key()}))
	app.ui.page_scroll.ensure_control_visible(editor.undo_button)
	await settle()
	await capture("editor-hand-undo")
	await press("EditorUndo")
	FileAccess.open(output.path_join("hand-undo.json"), FileAccess.WRITE).store_string(JSON.stringify({"events": hand_events, "undo_rect": str(editor.undo_button.get_global_rect()), "scroll_rect": str(app.ui.page_scroll.get_global_rect()), "before": before_hand_undo, "after": {"sfen": position_key(), "history": editor.history.histories, "text": counts.get_line_edit().text, "value": counts.value}}, "  "))
	check(editor.pos.hands[1][1] == 0 and position_key() == moved_key, "hand counts participate in setup undo")
	check(counts.value == 0 and counts.get_line_edit().text == "0", "undo synchronizes both numeric model and editable text")
	var clipboard = DisplayServer.clipboard_get()
	await press("EditorCopy")
	check(DisplayServer.clipboard_get() == moved_key, "copy exports current exact setup")
	DisplayServer.clipboard_set("9/9/9/9/9/9/9/9/9 b - 1")
	await press("EditorPaste")
	check(editor.pos.board.count(0) == 81 and not editor.checked(), "structural incomplete SFEN can be edited but cannot replace a game")
	DisplayServer.clipboard_set(moved_key)
	await press("EditorPaste")
	check(position_key() == moved_key and editor.checked(), "valid pasted setup replaces working draft")
	DisplayServer.clipboard_set(clipboard)
	editor.sfen_field.grab_focus()
	editor.sfen_field.select_all()
	editor.sfen_field.insert_text_at_caret("malformed")
	await settle(0.4)
	check(not editor.checked() and editor.analysis.details.is_empty() and editor.analysis.enabled, "malformed text blocks Done and clears score without changing pause preference")
	check(position_key() == moved_key, "invalid text preserves last valid board")
	await press("EditorDone")
	check(app.ui.page_name == "editor" and app.game == live, "Done cannot silently apply an old board behind malformed text")
	editor.sfen_field.select_all()
	editor.sfen_field.insert_text_at_caret(moved_key)
	await settle(0.5)
	check(editor.checked(), "corrected text recovers without reopening editor")
	var root: String = app.records.root
	var blocker = output.path_join("save-blocker")
	FileAccess.open(blocker, FileAccess.WRITE).store_string("A file blocks creation of a child directory.")
	app.records.root = blocker
	await press("EditorSave")
	check(position_key() == moved_key and not editor.feedback.text.is_empty() and app.ui.page_name == "editor", "failed archive save keeps draft available for retry")
	app.records.root = root
	await evaluated()
	pid = editor.analysis.engine.process.pid
	var backup = preload("res://scripts/shogi_backup.gd").new().collect(app, app.ui.tutorial)
	check(backup.preferences.studio.editor_positions == app.preferences.studio.editor_positions, "full backup includes the saved editor setup list")
	await press("EditorCancel")
	check(app.game == live and game_content(live.to_data()) == game_content(saved_live), "Cancel preserves original game and clock balances")
	await settle()
	check(not is_instance_valid(editor), "closing editor releases its UI and analysis owner")
	check(not OS.is_process_running(pid), "Cancel terminates the private engine process")
	app.ui.show_editor()
	editor = app.ui.editor
	check(editor.history.entries.size() >= 2 and editor.history.current() == source_key, "reopening restores saved setup navigation and starts at current board")
	editor.read_sfen(moved_key)
	editor.flipped = true
	await press("EditorDone")
	check(app.game != live and app.game.initial_sfen == moved_key and app.game.moves.is_empty() and app.flipped and app.replay_index < 0, "Done applies setup and orientation as an independent playable game")
	await settle()
	check(app._can_play(), "completed setup supports normal legal gameplay")
	app.review_game = live
	app.replay_index = 1
	app._refresh()
	app.ui.show_editor()
	editor = app.ui.editor
	check(position_key() == app.Codec.sfen(live.positions[1]), "editor opened from replay uses the selected ply")
	editor.read_sfen("9/9/9/9/9/9/9/9/9 b - 1")
	await press("EditorCancel")
	check(app.review_game == live and app.replay_index == 1, "Cancel preserves exact replay context after draft edits")
	app.preferences.studio.editor_eval_bar = false
	app.ui.show_editor()
	editor = app.ui.editor
	await settle(0.6)
	check(not editor.evaluation.visible and editor.analysis.engine == null, "hidden editor evaluation bar starts no private engine")
	app.preferences.studio.editor_eval_bar = true
	editor.read_sfen("k8/1G7/R1K6/9/9/9/9/9/9 w - 1")
	await evaluated()
	check(editor.analysis.details.score_type == "mate" and editor.analysis.details.depth == 0, "terminal setup has deterministic mate evaluation")
	await press("EditorDone")
	check(app.game.result_code == "mate" and app.game.winner == 1 and not app._can_play(), "Done preserves a terminal setup as a finished game")
	finish()
