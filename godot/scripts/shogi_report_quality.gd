extends RefCounted
## C1735i.m2703b: weighted pie values, unlike the raw category table.
const GOOD = ["定式", "妙手", "锐利", "最佳", "优秀", "好棋"]
const TITLES = ["严重失误", "不够精确", "良好着手"]
const COLORS = [Color.RED, Color.YELLOW, Color.GREEN]
const BODIES = ["漏着与错失胜机可能改变对局结果。回到棋盘检查关键局面。", "包括失误，以及按半次加权并取整的不精确着手。", "包括定式、妙手、锐利、最佳、优秀和好棋。"]
const COLLAPSED = ["定式", "妙手", "锐利", "失误", "漏着"]

static func weights(counts: Dictionary) -> Array[int]:
	var good = 0
	for category in GOOD: good += maxi(0, int(counts.get(category, 0)))
	return [maxi(0, int(counts.get("漏着", 0))) + maxi(0, int(counts.get("错失胜机", 0))),
		roundi(maxi(0, int(counts.get("不精确", 0))) / 2.0 + maxi(0, int(counts.get("失误", 0)))), good]

static func percentage(values: Array, group: int) -> float:
	var total = 0
	for value in values: total += int(value)
	return 100.0 * values[group] / total if total > 0 and group >= 0 and group < values.size() else 0.0

static func row_visible(category: String, expanded: bool, counts: Array) -> bool:
	return expanded or category in COLLAPSED or (category == "错失胜机" and counts.any(func(c): return int(c.get(category, 0)) > 0))

static func next_ply(rows: Array, category: String, side: int, current: int) -> int:
	var first = -1
	for row in rows:
		if row.category != category or (side != 0 and row.side != side): continue
		if first < 0: first = int(row.ply)
		if int(row.ply) > current: return int(row.ply)
	return first
