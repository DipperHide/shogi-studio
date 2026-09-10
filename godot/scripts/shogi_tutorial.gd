extends RefCounted
const Model = preload("res://scripts/shogi_tutorial_model.gd")
const Board = preload("res://scripts/shogi_tutorial_board.gd")
const Progress = preload("res://scripts/shogi_tutorial_progress.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const BOOK_PATHS = ["res://courses/hanyu-intro.json", "res://courses/hanyu-opening.json"]
const Motion = preload("res://scripts/shogi_history_motion.gd")
# Keep source IDs stable so existing learning progress survives the new catalog.
const HIDDEN_LESSONS = ["intro-welcome", "intro-professional", "opening-preface", "opening-online-column", "opening-titles-column", "opening-items-column", "opening-hands-column", "opening-styles-column", "opening-author-background"]
const TOPICS = [["开始对局", "棋子走法与禁手", "吃子与得失", "进攻手筋", "升变的时机", "将死练习", "收官与围杀", "围玉", "战法入门", "相居飞车实战", "四间飞车实战", "诘将棋", "将棋用语"], ["", "开局原则", "初形与保护", "飞车与角", "小驹的配合", "保护玉将", "序盘实战", "战法训练"]]
var replay_moves: Array = []
var menu
var books: Array = []
var progress = Progress.new()
var model = Model.new()
var book: Dictionary = {}
var lesson: Dictionary = {}
var step_index: int = 0
var generation: int = 0
var board
var feedback_label: Label
var action_column: VBoxContainer
var next_button: Button
var recorded: bool = false
var recorded_mistakes: int = 0
var load_errors: Array[String] = []
var loaded: bool = false
var progress_path: String = Progress.PATH
var replay_positions: Array = []
var replay_names: Array[String] = []
var answer_ply: int = 0
var replay_label: Label
var replay_previous: Button
var replay_next: Button

func initialize(owner_menu) -> void:
	menu = owner_menu

func _ensure_loaded() -> void:
	if loaded: return
	loaded = true
	progress.load_from(progress_path)
	load_books()

func load_books(paths: Array = BOOK_PATHS) -> void:
	books.clear()
	load_errors.clear()
	for path in paths:
		if not FileAccess.file_exists(path): load_errors.append("教材尚未制作：" + str(path).get_file()); continue
		var file = FileAccess.open(path, FileAccess.READ)
		if file == null: load_errors.append("教材暂时无法读取：" + str(path).get_file()); continue
		if file.get_length() > 16 * 1024 * 1024: file.close(); load_errors.append("教材文件过大：" + str(path).get_file()); continue
		var json = JSON.new()
		var result = json.parse(file.get_as_text())
		file.close()
		var parsed = json.data
		if result != OK or not _book_shape_valid(parsed):
			load_errors.append("教材文件格式不完整：" + str(path).get_file())
			continue
		books.append(parsed)

func _book_shape_valid(source) -> bool:
	if not source is Dictionary or source.get("schema") != 1 or not source.get("chapters") is Array or not source.get("coverage") is Array: return false
	if not source.get("id") is String or not source.get("title") is String: return false
	if not Progress._integer(source.get("page_count"), 1, 10000): return false
	var ids: Dictionary = {}
	for chapter in source.chapters:
		if not chapter is Dictionary or not chapter.get("title") is String or not chapter.get("lessons") is Array: return false
		for entry in chapter.lessons:
			if not entry is Dictionary or not entry.get("id") is String or not entry.get("title") is String or not entry.get("steps") is Array or not entry.get("pages") is Array: return false
			if entry.id.is_empty() or ids.has(entry.id) or entry.steps.size() > 1000: return false
			ids[entry.id] = true
			for step in entry.steps:
				if not step is Dictionary or not step.get("kind") is String: return false
				if step.has("source_pages") and not step.source_pages is Array: return false
				for page in step.get("source_pages", entry.pages):
					if not Progress._integer(page, 0, int(source.page_count) - 1): return false
	return true

func _page(title: String, name: String) -> VBoxContainer:
	generation += 1
	board = null
	feedback_label = null
	action_column = null
	next_button = null
	replay_positions.clear()
	replay_names.clear()
	replay_moves.clear()
	replay_label = null
	return menu._page(title, "tutorial_" + name)

func _guard(token: int, action: Callable) -> Callable:
	return func():
		if token == generation and menu.page != null and menu.page_name.begins_with("tutorial_"): action.call()

func _current_lesson(token: int) -> bool:
	return token == generation and menu.page != null and menu.page_name == "tutorial_lesson"

func _button(column: VBoxContainer, title: String, action: Callable) -> Button:
	var item = menu.button(title, _guard(generation, action))
	column.add_child(item)
	return item

func _network_active() -> bool:
	return menu.app.session != null

func show_catalog() -> void:
	_ensure_loaded()
	var column = _page("互动教程", "catalog")
	menu.banner(column, true)
	if _network_active():
		column.add_child(menu.label("联机对局期间先完成对局或退出连接，再开始教程。当前对局与棋钟继续按联机规则运行。"))
		_button(column, "返回对局", menu.close)
		return
	column.add_child(menu.label("从走法到实战，在棋盘上边学边练。答错的题会进入复习，独立做对后记为掌握。", 16))
	if not progress.error.is_empty(): column.add_child(menu.label(progress.error))
	if not progress.error.is_empty() and not progress.blocked_corrupt: _button(column, "重新保存学习进度", func(): progress.retry_save(); show_catalog())
	for error in load_errors: column.add_child(menu.label(error))
	var resume: Dictionary = progress.data.resume
	if not resume.is_empty() and resume.get("lesson", "") not in HIDDEN_LESSONS and _find_lesson(str(resume.get("book", "")), str(resume.get("lesson", ""))).size() > 0:
		_button(column, "继续上次学习", func(): open_lesson(resume.book, resume.lesson, _resume_index(resume)))
	_button(column, "复习待掌握的题", show_review)
	for item in books:
		var source: Dictionary = item
		column.add_child(menu.action_row(course_title(source), "规则、手筋与完整实战" if books.find(source) == 0 else "组阵、攻守配合与常见战法", "play", _guard(generation, func(): show_book(source)), true))
	_button(column, "重置学习进度", show_reset)

func _coverage_text(source: Dictionary) -> String:
	var counts = {"authored_verified": 0, "noninstructional_verified": 0, "pending": 0, "draft": 0}
	var seen: Dictionary = {}
	for item in source.get("coverage", []):
		if not item is Dictionary: continue
		var page = int(item.get("page", -1))
		if page < 0 or page >= int(source.get("page_count", 227)) or seen.has(page): continue
		seen[page] = true
		var status = str(item.get("status", "pending"))
		counts[status if counts.has(status) else "pending"] += 1
	counts.pending += maxi(0, int(source.get("page_count", 227)) - seen.size())
	if counts.pending == 0 and counts.draft == 0:
		var lessons = 0
		var exercises = 0
		for chapter in source.chapters:
			lessons += chapter.lessons.size()
			for entry in chapter.lessons:
				for step in entry.steps:
					if step.kind != "text": exercises += 1
		return menu.app.t("全书已编入 · %d 课 · %d 道练习。") % [lessons, exercises]
	return menu.app.t("原书 %d 页：已核实编写 %d 页，非教学页 %d 页，待制作 %d 页，待核实 %d 页。") % [source.get("page_count", 227), counts.authored_verified, counts.noninstructional_verified, counts.pending, counts.draft]

func course_title(source: Dictionary) -> String:
	return "基础入门" if books.find(source) == 0 else "开局进阶"

func visible_lessons(chapter: Dictionary) -> Array:
	return chapter.get("lessons", []).filter(func(entry): return entry.id not in HIDDEN_LESSONS and not entry.get("steps", []).is_empty())

func lesson_title(entry: Dictionary) -> String:
	return str(entry.title).trim_prefix("专栏：")

func topic_title(source: Dictionary, chapter: Dictionary) -> String:
	var course_index = books.find(source)
	var chapter_index = source.chapters.find(chapter)
	if course_index >= 0 and course_index < TOPICS.size() and chapter_index < TOPICS[course_index].size(): return TOPICS[course_index][chapter_index]
	return str(chapter.title)

func show_book(source: Dictionary) -> void:
	if _network_active(): show_catalog(); return
	var column = _page(course_title(source), "book")
	_button(column, "课程目录", show_catalog)
	for chapter in source.chapters:
		var entries = visible_lessons(chapter)
		if entries.is_empty(): continue
		var current: Dictionary = chapter
		var mastered = entries.filter(func(entry): return progress.lesson_state(source.id, entry) == "已掌握").size()
		column.add_child(menu.action_row(topic_title(source, chapter), "%d 课 · 已掌握 %d" % [entries.size(), mastered], "play", _guard(generation, func(): show_chapter(source, current)), true))

func show_chapter(source: Dictionary, chapter: Dictionary) -> void:
	var column = _page(topic_title(source, chapter), "chapter")
	_button(column, "返回" + course_title(source), func(): show_book(source))
	for entry in visible_lessons(chapter):
		var current: Dictionary = entry
		column.add_child(menu.action_row(lesson_title(current), menu.app.t(progress.lesson_state(source.id, current)), "play", _guard(generation, func(): open_lesson(source.id, current.id)), true))

func _find_lesson(book_id: String, lesson_id: String) -> Array:
	for source in books:
		if source.get("id") != book_id: continue
		for chapter in source.chapters:
			for entry in chapter.get("lessons", []):
				if entry.get("id") == lesson_id: return [source, entry]
	return []

func _resume_index(resume: Dictionary) -> int:
	var found = _find_lesson(resume.book, resume.lesson)
	if found.is_empty(): return 0
	var steps: Array = found[1].get("steps", [])
	var expected: String = resume.get("fingerprint", "")
	if expected.is_empty(): return 0
	for index in range(steps.size()):
		if Progress.fingerprint(steps[index]) == expected: return index
	return 0

func open_lesson(book_id: String, lesson_id: String, index: int = 0) -> void:
	_ensure_loaded()
	if _network_active(): show_catalog(); return
	var found = _find_lesson(book_id, lesson_id)
	if found.is_empty(): show_catalog(); return
	book = found[0]
	lesson = found[1]
	if lesson.get("steps", []).is_empty(): show_book(book); return
	step_index = clampi(index, 0, lesson.steps.size() - 1)
	_show_step()

func _show_step() -> void:
	var column = _page(lesson_title(lesson), "lesson")
	recorded = false
	recorded_mistakes = 0
	_button(column, "返回课程目录", func(): show_book(book))
	column.add_child(menu.label(menu.app.t("第 %d / %d 步") % [step_index + 1, lesson.steps.size()], 15))
	var valid = model.start(lesson.steps[step_index])
	progress.resume_at(book.id, lesson.id, step_index, Progress.fingerprint(lesson.steps[step_index]))
	if not valid:
		column.add_child(menu.label("这道题需要修订，已暂停：" + model.error))
		return
	var step: Dictionary = model.step
	column.add_child(menu.label(str(step.get("body" if step.kind == "text" else "prompt", "")).replace("本书", "本课程").replace("原书", "课程")))
	if model.position != null:
		column.add_child(menu.label("点选棋子，再点目标格。持驹可先点选后打入。" if step.kind != "targets" else "点选全部目标格，再点提交；再次点选可取消。", 15))
		board = Board.new()
		board.model = model
		board.app = menu.app
		column.add_child(board)
		var token = generation
		board.move_requested.connect(func(candidates):
			if _current_lesson(token): _select_move(candidates)
		)
		board.target_pressed.connect(func(square):
			if _current_lesson(token): model.toggle_target(square); board.queue_redraw()
		)
		board.invalid_action.connect(func(message):
			if _current_lesson(token): model._wrong(message); _refresh_answer()
		)
	if step.kind == "choice":
		for index in range(step.options.size()):
			var choice_index = index
			_button(column, str(step.options[index]), func(): model.choose(choice_index); _refresh_answer())
	if step.kind == "targets": _button(column, "提交所选格子", func(): model.submit_targets(); _refresh_answer())
	action_column = VBoxContainer.new()
	column.add_child(action_column)
	feedback_label = menu.label("")
	column.add_child(feedback_label)
	next_button = _button(column, "完成本课" if step_index == lesson.steps.size() - 1 else "下一步", _next)
	if step_index > 0: _button(column, "上一步", func(): step_index -= 1; _show_step())
	if step.kind != "text":
		_button(column, "重新练习这一步", _show_step)
		_button(column, "显示答案（记为待复习）", func(): model.reveal(); _refresh_answer())
	_refresh_answer()

func lesson_tokens(ply: int = -1) -> Array:
	var initial = Model.LessonRules.from_sfen(model.step.position)
	var position = initial.copy()
	var moves: Array = []
	var names: Array = model.step.moves if model.step.kind == "sequence" else ([model.chosen_move] + model.step.get("reply", []) if not model.chosen_move.is_empty() else [])
	for value in names:
		var move = Codec.parse_move(value, position)
		if move.is_empty(): break
		moves.append(move)
		position.apply_unchecked(move)
	var count = model.cursor if model.step.kind == "sequence" else moves.size()
	return Motion.state(initial, moves, clampi(ply if ply >= 0 else count, 0, moves.size()))

func _select_move(candidates: Array) -> void:
	if candidates.size() == 1:
		model.submit_move(Codec.move_name(candidates[0]))
		_refresh_answer()
	else:
		board.pending = true
		for child in action_column.get_children(): child.queue_free()
		action_column.add_child(menu.label("这步可以选择升变："))
		for item in candidates:
			var move: Dictionary = item
			_button(action_column, "升变" if move.promote else "不升变", func():
				if not board.pending: return
				board.pending = false
				model.submit_move(Codec.move_name(move))
				for child in action_column.get_children(): child.queue_free()
				_refresh_answer()
			)
		_button(action_column, "取消选择", func():
			board.pending = false
			for child in action_column.get_children(): child.queue_free()
		)

func _refresh_answer() -> void:
	if feedback_label == null: return
	while recorded_mistakes < model.mistakes:
		progress.note_mistake(book.id, lesson.id, step_index, Progress.fingerprint(lesson.steps[step_index]))
		recorded_mistakes += 1
	var messages: Array[String] = []
	for line in model.feedback.split("\n"): messages.append(menu.app.t(line))
	feedback_label.text = "\n".join(messages)
	if model.position != null:
		board.animate_to(lesson_tokens())
		board.queue_redraw()
		if not model.solved: feedback_label.text += ("\n" if not feedback_label.text.is_empty() else "") + menu.app.t("先手行棋" if model.position.turn == 1 else "后手行棋")
	next_button.disabled = model.step.kind != "text" and not model.solved
	if model.solved and not recorded:
		recorded = true
		progress.record(book.id, lesson.id, step_index, model.mastered(), 0, model.revealed, Progress.fingerprint(lesson.steps[step_index]))
		if model.step.kind in ["move", "sequence"]: _build_replay()
	if not progress.error.is_empty(): feedback_label.text += "\n" + menu.app.t(progress.error)

func _build_replay() -> void:
	for child in action_column.get_children(): child.queue_free()
	board.pending = false
	board.selected = -1
	board.selected_drop = 0
	var position = Model.LessonRules.from_sfen(model.step.position)
	replay_positions.append(position.copy())
	var moves: Array = model.step.moves if model.step.kind == "sequence" else [model.chosen_move] + model.step.get("reply", [])
	for value in moves:
		var move = Codec.parse_move(value, position)
		replay_moves.append(move)
		replay_names.append(position.notation(move).replace("☗", "▲").replace("☖", "△"))
		position.apply_unchecked(move)
		replay_positions.append(position.copy())
	replay_label = menu.label("")
	action_column.add_child(replay_label)
	replay_previous = _button(action_column, "示范：上一步", func(): _show_replay(answer_ply - 1))
	replay_next = _button(action_column, "示范：下一步", func(): _show_replay(answer_ply + 1))
	_button(action_column, "示范：回到起局", func(): _show_replay(0))
	_show_replay(0 if model.revealed else replay_positions.size() - 1)

func _show_replay(index: int) -> void:
	if replay_positions.is_empty(): return
	answer_ply = clampi(index, 0, replay_positions.size() - 1)
	model.position = replay_positions[answer_ply].copy()
	board.animate_to(Motion.state(replay_positions[0], replay_moves, answer_ply))
	replay_label.text = menu.app.t("示范 %d / %d 手") % [answer_ply, replay_names.size()] + " · " + (menu.app.t("起始局面") if answer_ply == 0 else replay_names[answer_ply - 1])
	replay_previous.disabled = answer_ply == 0
	replay_next.disabled = answer_ply == replay_positions.size() - 1
	board.queue_redraw()

func _next() -> void:
	if model.step.kind != "text" and not model.solved: return
	if model.step.kind == "text" and not recorded:
		recorded = true
		progress.record(book.id, lesson.id, step_index, true, 0, false, Progress.fingerprint(lesson.steps[step_index]))
	if step_index + 1 < lesson.steps.size(): step_index += 1; _show_step()
	else:
		var column = _page("本课完成", "complete")
		column.add_child(menu.label(str(lesson.title) + "：" + menu.app.t(progress.lesson_state(book.id, lesson))))
		_button(column, "返回课程目录", func(): show_book(book))
		_button(column, "重新练习本课", func(): open_lesson(book.id, lesson.id))
		_button(column, "复习待掌握的题", show_review)

func show_review() -> void:
	_ensure_loaded()
	if _network_active(): show_catalog(); return
	var column = _page("待掌握的题", "review")
	_button(column, "课程目录", show_catalog)
	var count = 0
	for source in books:
		for chapter in source.chapters:
			for entry in visible_lessons(chapter):
				for index in range(entry.get("steps", []).size()):
					var state = progress.state(source.id, entry.id, index, Progress.fingerprint(entry.steps[index]))
					if (state.get("done", false) or int(state.get("mistakes", 0)) > 0) and not state.get("mastered", false):
						count += 1
						var book_id: String = source.id
						var lesson_id: String = entry.id
						var step_id = index
						_button(column, menu.app.t("%s · 第 %d 步") % [entry.title, index + 1], func(): open_lesson(book_id, lesson_id, step_id))
	if count == 0: column.add_child(menu.label("目前没有待复习的题，可以从课程目录开始学习。"))

func show_reset() -> void:
	var column = _page("重置学习进度", "reset")
	column.add_child(menu.label("将清除学习断点、完成与掌握记录。原进度会保留一份本地备份。"))
	_button(column, "取消", show_catalog)
	_button(column, "确认重置学习进度", func(): progress.reset(); show_catalog())
