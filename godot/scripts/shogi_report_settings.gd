extends RefCounted
## Chessis' report controls, with complexity detection adapted to shogi's drops.
const DEFAULTS = {
	"quick_mode": "depth", "quick_time": 0.6, "quick_depth": 14,
	"deep_mode": "time", "deep_time": 1.2, "deep_depth": 18,
	"deep_lines": 1, "smart": false
}

static func normalized(value: Dictionary) -> Dictionary:
	var result = DEFAULTS.duplicate()
	for key in result:
		if not value.has(key): continue
		if typeof(value[key]) == typeof(result[key]): result[key] = value[key]
		elif (result[key] is int or result[key] is float) and (value[key] is int or value[key] is float) and is_finite(value[key]):
			result[key] = int(value[key]) if result[key] is int else float(value[key])
	for prefix in ["quick", "deep"]:
		if result[prefix + "_mode"] not in ["time", "depth"]: result[prefix + "_mode"] = DEFAULTS[prefix + "_mode"]
		var seconds: float = result[prefix + "_time"]
		result[prefix + "_time"] = snappedf(clampf(seconds, 0.1, 10), 0.1) if is_finite(seconds) else DEFAULTS[prefix + "_time"]
		result[prefix + "_depth"] = clampi(result[prefix + "_depth"], 1, 30)
	result.deep_lines = clampi(result.deep_lines, 1, 5)
	return result

static func complexity(position, legal: Array) -> int:
	# Captures/promotions, check evasions and many drop choices require the full budget.
	# Chess material-only endgame shortcuts are unsuitable: shogi pieces return as drops.
	if position.in_check(position.turn): return 2
	var tactical = 0
	var drops = 0
	for move in legal:
		if int(move.get("drop", 0)) > 0: drops += 1
		elif position.board[int(move.to)] != 0 or bool(move.get("promote", false)): tactical += 1
	if tactical >= 4 or drops >= 12: return 2
	if tactical > 0 or drops > 0: return 1
	return 0

static func limits(value: Dictionary, deep: bool, position, legal: Array) -> Dictionary:
	var settings = normalized(value)
	var prefix = "deep" if deep else "quick"
	var tier = complexity(position, legal) if settings.smart else 2
	if settings[prefix + "_mode"] == "depth":
		var depth: int = settings[prefix + "_depth"]
		return {"depth": mini(depth, [12, 18, 30][tier]), "complexity": tier}
	var milliseconds = roundi(settings[prefix + "_time"] * 1000)
	if tier == 0: milliseconds = mini(milliseconds, maxi(500, roundi(milliseconds * 0.15)))
	elif tier == 1: milliseconds = mini(milliseconds, maxi(2000, roundi(milliseconds * 0.5)))
	return {"milliseconds": milliseconds, "complexity": tier}
