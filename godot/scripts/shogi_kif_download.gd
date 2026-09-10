extends RefCounted
## Decode official UTF-8/CP932 KIFs and retain only game facts and main-line moves.
const TAGS = ["先手", "後手", "開始日時", "終了日時", "棋戦", "戦型", "場所", "持ち時間", "手合割"]
const TERMINALS = ["投了", "詰み", "千日手", "持将棋", "切れ負け"]
static var cp932: String = ""

static func decode(raw: PackedByteArray) -> String:
	# Validate UTF-8 before decoding to avoid engine error output on Shift JIS.
	var valid_utf8 = true
	var i = 0
	while i < raw.size():
		var byte = raw[i]
		if byte < 128: i += 1; continue
		var count = 2 if byte >= 0xc2 and byte <= 0xdf else 3 if byte >= 0xe0 and byte <= 0xef else 4 if byte >= 0xf0 and byte <= 0xf4 else 0
		if count == 0 or i + count > raw.size(): valid_utf8 = false; break
		for j in range(1, count):
			if raw[i + j] < 0x80 or raw[i + j] > 0xbf: valid_utf8 = false
		if (byte == 0xe0 and raw[i+1] < 0xa0) or (byte == 0xed and raw[i+1] >= 0xa0) or (byte == 0xf0 and raw[i+1] < 0x90) or (byte == 0xf4 and raw[i+1] >= 0x90): valid_utf8 = false
		if not valid_utf8: break
		i += count
	if valid_utf8: return raw.get_string_from_utf8().trim_prefix(String.chr(0xfeff))
	if cp932.is_empty(): cp932 = FileAccess.get_file_as_string("res://assets/data/cp932.txt")
	var result = ""
	i = 0
	while i < raw.size():
		var byte = raw[i]
		if byte < 0x80: result += String.chr(byte)
		elif byte >= 0xa1 and byte <= 0xdf: result += String.chr(0xff61 + byte - 0xa1)
		elif (byte >= 0x81 and byte <= 0x9f) or (byte >= 0xe0 and byte <= 0xfc):
			if i + 1 >= raw.size(): return ""
			var trail = raw[i + 1]
			if trail < 0x40 or trail > 0xfc or trail == 0x7f: return ""
			var row = byte - 0x81 if byte <= 0x9f else byte - 0xe0 + 31
			var index = row * 189 + trail - 0x40
			if index >= cp932.length() or cp932[index] == "�": return ""
			result += cp932[index]
			i += 1
		else: return ""
		i += 1
	return result

static func normalize(raw: PackedByteArray) -> Dictionary:
	if raw.size() > 2097152: return {}
	var source = decode(raw)
	var tags = {}
	var moves: Array[String] = []
	var pattern = RegEx.create_from_string("^(\\d+)\\s+(.+)")
	var timer = RegEx.create_from_string("\\s+\\(")
	for text_line in source.replace("\r", "").split("\n"):
		var line = text_line.strip_edges()
		if line.is_empty() or line.begins_with("*") or line.begins_with("#"): continue
		var colon = line.find("：")
		if colon >= 0 and line.left(colon) in TAGS:
			var value = line.substr(colon + 1).strip_edges()
			# Godot strip_edges() does not trim the Japanese fullwidth space
			# used to pad the official handicap header (e.g. "平手　　").
			while value.begins_with("　"): value = value.substr(1).strip_edges()
			while value.ends_with("　"): value = value.left(-1).strip_edges()
			tags[line.left(colon)] = value
		var found = pattern.search(line)
		if found != null:
			if int(found.get_string(1)) != moves.size() + 1: return {}
			var token = found.get_string(2)
			var time_match = timer.search(token)
			if time_match != null: token = token.left(time_match.get_start())
			token = token.replace(" ", "").replace("　", "")
			moves.append("%d %s" % [moves.size() + 1, token])
	if moves.size() < 2 or moves.size() > 1001: return {}
	if not TERMINALS.any(func(value): return moves[-1].contains(value)): return {}
	for key in ["先手", "後手", "開始日時", "棋戦"]:
		if str(tags.get(key, "")).is_empty(): return {}
	var facts: Array[String] = []
	for key in TAGS:
		if tags.has(key): facts.append(key + "：" + tags[key])
	return {"tags": tags, "plies": moves.size() - 1, "terminal": moves[-1],
		"kif": "\n".join(facts) + "\n手数----指手---------消費時間--\n" + "\n".join(moves),
		"moves_sha256": "\n".join(moves).sha256_text()}
