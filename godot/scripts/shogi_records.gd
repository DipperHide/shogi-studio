extends RefCounted
## Records are independent from the active session. Every read replays legal moves.
const Game = preload("res://scripts/shogi_game.gd")
const Archive = preload("res://scripts/shogi_archive_model.gd")
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

func document(path: String) -> Dictionary:
	var file = FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length()>Game.MAX_SAVE_BYTES: return {}
	var value = JSON.parse_string(file.get_as_text())
	return value if value is Dictionary else {}

func write(path: String, game, title: String, archive_data: Variant = null) -> bool:
	error = ""
	var created = FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else int(Time.get_unix_time_from_system())
	var meta = Archive.metadata(document(path).get("archive",{}) if archive_data == null else archive_data,created)
	if meta.is_empty(): error = "收藏或标签数据无效，棋谱未修改。"; return false
	return write_document(path,{"record_version":1,"title":title.strip_edges().left(100),"game":game.to_data(),"archive":meta})

func write_document(path: String, data: Dictionary, expected: String = "") -> bool:
	error = ""
	var serialized = JSON.stringify(data,"\t")
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
	if not expected.is_empty() and FileAccess.get_sha256(path)!=expected:
		DirAccess.remove_absolute(path+".tmp")
		error = "棋谱已被其他操作更新，请重新打开后再保存。"; return false
	if code != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "保存棋谱失败"
		return false
	return true

func archive(game, title: String = "", archive_data: Variant = null) -> String:
	var stamp = Time.get_datetime_string_from_system().replace(":", "-")
	var path = root.path_join(stamp + "-" + str(Time.get_ticks_usec()) + ".json")
	return path if write(path, game, stamp if title.is_empty() else title,archive_data) else ""

func update_metadata(path: String, metadata: Dictionary, expected: String) -> bool:
	error = ""
	if path.get_base_dir()!=root or not path.ends_with(".json"): error = "棋谱不在当前档案目录中。"; return false
	var doc = document(path)
	var meta = Archive.metadata(metadata,FileAccess.get_modified_time(path))
	if doc.is_empty() or meta.is_empty() or not doc.get("game",doc) is Dictionary: error = "棋谱或标签无法读取。"; return false
	if not doc.has("game"): doc = {"record_version":1,"title":path.get_file().trim_suffix(".json"),"game":doc}
	doc.archive = meta
	return write_document(path,doc,expected)

func list_all(cancel: Callable = Callable()) -> Array:
	var result: Array = []
	var dir = DirAccess.open(root)
	if dir == null: return result
	for name in dir.get_files():
		if cancel.is_valid() and cancel.call(): break
		if not name.ends_with(".json"): continue
		var path = root.path_join(name)
		var f = FileAccess.open(path, FileAccess.READ)
		if f == null or f.get_length() > 2097152: continue
		var source = f.get_as_text()
		var parser = JSON.new()
		var data = parser.data if parser.parse(source) == OK else null
		result.append(Archive.describe(path,data,FileAccess.get_modified_time(path),source.sha256_text()))
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
