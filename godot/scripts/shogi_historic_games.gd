extends RefCounted
## Offline, complete tournament games with a verifiable source for every record.
const Exchange = preload("res://scripts/shogi_exchange.gd")
static var cached: Array = []
var error: String = ""

static func entries() -> Array:
	if cached.is_empty():
		var file = FileAccess.open("res://assets/data/historic-games.json", FileAccess.READ)
		if file == null: return []
		var data = JSON.parse_string(file.get_as_text())
		if data is Dictionary: cached = data.get("games", [])
	return cached

static func event_name(entry: Dictionary) -> String:
	var path: String = entry.source
	for pair in [["/ryuou/", "龙王战"], ["/oui/", "王位战"], ["/ouza/", "王座战"], ["/kiou/", "棋王战"], ["/kisei/", "棋圣战"], ["/eiou/", "叡王战"]]:
		if pair[0] in path: return pair[1]
	return str(entry.tags.get("棋戦", "其他赛事"))

static func normalized(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("　", "").replace("聪", "聡").replace("边", "辺").replace("滨", "浜").replace("龙", "竜").replace("战", "戦")

static func search(query: String, event: String = "全部赛事", year: String = "全部年份") -> Array:
	return filter_entries(entries(), query, event, year)

static func filter_entries(source: Array, query: String, event: String = "全部赛事", year: String = "全部年份") -> Array:
	var result = []
	var needle = normalized(query)
	for entry in source:
		if event != "全部赛事" and event_name(entry) != event: continue
		if year != "全部年份" and not str(entry.tags.get("開始日時", "")).begins_with(year): continue
		if not needle.is_empty() and not normalized(str(entry.tags) + event_name(entry)).contains(needle): continue
		result.append(entry)
	return result

func game_for(entry: Dictionary):
	var exchange = Exchange.new()
	var game = exchange.parse(entry.kif)
	error = exchange.error
	if game != null:
		game.metadata["先手"] = str(entry.tags.get("先手", "先手"))
		game.metadata["后手"] = str(entry.tags.get("後手", "后手"))
		game.metadata["棋战"] = str(entry.tags.get("棋戦", event_name(entry)))
		game.metadata["日期"] = str(entry.tags.get("開始日時", "")).left(10)
		game.metadata["场所"] = str(entry.tags.get("場所", ""))
		game.metadata["来源"] = entry.source
		game.metadata["棋谱来源"] = entry.kif_source
		game.metadata["来源校验"] = entry.sha256
	return game
