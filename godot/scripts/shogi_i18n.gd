extends RefCounted
const CATALOG = preload("res://assets/locales/catalog.json")
const TUTORIAL_CATALOG = preload("res://assets/locales/tutorial.json")
var language: String = "zh"

func text(source: String, values: Array = []) -> String:
	var translated: String = source
	var catalog: Dictionary = TUTORIAL_CATALOG.data if TUTORIAL_CATALOG.data.has(source) else CATALOG.data
	if language != "zh" and catalog.has(source):
		translated = str(catalog[source][0 if language == "ja" else 1])
	return translated % values if not values.is_empty() else translated

func message(source: String) -> String:
	if TUTORIAL_CATALOG.data.has(source) or CATALOG.data.has(source): return text(source)
	for prefix in ["等待对手加入，房间码 "]:
		if source.begins_with(prefix): return text(prefix) + source.trim_prefix(prefix)
	return source

func result(game) -> String:
	if game.result.is_empty(): return ""
	var reason = text({"timeout": "超时", "declaration": "入玉宣言", "draw": "双方同意", "mate": "将死", "no_moves": "无合法着手", "perpetual_check": "连续王手千日手", "repetition": "千日手", "resign": "投了"}.get(game.result_code, "终局"))
	var outcome = text("和棋") if game.winner == 0 else text("先手胜" if game.winner == 1 else "后手胜")
	return outcome + " · " + reason
