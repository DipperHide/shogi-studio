extends RefCounted
## Geometry adapted from CustomLineChart; all positions refer to analyzed plies.
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Classification = preload("res://scripts/shogi_move_classification.gd")
const INSET_X = 8.0
const INSET_Y = 10.0
const ICON_SIZE = 12.0
const ICON_GAP = 2.0
const EDGE_GAP = 3.0
const MARKED = ["妙手", "锐利", "失误", "漏着", "错失胜机"]

static func plot_rect(dimensions: Vector2) -> Rect2:
	return Rect2(Vector2(INSET_X, INSET_Y), Vector2(maxf(1, dimensions.x - INSET_X * 2), maxf(1, dimensions.y - INSET_Y * 2)))

static func point(ply: float, score: float, plot: Rect2, total: int) -> Vector2:
	var scaled = clampf(score / Metrics.CP_SCALE / 1000.0, -1, 1)
	return Vector2(plot.position.x + ply / maxf(1, total) * plot.size.x, plot.position.y + (1 - scaled) * plot.size.y / 2)

static func markers(rows: Array, samples: Array, dimensions: Vector2, total: int) -> Array:
	var result = []
	var plot = plot_rect(dimensions)
	for row in rows:
		var ply = int(row.get("ply", -1))
		if row.get("category", "") not in MARKED or ply < 1 or ply >= samples.size(): continue
		if row.get("side", 0) not in [1, -1]: continue
		result.append({"ply": ply, "side": int(row.side), "category": row.category,
			"icon": Classification.ICONS[Classification.NAMES.find(row.category)],
			"point": point(ply, samples[ply].score, plot, total)})
	result.sort_custom(func(a, b): return a.ply < b.ply)
	return arrange(result, plot)

static func arrange(entries: Array, plot: Rect2) -> Array:
	var result = []
	var previous = {1: -INF, -1: -INF}
	var levels = {1: 0, -1: 0}
	var half = ICON_SIZE / 2
	var top = plot.position.y + half
	var bottom = maxf(top, plot.end.y - half)
	var spacing = ICON_SIZE + ICON_GAP
	for source in entries:
		var entry: Dictionary = source.duplicate()
		var side: int = entry.side
		var x: float = entry.point.x
		# Original DEX 00ff..012e: nearby same-side markers stack; a larger
		# gap resets their row. JADX inverted this comparison in its Java output.
		levels[side] = levels[side] + 1 if x - previous[side] < spacing else 0
		previous[side] = x
		var y = (top + EDGE_GAP if side == 1 else bottom - EDGE_GAP) + levels[side] * side * spacing
		entry.center = Vector2(x, clampf(y, top, bottom))
		entry.level = levels[side]
		entry.line_end = Vector2(x, clampf(entry.point.y, top, bottom))
		entry.line_start = entry.center + Vector2(0, side * half)
		entry.connector = absf(entry.center.y - entry.line_end.y) > half and (entry.line_end.y - entry.line_start.y) * side > 0
		result.append(entry)
	return result

static func marker_at(position: Vector2, entries: Array) -> int:
	var distance = ICON_SIZE * ICON_SIZE
	var ply = -1
	for entry in entries:
		var squared = position.distance_squared_to(entry.center)
		if squared < distance:
			ply = entry.ply
			distance = squared
	return ply
