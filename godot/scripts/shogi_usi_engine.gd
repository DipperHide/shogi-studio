class_name ShogiUSIEngine
extends Node
## Nonblocking USI process. Responses always carry the request's generation.

signal ready_changed(ready: bool)
signal analysis(request_id: int, details: Dictionary)
signal best_move(request_id: int, move: Dictionary, special: String)
signal failed(message: String)

const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Rules = preload("res://scripts/shogi_rules.gd")
const LEVELS = [
	{"name": "初学", "nodes": 80, "depth": 1, "milliseconds": 250},
	{"name": "入门", "nodes": 400, "depth": 2, "milliseconds": 400},
	{"name": "普通", "nodes": 2500, "depth": 4, "milliseconds": 700},
	{"name": "进阶", "nodes": 20000, "depth": 8, "milliseconds": 1200},
	{"name": "高手", "nodes": 180000, "depth": 18, "milliseconds": 2500},
	{"name": "最强", "nodes": 2000000, "depth": 40, "milliseconds": 5000},
]

var process: Dictionary = {}
var phase: String = "closed"
var engine_name: String = ""
var options: Dictionary = {}
var pending_bytes = PackedByteArray()
var stderr_bytes = PackedByteArray()
var deadline: int = 0
var eval_directory: String = ""
var engine_directory: String = ""
var current_request: int = -1
var request_position: ShogiRules
var queued_search: Dictionary = {}
var discard_search: bool = false
var variation_lines: Dictionary = {}
var last_error: String = ""
var transcript: Array[String] = []
var analysis_count: int = 3
var pv_interval: int = 300
var thread_count: int = 2
var hash_size: int = 64
var explicit_depth: bool = false

func available() -> bool:
	return phase in ["ready", "searching", "stopping"]

static func default_executable() -> String:
	if OS.get_name() == "Android":
		return Engine.get_singleton("ShogiPlatform").enginePath() if Engine.has_singleton("ShogiPlatform") else ""
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://../engines/yaneuraou/YaneuraOu.exe")
	return OS.get_executable_path().get_base_dir().path_join("engines/yaneuraou/YaneuraOu.exe")

func launch(executable: String = "", evaluation: String = "") -> Error:
	shutdown()
	transcript.clear()
	if executable.is_empty():
		executable = default_executable()
	eval_directory = evaluation if not evaluation.is_empty() else executable.get_base_dir().path_join("eval")
	engine_directory = executable.get_base_dir()
	if OS.get_name() == "Android":
		eval_directory = ProjectSettings.globalize_path("user://engine/eval")
		DirAccess.make_dir_recursive_absolute(eval_directory)
		var model = eval_directory.path_join("nn.bin")
		if not FileAccess.file_exists(model):
			var input = FileAccess.open("res://assets/engine/nn.bin", FileAccess.READ)
			var output = FileAccess.open(model + ".tmp", FileAccess.WRITE)
			if input == null or output == null:
				_fail("无法准备引擎评估文件")
				return ERR_CANT_CREATE
			while input.get_position() < input.get_length():
				output.store_buffer(input.get_buffer(1048576))
			output.flush()
			var error = output.get_error()
			input.close()
			output.close()
			if error != OK or DirAccess.rename_absolute(model + ".tmp", model) != OK:
				_fail("引擎评估文件写入失败")
				return ERR_CANT_CREATE
	# Godot's Android FileAccess scopes exclude /data/app/.../lib even when the
	# installed executable exists. The platform plugin validates its own packaged
	# engine with java.io.File; use that result without requesting storage access.
	var executable_exists = (not executable.is_empty() and executable == default_executable()) if OS.get_name() == "Android" else FileAccess.file_exists(executable)
	if not executable_exists or not FileAccess.file_exists(eval_directory.path_join("nn.bin")):
		_fail("未找到 YaneuraOu 引擎或评估文件")
		return ERR_FILE_NOT_FOUND
	if OS.get_name() == "Windows":
		var host = engine_directory.path_join("EngineHost.exe")
		if not FileAccess.file_exists(host):
			_fail("未找到引擎启动组件")
			return ERR_FILE_NOT_FOUND
		process = OS.execute_with_pipe(host, [executable], false)
	else:
		process = OS.execute_with_pipe(executable, [], false)
	if process.is_empty():
		_fail("无法启动 YaneuraOu 引擎")
		return ERR_CANT_FORK
	phase = "handshake"
	deadline = Time.get_ticks_msec() + 15000
	_send("usi")
	return OK

func search(position: ShogiRules, moves: Array, request_id: int, level: int = 2, analyze: bool = false, initial: String = "startpos", max_milliseconds: int = 0, limits: Dictionary = {}) -> bool:
	if not available():
		return false
	var job = {"position": position.copy(), "command": Codec.history_command(moves, initial), "request_id": request_id, "level": clampi(level, 0, LEVELS.size() - 1), "analyze": analyze, "max_ms": max_milliseconds, "limits": limits.duplicate()}
	if phase != "ready":
		queued_search = job
		cancel(false)
	else:
		_begin(job)
	return true

func cancel(clear_queue: bool = true) -> void:
	if clear_queue:
		queued_search.clear()
	if phase == "searching":
		discard_search = true
		_send("stop")
		phase = "stopping"
		deadline = Time.get_ticks_msec() + 3000

func _begin(job: Dictionary) -> void:
	current_request = job.request_id
	request_position = job.position
	discard_search = false
	variation_lines.clear()
	var budget: Dictionary = LEVELS[job.level]
	var thinking_ms: int = 8000 if job.analyze else budget.milliseconds
	if job.max_ms > 0: thinking_ms = mini(thinking_ms, maxi(20, job.max_ms))
	_set_option("MultiPV", str(analysis_count) if job.analyze else "1")
	_send(job.command)
	explicit_depth = job.limits.has("depth")
	if explicit_depth:
		_send("go depth %d" % clampi(int(job.limits.depth), 1, 30))
	elif job.limits.has("milliseconds"):
		thinking_ms = clampi(int(job.limits.milliseconds), 100, 10000)
		_send("go movetime %d" % thinking_ms)
	else:
		_send("go movetime %d nodes %d depth %d" % [thinking_ms, 3000000 if job.analyze else budget.nodes, 40 if job.analyze else budget.depth])
	phase = "searching"
	deadline = Time.get_ticks_msec() + (600000 if explicit_depth else thinking_ms + 3000)

func _send(command: String) -> void:
	if process.is_empty() or "\n" in command or "\r" in command:
		return
	_trace("> " + command)
	process.stdio.store_string(command + "\n")
	process.stdio.flush()
	if process.stdio.get_error() not in [OK, ERR_BUSY]:
		_fail("引擎通信中断")

func _set_option(option: String, value: String) -> void:
	if options.has(option):
		_send("setoption name " + option + " value " + value)

func _process(_delta: float) -> void:
	if process.is_empty():
		return
	# Both streams are drained in bounded chunks to keep rendering responsive.
	for i in range(16):
		var bytes: PackedByteArray = process.stdio.get_buffer(4096)
		pending_bytes.append_array(bytes)
		if bytes.size() < 4096:
			break
	if pending_bytes.size() > 262144:
		_fail("引擎响应超出限制")
		return
	var newline = pending_bytes.find(10)
	while newline >= 0:
		var line = pending_bytes.slice(0, newline).get_string_from_utf8().strip_edges()
		pending_bytes = pending_bytes.slice(newline + 1)
		_line(line)
		if process.is_empty():
			return
		newline = pending_bytes.find(10)
	var errors: PackedByteArray = process.stderr.get_buffer(4096)
	if not errors.is_empty():
		stderr_bytes.append_array(errors)
		if stderr_bytes.size() > 8192:
			stderr_bytes = stderr_bytes.slice(-8192)
	if not OS.is_process_running(process.pid):
		_fail("YaneuraOu 已退出，请重新启动引擎")
	elif phase != "ready" and Time.get_ticks_msec() > deadline:
		_fail("YaneuraOu 响应超时，请重试")

func _line(line: String) -> void:
	_trace("< " + line)
	if line.begins_with("id name "):
		engine_name = line.trim_prefix("id name ")
	elif line.begins_with("option name ") and " type " in line:
		options[line.trim_prefix("option name ").split(" type ")[0]] = line
	elif line == "usiok" and phase == "handshake":
		# EngineHost starts the child in its own directory, so the model path
		# remains portable even when the installation path contains Chinese.
		_set_option("EvalDir", "eval" if eval_directory == engine_directory.path_join("eval") else eval_directory)
		_set_option("FV_SCALE", "24")
		_set_option("Threads", str(thread_count))
		_set_option("USI_Hash", str(hash_size))
		_set_option("BookFile", "no_book")
		_set_option("EnteringKingRule", "CSARule27")
		_set_option("NetworkDelay", "0")
		_set_option("NetworkDelay2", "0")
		_set_option("MinimumThinkingTime", "1000")
		_set_option("PvInterval", str(clampi(pv_interval, 0, 1000)))
		_send("isready")
		phase = "loading"
		deadline = Time.get_ticks_msec() + 30000
	elif line == "readyok" and phase == "loading":
		_send("usinewgame")
		phase = "ready"
		ready_changed.emit(true)
	elif line.begins_with("info ") and phase == "searching" and not discard_search:
		if explicit_depth: deadline = Time.get_ticks_msec() + 600000
		var info = Codec.parse_info(line)
		if info.has("pv"):
			info.turn = request_position.turn
			variation_lines[info.multipv] = info
			analysis.emit(current_request, info)
	elif line.begins_with("bestmove ") and phase in ["searching", "stopping"]:
		phase = "ready"
		if not discard_search:
			var value = line.split(" ", false)[1]
			var move = Codec.parse_move(value, request_position)
			if move.is_empty() and value not in ["resign", "win", "none", "(none)"]:
				_fail("引擎返回了非法着手")
				return
			best_move.emit(current_request, move, value if move.is_empty() else "")
		if not queued_search.is_empty() and phase == "ready":
			var job = queued_search
			queued_search = {}
			_begin(job)

func _fail(message: String) -> void:
	shutdown()
	last_error = message
	phase = "error"
	failed.emit(message)

func _trace(line: String) -> void:
	transcript.append(line)
	if transcript.size() > 100:
		transcript.pop_front()

func shutdown() -> void:
	if not process.is_empty():
		var pid: int = process.pid
		# Terminate only the child process owned by this engine instance.
		if OS.is_process_running(pid):
			OS.kill(pid)
		process.stdio.close()
		process.stderr.close()
	process.clear()
	pending_bytes.clear()
	stderr_bytes.clear()
	queued_search.clear()
	options.clear()
	phase = "closed"
	current_request = -1
	ready_changed.emit(false)

func _exit_tree() -> void:
	shutdown()
