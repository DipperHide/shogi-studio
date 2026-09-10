extends RefCounted
## Accuracy insight data uses the same measured inputs as the main report.
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Classification = preload("res://scripts/shogi_move_classification.gd")
const Move = preload("res://scripts/shogi_report_move.gd")
const MODEL = "shogi-accuracy-insight-17-reference-adapted"

static func build(report, side: int) -> Dictionary:
	var result = {"model":MODEL, "side":side, "player":report.player_name(side), "overall":report.summary(side), "points":[], "impact":{}, "analyzed_plies":report.rows.size()}
	var scored: Array = []
	for row in report.rows:
		var metrics: Dictionary = row.get("metrics", {})
		if row.side != side or metrics.is_empty() or metrics.get("book", false) or metrics.get("weight", 0) <= 0: continue
		if row.ply <= 0 or row.ply >= report.samples.size(): continue
		scored.append(row)
		result.points.append({"ply":row.ply, "label":row.label, "category":row.category,
			"accuracy":clampf(float(metrics.accuracy),0,100), "before":report.samples[row.ply-1].duplicate(true), "after":report.samples[row.ply].duplicate(true)})
	# a2/p.d: remove one scored move at a time, compare the unpenalized aggregate,
	# then break equal gains by lower move accuracy and earlier original ply.
	if scored.size() >= 2 and result.overall.has_accuracy:
		var candidate = {}
		for i in range(scored.size()):
			var remaining = scored.duplicate()
			remaining.remove_at(i)
			var without = Metrics.aggregate(remaining,side,1,2147483647,false)
			if not without.has_accuracy: continue
			var entry = {"ply":scored[i].ply, "accuracy":scored[i].metrics.accuracy,
				"without":without.accuracy, "gain":roundf(maxf(0,without.accuracy-result.overall.accuracy)*10)/10}
			if prefers(entry,candidate): candidate=entry
		if candidate.get("gain",0) >= 0.5: result.impact=candidate
	return result

static func prefers(a: Dictionary, b: Dictionary) -> bool:
	if b.is_empty(): return true
	if a.gain != b.gain: return a.gain > b.gain
	if a.accuracy != b.accuracy: return a.accuracy < b.accuracy
	return a.ply < b.ply

static func state_label(sample: Dictionary) -> String:
	var cp = roundi(Classification.score(sample,1))
	if absi(cp) < 50: return "大致均势"
	var side = "先手" if cp > 0 else "后手"
	if absi(cp) < 250: return side + "略优"
	return side + ("明显占优" if absi(cp) < 600 else "胜势")

static func accuracy_label(point: Dictionary) -> String:
	if point.accuracy >= 100 and point.category in Classification.BAD: return "不适用（局面已定）"
	return "%.1f" % Metrics.rounded(point.accuracy)

static func engine_label(point: Dictionary) -> String:
	return "引擎：%s（%s）→ %s（%s）" % [Move.score_label(point.before),state_label(point.before),Move.score_label(point.after),state_label(point.after)]
