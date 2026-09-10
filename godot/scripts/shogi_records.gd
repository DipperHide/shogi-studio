extends RefCounted
## Records are independent from the active session. Every read replays legal moves.
const Game = preload("res://scripts/shogi_game.gd")
var root: String = "user://records"
var error: String = ""

func read(path: String):
	error = ""
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 2097152:
		error = "这份棋谱无法读取。"
		return null
	var parser = JSON.new()
	var data = parser.data if parser.parse(f.get_as_text()) == OK else null
	var game = Game.from_data(data.get("game", data) if data is Dictionary else data)
	if game == null: error = "这份棋谱无法读取。"
	return game

func write(path: String, game, title: String) -> bool:
	error = ""
	var serialized = JSON.stringify({"record_version": 1, "title": title.strip_edges().left(100), "game": game.to_data()}, "\t")
	if serialized.to_utf8_buffer().size() > Game.MAX_SAVE_BYTES:
		error = "棋谱文件过大，请拆分变化或缩短注释后保存。"
		return false
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		error = "无法建立棋谱目录"
		return false
	var f = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		error = "保存棋谱失败"
		return false
	f.store_string(serialized)
	f.flush()
	var code = f.get_error()
	f.close()
	if code != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "保存棋谱失败"
		return false
	return true

func archive(game, title: String = "") -> String:
	var stamp = Time.get_datetime_string_from_system().replace(":", "-")
	var path = root.path_join(stamp + "-" + str(Time.get_ticks_usec()) + ".json")
	return path if write(path, game, stamp if title.is_empty() else title) else ""

func list_all() -> Array:
	var result: Array = []
	var dir = DirAccess.open(root)
	if dir == null: return result
	for name in dir.get_files():
		if not name.ends_with(".json"): continue
		var path = root.path_join(name)
		var f = FileAccess.open(path, FileAccess.READ)
		if f == null or f.get_length() > 2097152: continue
		var parser = JSON.new()
		var data = parser.data if parser.parse(f.get_as_text()) == OK else null
		var title = str(data.get("title", name.trim_suffix(".json"))) if data is Dictionary else name
		result.append({"path": path, "title": title, "modified": FileAccess.get_modified_time(path)})
	result.sort_custom(func(a, b): return a.modified > b.modified)
	return result

func rename_record(path: String, title: String) -> bool:
	if title.strip_edges().is_empty():
		error = "请输入棋谱名称"
		return false
	var game = read(path)
	return game != null and write(path, game, title)

func delete_record(path: String) -> bool:
	if path.get_base_dir() != root or not path.ends_with(".json"): return false
	var success = DirAccess.remove_absolute(path) == OK
	if not success: error = "删除失败，请重试"
	return success

func migrate(destination: String, legacy_paths: Array):
	var current = Game.load_from(destination)
	if current != null: return current
	var newest = null
	var newest_time = -1
	var migration_error = ""
	for path in legacy_paths:
		if not path is String: continue
		var saved = Game.load_from(path)
		if saved == null: continue
		# Deterministic names make migration retryable after an interrupted write.
		var archive_path = root.path_join("legacy-" + path.get_file())
		if not FileAccess.file_exists(archive_path) and not write(archive_path, saved, path.get_file().trim_suffix(".json")):
			migration_error = error
		var stamp = FileAccess.get_modified_time(path)
		if stamp > newest_time:
			newest = saved
			newest_time = stamp
	if not migration_error.is_empty():
		error = migration_error
		return newest
	if newest != null and newest.save_to(destination) != OK:
		error = "未能保存本局"
	return newest
