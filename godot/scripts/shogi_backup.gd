extends RefCounted
const PREF_KEYS = ["confirm_move", "sound", "volume", "hints", "last_move", "coordinates", "auto_flip", "appearance", "color_mode", "language", "piece_font", "move_pace", "studio", "report"]
var error: String = ""

func collect(app, tutorial) -> Dictionary:
	var records: Array = []
	for entry in app.records.list_all():
		var saved = app.records.read(entry.path)
		if saved != null: records.append({"title": entry.title, "game": saved.to_data(), "archive":entry.archive})
	tutorial._ensure_loaded()
	var prefs = {}
	for key in PREF_KEYS: prefs[key] = app.preferences.get(key)
	return {"shogi_backup": 1, "created": Time.get_datetime_string_from_system(), "active": app.game.to_data(), "records": records, "preferences": prefs, "tutorial": tutorial.progress.data}.duplicate(true)

func restore(app, tutorial, data: Variant, restore_preferences: bool, restore_learning: bool) -> int:
	error = ""
	if not data is Dictionary or data.get("shogi_backup") != 1 or not data.get("records") is Array or data.records.size() > 3000:
		error = "备份格式无效。"; return -1
	var entries: Array = data.records.duplicate()
	if data.has("active"): entries.append({"title": "恢复的当前对局", "game": data.active})
	var validated: Array = []
	for entry in entries:
		if not entry is Dictionary: error = "备份内容无效。"; return -1
		var saved = app.Game.from_data(entry.get("game"))
		if saved == null: error = "备份包含损坏棋谱，未开始恢复。"; return -1
		var meta = app.records.Archive.metadata(entry.get("archive",{}),int(Time.get_unix_time_from_system()))
		if meta.is_empty(): error = "备份包含无效收藏或标签，未开始恢复。"; return -1
		validated.append({"game": saved, "title": str(entry.get("title", "恢复棋谱")).left(100),"archive":meta})
	var next_preferences
	var next_progress
	var temporary: String = app.records.root.get_base_dir().path_join("restore-validation-" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
	if restore_preferences:
		if not data.get("preferences") is Dictionary: error = "备份缺少设置。"; return -1
		var config = ConfigFile.new()
		for key in PREF_KEYS:
			if data.preferences.has(key): config.set_value("preferences", key, data.preferences[key])
		config.set_value("preferences", "ui_version", 8)
		if config.save(temporary + ".cfg") != OK: error = "无法校验设置。"; return -1
		next_preferences = app.Preferences.new()
		next_preferences.load_from(temporary + ".cfg")
		DirAccess.remove_absolute(temporary + ".cfg")
	if restore_learning:
		if not data.get("tutorial") is Dictionary: error = "备份缺少学习记录。"; return -1
		var file = FileAccess.open(temporary + ".json", FileAccess.WRITE)
		if file == null: error = "无法校验学习记录。"; return -1
		file.store_string(JSON.stringify(data.tutorial))
		file.close()
		next_progress = preload("res://scripts/shogi_tutorial_progress.gd").new()
		next_progress.load_from(temporary + ".json")
		DirAccess.remove_absolute(temporary + ".json")
		if next_progress.blocked_corrupt or next_progress.blocked_read: error = next_progress.error; return -1
	# Keep an inspectable snapshot before changing settings or learning progress.
	var snapshot_path: String = app.records.root.get_base_dir().path_join("before-restore-" + str(Time.get_ticks_usec()) + ".json")
	var snapshot = FileAccess.open(snapshot_path, FileAccess.WRITE)
	if snapshot == null: error = "无法保存恢复前备份，未修改数据。"; return -1
	snapshot.store_string(JSON.stringify(collect(app, tutorial)))
	snapshot.flush()
	if snapshot.get_error() != OK: error = "恢复前备份写入失败。"; return -1
	snapshot.close()
	var count = 0
	for entry in validated:
		if app.records.archive(entry.game, entry.title,entry.archive).is_empty(): error = "已恢复 %d 份，后续写入失败。" % count; return -1
		count += 1
	if restore_preferences:
		if not app.testing and next_preferences.save_to() != OK: error = "棋谱已恢复，设置写入失败。"; return -1
		app.preferences = next_preferences
		app.set_appearance(next_preferences.appearance)
		app.apply_preferences()
	if restore_learning:
		tutorial._ensure_loaded()
		next_progress.path = tutorial.progress.path
		if not next_progress.save(): error = next_progress.error; return -1
		tutorial.progress = next_progress
	return count
