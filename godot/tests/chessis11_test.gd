extends "res://tests/unified_test.gd"

func capture(name: String) -> void:
	await settle(0.06)
	await RenderingServer.frame_post_draw
	app.get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png"))
	screenshots.append(name)

func displayed_motion(reader: Callable = Callable()) -> bool:
	var deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await RenderingServer.frame_post_draw
		var progress: float = reader.call() if reader.is_valid() else app.motion_progress
		if progress > 0 and progress < 1: return true
		if progress >= 1: return false
	return false

func run(instance) -> void:
	app = instance
	output = ProjectSettings.globalize_path("res://../review/app/chessis11/ui")
	if "--chessis26-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis26/chessis11_test")
	if "--chessis27-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis27/chessis11_test")
	if "--chessis24-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis24/chessis11_test")
	if "--chessis25-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis25/chessis11_test")
	if "--chessis12-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis12/coach-replay-ui")
	if "--chessis13-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis13/coach-replay-ui")
	if "--chessis14-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis14/coach-replay-ui")
	if "--chessis15-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis15/coach-replay-ui")
	if "--chessis16-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis16/coach-replay-ui")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/chessis11_test")
	if "--chessis17-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis17/coach-replay-ui")
	if "--chessis28-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis28/chessis11_test")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root = output.path_join("records")
	app.ui.tutorial.progress_path = output.path_join("learning.json")
	app.get_tree().create_timer(150).timeout.connect(func(): app.get_tree().quit(2))
	app._start_match("local", 1, 2, "basic")
	app.ui.close()
	for value in ["7g7f", "3c3d", "8h2b+", "3a2b", "B*4e"]: await play(value)
	app.preferences.studio.animation = 0.4
	for style in ["anime2d", "wood"]:
		app.set_appearance(style)
		for dimensions in [Vector2i(360, 760), Vector2i(393, 852), Vector2i(852, 393), Vector2i(1100, 800)]:
			await resize(dimensions)
			for side in [-1, 1]:
				var slot: Rect2 = app.hand_slot(side, 6)
				var rect: Rect2 = app.board_view.piece_rect(slot)
				check(is_equal_approx(rect.size.x, rect.size.y) and slot.encloses(rect), style + " hand aspect fixed " + str(dimensions))
			check(app.safe_rect().encloses(app.ui.toolbar.get_global_rect()) and app.ui.toolbar.get_child_count() == 8, "undo toolbar fits " + str(dimensions))
			await capture(style + "-%dx%d" % [dimensions.x, dimensions.y])
		await resize(Vector2i(393, 852))
		for ply in [4, 3, 2, 3, 4, 5]:
			app.ui.show_history(ply)
			check(app.motion_progress < 1 and not app.transition.is_empty(), style + " replay starts motion " + str(ply))
			check(await displayed_motion(), style + " replay has intermediate frame " + str(ply))
			if ply == 2: await capture(style + "-capture-reverse-motion")
			# A render stall may extend visible movement; completion is an event,
			# while actual frame-time limits are checked by the motion probes.
			check(await until(func(): return app.motion_progress == 1, 3), style + " replay settles " + str(ply))
		app.ui.show_menu()
		app.ui.show_history(1)
		check(app.ui.page == null and app.motion_progress < 1, style + " close dialog does not cancel replay")
		await settle(0.45)
		app.preferences.studio.autoplay = 0.5
		app.ui.toggle_autoplay()
		check(await until(func(): return app.replay_index >= 3, 3), style + " autoplay advances")
		app.ui.autoplay_on = false
		await settle(0.5)
		app.ui.show_history(1)
		await settle(0.08)
		app.ui.seek(1)
		app.ui.seek(1)
		check(app.replay_index == 3 and app.motion_progress < 1, style + " repeated seeks immediately retarget the visible animation")
		check(await until(func(): return app.replay_index == 3 and app.motion_progress == 1, 3), style + " retargeted seek reaches selected position")
	app.set_appearance("anime2d")
	app.ui.close()
	app.active = true
	var original = app.game
	var original_key: String = original.position.key()
	app.game.mode = "ai"
	app.ui.show_history(2)
	await settle(0.45)
	check(app.ui.continue_button.visible, "continue button exposed during replay")
	app.ui.continue_button.pressed.emit()
	await settle(0.5)
	app.active = true
	check(app.game != original and app.game.moves.size() == 2 and app.game.position.key() == original.positions[2].key(), "branch begins at exact selected position")
	check(original.position.key() == original_key and original.moves.size() == 5, "branch preserves original game")
	check(app.game.mode == "ai" and app.game.human_side == app.game.position.turn and app._can_play(), "branch can be played immediately against AI")
	await play("2g2f")
	app.ui.toolbar.get_child(6).pressed.emit()
	await settle(0.5)
	check(app.game.moves.size() == 2, "main toolbar undo removes human move")
	await capture("continue-and-undo")
	await tutorials()
	await coaching()
	check(not app.ui.has_method("show_membership"), "paid membership removed")
	await finish()

func tutorials() -> void:
	var tutorial = app.ui.tutorial
	tutorial.show_catalog()
	await capture("tutorial-catalog")
	var texts = ""
	for node in app.ui.page.find_children("*", "Label", true, false): texts += node.text
	check(not texts.contains(tutorial.books[0].title) and not texts.contains("两本书"), "catalog removes book names")
	tutorial.show_book(tutorial.books[0])
	await capture("tutorial-topics")
	var chapter: Dictionary = tutorial.books[0].chapters[0]
	check(tutorial.visible_lessons(chapter).all(func(entry): return entry.id != "intro-welcome"), "noninstructional introduction removed")
	tutorial.show_chapter(tutorial.books[0], chapter)
	await capture("tutorial-lessons")
	var entry: Dictionary = tutorial._find_lesson(tutorial.books[0].id, "intro-first-game")[1]
	var index = 0
	for i in range(entry.steps.size()):
		if entry.steps[i].kind in ["move", "sequence"]: index = i; break
	tutorial.open_lesson(tutorial.books[0].id, entry.id, index)
	await capture("tutorial-board")
	var move = app.Codec.parse_move(tutorial.model.step.moves[0], tutorial.model.position)
	tutorial._select_move([move])
	check(await displayed_motion(func(): return tutorial.board.motion) and tutorial.model.cursor == 1, "interactive exercise move animates and advances")
	await settle(0.5)
	tutorial.model.reveal()
	tutorial._refresh_answer()
	await settle(0.5)
	check(tutorial.replay_positions.size() > 1, "lesson builds actual answer replay")
	tutorial._show_replay(1)
	check(await displayed_motion(func(): return tutorial.board.motion), "tutorial replay interpolates pieces")
	await capture("tutorial-motion")
	await settle(0.5)
	tutorial._show_replay(0)
	check(tutorial.board.motion < 1, "tutorial reverse replay animates")
	await settle(0.04)
	var start_rect: Rect2 = tutorial.board.visual_rect(0)
	tutorial._show_replay(1)
	check(tutorial.board.visual_rect(0).is_equal_approx(start_rect), "tutorial retarget begins at currently drawn pose")
	await settle(0.5)
	app.ui.close()

func coaching() -> void:
	app._start_match("local", 1, 0, "yaneuraou")
	app.game.set_initial("8k/9/4p4/9/4R4/9/9/9/K8 b - 1")
	app._refresh()
	app.ui.close()
	app.active = true
	app.coach.enabled = true
	app.preferences.studio.animation = 0.22
	await play("5e5d")
	check(await until(func(): return not app.coach.warning.is_empty(), 20), "real engine detects hanging rook")
	if not app.coach.warning.is_empty():
		check(app.coach.warning.loss >= 300 and not app.coach.warning.best.pv.is_empty(), "warning contains evaluated loss and real alternative")
		await capture("bad-move-warning")
		check(app.ui.win_rate_label.text.contains("%"), "real evaluation displays win estimate")
		app.ui.coach_notice.pressed.emit()
		await settle(0.3)
		check(app.replay_index == 0 and app.ui.live_details.has(1), "warning opens move before mistake and good line")
		await capture("better-line")
		app.ui.preview_pv(1)
		await settle(0.6)
		check(not app.ui.pv_context.is_empty(), "good line has playable preview")
		await capture("good-line-preview")
		app.ui.stop_pv(false)
	app.ui.close()
	app._undo_move()
	check(app.coach.warning.is_empty(), "undo clears stale coach warning")
	app.coach.enabled = false
	app.coach.clear()
	if app.coach.engine != null:
		var file = FileAccess.open(output.path_join("coach-usi.txt"), FileAccess.WRITE)
		file.store_string("\n".join(app.coach.engine.transcript)); file.close()
		app.coach.engine.shutdown()
	app.game = app.Game.new()
	app._refresh()
	app.ui.show_good_line()
	app.active = true
	check(await until(func(): return app.ui.live_details.has(1), 15), "good-line shortcut launches real analysis")
	await capture("good-line-startpos")
	app.ui.live_enabled = false
	app._pause_search()
	if app.usi != null: app.usi.shutdown()
