extends RefCounted
const PATH = "user://tutorial-progress.json"
var path: String = PATH
var data: Dictionary = {"schema": 1, "steps": {}, "resume": {}}
var error: String = ""
var blocked_corrupt: bool = false
var blocked_read: bool = false

func load_from(value: String = PATH) -> void:
	path = value
	data = {"schema": 1, "steps": {}, "resume": {}}
	error = ""
	blocked_corrupt = false
	blocked_read = false
	if not FileAccess.file_exists(path): return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: blocked_read = true; error = "学习记录暂时无法读取，原文件已受保护。可稍后重试保存。"; return
	if file.get_length() > 4 * 1024 * 1024: file.close(); _corrupt(); return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK: _corrupt(); return
	var parsed = json.data
	if not parsed is Dictionary or parsed.get("schema") != 1 or not parsed.get("steps") is Dictionary or not parsed.get("resume") is Dictionary: _corrupt(); return
	if parsed.steps.size() > 20000: _corrupt(); return
	for key in parsed.steps:
		var item = parsed.steps[key]
		if not key is String or key.length() > 512 or not item is Dictionary: _corrupt(); return
		for field in ["done", "mastered", "revealed"]:
			if item.has(field) and not item[field] is bool: _corrupt(); return
		for field in ["mistakes", "attempts"]:
			if item.has(field) and not _integer(item[field], 0, 10000000): _corrupt(); return
		if item.has("fingerprint") and (not item.fingerprint is String or item.fingerprint.length() != 64): _corrupt(); return
	var resume: Dictionary = parsed.resume
	if not resume.is_empty():
		if not resume.get("book") is String or not resume.get("lesson") is String or not _integer(resume.get("step"), 0, 20000): _corrupt(); return
		if resume.has("fingerprint") and (not resume.fingerprint is String or resume.fingerprint.length() != 64): _corrupt(); return
	data = parsed

func _corrupt() -> void:
	blocked_corrupt = true
	error = "学习记录无法读取，已保留原文件。"

static func _integer(value, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and int(value) == value and value >= minimum and value <= maximum

static func fingerprint(step: Dictionary) -> String:
	return JSON.stringify(step).sha256_text()

func save() -> bool:
	if blocked_corrupt or blocked_read: return false
	error = ""
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: error = "学习进度保存失败。"; return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var result = file.get_error()
	file.close()
	if result != OK or DirAccess.rename_absolute(temporary, path) != OK:
		error = "学习进度保存失败。"
		return false
	return true

func retry_save() -> bool:
	if blocked_read:
		var pending = data.duplicate(true)
		load_from(path)
		if blocked_read or blocked_corrupt: return false
		for key in pending.steps:
			data.steps[key] = pending.steps[key]
		if not pending.resume.is_empty(): data.resume = pending.resume
	return save()

func key(book: String, lesson: String, index: int) -> String:
	return book + "/" + lesson + "/" + str(index)

func state(book: String, lesson: String, index: int, expected_fingerprint: String = "") -> Dictionary:
	var item = data.steps.get(key(book, lesson, index), {})
	if not expected_fingerprint.is_empty() and (not item is Dictionary or item.get("fingerprint", "") != expected_fingerprint): return {}
	return item if item is Dictionary else {}

func resume_at(book: String, lesson: String, index: int, content_fingerprint: String = "") -> void:
	data.resume = {"book": book, "lesson": lesson, "step": index}
	if not content_fingerprint.is_empty(): data.resume.fingerprint = content_fingerprint
	save()

func record(book: String, lesson: String, index: int, mastered: bool, mistakes: int, revealed: bool, content_fingerprint: String = "") -> void:
	var old = state(book, lesson, index, content_fingerprint)
	data.steps[key(book, lesson, index)] = {"done": true, "mastered": mastered, "mistakes": int(old.get("mistakes", 0)) + mistakes, "revealed": revealed, "attempts": int(old.get("attempts", 0)) + 1}
	if not content_fingerprint.is_empty(): data.steps[key(book, lesson, index)].fingerprint = content_fingerprint
	save()

func note_mistake(book: String, lesson: String, index: int, content_fingerprint: String = "") -> void:
	var old = state(book, lesson, index, content_fingerprint).duplicate()
	old["mastered"] = false
	old["mistakes"] = int(old.get("mistakes", 0)) + 1
	if not content_fingerprint.is_empty(): old.fingerprint = content_fingerprint
	data.steps[key(book, lesson, index)] = old
	save()

func lesson_state(book: String, lesson: Dictionary) -> String:
	if lesson.get("steps", []).is_empty(): return "待制作"
	var completed = 0
	var mastered = 0
	for index in range(lesson.steps.size()):
		var item = state(book, lesson.id, index, fingerprint(lesson.steps[index]))
		if item.get("done", false): completed += 1
		if item.get("mastered", false): mastered += 1
	if mastered == lesson.steps.size(): return "已掌握"
	if completed == lesson.steps.size(): return "已完成 · 待复习"
	return "未开始" if completed == 0 else "学习中"

func reset() -> bool:
	# Explicit confirmation belongs to the tutorial page. A corrupt original is backed up.
	if FileAccess.file_exists(path):
		var backup = path + ".before-reset-" + str(Time.get_unix_time_from_system())
		if DirAccess.copy_absolute(path, backup) != OK: error = "无法备份学习记录，尚未重置。"; return false
	error = ""
	blocked_corrupt = false
	blocked_read = false
	data = {"schema": 1, "steps": {}, "resume": {}}
	return save()
