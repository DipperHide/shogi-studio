extends Node
## A separate USI session keeps a cancellable game report independent of live play.
signal changed
const EngineBridge = preload("res://scripts/shogi_usi_engine.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Settings = preload("res://scripts/shogi_report_settings.gd")
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Classification = preload("res://scripts/shogi_move_classification.gd")
const Story = preload("res://scripts/shogi_report_story.gd")
const CATEGORIES = ["定式", "妙手", "锐利", "最佳", "优秀", "好棋", "不精确", "失误", "漏着", "错失胜机"]
var engine
var game
var running: bool = false
var index: int = 0
var generation: int = 0
var milliseconds: int = 300
var samples: Array = []
var rows: Array = []
var latest: Dictionary = {}
var error: String = ""
var settings: Dictionary = Settings.DEFAULTS.duplicate()
var deep_report: bool = false
var resources: Dictionary = {}
var candidates: Dictionary = {}
var candidates_by_depth: Dictionary = {}
var searches: Array = []
var active_limits: Dictionary = {}
var legal_count: int = 0
var book_plies: int = 0
var phase_cache: Array = []
var phase_cache_size: int = -1
var verifying: bool = false
var verification_cursor: int = 0
var verification_searches: Array = []
var reached_endgame: bool = false

func start(source, deep: bool = false, options: Dictionary = {}, engine_options: Dictionary = {}) -> void:
	cancel()
	samples.clear()
	rows.clear()
	searches.clear()
	verification_searches.clear()
	verification_cursor = 0
	reached_endgame = false
	phase_cache.clear()
	phase_cache_size = -1
	error = ""
	game = preload("res://scripts/shogi_game.gd").from_data(source.to_data())
	if game == null: error = "棋谱无法分析。"; changed.emit(); return
	if game.moves.is_empty(): error = "请先走几步或导入一份棋谱。"; changed.emit(); return
	index = 0
	book_plies = Metrics.book_prefix(game)
	settings = Settings.normalized(options)
	deep_report = deep
	resources = engine_options.duplicate()
	_launch()

func _launch() -> void:
	running = true
	error = ""
	engine = EngineBridge.new()
	# Retain complete depth iterations even when the verification budget is shorter
	# than YaneuraOu's normal 300 ms PV output interval.
	engine.pv_interval = 0
	engine.analysis_count = settings.deep_lines if deep_report else 1
	engine.thread_count = clampi(int(resources.get("threads", 2)), 1, 8)
	engine.hash_size = clampi(int(resources.get("hash", 64)), 16, 512)
	add_child(engine)
	engine.ready_changed.connect(func(ready):
		if ready and running: _next(generation)
	)
	engine.analysis.connect(func(id, details):
		if running and id == generation:
			var line: int = int(details.get("multipv", 1))
			candidates[line] = details.duplicate(true)
			if line == 1: latest = details.duplicate(true)
			if details.has("score") and not details.get("pv", []).is_empty() and details.get("bound", "").is_empty():
				var depth = int(details.get("depth", 0))
				if not candidates_by_depth.has(depth): candidates_by_depth[depth] = {}
				candidates_by_depth[depth][line] = details.duplicate(true)
	)
	engine.best_move.connect(_best)
	engine.failed.connect(func(message): error = message; running = false; changed.emit())
	engine.launch()
	changed.emit()

func can_resume() -> bool:
	return not running and game != null and not game.moves.is_empty() and (index < game.positions.size() or verification_cursor < rows.size())

func resume() -> void:
	if not can_resume(): return
	cancel()
	_launch()

func cancel() -> void:
	running = false
	verifying = false
	generation += 1
	if is_instance_valid(engine):
		engine.shutdown()
		engine.queue_free()
	engine = null

func _next(expected: int) -> void:
	if not running or expected != generation: return
	if index >= game.positions.size():
		_verify_next(expected)
		return
	latest = {}
	candidates.clear()
	candidates_by_depth.clear()
	generation += 1
	var pos = game.positions[index]
	var legal: Array = pos.legal_moves()
	legal_count = legal.size()
	if legal.is_empty():
		latest = {"score_type": "mate", "score": "-1", "depth": 0, "pv": []}
		_best.call_deferred(generation, {}, "resign")
		return
	active_limits = Settings.limits(settings, deep_report, pos, legal)
	milliseconds = int(active_limits.get("milliseconds", 0))
	searches.append({"ply": index, "limits": active_limits.duplicate(), "lines": engine.analysis_count})
	engine.search(pos, game.moves.slice(0, index), generation, 5, true, "startpos" if game.initial_sfen.is_empty() else "sfen " + game.initial_sfen, 0, active_limits)

func _best(id: int, _move: Dictionary, _special: String) -> void:
	if not running or id != generation: return
	if verifying:
		_finish_verification()
		return
	var complete = _coherent_candidates(mini(engine.analysis_count, legal_count))
	if not complete.is_empty():
		candidates = complete
		latest = complete[1]
	if not latest.has("score"):
		error = "引擎没有返回评分，分析已停止。"
		running = false
		changed.emit()
		return
	var raw = int(latest.score)
	var score = raw if latest.get("score_type") != "mate" else (30000 if raw > 0 else -30000)
	var lines: Array = []
	var keys = candidates.keys()
	keys.sort()
	for key in keys: lines.append(candidates[key].duplicate(true))
	samples.append({"score": score * game.positions[index].turn, "depth": int(latest.get("depth", 0)), "pv": latest.get("pv", []), "mate": latest.get("score_type") == "mate", "mate_distance": raw if latest.get("score_type") == "mate" else 0, "candidates": lines, "limits": active_limits.duplicate(), "legal_count": legal_count})
	reached_endgame = reached_endgame or samples.back().mate or Metrics.king_pressure(game.positions[index]) >= 4
	if index > 0:
		var loss = maxi(0, int((samples[index - 1].score - samples[index].score) * game.positions[index - 1].turn))
		var best: String = samples[index - 1].pv[0] if not samples[index - 1].pv.is_empty() else ""
		var is_best = not best.is_empty() and best == Codec.move_name(game.moves[index - 1])
		var observed_loss = loss
		if is_best: loss = 0
		var metrics = Metrics.move_metrics(samples[index - 1], samples[index], game.positions[index - 1].turn, is_best, index <= book_plies, samples[index - 1].get("legal_count", 0))
		var row = {"ply": index, "side": game.positions[index - 1].turn, "loss": loss, "observed_loss": observed_loss, "label": game.labels[index - 1], "score": samples[index].score, "best": best, "metrics": metrics}
		row.merge(Classification.classify(game, index, samples[index - 1], samples[index], metrics, reached_endgame))
		rows.append(row)
	index += 1
	changed.emit()
	_next.call_deferred(id)

static func category_color(category: String) -> Color:
	var category_index = Classification.NAMES.find(category)
	return Color(Classification.COLORS[category_index]) if category_index >= 0 else Color("98aeb0")

static func classify(loss: int, is_best: bool) -> String:
	# Compatibility helper for callers without a before score; reports use full context.
	return "最佳" if is_best else Classification.NAMES[Classification.score_category(0, -float(loss) / Metrics.CP_SCALE)]

func progress_text() -> String:
	if not error.is_empty(): return error
	if verifying: return "正在复核关键着手 · 第 %d / %d 手" % [verification_cursor + 1, rows.size()]
	return "正在分析 %d / %d 个局面" % [samples.size(), game.positions.size()] if running else "已分析 %d 手" % rows.size()

func _verify_next(expected: int) -> void:
	if not running or expected != generation: return
	while verification_cursor < rows.size():
		var row: Dictionary = rows[verification_cursor]
		if row.classification.tactics.get("candidate", false): break
		verification_cursor += 1
	if verification_cursor >= rows.size():
		verifying = false
		running = false
		engine.shutdown()
		changed.emit()
		return
	verifying = true
	latest.clear()
	candidates.clear()
	candidates_by_depth.clear()
	generation += 1
	var ply: int = rows[verification_cursor].ply - 1
	engine.analysis_count = 2
	var limits = {"milliseconds": 100}
	verification_searches.append({"ply": ply, "limits": limits, "lines": 2, "generation": generation})
	engine.search(game.positions[ply], game.moves.slice(0, ply), generation, 5, true, game.initial_command(), 0, limits)
	changed.emit()

func _finish_verification() -> void:
	var expected = generation
	var row: Dictionary = rows[verification_cursor]
	var valid: Dictionary = {}
	var coherent = _coherent_candidates(2)
	var position = game.positions[row.ply - 1]
	for key in [1, 2]:
		if not coherent.has(key) or coherent[key].get("pv", []).is_empty(): continue
		var move = Codec.parse_move(str(coherent[key].pv[0]), position)
		if move in position.legal_moves(): valid[key] = coherent[key]
	var proof = Classification.verify_best(row, valid)
	proof.search = verification_searches.back().duplicate(true)
	row.classification.verification = proof
	if proof.accepted:
		row.category_id = proof.category_id
		row.category = Classification.NAMES[proof.category_id]
	verification_cursor += 1
	changed.emit()
	_verify_next.call_deferred(expected)

func _coherent_candidates(count: int) -> Dictionary:
	if count < 1: return {}
	var depths = candidates_by_depth.keys()
	depths.sort()
	depths.reverse()
	for depth in depths:
		var lines: Dictionary = candidates_by_depth[depth]
		var complete: Dictionary = {}
		for number in range(1, count + 1):
			if lines.has(number): complete[number] = lines[number]
		if complete.size() == count: return complete
	return {}

func score_text(ply: int) -> String:
	if ply < 0 or ply >= samples.size(): return "—"
	var sample: Dictionary = samples[ply]
	if sample.mate: return ("先手" if sample.score > 0 else "后手") + "詰み %d" % absi(int(sample.get("mate_distance", 0)))
	return "%+.2f" % (sample.score / 100.0)

func summary(side: int) -> Dictionary:
	return Metrics.aggregate(rows, side)

func story() -> Dictionary:
	return Story.build(game, samples, rows, phases(), not running and not can_resume())

func phases() -> Array:
	if phase_cache_size != samples.size():
		phase_cache = Metrics.phases(game, samples)
		phase_cache_size = samples.size()
	return phase_cache

func phase_summary(side: int, segment: Dictionary) -> Dictionary:
	return Metrics.aggregate(rows, side, segment.start, segment.end, false)

func player_name(side: int) -> String:
	var fallback = "先手" if side == 1 else "后手"
	if game == null: return fallback
	return str(game.metadata.get(fallback, game.metadata.get("後手", fallback) if side == -1 else fallback))

func _exit_tree() -> void:
	if is_instance_valid(engine): engine.shutdown()
