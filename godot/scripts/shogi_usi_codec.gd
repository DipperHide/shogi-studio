class_name ShogiUSICodec
extends RefCounted

const Rules = preload("res://scripts/shogi_rules.gd")
const LETTERS = " PLNSGBRK"

static func square_name(square: int) -> String:
	if square < 0 or square >= 81:
		return ""
	return str(9 - square % 9) + String.chr(97 + square / 9)

static func parse_square(value: String) -> int:
	if value.length() != 2 or value[0] < "1" or value[0] > "9" or value[1] < "a" or value[1] > "i":
		return -1
	return (value.unicode_at(1) - 97) * 9 + 9 - int(value[0])

static func move_name(move: Dictionary) -> String:
	if move.get("drop", 0) > 0 and move.drop < 8:
		return LETTERS[move.drop] + "*" + square_name(move.to)
	return square_name(move.get("from", -1)) + square_name(move.get("to", -1)) + ("+" if move.get("promote", false) else "")

static func parse_move(value: String, position: ShogiRules) -> Dictionary:
	if value.length() not in [4, 5]:
		return {}
	var move = {"from": -1, "to": parse_square(value.substr(2, 2)), "drop": 0, "promote": value.length() == 5}
	if value[1] == "*":
		move.drop = LETTERS.find(value[0])
		if move.drop < 1 or move.drop > 7 or value.length() != 4:
			return {}
	else:
		move.from = parse_square(value.substr(0, 2))
		if move.from < 0 or (value.length() == 5 and value[4] != "+"):
			return {}
	return move if position.is_legal_move(move) else {}

static func sfen(position: ShogiRules, ply: int = 1) -> String:
	var rows: Array[String] = []
	for row in range(9):
		var value = ""
		var empty = 0
		for column in range(9):
			var piece: int = position.board[row * 9 + column]
			if piece == 0:
				empty += 1
				continue
			if empty > 0:
				value += str(empty)
				empty = 0
			var symbol: String = LETTERS[Rules.base(piece)]
			value += ("+" if absi(piece) > 8 else "") + (symbol if piece > 0 else symbol.to_lower())
		if empty > 0:
			value += str(empty)
		rows.append(value)
	var hands = ""
	for side in [1, -1]:
		for kind in [7, 6, 5, 4, 3, 2, 1]:
			var count: int = position.hands[side][kind]
			if count > 0:
				var symbol: String = LETTERS[kind]
				hands += (str(count) if count > 1 else "") + (symbol if side == 1 else symbol.to_lower())
	return "/".join(rows) + (" b " if position.turn == 1 else " w ") + ("-" if hands.is_empty() else hands) + " " + str(maxi(1, ply))

static func parse_sfen(value: String) -> ShogiRules:
	var fields = value.strip_edges().split(" ", false)
	if fields.size() != 4 or fields[1] not in ["b", "w"] or not fields[3].is_valid_int() or int(fields[3]) < 1:
		return null
	var rows = fields[0].split("/")
	if rows.size() != 9:
		return null
	var position = Rules.new(false)
	position.turn = 1 if fields[1] == "b" else -1
	for row in range(9):
		var column = 0
		var promoted = false
		for symbol in rows[row]:
			if symbol == "+":
				if promoted:
					return null
				promoted = true
			elif symbol >= "1" and symbol <= "9":
				if promoted:
					return null
				column += int(symbol)
			else:
				var kind = LETTERS.find(symbol.to_upper())
				if kind < 1 or column >= 9 or (promoted and kind in [5, 8]):
					return null
				position.board[row * 9 + column] = (kind + (8 if promoted else 0)) * (1 if symbol == symbol.to_upper() else -1)
				column += 1
				promoted = false
		if column != 9 or promoted:
			return null
	if fields[2] != "-":
		var digits = ""
		for symbol in fields[2]:
			if symbol >= "0" and symbol <= "9":
				digits += symbol
				if digits.length() > 2:
					return null
			else:
				var kind = LETTERS.find(symbol.to_upper())
				var side = 1 if symbol == symbol.to_upper() else -1
				var count = 1 if digits.is_empty() else int(digits)
				if kind < 1 or kind > 7 or count < 1 or count > 18 or position.hands[side][kind] != 0:
					return null
				position.hands[side][kind] = count
				digits = ""
		if not digits.is_empty():
			return null
	return position

static func history_command(moves: Array, initial: String = "startpos") -> String:
	var names: Array[String] = []
	for move in moves:
		names.append(move_name(move))
	return "position " + initial + (" moves " + " ".join(names) if not names.is_empty() else "")

static func parse_info(line: String) -> Dictionary:
	var tokens = line.split(" ", false)
	if tokens.is_empty() or tokens[0] != "info" or (tokens.size() > 1 and tokens[1] == "string"):
		return {}
	var out: Dictionary = {"multipv": 1}
	var i = 1
	while i < tokens.size():
		var field: String = tokens[i]
		if field in ["lowerbound", "upperbound"]:
			out.bound = field
			i += 1
			continue
		if field == "pv":
			out.pv = Array(tokens.slice(i + 1))
			break
		if field == "score" and i + 2 < tokens.size() and tokens[i + 1] in ["cp", "mate"]:
			out.score_type = tokens[i + 1]
			out.score = tokens[i + 2]
			i += 3
			continue
		if field in ["depth", "seldepth", "multipv", "nodes", "nps", "time", "hashfull"] and i + 1 < tokens.size() and tokens[i + 1].is_valid_int():
			out[field] = int(tokens[i + 1])
			i += 2
		else:
			i += 1
	return out
