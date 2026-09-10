extends RefCounted
## Reconnect credentials and game history form one atomic, recoverable snapshot.
const Game = preload("res://scripts/shogi_game.gd")
const MAX_BYTES = 1048576
var error: String = ""
var recovered: bool = false
var validated_hashes: Dictionary = {}

func write(path: String, session) -> bool:
	error = ""
	var data = {"version": 1, "game": session.game.to_data(), "is_host": session.is_host, "side": session.local_side, "room": session.room_code, "match": session.match_id, "token": session.resume_token, "transport": session.transport, "address": session.address, "port": session.port}
	var file = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "联机存档写入失败"
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var code = file.get_error()
	file.close()
	if code != OK:
		error = "联机存档写入失败"
		return false
	# A corrupt primary must not replace the last readable backup after recovery.
	var old_hash = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var valid_primary = not old_hash.is_empty() and (validated_hashes.get(path, "") == old_hash or not _read_one(path).is_empty())
	if valid_primary and DirAccess.copy_absolute(path, path + ".bak") != OK:
		error = "联机存档写入失败"
		return false
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "联机存档写入失败"
		return false
	validated_hashes[path] = FileAccess.get_sha256(path)
	return true

func read(path: String) -> Dictionary:
	error = ""
	recovered = false
	for candidate in [path, path + ".bak"]:
		var result = _read_one(candidate)
		if not result.is_empty():
			recovered = candidate != path
			return result
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		error = "联机存档无法读取，已保留原文件"
	return {}

func _read_one(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK: return {}
	var data = parser.data
	if not data is Dictionary or not _integer(data.get("version"), 1, 1) or not data.get("is_host") is bool or data.get("transport") not in ["tcp", "bluetooth"]:
		return {}
	for field in ["room", "match", "token", "address"]:
		if not data.get(field) is String or data[field].length() > 256:
			return {}
	if not _integer(data.get("side"), -1, 1) or data.side == 0 or not _integer(data.get("port"), 1024, 65535):
		return {}
	var game = Game.from_data(data.get("game"))
	if game == null:
		return {}
	game.clock_authority = data.is_host
	game.clock.paused = true
	validated_hashes[path] = FileAccess.get_sha256(path)
	return {"meta": data, "game": game}

func clear(path: String) -> bool:
	error = ""
	for candidate in [path, path + ".bak", path + ".tmp"]:
		validated_hashes.erase(candidate)
		if FileAccess.file_exists(candidate) and DirAccess.remove_absolute(candidate) != OK:
			error = "联机存档写入失败"
	return error.is_empty()

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum
