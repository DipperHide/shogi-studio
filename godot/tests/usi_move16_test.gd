extends SceneTree
const Rules = preload("res://scripts/shogi_rules.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Historic = preload("res://scripts/shogi_historic_games.gd")
var checks = 0
var comparisons = 0
var failures: Array[String] = []
var output = "res://../review/app/chessis16/usi-move-core.json"

func _initialize() -> void: call_deferred("run")

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures.append(title); printerr("USI MOVE FAIL: ", title)

func compare_position(position, title: String) -> void:
	var legal = position.legal_moves()
	var expected = {}
	for move in legal: expected[Codec.move_name(move)] = true
	var before: String = position.key()
	var mismatches: Array[String] = []
	# Exhaust all syntactically valid USI board moves and drops, including illegal
	# moves. The reference is the pre-existing, unchanged full move generator.
	for origin in range(81):
		for dest in range(81):
			for promote in [false, true]:
				var value = Codec.square_name(origin) + Codec.square_name(dest) + ("+" if promote else "")
				var accepted = not Codec.parse_move(value, position).is_empty()
				comparisons += 1
				if accepted != expected.has(value): mismatches.append(value)
	for kind in range(1, 8):
		for dest in range(81):
			var value = Codec.LETTERS[kind] + "*" + Codec.square_name(dest)
			var accepted = not Codec.parse_move(value, position).is_empty()
			comparisons += 1
			if accepted != expected.has(value): mismatches.append(value)
	check(mismatches.is_empty(), title + " agrees with full legal generator: " + str(mismatches))
	check(position.key() == before, title + " validation leaves position unchanged")

func mirror(position):
	var result = Rules.new(false)
	for i in range(81): result.board[80-i] = -position.board[i]
	result.hands[1] = position.hands[-1].duplicate()
	result.hands[-1] = position.hands[1].duplicate()
	result.turn = -position.turn
	return result

func original_parse(value: String, position) -> Dictionary:
	# Original codec baseline, retained here only for the timing comparison.
	if value.length() not in [4, 5]: return {}
	var move = {"from": -1, "to": Codec.parse_square(value.substr(2, 2)), "drop": 0, "promote": value.length() == 5}
	if value[1] == "*":
		move.drop = Codec.LETTERS.find(value[0])
		if move.drop < 1 or move.drop > 7 or value.length() != 4: return {}
	else:
		move.from = Codec.parse_square(value.substr(0, 2))
		if move.from < 0 or (value.length() == 5 and value[4] != "+"): return {}
	return move if move in position.legal_moves() else {}

func run() -> void:
	var start = Time.get_ticks_msec()
	var historic = Historic.new()
	var game = historic.game_for(historic.entries()[0])
	check(game != null and game.moves.size() >= 100, "real complete historical fixture loads")
	for ply in [0, 20, 40, 60, 80, 100, 120, 139]:
		if ply >= game.positions.size(): continue
		compare_position(game.positions[ply], "historical ply %d" % ply)
	var position = Rules.new(false)
	position.board[80] = Rules.KING
	position.board[4] = -Rules.KING
	position.board[3] = -Rules.LANCE
	position.board[5] = -Rules.LANCE
	position.board[22] = Rules.GOLD
	position.hands[1][Rules.PAWN] = 1
	position.hands[1][Rules.GOLD] = 1
	compare_position(position, "pawn drop mate versus gold drop mate")
	compare_position(mirror(position), "gote pawn drop mate")
	check(Codec.parse_move("P*5b", position).is_empty(), "uchi-fuzume explicitly rejected")
	check(not Codec.parse_move("G*5b", position).is_empty(), "non-pawn drop mate explicitly accepted")
	position.board[3] = 0
	check(not Codec.parse_move("P*5b", position).is_empty(), "pawn check with escape accepted")
	compare_position(position, "pawn drop with king escape")
	position = Rules.new(false)
	position.board[76] = Rules.KING
	position.board[0] = -Rules.KING
	position.board[4] = -Rules.ROOK
	position.board[67] = Rules.GOLD
	for kind in range(1, 8): position.hands[1][kind] = 1
	position.board[11] = Rules.LANCE
	position.board[20] = Rules.KNIGHT
	position.board[56] = Rules.PAWN
	position.board[60] = 9
	compare_position(position, "pins forced promotion nifu promoted pawn and all drops")
	compare_position(mirror(position), "mirrored pins promotion and all drops")
	position.board[67] = 0
	compare_position(position, "check evasion by movement and interposition")
	compare_position(mirror(position), "gote check evasion")
	for value in ["", "7g", "7g7f++", "7g7f?", "0a1a", "1a0a", "1j1i", "P*5e+", "K*5e", "p*5e", "X*5e", "9a9a"]:
		check(Codec.parse_move(value, position).is_empty(), "malformed or impossible USI rejected: " + value)
	# Preserve a before/after timing measurement from the same actual saved lines.
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://../review/app/chessis16/ui/actual-report.json"))
	var root = Rules.new()
	for value in ["7g7f", "3c3d"]: root = root.after(Codec.parse_move(value, root))
	var benchmark = {}
	for mode in ["full_generator", "single_move"]:
		var began = Time.get_ticks_usec()
		var labels = []
		for candidate in data.samples[2].candidates:
			var current = root.copy()
			for value in candidate.pv:
				var parsed = original_parse(value, current) if mode == "full_generator" else Codec.parse_move(value, current)
				if parsed.is_empty(): break
				labels.append(current.notation(parsed))
				current = current.after(parsed)
		benchmark[mode] = {"milliseconds": (Time.get_ticks_usec()-began)/1000.0, "labels": labels}
	benchmark["input"] = {"initial_sfen":Codec.sfen(root), "candidates":data.samples[2].candidates}
	check(benchmark.full_generator.labels == benchmark.single_move.labels and not benchmark.single_move.labels.is_empty(), "optimized PV formatting preserves complete notation")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"comparisons":comparisons,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-start,"benchmark":benchmark},"  "))
	print("USI MOVE 16: ", checks, " checks; ", comparisons, " comparisons; ", failures, " benchmark ms ", benchmark.full_generator.milliseconds, " -> ", benchmark.single_move.milliseconds)
	quit(0 if failures.is_empty() else 1)
