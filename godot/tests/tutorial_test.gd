extends SceneTree
const Tutorial = preload("res://scripts/shogi_tutorial.gd")
const Model = preload("res://scripts/shogi_tutorial_model.gd")
const LessonRules = preload("res://scripts/shogi_tutorial_rules.gd")
const Progress = preload("res://scripts/shogi_tutorial_progress.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var checks: int = 0
var failures: Array[String] = []
var app
var tutorial
var output: String
var source_steps: int = 0
var source_hashes: Dictionary = {}
var source_errors: Array[String] = []
var source_simulated: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, name: String) -> void:
	checks += 1
	if not value: failures.append(name); printerr("TUTORIAL FAIL: ", name)

func settle(seconds: float = 0.07) -> void:
	await create_timer(seconds).timeout

func write_json(path: String, data: Dictionary) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func click(title: String) -> void:
	await settle()
	for button in app.ui.root.find_children("*", "Button", true, false):
		if button.text != title or not button.is_visible_in_tree(): continue
		var parent = button.get_parent()
		while parent != null:
			if parent is ScrollContainer: parent.ensure_control_visible(button)
			parent = parent.get_parent()
		await settle()
		for pressed in [true, false]:
			var event = InputEventMouseButton.new()
			event.position = button.get_global_rect().get_center()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			Input.parse_input_event(event)
			Input.flush_buffered_events()
			await settle(0.015)
		return
	check(false, "visible button " + title)

func tap_square(square: String) -> void:
	var board = tutorial.board
	var parent = board.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(board)
		parent = parent.get_parent()
	await settle()
	var point = board.global_position + board.square_rect(Codec.parse_square(square)).get_center()
	for pressed in [true, false]:
		var event = InputEventScreenTouch.new()
		event.index = 0
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await settle(0.015)

func capture(name: String) -> void:
	await settle()
	RenderingServer.force_draw(false)
	await process_frame
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func drag_board() -> void:
	var board = tutorial.board
	var scroller = board.get_parent()
	while not scroller is ScrollContainer: scroller = scroller.get_parent()
	scroller.ensure_control_visible(board)
	await settle()
	var point = board.global_position + board.board_rect.get_center()
	var before_scroll = scroller.scroll_vertical
	var before_position = tutorial.model.position.key()
	var press = InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = point
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	for index in range(6):
		var event = InputEventScreenDrag.new()
		event.index = 0
		event.relative = Vector2(0, -24)
		point.y -= 24
		event.position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await settle(0.015)
	var release = InputEventScreenTouch.new()
	release.index = 0
	release.position = point
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await settle()
	check(scroller.scroll_vertical >= before_scroll + 80, "native board drag scrolls page to reach actions")
	check(tutorial.model.position.key() == before_position and board.selected == -1 and tutorial.model.selected_targets.is_empty(), "scroll gesture never selects or moves")

func fixture_steps() -> Array:
	return [
		{"kind": "text", "body": "先阅读，再动手。在独立练习盘上学习步的走法。"},
		{"kind": "choice", "prompt": "步能向哪个方向移动？", "options": ["向前一格", "横向两格"], "answer": 0, "explanation": "步向自己前方走一格。"},
		{"kind": "move", "prompt": "把 5 五的步前进一步。", "position": "9/9/9/9/4P4/9/9/9/9 b - 1", "accepted": ["5e5d"], "explanation": "先手向上前进。"},
		{"kind": "targets", "prompt": "选出金将的全部几何攻击格。", "position": "9/9/9/9/4G4/9/9/9/9 b - 1", "from": "5e", "targets": ["6d", "5d", "4d", "6e", "4e", "5f"], "explanation": "金可以走六个方向。"},
		{"kind": "sequence", "prompt": "练习开局。你执先手：先 7 六步，再 2 六步。", "position": "startpos", "moves": ["7g7f", "3c3d", "2g2f", "8c8d"], "student_side": 1, "explanation": "两次先手着法完成。"},
		{"kind": "move", "prompt": "5 三的步可走到 5 二并选择成或不成，练习选择成。", "position": "9/9/4P4/9/9/9/9/9/9 b - 1", "accepted": ["5c5b", "5c5b+"], "explanation": "升变后成为と金。"},
		{"kind": "move", "prompt": "把持驹中的步打到 5 五。", "position": "9/9/9/9/9/9/9/9/9 b P 1", "accepted": ["P*5e"], "explanation": "持驹回到棋盘。"}
	]

func pure_tests() -> void:
	var steps = fixture_steps()
	for step in steps: check(Model.validate_step(step).is_empty(), "fixture is legal " + step.kind)
	var pos = LessonRules.from_sfen(steps[2].position)
	check(pos.legal_moves().size() == 1, "partial diagram legal move with missing kings")
	check(not pos.copy().in_check(1), "copy preserves tutorial rule subclass")
	var checked = LessonRules.from_sfen("4r4/9/9/9/4K4/9/9/9/9 b - 1")
	check(checked.in_check(1), "present king still obeys check")
	var nifu = LessonRules.from_sfen("9/9/9/9/4P4/9/9/9/9 b P 1")
	check(Codec.parse_move("P*5f", nifu).is_empty(), "partial rules retain nifu")
	check(Codec.parse_move("P*4a", nifu).is_empty(), "partial rules retain dead rank rule")
	var mandatory = LessonRules.from_sfen("9/4P4/9/9/9/9/9/9/9 b - 1")
	check(Codec.parse_move("5b5a", mandatory).is_empty() and not Codec.parse_move("5b5a+", mandatory).is_empty(), "mandatory promotion remains enforced")
	var model = Model.new()
	model.start(steps[1])
	check(not model.choose(1) and model.mistakes == 1 and not model.solved, "wrong choice does not complete")
	check(model.choose(0) and model.solved and not model.mastered(), "correct after error is completed but not mastered")
	check(not model.choose(0) and model.mistakes == 1, "duplicate completed answer rejected")
	model.start(steps[1])
	model.reveal()
	check(model.solved and model.revealed and not model.mastered(), "reveal never grants mastery")
	model.start(steps[1])
	model.choose(0)
	check(model.mastered(), "fresh unaided success grants mastery")
	model.start(steps[2])
	var before = model.position.key()
	check(not model.submit_move("5e5c") and model.position.key() == before, "illegal move rejected without mutation")
	check(model.submit_move("5e5d") and model.mastered() == false, "legal move after error needs review")
	model.start(steps[3])
	model.toggle_target("5d")
	check(not model.submit_targets(), "incomplete target set rejected")
	for square in ["6d", "4d", "6e", "4e", "5f"]: model.toggle_target(square)
	check(model.submit_targets(), "exact target set accepted")
	model.start(steps[4])
	check(model.submit_move("7g7f") and model.cursor == 2 and model.position.turn == 1 and not model.solved, "opponent reply advances automatically")
	check(model.submit_move("2g2f") and model.cursor == 4 and model.mastered(), "learner completes assigned sequence")
	var invalid = steps[4].duplicate(true)
	invalid.moves = ["7g7e"]
	check(not model.start(invalid) and not model.error.is_empty(), "invalid source sequence fails closed")
	invalid = steps[2].duplicate(true)
	invalid.reply = ["1a1b"]
	check(not Model.validate_step(invalid).is_empty(), "illegal automatic reply fails validation")
	var path = output.path_join("progress-test.json")
	var saved = Progress.new()
	saved.load_from(path)
	saved.reset()
	saved.resume_at("test", "fixture", 3)
	saved.note_mistake("test", "fixture", 1)
	saved.record("test", "fixture", 1, false, 0, true)
	var restored = Progress.new()
	restored.load_from(path)
	check(restored.data.resume.step == 3 and restored.state("test", "fixture", 1).revealed, "resume and revealed state survive reload")
	check(restored.state("test", "fixture", 1).mistakes == 1, "mistakes persisted without double count")
	check(restored.reset() and restored.data.steps.is_empty(), "explicit reset clears only tutorial progress")
	var digest = Progress.fingerprint(steps[1])
	saved = Progress.new()
	saved.load_from(path)
	saved.record("test", "fixture", 1, true, 0, false, digest)
	check(saved.state("test", "fixture", 1, digest).get("mastered", false), "matching question fingerprint retains mastery")
	check(saved.state("test", "fixture", 1, Progress.fingerprint(steps[2])).is_empty(), "changed question cannot inherit old mastery")
	var invalid_path = output.path_join("unavailable-parent/progress.json")
	saved.path = invalid_path
	check(not saved.save() and not saved.blocked_corrupt, "transient save failure is retryable")
	saved.path = path
	check(saved.save() and saved.error.is_empty(), "retry saves retained progress after transient failure")
	write_json(path, {"schema": 1, "steps": {"bad": {"mastered": "yes", "mistakes": []}}, "resume": {}})
	var invalid_before = FileAccess.get_file_as_string(path)
	restored.load_from(path)
	check(restored.blocked_corrupt and not restored.save() and FileAccess.get_file_as_string(path) == invalid_before, "malformed nested records preserved and protected")
	var invalid_file = FileAccess.open(path, FileAccess.WRITE)
	invalid_file.store_string("{broken")
	invalid_file.close()
	restored.load_from(path)
	check(restored.blocked_corrupt and restored.data.steps.is_empty(), "invalid JSON handled without parser error or overwrite")
	check(restored.reset() and not restored.blocked_corrupt, "explicit reset recovers corrupt progress with backup")

func validate_books() -> void:
	var validator = Tutorial.new()
	validator.load_books()
	for path in Tutorial.BOOK_PATHS:
		source_hashes[path.get_file().get_basename()] = FileAccess.get_sha256(path)
	check(validator.load_errors.is_empty(), "both source books parse without load failures")
	for source in validator.books:
		for chapter in source.chapters:
			for entry in chapter.get("lessons", []):
				for index in range(entry.get("steps", []).size()):
					source_steps += 1
					var model = Model.new()
					model.start(entry.steps[index])
					var error = model.error
					if not error.is_empty(): source_errors.append("%s/%s/%d: %s" % [source.id, entry.id, index, error])
					else:
						match model.step.kind:
							"choice": model.choose(int(model.step.answer))
							"move": model.submit_move(model.step.accepted[0])
							"targets":
								for square in model.step.targets: model.toggle_target(square)
								model.submit_targets()
							"sequence":
								var moves_left = model.step.moves.size()
								while not model.solved and moves_left > 0:
									model.submit_move(model.step.moves[model.cursor])
									moves_left -= 1
						if model.step.kind != "text":
							source_simulated += 1
							if not model.mastered(): source_errors.append("%s/%s/%d: 无法按指定答案完成" % [source.id, entry.id, index])
		print("TUTORIAL SOURCE: ", source.id, " checked; cumulative steps: ", source_steps)
	for error in source_errors: check(false, error)
	check(source_errors.is_empty(), "all available source steps validated")

func run() -> void:
	output = ProjectSettings.globalize_path("res://../review/app/tutorial")
	DirAccess.make_dir_recursive_absolute(output)
	pure_tests()
	validate_books()
	app = preload("res://tests/tutorial_fixture_app.gd").new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	root.content_scale_size = Vector2i(360, 800)
	root.size = Vector2i(360, 800)
	await settle()
	check(not app.ui.tutorial.loaded, "menu initialization does not read course or progress files")
	tutorial = Tutorial.new()
	tutorial.initialize(app.ui)
	tutorial.loaded = true
	tutorial.progress.load_from(output.path_join("ui-progress.json"))
	tutorial.progress.reset()
	tutorial.books = [{"schema": 1, "id": "test", "title": "测试教程", "page_count": 3, "coverage": [{"page": 0, "status": "authored_verified"}], "chapters": [{"id": "chapter", "title": "基本走法", "lessons": [{"id": "fixture", "title": "步与金", "pages": [0], "summary": "真实触摸练习", "steps": fixture_steps()}]}]}]
	var active_before = app.game.position.key()
	var data_before = JSON.stringify(app.game.to_data())
	tutorial.show_catalog()
	check(tutorial._coverage_text(tutorial.books[0]).contains("待制作 2 页"), "unmapped pages visibly remain pending")
	tutorial.open_lesson("test", "fixture")
	await settle()
	await click("下一步")
	check(tutorial.step_index == 1, "text next records progress")
	await click("横向两格")
	check(not tutorial.model.solved and tutorial.next_button.disabled, "wrong input locks next")
	await click("向前一格")
	check(tutorial.model.solved and not tutorial.next_button.disabled, "correct UI choice unlocks next")
	await click("下一步")
	await tap_square("5e")
	await tap_square("5d")
	check(tutorial.model.solved and tutorial.model.position.board[Codec.parse_square("5d")] == 1, "native touch selects and moves exactly once")
	await click("下一步")
	for square in ["6d", "5d", "4d", "6e", "4e", "5f"]: await tap_square(square)
	await click("提交所选格子")
	check(tutorial.model.solved, "native target selection and submission")
	await click("下一步")
	await tap_square("7g")
	await tap_square("7f")
	check(tutorial.model.cursor == 2 and not tutorial.model.solved, "UI sequence automatically plays opponent")
	await tap_square("2g")
	await tap_square("2f")
	check(tutorial.model.solved, "UI sequence finishes assigned learner moves")
	check(tutorial.replay_positions.size() == 5, "completed sequence exposes every replay position")
	await click("示范：回到起局")
	check(tutorial.answer_ply == 0 and tutorial.model.position.key() == LessonRules.from_sfen("startpos").key(), "replay can return to initial position")
	await click("示范：下一步")
	check(tutorial.answer_ply == 1 and tutorial.model.position.board[Codec.parse_square("7f")] == 1, "replay advances one legal move")
	await click("下一步")
	await tap_square("5c")
	await tap_square("5b")
	check(tutorial.board.pending and not tutorial.model.solved, "promotion requires explicit choice")
	await click("升变")
	check(tutorial.model.solved and tutorial.model.position.board[Codec.parse_square("5b")] == 9, "promotion choice commits promoted piece")
	check(tutorial.replay_positions.back().board[Codec.parse_square("5b")] == 9, "replay preserves the learner's accepted alternative instead of replacing it with the first answer")
	await click("下一步")
	await settle()
	var board = tutorial.board
	var parent = board.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(board)
		parent = parent.get_parent()
	await settle()
	var hand_point = board.global_position + board.hands[1].get_center()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.position = hand_point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await settle(0.02)
	await tap_square("5e")
	check(tutorial.model.solved and tutorial.model.position.hands[1][1] == 0, "hand selection and legal drop through GUI")
	await click("完成本课")
	check(app.ui.page_name == "tutorial_complete", "lesson completion screen")
	tutorial.show_review()
	check(app.ui.page.find_children("*", "Button", true, false).any(func(button): return button.text == "步与金 · 第 2 步"), "mistake appears in review")
	tutorial.open_lesson("test", "fixture", 1)
	await click("向前一格")
	check(tutorial.progress.state("test", "fixture", 1).mastered, "successful review updates mastery")
	tutorial.open_lesson("test", "fixture", 4)
	await click("显示答案（记为待复习）")
	check(tutorial.model.revealed and tutorial.answer_ply == 0 and tutorial.replay_positions.size() == 5, "revealing a sequence begins a step-by-step demonstration")
	check(not tutorial.progress.state("test", "fixture", 4).mastered, "revealed sequence remains due for review")
	var stale = tutorial._guard(tutorial.generation, func(): tutorial.step_index = 99)
	tutorial.show_catalog()
	stale.call()
	check(tutorial.step_index != 99, "stale page callback rejected")
	check(app.game.position.key() == active_before and JSON.stringify(app.game.to_data()) == data_before, "active game remains unchanged after every lesson type")
	app.session = RefCounted.new()
	tutorial.show_catalog()
	check(tutorial.board == null and app.session != null, "network tutorial gate preserves session")
	app.session = null
	root.content_scale_size = Vector2i(280, 620)
	root.size = Vector2i(280, 620)
	await settle()
	tutorial.open_lesson("test", "fixture", 3)
	await settle()
	check(tutorial.board.size.x <= 240 and tutorial.board.board_rect.end.x <= tutorial.board.size.x and tutorial.board.cell >= 20, "small portrait board fits without horizontal overflow")
	await capture("portrait-280")
	await drag_board()
	await click("提交所选格子")
	check(tutorial.model.mistakes == 1, "scrolled submit button remains reachable by input")
	root.content_scale_size = Vector2i(480, 800)
	root.size = Vector2i(480, 800)
	await settle()
	tutorial.open_lesson("test", "fixture", 4)
	await capture("portrait-480")
	tutorial.load_books()
	var captured_source = false
	for source in tutorial.books:
		for chapter in source.chapters:
			for entry in chapter.get("lessons", []):
				for index in range(entry.get("steps", []).size()):
					if captured_source or entry.steps[index].get("kind") != "move": continue
					tutorial.open_lesson(source.id, entry.id, index)
					await settle()
					await capture("book-before")
					await click("显示答案（记为待复习）")
					await click("示范：下一步")
					var feedback_parent = tutorial.feedback_label.get_parent()
					while feedback_parent != null:
						if feedback_parent is ScrollContainer: feedback_parent.ensure_control_visible(tutorial.next_button)
						feedback_parent = feedback_parent.get_parent()
					await capture("book-feedback")
					captured_source = true
					break
	check(captured_source or source_steps == 0, "real course page and answer visually captured")
	for language in ["ja", "en"]:
		app.set_preference("language", language)
		tutorial.show_catalog()
		await settle()
		check(app.t("互动教程") != "互动教程", "tutorial heading translated " + language)
		check(tutorial._coverage_text(tutorial.books[0]) != "" and not tutorial._coverage_text(tutorial.books[0]).contains("原书"), "coverage template translated " + language)
		await capture("catalog-" + language)
		await click(app.t("复习待掌握的题"))
		check(app.ui.page_name == "tutorial_review", "translated review button navigates " + language)
		await click(app.t("教材目录"))
		check(app.ui.page_name == "tutorial_catalog", "translated catalog button returns " + language)
		var first_book = tutorial.books[0]
		var first_lesson = first_book.chapters[0].lessons[0]
		tutorial.open_lesson(first_book.id, first_lesson.id)
		await settle()
		check(tutorial.next_button.text in [app.t("下一步"), app.t("完成本课")], "lesson navigation translated " + language)
		await capture("lesson-" + language)
	write_json(output.path_join("tests.json"), {"checks": checks, "failures": failures, "source_steps": source_steps, "source_simulated": source_simulated, "source_errors": source_errors, "source_hashes": source_hashes})
	print("TUTORIAL CHECKS: ", checks, " failures: ", failures.size(), " source steps: ", source_steps)
	app.session = null
	app.ui.close()
	app.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
