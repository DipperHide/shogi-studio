extends RefCounted
## Text interchange is parsed into legal positions before it reaches the app.
const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const CSA = ["", "FU", "KY", "KE", "GI", "KI", "KA", "HI", "OU", "TO", "NY", "NK", "NG", "", "UM", "RY"]
var error: String = ""

func parse(source: String):
	error = ""
	if source.length() > 2097152: return fail("棋谱文件过大。")
	var text = source.strip_edges().trim_prefix("\ufeff")
	if text.begins_with("{"):
		var data = JSON.parse_string(text)
		var game = Game.from_data(data.get("game", data) if data is Dictionary else data)
		return game if game != null else fail("JSON 棋谱损坏或包含非法着手。")
	if text.begins_with("position ") or text.begins_with("startpos") or text.begins_with("sfen "):
		return parse_usi(text.trim_prefix("position "))
	if text.split("\n")[0].count("/") == 8: return parse_usi("sfen " + text)
	if text.contains("\nPI") or text.begins_with("PI") or text.begins_with("V2") or text.contains("\nP1"): return parse_csa(text)
	return parse_kif(text)

func fail(message: String):
	error = message
	return null

func parse_usi(text: String):
	var parts = text.split(" moves ")
	var game = Game.new()
	game.mode = "local"
	if parts[0] != "startpos" and (not parts[0].begins_with("sfen ") or not game.set_initial(parts[0].trim_prefix("sfen "))): return fail("SFEN 局面无效，请检查棋子、持驹和行棋方。")
	if parts.size() > 2: return fail("USI 格式无效。")
	if parts.size() == 2:
		for value in parts[1].split(" ", false):
			var move = Codec.parse_move(value, game.position)
			if move.is_empty() or not game.play(move): return fail("第 %d 手不合法：%s" % [game.moves.size() + 1, value])
	return game

func parse_csa(text: String):
	var game = Game.new()
	game.mode = "local"
	var pos = Game.Rules.new(false)
	var custom = false
	var started = false
	for raw in text.split("\n"):
		var line = raw.trim_suffix("\r") if raw.begins_with("P") and raw.length() > 1 and raw[1] in "123456789" else raw.strip_edges()
		if line.begins_with("PI"):
			pos = Game.Rules.new()
			for i in range(2, line.length(), 4):
				var sq = csa_square(line.substr(i, 2))
				if sq < 0: return fail("CSA 让子设置无效。")
				pos.board[sq] = 0
			custom = line.length() > 2
		elif line.length() >= 2 and line[0] == "P" and line[1] in "123456789":
			if line.length() != 29: return fail("CSA 棋盘行长度无效。")
			custom = true
			for x in range(9):
				var code = line.substr(2 + x * 3, 3)
				if code == " * ": continue
				var kind = CSA.find(code.substr(1))
				if kind < 1 or code[0] not in ["+", "-"]: return fail("CSA 棋子代码无效。")
				pos.board[(int(line[1]) - 1) * 9 + x] = kind * (1 if code[0] == "+" else -1)
		elif line.begins_with("P+") or line.begins_with("P-"):
			custom = true
			var side = 1 if line[1] == "+" else -1
			for i in range(2, line.length(), 4):
				var kind = CSA.find(line.substr(i + 2, 2))
				if kind < 1: return fail("不支持该 CSA 持驹代码。")
				if line.substr(i, 2) == "00":
					if kind > 7: return fail("持驹不能包含玉或成驹。")
					pos.hands[side][kind] += 1
				else:
					var sq = csa_square(line.substr(i, 2))
					if sq < 0: return fail("CSA 坐标无效。")
					pos.board[sq] = side * kind
		elif line in ["+", "-"]:
			if not custom: pos = Game.Rules.new()
			pos.turn = 1 if line == "+" else -1
			if not game.set_initial(Codec.sfen(pos)): return fail(Game.position_error(pos))
			started = true
		elif line.length() == 7 and line[0] in ["+", "-"]:
			if not started: return fail("CSA 缺少行棋方。")
			if (1 if line[0] == "+" else -1) != game.position.turn: return fail("CSA 行棋方顺序错误。")
			var source = csa_square(line.substr(1, 2))
			var dest = csa_square(line.substr(3, 2))
			var kind = CSA.find(line.substr(5, 2))
			var found = false
			for move in game.position.legal_moves():
				if move.from == source and move.to == dest and absi(game.position.after(move).board[dest]) == kind:
					game.play(move); found = true; break
			if not found: return fail("CSA 第 %d 手不合法。" % [game.moves.size() + 1])
		elif line.begins_with("N+"): game.metadata["先手"] = line.substr(2)
		elif line.begins_with("N-"): game.metadata["后手"] = line.substr(2)
		elif line.begins_with("' "): game.comments[str(game.moves.size())] = str(game.comments.get(str(game.moves.size()), "")) + line.substr(2) + "\n"
		elif line == "%TORYO": game.resign()
	return game if started else fail("未找到 CSA 棋局。")

static func csa_square(value: String) -> int:
	if value.length() != 2 or value[0] not in "123456789" or value[1] not in "123456789": return -1
	return (int(value[1]) - 1) * 9 + 9 - int(value[0])

func parse_kif(text: String):
	var game = Game.new()
	game.mode = "local"
	var pattern = RegEx.new()
	pattern.compile("^\\s*(\\d+)\\s+(.+)")
	var origin = RegEx.new()
	origin.compile("\\(([1-9])([1-9])\\)")
	var last_to = -1
	var recognized = false
	for raw in text.split("\n"):
		var line = raw.strip_edges()
		if line.begins_with("#SFEN "):
			if not game.set_initial(line.substr(6)): return fail("KIF 中的 SFEN 局面无效。")
		elif line.begins_with("*"): game.comments[str(game.moves.size())] = str(game.comments.get(str(game.moves.size()), "")) + line.substr(1) + "\n"
		elif line.contains("："):
			var pair = line.split("：", true, 1)
			if pair[0] == "手合割" and pair[1] not in ["平手", "その他"]: return fail("让子 KIF 请先转换为 CSA 或带 SFEN 的棋谱。")
			game.metadata[pair[0]] = pair[1]
		else:
			var matched = pattern.search(line)
			if matched == null: continue
			var value = matched.get_string(2).replace("　", "")
			if int(matched.get_string(1)) != game.moves.size() + 1: return fail("KIF 手数不连续。")
			if value.begins_with("投了"): game.resign(); recognized = true; break
			if value.begins_with("千日手") or value.begins_with("持将棋"):
				game.agreed_draw = true
				game.update_result()
				recognized = true
				break
			if value.begins_with("詰み"):
				game.update_result()
				if game.result.is_empty(): return fail("KIF 终局标记与局面不一致。")
				recognized = true
				break
			var dest = last_to
			if not value.begins_with("同"):
				if value.length() < 3: return fail("KIF 着手格式无效。")
				var file = "１２３４５６７８９".find(value[0]) + 1
				if file == 0 and value[0] in "123456789": file = int(value[0])
				var rank = "一二三四五六七八九".find(value[1]) + 1
				if file == 0 or rank == 0: return fail("KIF 目标坐标无效。")
				dest = (rank - 1) * 9 + 9 - file
			var source = origin.search(value)
			var found = false
			for move in game.position.legal_moves():
				if move.to != dest: continue
				if source != null and move.from != csa_square(source.get_string(1) + source.get_string(2)): continue
				if source == null and (not "打" in value or move.drop == 0): continue
				if move.drop > 0 and not value.contains(Game.Rules.NAMES[move.drop] + "打"): continue
				var prefix = value.split("(")[0]
				var promotes = prefix.ends_with("成") and not prefix.ends_with("不成")
				if move.promote != promotes: continue
				game.play(move); found = true; break
			if not found: return fail("KIF 第 %d 手无法解析或不合法。" % [game.moves.size() + 1])
			last_to = dest
			recognized = true
	return game if recognized else fail("支持 JSON、USI、SFEN、CSA 和带起点坐标的 KIF 棋谱。")

static func export_game(game, format: String) -> String:
	if format == "JSON": return JSON.stringify(game.to_data(), "  ")
	if format == "USI": return Codec.history_command(game.moves, game.initial_command())
	if format == "SFEN": return Codec.sfen(game.position, game.moves.size() + 1)
	var lines: Array[String] = []
	if format == "CSA":
		lines = ["V2.2", "N+" + str(game.metadata.get("先手", "先手")), "N-" + str(game.metadata.get("后手", "后手"))]
		var initial = game.positions[0]
		for y in range(9):
			var row = "P" + str(y + 1)
			for x in range(9):
				var piece: int = initial.board[y * 9 + x]
				row += " * " if piece == 0 else ("+" if piece > 0 else "-") + CSA[absi(piece)]
			lines.append(row)
		for side in [1, -1]:
			var hand = "P" + ("+" if side == 1 else "-")
			for kind in range(1, 8): hand += ("00" + CSA[kind]).repeat(initial.hands[side][kind])
			if hand.length() > 2: lines.append(hand)
		lines.append("+" if initial.turn == 1 else "-")
	else:
		lines = ["#KIF version=2.0 encoding=UTF-8", "#SFEN " + Codec.sfen(game.positions[0])]
		for key in game.metadata: lines.append(str(key) + "：" + str(game.metadata[key]).replace("\n", " "))
		lines.append("手数----指手---------消費時間--")
	for i in range(game.moves.size()):
		var move = game.moves[i]
		var pos = game.positions[i]
		var dest = str(9 - move.to % 9) + str(move.to / 9 + 1)
		var source = "00" if move.from < 0 else str(9 - move.from % 9) + str(move.from / 9 + 1)
		if format == "CSA": lines.append(("+" if pos.turn == 1 else "-") + source + dest + CSA[absi(game.positions[i + 1].board[move.to])])
		else:
			var name = Game.Rules.NAMES[move.drop if move.drop > 0 else absi(pos.board[move.from])]
			lines.append("%4d %s%s%s%s%s" % [i + 1, "１２３４５６７８９"[8 - move.to % 9], "一二三四五六七八九"[move.to / 9], name, "成" if move.promote else "", "打" if move.drop > 0 else "(" + source + ")"])
		for comment in str(game.comments.get(str(i + 1), "")).split("\n", false): lines.append(("' " if format == "CSA" else "*") + comment)
	if game.resigned: lines.append("%TORYO" if format == "CSA" else "%4d 投了" % [game.moves.size() + 1])
	return "\n".join(lines) + "\n"
