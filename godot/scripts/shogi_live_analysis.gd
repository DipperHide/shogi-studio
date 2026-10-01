extends Node
## Debounced, staged analysis using the already-warm play engine.
var app
var enabled = true
var manual_paused = false
var cache: Dictionary = {}
var pending: Dictionary = {}
var wanted = ""
var active_key = ""
var stage = ""
var due = 0
var last_flush = 0
var started = 0
var first_result_ms = -1
var measurements: Array = []
var signature_version = ""
var signature_value = ""
var deep_requested = false

func initialize(owner_app) -> void:
	app = owner_app; enabled = not app.testing

func enter(new_session: bool = false) -> void:
	if new_session: manual_paused = false
	if app.preferences.studio.auto_analysis and not manual_paused:
		app.ui.live_enabled = true
		wanted = ""

func pause() -> void:
	manual_paused = true
	app.ui.live_enabled = false
	cancel()

func cancel() -> void:
	invalidate()
	# Analysis may be paused while the local opponent is thinking. Do not
	# invalidate its revision or discard an already selected computer move.
	if app.engine_context.get("kind") == "analysis":
		app.engine_context.clear()
		if app.usi != null: app.usi.cancel()

func invalidate() -> void:
	wanted = ""; active_key = ""; stage = ""; pending.clear()

func signature() -> String:
	var source = app._view_game()
	var count: int = source.moves.size() if app.replay_index < 0 else app.replay_index
	var settings: Dictionary = app.preferences.studio
	var engine_name: String = app.usi.engine_name if app.usi != null else ""
	var version = str([source.get_instance_id(), app.revision, count, settings.analysis_lines, settings.threads, settings.hash, engine_name])
	if version != signature_version:
		signature_version = version
		signature_value = str([app.Codec.history_command(source.moves.slice(0, count), source.initial_command()), settings.analysis_lines, settings.threads, settings.hash, engine_name, "nnue-fv24-v1"]).sha256_text()
	return signature_value

func allowed() -> bool:
	var computer_turn: bool = app.review_game == null and app.replay_index < 0 and not app._study_active() and app.game.result.is_empty() and app.game.mode == "ai" and (app.game.engine_match or app.game.position.turn != app.game.human_side)
	return app.active and app.session == null and app.ui.page == null and app.ui.live_enabled and not app.ui.report.running and app.ui.pv_context.is_empty() and not app._practice_active() and not computer_turn and player_turn()

func player_turn(source = null, position = null) -> bool:
	if source == null: source = app._view_game()
	if position == null: position = app._display_position()
	# A human/AI record keeps its seat during replay and variation editing.
	# Imported and local records have no assigned player seat.
	return source.mode != "ai" or source.engine_match or position.turn == source.human_side

func _process(_delta: float) -> void:
	if not enabled: return
	if not allowed():
		if not player_turn() and app.ui.pv_context.is_empty(): app.ui.hide_opponent_lines()
		if app.ui.live_enabled and app.ui.live_key != app._display_position().key():
			app.ui.live_details.clear(); app.ui.arrows.clear(); app.ui.clear_pv_rows()
		if not active_key.is_empty():
			cancel()
		return
	var key = signature()
	var now = Time.get_ticks_msec()
	if wanted != key or app.ui.live_key.is_empty():
		if app.engine_context.get("kind") == "analysis": cancel()
		wanted = key; active_key = ""; stage = ""; pending.clear(); due = now + 200
		app.ui.live_key = app._display_position().key()
		app.ui.live_details.clear(); app.ui.arrows.clear(); app.ui.clear_pv_rows()
		if cache.has(key):
			var entry: Dictionary = cache[key]
			for details in entry.lines.values(): app.ui.receive_info(details)
			app.ui.eval_label.text = "已缓存 · " + ("深入分析" if entry.stage == "deep" else "快速分析")
			if entry.stage in ["refine", "deep"] and not deep_requested: stage = "done"
		else: app.ui.live_text.text = app.t("准备分析…")
	if stage.is_empty() and now >= due: request(deep_requested)
	if now - last_flush >= 100: flush()

func request(deep: bool = false) -> void:
	if not allowed(): return
	if app.usi == null: app._load_engine()
	if app.usi.phase in ["closed", "error"]:
		app.ui.live_text.text = app.t("引擎暂不可用，请点击重试")
		stage = "error"
		return
	if not app.usi.available(): return
	wanted = signature(); active_key = wanted
	app.ui.live_key = app._display_position().key()
	stage = "deep" if deep else "quick"
	deep_requested = false
	started = Time.get_ticks_msec(); first_result_ms = -1
	_search()

func _search() -> void:
	if not allowed() or active_key != signature(): invalidate(); return
	var source = app._view_game()
	var count: int = source.moves.size() if app.replay_index < 0 else app.replay_index
	var lines: int = 1 if stage == "quick" else app.preferences.studio.analysis_lines
	var budget = 300 if stage == "quick" else 1700 if stage == "refine" else 8000
	app._request_engine("analysis", app._display_position(), source.moves.slice(0, count), true, {"milliseconds": budget, "multipv": lines})
	var deeper = app.ui.root.find_child("DeepenAnalysis", true, false)
	if deeper != null: deeper.text = app.t("继续深入")
	app.ui.eval_label.text = app.t("初步分析…" if stage == "quick" else "正在深入…" if stage == "deep" else "正在完善…")

func receive(details: Dictionary) -> void:
	if active_key.is_empty() or active_key != signature() or not allowed(): return
	if first_result_ms < 0: first_result_ms = Time.get_ticks_msec() - started
	pending[int(details.get("multipv", 1))] = details.duplicate(true)

func flush() -> void:
	last_flush = Time.get_ticks_msec()
	if active_key.is_empty() or active_key != signature() or not allowed(): pending.clear(); return
	for details in pending.values(): app.ui.receive_info(details)
	pending.clear()

func completed() -> void:
	if active_key.is_empty() or active_key != signature() or not allowed(): return
	flush()
	if not app.ui.live_details.is_empty():
		cache.erase(active_key)
		cache[active_key] = {"stage": stage, "lines": app.ui.live_details.duplicate(true)}
		if cache.size() > 160: cache.erase(cache.keys()[0])
	if stage == "quick":
		stage = "refine"
		_search.call_deferred()
	else:
		measurements.append({"key": active_key, "first_ms": first_result_ms, "total_ms": Time.get_ticks_msec() - started, "stage": stage})
		if measurements.size() > 160: measurements.pop_front()
		app.ui.eval_label.text = app.t("深入完成" if stage == "deep" else "快速分析") + " · " + str(app.ui.live_details.get(1, {}).get("depth", 0))
		stage = "done"

func deepen() -> void:
	manual_paused = false; app.ui.live_enabled = true
	cancel()
	deep_requested = true
	if not allowed(): return
	if app.usi == null or app.usi.phase in ["closed", "error"]: app._load_engine()
	request(true)

func failed() -> void:
	active_key = ""; pending.clear(); stage = "error"
	app.ui.live_text.text = app.t("引擎暂不可用，请点击重试")
	app.ui.live_text.show()
	var retry = app.ui.root.find_child("DeepenAnalysis", true, false)
	if retry != null: retry.text = app.t("重试分析")
