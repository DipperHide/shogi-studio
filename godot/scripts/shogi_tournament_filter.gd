extends RefCounted
const Historic = preload("res://scripts/shogi_historic_games.gd")

static func options(entries: Array) -> Dictionary:
	var events: Array[String] = []
	var years: Array[String] = []
	for entry in entries:
		var event = Historic.event_name(entry)
		var year = str(entry.tags.get("開始日時", "")).left(4)
		if not events.has(event): events.append(event)
		if not year.is_empty() and not years.has(year): years.append(year)
	events.sort(); years.sort(); years.reverse()
	return {"events": events, "years": years}

static func select(entries: Array, query: String, events: Array, year: String) -> Array:
	var result = []
	var words = Array(query.replace("　", " ").replace("\t", " ").strip_edges().split(" ", false))
	for entry in entries:
		if not events.is_empty() and Historic.event_name(entry) not in events: continue
		if not year.is_empty() and not str(entry.tags.get("開始日時", "")).begins_with(year): continue
		var haystack = Historic.normalized(str(entry.tags) + Historic.event_name(entry))
		if not words.all(func(word): return haystack.contains(Historic.normalized(word))): continue
		result.append(entry)
	return result

static func outcome(entry: Dictionary) -> String:
	var ending = str(entry.get("terminal", ""))
	if ending.contains("千日手"): return "千日手"
	if ending.contains("持将棋"): return "持将棋"
	if ["投了", "詰み", "切れ負け"].any(func(value): return ending.contains(value)):
		return "先手胜" if int(entry.plies) % 2 == 1 else "后手胜"
	return "结果未注明"
