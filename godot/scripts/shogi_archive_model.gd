extends RefCounted
const Historic = preload("res://scripts/shogi_historic_games.gd")

static func metadata(value: Variant, created: int = 0) -> Dictionary:
	if not value is Dictionary or not value.get("favorite",false) is bool or not value.get("tags",[]) is Array: return {}
	var stamp = value.get("created",created)
	if (not stamp is int and not stamp is float) or not is_finite(float(stamp)) or stamp < 0 or stamp != int(stamp): return {}
	if value.get("tags",[]).size() > 32: return {}
	var tags: Array = []
	for item in value.get("tags",[]):
		if not item is String or item.length() > 60: return {}
		var tag = item.strip_edges()
		if not tag.is_empty() and tag not in tags: tags.append(tag)
	return {"favorite":value.get("favorite",false),"tags":tags,"created":int(stamp)}

static func describe(path: String, data: Variant, modified: int, digest: String) -> Dictionary:
	var document: Dictionary = data if data is Dictionary else {}
	var game = document.get("game",document)
	if not game is Dictionary: game = {}
	var tags: Dictionary = game.get("metadata",{}) if game.get("metadata",{}) is Dictionary else {}
	var archive = metadata(document.get("archive",{}),modified)
	if archive.is_empty(): archive = metadata({},modified)
	var title = str(document.get("title",path.get_file().trim_suffix(".json"))).left(100)
	var first = str(tags.get("先手","")).strip_edges(); var second = str(tags.get("后手",tags.get("後手",""))).strip_edges()
	var names = title if first.is_empty() and second.is_empty() else (first if not first.is_empty() else "先手") + " vs " + (second if not second.is_empty() else "后手")
	var event = str(tags.get("棋战",tags.get("棋戦","")))
	var date = str(tags.get("开始日時",tags.get("開始日時",tags.get("日期",""))))
	if date.is_empty(): date = Time.get_datetime_string_from_unix_time(archive.created).left(10)
	var count = game.get("moves",[]).size() if game.get("moves",[]) is Array else 0
	var searchable = Historic.normalized(" ".join([title,names,event,date,str(tags)," ".join(archive.tags)]))
	return {"path":path,"title":title,"names":names,"event":event,"date":date,"plies":count,"metadata":tags.duplicate(true),
		"archive":archive,"modified":modified,"created":archive.created,"favorite":archive.favorite,"tags":archive.tags,
		"search":searchable,"sha256":digest,"readable":game.get("version")==1 and game.get("moves") is Array}

static func defaults() -> Dictionary:
	return {"query":"","favorites":0,"tags":[],"oldest":false,"sfen":""}

static func select(entries: Array, filters: Dictionary) -> Array:
	var words: Array = Array(str(filters.get("query","")).replace("　"," ").replace("\t"," ").split(" ",false)).map(Historic.normalized)
	var favorites = int(filters.get("favorites",0)); var tags: Array = filters.get("tags",[])
	var result = entries.filter(func(item):
		return (favorites==0 or item.favorite==(favorites==1)) and (tags.is_empty() or tags.any(func(tag): return tag in item.tags)) and words.all(func(word): return word in item.search)
	)
	result.sort_custom(func(a,b):
		if a.created==b.created: return a.path<b.path if filters.get("oldest",false) else a.path>b.path
		return a.created<b.created if filters.get("oldest",false) else a.created>b.created
	)
	return result

static func all_tags(entries: Array) -> Array:
	var result = []
	for entry in entries:
		for tag in entry.tags:
			if tag not in result: result.append(tag)
	result.sort()
	return result
