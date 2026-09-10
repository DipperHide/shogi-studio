extends "res://tests/unified_test.gd"
var live
var saved_live: Dictionary
var report
var practice

func resize(dimensions: Vector2i) -> void:
	app.get_window().mode = Window.MODE_WINDOWED
	for _attempt in range(3):
		app.get_window().content_scale_size = dimensions
		app.get_window().size = dimensions
		await settle(0.15)
		if app.get_window().size == dimensions: break
	app._layout()
	check(app.get_window().size == dimensions, "native test window resized to " + str(dimensions))

func capture(name: String) -> void:
	await settle(0.06)
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	screenshots.append(name)

func press(name: String) -> void:
	await settle()
	var button = app.ui.root.find_child(name, true, false)
	check(button != null and not button.disabled, "available practice control " + name)
	if button == null or button.disabled: return
	var parent = button.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(button)
		parent = parent.get_parent()
	await settle()
	print("PRACTICE PRESS ", name, " window=", app.get_window().size, " viewport=", app.get_viewport_rect().size, " target=", button.get_global_rect())
	await tap(button.get_global_rect().get_center())

func attempt(value: String) -> void:
	app.active = true
	var move = app.Codec.parse_move(value, app._play_game().position)
	check(not move.is_empty(), "legal exercise input " + value)
	if move.is_empty(): return
	if move.from >= 0: await tap(app.square_rect(move.from).get_center())
	else: await tap(app.hand_hit_rect(app._play_game().position.turn, move.drop).get_center())
	await tap(app.square_rect(move.to).get_center())
	if app.ui.page_name == "promotion": await click("升变" if move.promote else "不变")
	if app.ui.page_name == "confirm-move": await click("确认落子")

func preserve(label: String) -> void:
	check(app.game == live and game_content(app.game.to_data()) == game_content(saved_live), label + " preserves live moves, metadata and clock balances")
	if practice.active: check(live.clock.paused, "live clock paused while practicing")

func game_content(data: Dictionary) -> Dictionary:
	var content = data.duplicate(true)
	# Opening a page pauses the clock; balances and every other saved field must stay.
	content.clock.erase("paused")
	return content

func fixture(sfen: String, played: String, best: String, pv: Array = []) -> void:
	# Explicit deterministic legality fixture, not a measured engine evaluation.
	if practice.active: practice.stop(false)
	var source = app.Game.new()
	check(source.set_initial(sfen), "exercise fixture accepts SFEN")
	source.metadata = {"先手": "测试夹具", "后手": "测试夹具"}
	var move = app.Codec.parse_move(played, source.position)
	check(not move.is_empty() and source.play(move), "exercise fixture contains legal original move")
	report.cancel()
	report.game = source
	report.phase_cache_size = -1
	report.samples = [{"score": 600, "pv": pv if not pv.is_empty() else [best], "mate": false, "depth": 0}, {"score": -600, "pv": [], "mate": false, "depth": 0}]
	report.rows = [{"ply": 1, "side": source.positions[0].turn, "loss": 1200, "category": "漏着", "label": source.labels[0], "best": best, "score": -600}]
	report.index = 2
	app.ui.retry_from_report = false
	check(practice.start(report, {"side": 0, "categories": ["漏着"], "skip_tried": false}), "deterministic exercise starts")
	app.active = true
	await settle()

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis13/ui")
	if "--chessis24-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis24/chessis13_test")
	if "--chessis25-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis25/chessis13_test")
	if "--chessis14-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis14/practice-ui")
	if "--chessis15-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis15/practice-ui")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/practice-ui")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis13_test")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/practice-ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.ui.tutorial.progress_path = output.path_join("practice-progress-" + str(Time.get_ticks_usec()) + ".json")
	app.get_tree().create_timer(165).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	await play("7g7f")
	await play("3c3d")
	app.game.mode = "ai"
	app.game.human_side = -1
	app.preferences.studio.animation = 0.4
	live = app.game
	saved_live = live.to_data().duplicate(true)
	report = app.ui.report
	practice = app.ui.practice
	var source = app.Game.new()
	source.set_initial("8k/9/4p4/9/4R4/9/9/9/K8 b - 1")
	source.play(app.Codec.parse_move("5e5d", source.position))
	report.start(source, true, {"deep_mode": "time", "deep_time": 0.5, "deep_lines": 3})
	check(await until(func(): return not report.running, 15), "actual engine produces hanging-rook report")
	check(report.error.is_empty() and report.rows.size() == 1 and report.rows[0].category in ["失误", "漏着", "错失胜机"], "actual report identifies a practice mistake")
	FileAccess.open(output.path_join("real-engine-report.json"), FileAccess.WRITE).store_string(JSON.stringify({"source": source.to_data(), "rows": report.rows, "samples": report.samples}, "  "))
	await resize(Vector2i(393, 852))
	app.ui.show_report()
	app.ui.select_report_move(1)
	app.ui.review_mistake()
	await capture("retry-settings")
	check(app.ui.page_name == "retry-settings" and app.ui.page.find_child("RetryCount", true, false).text.contains("1"), "settings lists one actual eligible mistake")
	app.ui.page.find_child("RetrySide-1", true, false).button_pressed = true
	check(app.ui.page.find_child("BeginMistakePractice", true, false).disabled, "player filter excludes other side")
	app.ui.page.find_child("RetrySide1", true, false).button_pressed = true
	await press("BeginMistakePractice")
	app.active = true
	if not practice.active:
		check(false, "practice did not start after visible begin control")
		await capture("failed-begin")
		FileAccess.open(output.path_join("failed-begin.json"), FileAccess.WRITE).store_string(JSON.stringify({"page": app.ui.page_name, "error": practice.error, "window": str(app.get_window().size), "viewport": str(app.get_viewport_rect().size)}, "  "))
		app.get_tree().quit(1)
		return
	check(practice.active and app._can_play() and not app._ai_allowed(), "board input enabled for exercise while active game's AI remains paused")
	check(app.review_game == practice.exercise and app._display_position().key() == source.positions[0].key(), "practice starts before the mistaken move")
	check(not app.ui.win_rate_label.visible and not app.ui.analysis_scroll.visible and app.ui.toolbar.get_child(2).disabled, "answer and evaluation remain hidden while guessing")
	preserve("practice start")
	var original_clock = live.clock
	live.clock = app.Game.Clock.new()
	live.clock.configure(1)
	var balance: Dictionary = live.clock.remaining.duplicate()
	await settle(0.25)
	check(live.clock.paused and live.clock.remaining == balance, "timed active game spends no clock time during practice")
	live.clock = original_clock
	await capture("guess-best")
	await attempt("5e5d")
	check(practice.stage == "wrong" and app.motion_progress > 0 and app.motion_progress < 1, "wrong move is animated before returning")
	await capture("wrong-move-animation")
	check(await until(func(): return practice.stage == "answer" and app.motion_progress >= 1, 4), "wrong answer returns to the original exercise position")
	check(practice.exercise.moves.is_empty() and practice.mistakes == 1, "wrong move is not left in exercise history")
	preserve("wrong attempt")
	await press("PracticeHint")
	check(practice.hint_level == 1 and practice.exercise.moves.is_empty(), "first hint selects piece without playing the answer")
	await capture("piece-hint")
	await press("PracticeHint")
	check(practice.hint_level == 2 and practice.message.begins_with("建议"), "second hint shows complete move")
	await capture("move-hint")
	var best: String = app.Codec.move_name(practice.entry().best)
	await attempt(best)
	check(practice.stage == "solved" and practice.exercise.moves.size() == 1, "actual engine's best move is accepted")
	check(not practice.progress().state("mistakes", practice.entry().key, 0).mastered, "assisted or previously wrong answer is not marked mastered")
	await capture("correct-assisted")
	await press("PracticeLine")
	check(await until(func(): return practice.stage == "preview" and app.replay_index >= 1, 3), "saved real engine line plays on board")
	await capture("answer-line-animation")
	app.ui.back()
	check(await until(func(): return practice.stage == "solved" and app.motion_progress >= 1, 3), "preview back returns to answered exercise")
	app.ui.back()
	await settle()
	check(not practice.active and app.ui.page_name == "report" and app.ui.report_selected_ply == 1, "exit restores exact selected report move")
	preserve("exercise exit")
	app.ui.review_mistake()
	check(app.ui.page.find_child("BeginMistakePractice", true, false).disabled, "attempted move skipped by default on next practice session")
	app.ui.page.find_child("SkipTriedMistakes", true, false).button_pressed = false
	check(not app.ui.page.find_child("BeginMistakePractice", true, false).disabled, "attempted moves can be included again")
	app.ui.back()
	var trade = preload("res://scripts/shogi_exchange.gd").new().parse("position startpos moves 7g7f 3c3d 8h2b+ 3a2b")
	await fixture(app.Codec.sfen(trade.position), "7f7e", "B*4e", ["B*4e", "B*5d"])
	for style in ["anime2d", "wood"]:
		app.set_appearance(style)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			check(app.safe_rect().encloses(app.ui.toolbar.get_global_rect()), "practice toolbar fits " + style + str(dimensions))
			check(app.ui.live_panel.get_global_rect().end.y <= app.ui.toolbar.position.y + 1, "practice panel avoids navigation " + style + str(dimensions))
			await capture(style + "-practice-%dx%d" % [dimensions.x, dimensions.y])
		await resize(Vector2i(393, 852))
		await attempt("B*4e")
		check(practice.stage == "solved" and app.motion_progress < 1, style + " hand drop accepted with animation")
		await capture(style + "-drop-animation")
		check(practice.progress().state("mistakes", practice.entry().key, 0).mastered, "unassisted first answer records mastery")
		await until(func(): return app.motion_progress >= 1)
		await press("PracticeLine")
		check(await until(func(): return app.replay_index == 1, 3), style + " answer replay advances")
		app.ui.back()
		await until(func(): return practice.stage == "solved" and app.motion_progress >= 1)
		await press("RetryPractice")
		await until(func(): return app.motion_progress >= 1)
		check(practice.stage == "answer" and practice.exercise.position.hands[1][6] == 1, style + " retry restores captured bishop in hand")
	app.set_appearance("anime2d")
	practice.stop(false)
	app.preferences.confirm_move = true
	await fixture("8k/9/9/4S4/9/9/9/9/K8 b - 1", "5d4c", "5d5c+")
	await attempt("5d5c")
	check(practice.stage == "wrong", "nonpromotion is distinguished from required promoted answer")
	await until(func(): return practice.stage == "answer" and app.motion_progress >= 1, 4)
	await attempt("5d5c+")
	check(practice.stage == "solved" and practice.exercise.position.board[22] == 12, "promotion and confirmation dialogs commit only to exercise")
	preserve("promotion confirmation")
	await until(func(): return app.motion_progress >= 1)
	await fixture("k8/9/9/9/9/4s4/9/9/8K w - 1", "5f4g", "5f5g+")
	check(app.flipped and practice.entry().side == -1 and app._can_play(), "gote exercise rotates board and allows gote input")
	await press("RevealPractice")
	check(practice.stage == "revealed" and not practice.progress().state("mistakes", practice.entry().key, 0).mastered, "revealing answer never awards mastery")
	await capture("gote-reveal")
	await press("NextPractice")
	check(await until(func(): return practice.stage == "complete", 3), "next during reveal animation waits then completes")
	check(practice.totals().revealed == 1 and practice.totals().solved == 0, "completion summary separates reveals from solved answers")
	await capture("practice-complete")
	var backup = preload("res://scripts/shogi_backup.gd").new().collect(app, app.ui.tutorial)
	check(game_content(backup.active) == game_content(saved_live), "backup retains real active game at completed session")
	check(backup.tutorial.steps.keys().any(func(key): return key.begins_with("mistakes/")), "practice progress included in existing learning backup")
	var restored = preload("res://scripts/shogi_tutorial_progress.gd").new()
	restored.load_from(app.ui.tutorial.progress.path)
	check(not restored.blocked_corrupt and not restored.blocked_read, "practice history reloads through validated learning schema")
	check(restored.data.steps == JSON.parse_string(JSON.stringify(practice.progress().data.steps)), "practice history persists with JSON numeric normalization")
	FileAccess.open(output.path_join("practice-backup.json"), FileAccess.WRITE).store_string(JSON.stringify(backup, "  "))
	practice.stop(false)
	check(app.review_game == null and app.replay_index == -1, "final exit restores original board view")
	preserve("all exercises")
	app.preferences.confirm_move = false
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "screenshots": screenshots}, "  "))
	print("CHESSIS 13 UI: ", checks, " checks; ", failures)
	app.get_tree().quit(0 if failures.is_empty() else 1)
