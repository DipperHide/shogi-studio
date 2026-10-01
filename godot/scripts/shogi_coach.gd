extends Node
## Independent, bounded analysis; delayed answers must still belong to this game.
const EngineBridge = preload("res://scripts/shogi_usi_engine.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Classification = preload("res://scripts/shogi_move_classification.gd")
var marks: Dictionary = {}
var key_cache: Dictionary = {}
var key_revision = -1
var app
var engine
var queued: Dictionary = {}
var job: Dictionary = {}
var latest: Dictionary = {}
var cache: Dictionary = {}
var warning: Dictionary = {}
var generation: int = 0
var stage: int = 0
var error: String = ""
var enabled: bool = true

static func sente_chance(details: Dictionary, turn: int) -> float:
	var score = float(details.get("score", 0)) * turn
	if details.get("score_type") == "mate": return 1.0 if score > 0 else 0.0
	return 1.0 / (1.0 + exp(-clampf(score, -12000, 12000) / 600.0))

static func global_score(details: Dictionary, turn: int) -> int:
	return int(details.get("score", 0)) * turn if details.get("score_type") != "mate" else 30000 * signi(int(details.get("score", -1))) * turn

func initialize(owner_app) -> void:
	app = owner_app
	enabled = not app.testing

func key_for(source, ply: int) -> String:
	if key_revision != app.revision: key_revision = app.revision; key_cache.clear()
	var stamp = str([source.get_instance_id(), ply, source.moves.size(), source.positions[ply].key()])
	if not key_cache.has(stamp):
		key_cache[stamp] = "%s:%d:%s" % [source.get_instance_id(), ply, Codec.history_command(source.moves.slice(0, ply), source.initial_command()).sha256_text()]
	return key_cache[stamp]

func valid(item: Dictionary) -> bool:
	return not item.is_empty() and app.session == null and app.game.get_instance_id() == item.owner and app.game.moves.size() >= item.ply and app.game.positions[item.ply].key() == item.key and key_for(app.game, item.ply) == item.cache_key

func mark_for(source, ply: int) -> int:
	return int(marks.get(key_for(source, ply), 0))

static func reliable(details: Dictionary) -> bool:
	return details.has("score") and str(details.get("bound", "")).is_empty() and (int(details.get("depth", 0)) > 0 or details.get("score_type") == "mate")

static func category(before: Dictionary, after: Dictionary) -> int:
	if not reliable(before) or not reliable(after): return 0
	# Both engine scores are side-to-move relative; the post-move side is opposite.
	return Classification.score_category(Classification.candidate_score(before), -Classification.candidate_score(after))

func committed() -> void:
	if not enabled or app.session != null or not app.preferences.studio.bad_move_warning or app.game.engine_match: return
	var ply: int = app.game.moves.size()
	if ply == 0: return
	var side: int = app.game.positions[ply - 1].turn
	if app.game.mode == "ai" and side != app.game.human_side: return
	warning.clear()
	queued = snapshot(app.game, ply)
	queued["check"] = true
	queued["before"] = app.game.positions[ply - 1].copy()
	queued["label"] = app.game.labels[ply - 1]
	queued["move"] = Codec.move_name(app.game.moves[ply - 1])
	queued["side"] = side
	queued["before_cache"] = key_for(app.game, ply - 1)
	if not job.is_empty(): _stop()

func snapshot(source, ply: int) -> Dictionary:
	return {"owner": source.get_instance_id(), "ply": ply, "key": source.positions[ply].key(), "cache_key": key_for(source, ply), "position": source.positions[ply].copy(), "moves": source.moves.slice(0, ply).duplicate(true), "initial": source.initial_command(), "check": false}

func clear() -> void:
	queued.clear()
	warning.clear()
	marks.clear()
	_stop()

func _stop() -> void:
	generation += 1
	job.clear()
	if is_instance_valid(engine): engine.cancel()

func _process(_delta: float) -> void:
	if app == null: return
	if not warning.is_empty() and (not valid(warning) or not app.preferences.studio.bad_move_warning): warning.clear()
	if not enabled or app.session != null or not app.active or app.ui.page != null or app.ui.report.running or not app.ui.pv_context.is_empty() or app._practice_active() or app._ai_allowed() or app.engine_context.get("kind") in ["play", "analysis"] or (app.live != null and app.ui.live_enabled and app.live.stage in ["", "quick", "refine", "deep"]):
		if not job.is_empty():
			if job.check and valid(job): queued = job.duplicate()
			_stop()
		return
	if not queued.is_empty() and queued.check and (not valid(queued) or not app.preferences.studio.bad_move_warning): queued.clear()
	if not job.is_empty(): return
	if queued.is_empty():
		if not app.preferences.studio.win_rate or app.ui.live_enabled or app._ai_allowed(): return
		var source = app._view_game()
		var ply: int = source.moves.size() if app.replay_index < 0 else app.replay_index
		if cache.has(key_for(source, ply)): return
		queued = snapshot(source, ply)
	if engine == null:
		engine = EngineBridge.new()
		engine.analysis_count = 1
		engine.thread_count = 1
		engine.hash_size = 32
		add_child(engine)
		engine.analysis.connect(func(id, detail):
			if id == generation and int(detail.get("multipv", 1)) == 1: latest = detail.duplicate(true)
		)
		engine.best_move.connect(_best)
		engine.failed.connect(func(message): error = message; queued.clear(); _stop())
		engine.launch()
	if engine.phase != "ready": return
	job = queued
	queued = {}
	stage = 0 if job.check else 1
	if job.check and reliable(cache.get(job.before_cache, {})):
		job["best"] = cache[job.before_cache].duplicate(true)
		stage = 1
	_search()

func _search(expected: int = -1) -> void:
	if job.is_empty() or (expected >= 0 and expected != generation): return
	generation += 1
	latest = {}
	var position = job.before if stage == 0 else job.position
	var count: int = job.ply - 1 if stage == 0 else job.ply
	if position.legal_moves().is_empty():
		latest = {"score": -1, "score_type": "mate", "pv": [], "depth": 0}
		_best.call_deferred(generation, {}, "resign")
		return
	if not engine.search(position, job.moves.slice(0, count), generation, 5, true, job.initial, 0, {"milliseconds": 500}): _stop()

func _best(id: int, _move: Dictionary, _special: String) -> void:
	if id != generation or job.is_empty(): return
	if not latest.has("score"): _stop(); return
	if stage == 0:
		job["best"] = latest.duplicate(true)
		cache[job.before_cache] = latest.duplicate(true)
		stage = 1
		_search.call_deferred(generation)
		return
	cache[job.cache_key] = latest.duplicate(true)
	app._redraw()
	if cache.size() > 160: cache.erase(cache.keys()[0])
	if job.check and valid(job):
		var best: Dictionary = job.best
		var pv: Array = best.get("pv", [])
		var loss = maxi(0, (global_score(best, job.before.turn) - global_score(latest, job.position.turn)) * int(job.side))
		var classification = category(best, latest)
		if not pv.is_empty() and pv[0] == job.move: classification = 4
		marks[job.cache_key] = classification
		if marks.size() > 2000: marks.erase(marks.keys()[0])
		app.ui.ribbon_key = ""
		if classification in [8, 9, 10] and not pv.is_empty() and pv[0] != job.move:
			warning = job.duplicate(true)
			warning["loss"] = loss
			warning["category"] = Classification.NAMES[classification]
	job = {}

func _exit_tree() -> void:
	if is_instance_valid(engine): engine.shutdown()
