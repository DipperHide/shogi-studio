extends Node
## Daily HTTPS catalog refresh, validated local KIF downloads and atomic cache.
signal changed
signal game_ready(game)
const Download = preload("res://scripts/shogi_kif_download.gd")
const Historic = preload("res://scripts/shogi_historic_games.gd")
const MAX_INDEX = 4194304
var storage = "user://tournaments"
var index: Dictionary = {}
var message = ""
var refreshing = false
var downloading = false
var last_checked: int = 0
var automatic = true
var config: Dictionary = {}

static func official_url(url: String) -> bool:
	return RegEx.create_from_string("^https?://live\\.shogi\\.or\\.jp/[a-z]+/[A-Za-z0-9_./-]+\\.(html|kif)$").search(url) != null and not url.contains("..")

static func valid_index(data) -> bool:
	if not data is Dictionary or data.get("schema") != 1 or not data.get("games") is Array or not data.get("updated_utc") is String: return false
	if data.games.is_empty() or data.games.size() > 10000: return false
	var ids = {}
	var digest = RegEx.create_from_string("^[0-9a-f]{64}$")
	for item in data.games:
		if not item is Dictionary: return false
		for key in ["id", "source", "kif_source", "sha256", "moves_sha256", "terminal"]:
			if not item.get(key) is String: return false
		if RegEx.create_from_string("^[A-Za-z0-9_-]{1,96}$").search(item.id) == null or ids.has(item.id): return false
		ids[item.id] = true
		if not official_url(item.source) or not item.source.ends_with(".html") or not official_url(item.kif_source) or not item.kif_source.ends_with(".kif"): return false
		if digest.search(item.sha256) == null or digest.search(item.moves_sha256) == null: return false
		if not item.get("plies") is float and not item.get("plies") is int: return false
		if item.plies != int(item.plies) or item.plies < 1 or item.plies > 1000 or not item.get("tags") is Dictionary: return false
		for key in ["先手", "後手", "開始日時", "棋戦"]:
			if not item.tags.get(key) is String or item.tags[key].is_empty() or item.tags[key].length() > 256: return false
		if not Download.TERMINALS.any(func(value): return item.terminal.contains(value)): return false
	return true

func initialize(path: String = "user://tournaments", allow_automatic: bool = true) -> void:
	storage = path
	automatic = allow_automatic
	config = JSON.parse_string(FileAccess.get_file_as_string("res://config/tournaments.json"))
	index = _read("res://assets/data/tournament-index.json")
	var saved = _read(storage.path_join("index.json"))
	if valid_index(saved) and str(saved.updated_utc) >= str(index.get("updated_utc", "")): index = saved
	if not valid_index(index): index = {"games": []}
	var state = _read(storage.path_join("state.json"))
	last_checked = int(state.get("last_checked", 0))

func entries() -> Array:
	return index.get("games", [])

func status_text() -> String:
	if not message.is_empty(): return message
	var latest = str(index.get("updated_utc", "")).left(10)
	return "%d 局近期赛事 · 目录 %s · 每日自动检查" % [entries().size(), latest]

func refresh(force: bool = false) -> void:
	if refreshing: return
	var now = int(Time.get_unix_time_from_system())
	if not force and (not automatic or (now >= last_checked and now - last_checked < int(config.check_interval_seconds))): return
	refreshing = true
	message = "正在检查赛事更新…"
	changed.emit()
	var response = await _request(str(config.index_url), MAX_INDEX)
	if response.ok:
		var data = JSON.parse_string(response.body.get_string_from_utf8())
		if valid_index(data) and str(data.updated_utc) >= str(index.get("updated_utc", "")):
			if _save("index.json", data):
				index = data
				last_checked = now
				_save("state.json", {"last_checked": now})
				message = "目录已更新 · %d 局 · %s" % [entries().size(), str(index.updated_utc).left(10)]
			else: message = "目录保存失败，已保留原有数据。"
		else: message = "目录校验失败或版本较旧，已保留原有数据。"
	else: message = "暂时无法更新，请稍后重试。已有目录和已下载棋谱仍可使用。"
	refreshing = false
	changed.emit()

func cached_game(entry: Dictionary):
	var data = _read(storage.path_join(entry.id + ".json"))
	if data.is_empty() or not data.get("kif") is String: return null
	var normalized = Download.normalize(data.kif.to_utf8_buffer())
	if normalized.get("moves_sha256", "") != entry.moves_sha256: return null
	return _validated_game(entry, normalized)

func open_game(entry: Dictionary) -> void:
	if downloading: return
	# Validate even caller-supplied metadata before constructing a filename/URL.
	if not valid_index({"schema": 1, "updated_utc": "", "games": [entry]}):
		message = "赛事信息校验失败。"; changed.emit(); return
	var game = cached_game(entry)
	if game != null: game_ready.emit(game); return
	downloading = true
	message = "正在读取官方棋谱…"
	changed.emit()
	var response = await _request(entry.kif_source, 2097152)
	game = null
	if response.ok:
		var normalized = Download.normalize(response.body)
		if normalized.get("moves_sha256", "") == entry.moves_sha256:
			game = _validated_game(entry, normalized)
			if game != null and not _save(entry.id + ".json", normalized): message = "棋谱已打开，本地保存失败。"
	if game == null: message = "官方棋谱暂不可用或校验未通过。请刷新目录后重试，也可打开官方页面。"
	elif message == "正在读取官方棋谱…": message = "棋谱已下载，可离线回放和分析。"
	downloading = false
	changed.emit()
	if game != null: game_ready.emit(game)

func _validated_game(entry: Dictionary, normalized: Dictionary):
	if normalized.get("plies", 0) != entry.plies: return null
	var combined = entry.duplicate(true)
	combined.kif = normalized.kif
	var game = Historic.new().game_for(combined)
	if game == null or game.moves.size() != int(entry.plies) or game.result.is_empty(): return null
	return game

func _request(url: String, limit: int) -> Dictionary:
	var request = HTTPRequest.new()
	request.timeout = 20
	request.body_size_limit = limit
	request.max_redirects = 0
	add_child(request)
	var error = request.request(url)
	if error != OK: request.queue_free(); return {"ok": false, "body": PackedByteArray()}
	var response = await request.request_completed
	request.queue_free()
	return {"ok": response[0] == HTTPRequest.RESULT_SUCCESS and response[1] == 200, "body": response[3]}

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_INDEX: return {}
	var data = JSON.parse_string(file.get_as_text())
	return data if data is Dictionary else {}

func _save(filename: String, data: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(storage) != OK: return false
	var target = storage.path_join(filename)
	var temporary = target + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var success = file.get_error() == OK
	file.close()
	if not success: return false
	return DirAccess.rename_absolute(temporary, target) == OK
