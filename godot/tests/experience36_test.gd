extends "res://tests/chessis23_test.gd"

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/experience36")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.save_path = output.path_join("active.json")
	app.get_tree().create_timer(180).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic"); app.ui.close()
	check(app.game.set_initial("4k4/9/9/9/9/9/9/9/4K4 b 2P 1"), "hand regression fixture")
	app._refresh()
	await settle()
	var start: Vector2 = app.hand_slot(1, 1).get_center()
	var end: Vector2 = app.ui.toolbar.get_global_rect().get_center()
	var down = InputEventScreenTouch.new()
	down.index = 0; down.pressed = true; down.position = start
	app._input(down)
	var drag = InputEventScreenDrag.new()
	drag.index = 0; drag.position = end; drag.relative = end - start
	app._input(drag)
	check(app.drag_drop == 1 and app.pointer_moved, "fixture is dragging a pawn over toolbar")
	var up = InputEventScreenTouch.new()
	up.index = 0; up.pressed = false; up.position = end
	app._input(up)
	check(app.pointer_id == -2 and app.drag_drop == 0, "release over toolbar always ends hand drag")
	check(app.game.position.hands[1][1] == 2, "cancelled drop preserves both pawns")
	for appearance in ["anime2d", "wood"]:
		app.set_appearance(appearance)
		app._pointer_down(2, app.hand_slot(1,1).get_center())
		app.pointer_moved = true
		app.pointer_current = app.board_rect.get_center()
		app._redraw()
		check(app.board_view.hand_remaining(app.game.position, 1, 1) == 1 and app.game.position.hands[1][1] == 2, appearance + " dragging reserves one visible hand without changing game state")
		if DisplayServer.get_name() != "headless": await capture("hand-drag-" + appearance)
		var cancelled = InputEventScreenTouch.new()
		cancelled.index = 2; cancelled.canceled = true; cancelled.position = app.board_rect.get_center()
		app._input(cancelled)
		check(app.pointer_id == -2 and app.drag_drop == 0 and app.game.position.hands[1][1] == 2, appearance + " system touch cancellation restores hands")
		app._pointer_down(2, app.hand_slot(1,1).get_center()); app.pointer_moved = true
		app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
		app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
		check(app.pointer_id == -2 and app.drag_drop == 0, appearance + " background transition cancels drag")
	app.set_appearance("anime2d")
	await interface_checks()
	await own_side_checks()
	if "--portable-experience" not in OS.get_cmdline_user_args(): await live_checks()
	await warning_checks()
	await finish()

func gesture(start: Vector2, distance: Vector2) -> void:
	var down = InputEventScreenTouch.new()
	down.index = 4; down.pressed = true; down.position = start
	Input.parse_input_event(down); Input.flush_buffered_events()
	await settle(0.025)
	for step in range(1, 7):
		var drag = InputEventScreenDrag.new()
		drag.index = 4; drag.position = start + distance * step / 6.0; drag.relative = distance / 6.0
		Input.parse_input_event(drag); Input.flush_buffered_events()
		await settle(0.025)
	var up = InputEventScreenTouch.new()
	up.index = 4; up.position = start + distance
	Input.parse_input_event(up); Input.flush_buffered_events()
	await settle(0.1)

func interface_checks() -> void:
	var historic = preload("res://scripts/shogi_historic_games.gd").new()
	var source = historic.game_for(historic.entries()[0])
	check(source != null and source.moves.size() >= 140, "long record fixture")
	app.review_game = source; app.replay_index = 0; app._refresh()
	await resize(Vector2i(360, 760))
	await settle()
	var ribbon = app.ui.ribbon
	check(ribbon.entries.size() == source.moves.size() + 1, "ribbon includes every ply")
	check(app.ui.move_strip.get_child_count() < 30, "ribbon virtualizes controls")
	var original = app.replay_index
	await gesture(app.ui.move_scroll.get_global_rect().get_center(), Vector2(-110, 0))
	check(app.ui.move_scroll.scroll_horizontal > 40, "touch scrolls move ribbon")
	check(app.replay_index == original, "ribbon drag does not select a move")
	var scrolled = app.ui.move_scroll.scroll_horizontal
	await settle(0.2)
	check(app.ui.move_scroll.scroll_horizontal == scrolled, "manual ribbon scroll is retained")
	app.ui.move_scroll.scroll_horizontal = int(ribbon.extent)
	await settle()
	check(ribbon.last == source.moves.size(), "virtualized last move is reachable")
	var last = app.ui.move_strip.find_child("HistoryMove_%d" % source.moves.size(), true, false)
	check(last != null, "last move button exists at far end")
	app.ui.show_history(0); app._cancel_motion()
	var pv: Array = []
	for move in source.moves: pv.append(app.Codec.move_name(move))
	app.preferences.studio.analysis_lines = 5
	for line in range(1, 6): app.ui.receive_info({"multipv": line, "score": line * 10, "score_type": "cp", "depth": 10, "pv": pv})
	await settle()
	var row = app.ui.pv_rows[1]
	var parses: int = row.parse_count
	row.update_line({"multipv": 1, "score": 25, "score_type": "cp", "depth": 11, "pv": pv}, source.positions[0], app.Codec)
	check(row.parse_count == parses and row.score_label.text == "+0.25", "score updates reuse parsed notation")
	var area: Rect2 = row.scroll.get_global_rect()
	await gesture(area.get_center(), Vector2(-75, 0))
	check(row.scroll.scroll_horizontal > 20, "candidate scrolls horizontally")
	check(app.ui.pv_context.is_empty(), "candidate drag does not start playback")
	var vertical_before = app.ui.analysis_scroll.scroll_vertical
	await gesture(area.get_center(), Vector2(0, -55))
	check(app.ui.analysis_scroll.scroll_vertical > vertical_before, "vertical drag inside candidate reaches outer scroll")
	for appearance in ["anime2d", "wood"]:
		app.set_appearance(appearance)
		for dimensions in [Vector2i(360,760), Vector2i(852,393)]:
			await resize(dimensions)
			for mode in [0, 1, 2]:
				app.ui.analysis_panel.set_mode(mode)
				await settle()
				var panel: Rect2 = app.ui.live_panel.get_global_rect()
				check(app.safe_rect().grow(1).encloses(panel), "analysis panel fits safe area %s %s %d" % [appearance, dimensions, mode])
				check(not panel.intersects(app.ui.toolbar.get_global_rect()), "analysis never covers toolbar")
				if mode == 2:
					var ply = app.replay_index
					app._back_requested()
					check(app.ui.analysis_panel.mode == 0 and app.replay_index == ply, "back collapses without moving cursor")
			if DisplayServer.get_name() != "headless":
				app.ui.analysis_panel.set_mode(1)
				await capture("analysis-%s-%d" % [appearance, dimensions.x])
	app.ui.analysis_panel.set_mode(0)
	await resize(Vector2i(360,760))
	app.set_appearance("anime2d")
	var start: Vector2 = app.ui.analysis_panel.handle.get_global_rect().get_center()
	await gesture(start, Vector2(0, -250))
	check(app.ui.analysis_panel.mode > 0, "handle drag expands workbench")
	app.ui.analysis_panel.set_mode(0)
	app.ui.start_variation_analysis(source, 20)
	await settle()
	check(app.ui.ribbon.entries.size() == source.moves.size() + 1, "variation ribbon covers full main line")
	check(app.ui.move_strip.get_child_count() < 30, "variation ribbon is also virtualized")
	await gesture(app.ui.move_scroll.get_global_rect().get_center(), Vector2(-100,0))
	await settle(0.5)
	check(app.ui.page == null, "scrolling a variation does not fire delayed long press")
	app.ui.finish_study()
	app._cancel_motion()

func live_checks() -> void:
	app.ui.live_enabled = false
	app._load_engine()
	check(await until(func(): return app.usi.available(), 40), "real NNUE engine ready")
	if not app.usi.available(): return
	app.review_game = app.Game.new(); app.replay_index = 0; app._refresh()
	var baseline = {"first_ms": -1, "total_ms": -1}
	var started = Time.get_ticks_msec()
	var on_info = func(id, _details):
		if id == 9001 and baseline.first_ms < 0: baseline.first_ms = Time.get_ticks_msec() - started
	var on_best = func(id, _move, _special):
		if id == 9001: baseline.total_ms = Time.get_ticks_msec() - started
	app.usi.analysis.connect(on_info); app.usi.best_move.connect(on_best)
	app.usi.analysis_count = 5
	app.usi._set_option("PvInterval", "300")
	app.usi.search(app._display_position(), [], 9001, 5, true)
	check(await until(func(): return baseline.total_ms >= 0, 15), "previous 8 second analysis baseline completes")
	app.usi.analysis.disconnect(on_info); app.usi.best_move.disconnect(on_best)
	# Restart to compare both approaches with a fresh search hash, excluding load time.
	app._load_engine()
	check(await until(func(): return app.usi.available(), 40), "fresh engine for staged timing")
	app.live.enabled = true
	app.live.enter(true)
	check(await until(func(): return app.live.stage == "done", 15), "automatic two-stage analysis completes")
	check(app.ui.live_details.size() == 5, "refinement restores configured five candidates")
	var key = app.live.signature()
	check(app.live.cache.has(key), "completed analysis is cached")
	var performance = {"platform": OS.get_name(), "baseline": baseline, "staged": app.live.measurements.duplicate(true)}
	FileAccess.open(output.path_join("analysis-timing.json"), FileAccess.WRITE).store_string(JSON.stringify(performance, "\t"))
	var request_id = app.engine_request
	app.live.pause()
	app.ui.show_history(0)
	await settle(0.4)
	check(not app.ui.live_enabled and app.engine_request == request_id, "manual pause survives navigation")
	app.live.enter(true)
	await settle(0.4)
	check(app.live.stage == "done" and app.engine_request == request_id, "cached position is immediate without new search")
	var source = app.Game.new()
	for value in ["7g7f", "3c3d", "2g2f", "8c8d"]: source.play(app.Codec.parse_move(value, source.position))
	app.review_game = source; app.replay_index = 0; app._refresh()
	for ply in range(1, 5):
		app.ui.show_history(ply)
		await settle(0.025)
	check(app.engine_request == request_id, "rapid navigation is debounced")
	app._cancel_motion()
	check(await until(func(): return app.live.stage == "done", 15), "final navigated position completes")
	check(app.engine_request == request_id + 2, "only final position launches quick and refinement searches")
	var latest = app.ui.live_details.duplicate(true)
	app._engine_info(request_id, {"multipv":1,"score":99999,"pv":[]})
	check(app.ui.live_details == latest, "obsolete engine generation cannot overwrite current result")
	var searches = app.engine_request
	app.ui.report.running = true
	app.ui.live_key = ""
	await settle(0.4)
	check(app.engine_request == searches, "whole-game report suspends live analysis")
	app.ui.report.running = false
	app.live.pause()
	app.usi.shutdown()
	app.usi.phase = "error"
	app.live.failed()
	app.live.deepen()
	check(await until(func(): return app.live.stage == "done", 20), "retry restarts failed engine and completes deeper search")
	check(app.live.measurements.back().stage == "deep", "requested deep stage survives engine startup")
	app.live.pause(); app.live.enabled = false
	app.ui.live_details.clear(); app.ui.clear_pv_rows()
	app.usi.shutdown()

func own_side_checks() -> void:
	app.live.enabled = false
	app.ui.report_board_active = false
	for side in [1, -1]:
		app._start_match("ai", side, 7, "basic"); app.ui.close()
		if side == -1: app.game.play(app.Codec.parse_move("7g7f", app.game.position))
		app.active = true; app._cancel_motion(); app._refresh()
		app.ui.show_analysis()
		var values = ["7g7f", "3c3d"] if side == 1 else ["3c3d", "2g2f"]
		var details = {"multipv":1,"score":80,"depth":10,"score_type":"cp","pv":values,"turn":side}
		check(app.live.allowed(), "own turn permits analysis for seat %d" % side)
		app.ui.receive_info(details)
		check(app.ui.pv_rows.size() == 1 and app.ui.live_details[1].pv.size() == 2, "own line retains opponent replies for seat %d" % side)
		if side == -1 and DisplayServer.get_name() != "headless": await capture("own-side-gote")
		app.ui.preview_pv(1)
		check(not app.ui.pv_context.is_empty() and app.review_game.moves.size() == 2, "own line preview plays full alternating line")
		app.ui.stop_pv(); app._cancel_motion()
		app.game.play(app.Codec.parse_move(values[0], app.game.position)); app._refresh()
		# Also reject a late result whose root key has already been updated.
		app.ui.live_key = app.game.position.key()
		app.ui.receive_info({"multipv":1,"pv":[values[1]],"turn":-side})
		check(not app.live.allowed() and app.ui.live_details.is_empty() and app.ui.pv_rows.is_empty() and app.ui.arrows.is_empty(), "computer turn hides candidates and arrows for seat %d" % side)
		if side == -1 and DisplayServer.get_name() != "headless": await capture("own-side-computer-turn")
		check(app.ui.live_text.visible and app.ui.live_text.text.contains("仅显示你的"), "computer turn explains that only player lines are shown")
		if side == -1:
			FileAccess.open(output.path_join("own-side-layout.json"), FileAccess.WRITE).store_string(JSON.stringify({"text_rect":str(app.ui.live_text.get_global_rect()),"scroll_rect":str(app.ui.analysis_scroll.get_global_rect()),"scroll_y":app.ui.analysis_scroll.scroll_vertical,"parent_visible":app.ui.live_text.is_visible_in_tree()}, "\t"))
			check(app.ui.live_text.size.y >= 16 and app.ui.live_text.get_global_rect().intersects(app.ui.analysis_scroll.get_global_rect()), "waiting message is readable inside analysis scroll area")
		var selected = app.Codec.parse_move(values[1], app.game.position)
		app.pending_ai = selected.duplicate()
		var revision = app.revision
		app.live.active_key = "previous-player-analysis"
		app.live.enabled = true; app.live._process(0); app.live.enabled = false
		check(app.pending_ai == selected and app.revision == revision, "own-side analysis cancellation preserves weak opponent selection")
		app.ui.toggle_live()
		check(app.pending_ai == selected and app.revision == revision, "manual pause preserves weak opponent selection")
		app.live.deepen()
		check(app.pending_ai == selected and app.revision == revision and app.live.deep_requested, "deepen on computer turn waits without interrupting opponent")
		app.live.deep_requested = false
		app.pending_ai.clear()
		var own_ply: int = app.game.moves.size() - 1
		app.replay_index = own_ply; app.ui.live_enabled = true
		check(app.live.allowed(), "replay recognizes player's seat")
		app.replay_index = own_ply + 1
		check(not app.live.allowed(), "replay suppresses computer root")
		app.replay_index = -1
		app.ui.start_variation_analysis(app.game, own_ply)
		check(app.live.allowed() and app.ui.study.current.human_side == side, "variation retains original player seat")
		var restored = app.Game.from_data(app.ui.study.document().to_data())
		check(restored.mode == "ai" and restored.human_side == side, "saved variation retains player seat")
		app.ui.study.seek(own_ply + 1)
		check(not app.live.allowed(), "variation suppresses opponent root")
		app.ui.finish_study(); app._cancel_motion()
		# Even a misrouted strong-engine response must never select a weak move.
		app.ui.live_enabled = false
		app.review_game = null; app.replay_index = -1
		app.engine_provider = "yaneuraou"
		for level in range(6, 10):
			app.engine_level = level
			var id: int = app.engine_request
			app._request_engine("play", app.game.position, app.game.moves, false)
			check(app.engine_request == id, "weak grade %d cannot request USI play" % level)
			app.engine_context = {"id":700,"kind":"analysis","revision":app.revision,"key":app.game.position.key()}
			app._engine_best(700, selected, "")
			check(app.pending_ai.is_empty(), "analysis result cannot play weak grade %d" % level)
			app.engine_context = {"id":701,"kind":"play","revision":app.revision,"key":app.game.position.key()}
			app._engine_best(701, selected, "")
			check(app.pending_ai.is_empty(), "misrouted USI play cannot override weak grade %d" % level)
		app.engine_level = 0
		app.engine_context = {"id":702,"kind":"analysis","revision":app.revision,"key":app.game.position.key()}
		app._engine_best(702, selected, "")
		check(app.pending_ai.is_empty(), "analysis result cannot play legacy grade either")
	var source = app.Game.new(); source.mode = "local"
	source.play(app.Codec.parse_move("7g7f", source.position))
	app.review_game = source; app.replay_index = 1; app.ui.live_enabled = true
	check(app.live.allowed(), "unassigned imported record can analyze either side")
	app.live.pause()
	app.ui.live_details.clear(); app.ui.clear_pv_rows()
	for side in [1, -1]:
		for level in range(6, 10):
			app._start_match("ai", side, level, "basic"); app.ui.close()
			app.engine_provider = "yaneuraou"
			if side == 1: app.game.play(app.Codec.parse_move("7g7f", app.game.position))
			app._cancel_motion(); app.active = true; app._refresh()
			var count: int = app.game.moves.size()
			var requests: int = app.engine_request
			var legal = app.game.position.legal_moves()
			app.ui.live_enabled = true; app.auto_play = true
			check(await until(func(): return app.game.moves.size() == count + 1, 4), "weak grade %d plays with analysis enabled, seat %d" % [level, side])
			app.auto_play = false
			check(app.game.moves.back() in legal and app.engine_request == requests and app.engine_level == level, "weak move stays legal and uses its configured local chooser")
	app.ui.live_enabled = false; app._cancel_motion()

func warning_checks() -> void:
	app._start_match("ai", 1, 7, "basic"); app.ui.close()
	app.game.set_initial("4k4/9/9/4r4/4R4/9/9/9/4K4 b - 1")
	check(app.game.play(app.Codec.parse_move("5e5f", app.game.position)), "player warning fixture move is legal")
	var warning = app.coach.snapshot(app.game, 1)
	warning.merge({"loss":1000,"label":"4五飛","category":"漏着","best":{"score":500,"depth":10,"score_type":"cp","pv":["5e5d"]}})
	check(app.game.play(app.Codec.parse_move("5a4a", app.game.position)), "computer warning fixture reply is legal")
	app.coach.warning = warning
	app._refresh(); app.ui.update_coach_display()
	check(app.coach.valid(warning) and app.ui.coach_notice.visible and app.ui.coach_actions.visible, "warning remains actionable after computer reply")
	app.ui.retry_coach(); app._cancel_motion()
	check(app.game.moves.is_empty() and app.game.position.turn == 1, "retry undoes player move and computer reply")
	check(not app.coach.valid(warning), "undo invalidates old warning")
	app.coach.warning = warning
	app.ui.dismiss_coach()
	check(app.coach.warning.is_empty() and not app.ui.coach_notice.visible, "dismiss hides warning")
