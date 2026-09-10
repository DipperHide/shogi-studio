extends RefCounted
## Report math follows the inspected reference; the evaluation scale and phases are
## explicitly adapted to shogi. These are estimates, not a calibrated player rating.
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Openings = preload("res://scripts/shogi_openings.gd")
const CP_SCALE = 600.0 * 0.00368208
const PHASE_NAMES = {1: "开局", 2: "中局", 3: "终局"}

static func chance(score: float) -> float:
	return 100.0 / (1.0 + exp(-clampf(score / 600.0, -50, 50)))

static func rounded(value: float) -> float:
	var result = snappedf(clampf(value, 0, 100), 0.1)
	return 99.9 if value < 100 and result >= 100 else result

static func accuracy_color(value: float) -> Color:
	for entry in [[95, "24a993"], [92, "afde4d"], [90, "abda4d"], [85, "96af8b"], [80, "f7c045"], [70, "e48f2a"], [50, "c93431"]]:
		if value >= entry[0]: return Color(entry[1])
	return Color("fe0000")

static func book_prefix(source) -> int:
	# Only the shared prefix actually present in our curated opening examples counts.
	if not source.initial_sfen.is_empty(): return 0
	var longest = 0
	for line in Openings.LINES:
		var sequence = line.moves.split(" ")
		var matched = 0
		for i in range(mini(sequence.size(), source.moves.size())):
			if Codec.move_name(source.moves[i]) != sequence[i]: break
			matched += 1
		longest = maxi(longest, matched)
	return longest

static func move_metrics(before: Dictionary, after: Dictionary, side: int, is_best: bool, book: bool, choices: int) -> Dictionary:
	# Transfer the reference's ±1000-cp saturation through its win-chance scale,
	# keeping exactly the same score/600 convention as the live shogi win display.
	var a = clampf(float(before.score) * side / CP_SCALE, -1000, 1000)
	var b = clampf(float(after.score) * side / CP_SCALE, -1000, 1000)
	var before_chance = chance(a * CP_SCALE)
	var after_chance = chance(b * CP_SCALE)
	var loss = 0.0 if is_best else maxf(0, a - b)
	var wpl = 0.0 if is_best else maxf(0, before_chance - after_chance)
	var accuracy = 100.0 if wpl <= 0 else clampf(103.1668 * exp(-0.04354 * wpl) - 3.1669, 0, 100)
	return {"accuracy": accuracy, "cpl": loss, "shogi_cpl": loss * CP_SCALE, "wpl": wpl,
		"before_chance": before_chance, "after_chance": after_chance, "book": book,
		"weight": 0.0 if book or choices <= 1 else 1.0}

static func aggregate(rows: Array, side: int, start: int = 1, end: int = 2147483647, penalties: bool = true) -> Dictionary:
	var result = {"count": 0, "evaluated": 0, "book": 0, "forced": 0, "counts": {}, "has_accuracy": false,
		"accuracy": 0.0, "average_loss": 0.0, "wpl": 0.0}
	var weight = 0.0
	var sum_accuracy = 0.0
	var sum_cpl = 0.0
	var sum_wpl = 0.0
	var bad = [0.0, 0.0, 0.0]
	for row in rows:
		if row.side != side or row.ply < start or row.ply > end: continue
		result.count += 1
		result.counts[row.category] = int(result.counts.get(row.category, 0)) + 1
		var metrics: Dictionary = row.get("metrics", {})
		if metrics.is_empty(): continue
		if metrics.book: result.book += 1
		elif metrics.weight <= 0: result.forced += 1
		if metrics.weight <= 0: continue
		result.evaluated += 1
		weight += metrics.weight
		sum_accuracy += metrics.accuracy * metrics.weight
		sum_cpl += metrics.cpl * metrics.weight
		sum_wpl += metrics.wpl * metrics.weight
		var severity = ["不精确", "失误", "漏着"].find("漏着" if row.category == "错失胜机" else row.category)
		if severity >= 0:
			var saturation = (metrics.before_chance >= 95 and metrics.after_chance >= 90) or (metrics.before_chance <= 5 and metrics.after_chance <= 10)
			bad[severity] += 0.25 if saturation else 1.0
	if weight <= 0: return result
	result.has_accuracy = true
	result.average_loss = sum_cpl / weight * CP_SCALE
	result.wpl = sum_wpl / weight
	var value = sum_accuracy / weight
	if result.evaluated > 1:
		value = clampf(-1.668449 * result.wpl - 5.38865 * log(sum_cpl / weight + 10) + 0.672122 * value + 48.1131, 0, 100)
	if penalties:
		var penalty = 0.0
		for i in range(3): penalty += bad[i] * [0.25, 0.7, 1.0][i] + (bad[i] - 1) * [0.05, 0.15, 0.25][i] * bad[i] / 2
		value -= minf(6, penalty)
	result.accuracy = rounded(value)
	return result

static func king_pressure(position) -> int:
	var pressure = 0
	for side in [1, -1]:
		var king: int = position.board.find(side * 8)
		if king < 0: continue
		var threats = 0
		var attackers = 0
		var promoted = false
		for square in range(81):
			var piece: int = position.board[square]
			if piece * side >= 0 or absi(piece) == 8: continue
			var distance = maxi(absi(square % 9 - king % 9), absi(square / 9 - king / 9))
			if distance > 2: continue
			attackers += 1
			threats += 2 if distance <= 1 else 1
			if absi(piece) > 8: promoted = true; threats += 1
		# Count an actual attack formation, not a single early bishop checking a king.
		if attackers >= 2 and promoted: pressure = maxi(pressure, threats)
	return pressure

static func phases(source, samples: Array = []) -> Array:
	if source == null or source.moves.is_empty(): return []
	var result: Array = []
	var phase = 1 if source.initial_sfen.is_empty() else 2
	var start = 1
	var reason = "平手初始局面" if phase == 1 else "自定义起点按中局开始评估"
	var captures = 0
	var developed: Dictionary = {}
	for index in range(source.positions.size()):
		var position = source.positions[index]
		if index > 0:
			var move: Dictionary = source.moves[index - 1]
			var before = source.positions[index - 1]
			if before.board[int(move.to)] != 0: captures += 1
			if int(move.get("drop", 0)) == 0 and absi(before.board[int(move.from)]) > 1:
				developed[str(before.turn) + ":" + str(move.from)] = true
		var next_phase = phase
		var next_reason = reason
		if phase == 1 and (index >= 40 or (index >= 16 and (captures >= 2 or developed.size() >= 12))):
			next_phase = 2
			next_reason = "已进入交战或主要子力展开；开局最多保留前 39 手"
		if phase < 3 and ((index < samples.size() and samples[index].get("mate", false)) or king_pressure(position) >= 4):
			next_phase = 3
			next_reason = "引擎发现詰み线路" if index < samples.size() and samples[index].get("mate", false) else "成子与多枚攻子接近王，进入终盘攻防"
		var boundary = maxi(1, index)
		if next_phase != phase:
			if boundary > start: result.append({"type": phase, "name": PHASE_NAMES[phase], "start": start, "end": boundary - 1, "reason": reason})
			phase = next_phase
			start = boundary
			reason = next_reason
	result.append({"type": phase, "name": PHASE_NAMES[phase], "start": start, "end": source.moves.size(), "reason": reason})
	return result

static func span(segment: Dictionary, total: int) -> Vector2:
	# Shared half-ply boundaries align the chart, phase names and both players' bars.
	return Vector2(0 if segment.start == 1 else segment.start - 0.5, total if segment.end == total else segment.end + 0.5)
