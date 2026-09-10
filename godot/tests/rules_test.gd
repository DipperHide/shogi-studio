extends SceneTree

const Rules = preload("res://scripts/shogi_rules.gd")
const Game = preload("res://scripts/shogi_game.gd")
const AI = preload("res://scripts/shogi_ai.gd")
var failures: Array[String] = []
var checks: int = 0
var started: int

func _initialize() -> void:
	started = Time.get_ticks_msec()
	create_timer(30).timeout.connect(func(): printerr("RULE TEST TIMEOUT"); quit(1))
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ",label)

func move(from: int, to: int, promote: bool = false, drop: int = 0) -> Dictionary:
	return {"from":from,"to":to,"promote":promote,"drop":drop}

func empty() -> ShogiRules:
	var p = Rules.new(false)
	p.board[80] = 8
	p.board[0] = -8
	return p

func perft(p: ShogiRules, depth: int) -> int:
	if depth == 0:
		return 1
	var total = 0
	for m in p.legal_moves():
		total += perft(p.after(m),depth-1)
	return total

func run() -> void:
	var p = Rules.new()
	check(p.board.filter(func(v): return v != 0).size() == 40,"initial 40 pieces")
	check(p.legal_moves().size() == 30,"initial perft 1 = 30")
	check(perft(p,2) == 900,"initial perft 2 = 900")
	check(perft(p,3) == 25470,"initial perft 3 = 25470")
	check(not p.in_check(1) and not p.in_check(-1),"initial kings safe")
	var initial_key = p.key()
	p.legal_moves()
	check(p.key() == initial_key,"move generation is pure")
	for kind in [1,2,3,4,5,6,7,8,9,10,11,12,14,15]:
		var centered = Rules.new(false)
		centered.board[40] = kind
		var expected = {1:1,2:4,3:2,4:5,5:6,6:16,7:16,8:8,9:6,10:6,11:6,12:6,14:20,15:20}
		check(centered.targets(40).size() == expected[kind],"movement count type %d" % kind)
		var first = centered.targets(40)
		centered.board[40] = -kind
		var reverse = centered.targets(40)
		check(first.all(func(s): return (80-s) in reverse),"mirrored movement type %d" % kind)
	p = empty()
	p.board[40] = 7
	p.board[31] = 1
	check(22 not in p.targets(40) and 31 in p.targets(40),"ray stops at blocker")
	check(move(40,31) not in p.legal_moves(),"cannot capture own piece")
	p = empty()
	p.board[20] = 1
	check(move(20,11) in p.legal_moves() and move(20,11,true) in p.legal_moves(),"optional promotion")
	p.board[20] = 0
	p.board[11] = 1
	check(move(11,2) not in p.legal_moves() and move(11,2,true) in p.legal_moves(),"forced pawn promotion")
	p.board[11] = 2
	check(move(11,2) not in p.legal_moves() and move(11,2,true) in p.legal_moves(),"forced lance promotion")
	p.board[11] = 0
	p.board[20] = 3
	check(move(20,1) not in p.legal_moves() and move(20,1,true) in p.legal_moves(),"forced knight promotion")
	p = empty()
	p.board[20] = 4
	check(move(20,30,true) in p.legal_moves(),"promotion when leaving zone")
	p = empty()
	p.board[40] = 7
	p.board[31] = -12
	var captured = p.after(move(40,31))
	check(captured.hands[1][4] == 1 and captured.board[31] == 7,"capture unpromotes and changes ownership")
	check(p.hands[1][4] == 0 and p.board[31] == -12,"copy does not share hands or board")
	p = empty()
	p.hands[1][1] = 1
	p.hands[1][2] = 1
	p.hands[1][3] = 1
	p.board[56] = 1
	var legal = p.legal_moves()
	check(move(-1,29,false,1) not in legal,"nifu prohibited")
	check(move(-1,3,false,1) not in legal,"pawn dead rank drop prohibited")
	check(move(-1,3,false,2) not in legal,"lance dead rank drop prohibited")
	check(move(-1,12,false,3) not in legal,"knight dead rank drop prohibited")
	check(move(-1,30,false,1) in legal,"normal pawn drop allowed")
	p.board[56] = 9
	check(move(-1,29,false,1) in p.legal_moves(),"promoted pawn does not cause nifu")
	var dropped = p.after(move(-1,29,false,1))
	check(dropped.hands[1][1] == 0 and dropped.board[29] == 1,"drop consumes hand and stays unpromoted")
	p = empty()
	p.board[80] = 0
	p.board[76] = 8
	p.board[4] = -7
	p.board[67] = 5
	check(move(67,66) not in p.legal_moves(),"pinned piece cannot expose king")
	p.board[67] = 0
	check(p.in_check(1),"rook check detected")
	p.hands[1][5] = 1
	check(move(-1,67,false,5) in p.legal_moves(),"drop can block check")
	check(move(-1,66,false,5) not in p.legal_moves(),"drop must answer check")
	p = empty()
	p.board[0] = 0
	p.board[4] = -8
	p.board[3] = -2
	p.board[5] = -2
	p.board[22] = 5
	p.hands[1][1] = 1
	check(move(-1,13,false,1) not in p.legal_moves(),"pawn drop mate prohibited")
	p.board[3] = 0
	check(move(-1,13,false,1) in p.legal_moves(),"pawn drop check with escape allowed")
	p.board[3] = -2
	p.hands[1][5] = 1
	check(move(-1,13,false,5) in p.legal_moves(),"gold drop mate allowed")
	var mate = p.after(move(-1,13,false,5))
	check(mate.in_check(-1) and mate.legal_moves().is_empty(),"mate detected without king capture")
	var game = Game.new()
	game.mode = "local"
	check(not game.play(move(54,0)),"game rejects illegal move")
	check(game.play(move(56,47)),"game accepts opening pawn")
	check(game.play(move(24,33)),"game accepts reply")
	check(game.positions[0].key() == Rules.new().key(),"history snapshots immutable")
	var restored = Game.from_data(JSON.parse_string(JSON.stringify(game.to_data())))
	check(restored != null and restored.position.key() == game.position.key(),"JSON save roundtrip")
	game.undo()
	check(game.moves.size() == 1 and game.position.turn == -1,"local undo one ply")
	game.mode = "ai"
	game.play(move(24,33))
	game.undo()
	check(game.moves.is_empty() and game.position.turn == 1,"AI undo human and AI pair")
	game.resign()
	check(not game.result.is_empty() and not game.play(move(56,47)),"resignation locks game")
	game.undo()
	check(game.result.is_empty(),"resign undo at initial position")
	for invalid in [null,{}, {"version":7,"mode":"ai","moves":[]}, {"version":1,"mode":"ai","moves":[move(999,0)]}, {"version":1,"mode":"ai","moves":[{"from":"a","to":0,"drop":0,"promote":false}]}]:
		check(Game.from_data(invalid) == null,"invalid save rejected")
	var save_path = "user://test-current-game.json"
	check(game.save_to(save_path) == OK,"first save")
	game.play(move(56,47))
	check(game.save_to(save_path) == OK,"replace save")
	check(Game.load_from(save_path).moves.size() == 1,"load replaced save")
	var broken = FileAccess.open(save_path,FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	check(Game.load_from(save_path).moves.is_empty(),"backup recovers damaged save")
	var gote_game = Game.new()
	gote_game.human_side = -1
	gote_game.difficulty = 0
	for m in [move(56,47),move(24,33),move(55,46)]:
		check(gote_game.play(m),"human gote game sequence")
	var gote_restored = Game.from_data(JSON.parse_string(JSON.stringify(gote_game.to_data())))
	check(gote_restored.human_side == -1 and gote_restored.difficulty == 0,"seat and difficulty persist in game save")
	gote_game.undo()
	check(gote_game.moves.size() == 1 and gote_game.position.turn == -1,"gote undo removes human move plus AI reply")
	check(Game.from_data({"version":1,"mode":"ai","moves":[],"human_side":2}) == null,"invalid saved seat rejected")
	check(Game.from_data({"version":1,"mode":"ai","moves":[],"difficulty":4}) == null,"invalid saved difficulty rejected")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(save_path+suffix):
			DirAccess.remove_absolute(save_path+suffix)
	# Fourfold repetition and perpetual check, with complete intermediate positions.
	game = Game.new()
	game.mode = "local"
	game.position = empty()
	game.positions = [game.position.copy()]
	for cycle in range(3):
		for m in [move(80,79),move(0,1),move(79,80),move(1,0)]:
			check(game.play(m),"repetition move")
	check(game.result.begins_with("千日手"),"fourfold repetition ends game")
	game = Game.new()
	game.mode = "local"
	game.position = empty()
	game.position.board[0] = 0
	game.position.board[4] = -8
	game.position.board[22] = 7
	game.position.turn = -1
	game.positions = [game.position.copy()]
	for cycle in range(3):
		for m in [move(4,5),move(22,23),move(5,4),move(23,22)]:
			check(game.play(m),"perpetual check move")
	check(game.result.begins_with("先手判负"),"perpetual checker loses")
	var engine = AI.new()
	p = Rules.new().after(move(56,47))
	var key_before = p.key()
	var answer = engine.choose(p,250)
	check(answer.has("move") and answer.move in p.legal_moves(),"AI returns legal move within budget")
	check(p.key() == key_before,"AI does not mutate input")
	# Deterministic playouts also feed an independent python-shogi oracle.
	var fixtures = []
	var rng = RandomNumberGenerator.new()
	rng.seed = 1122
	for match_index in range(4):
		p = Rules.new()
		for ply in range(70):
			var options = p.legal_moves()
			fixtures.append({"board":p.board.duplicate(),"sente_hand":p.hands[1].duplicate(),"gote_hand":p.hands[-1].duplicate(),"turn":p.turn,"moves":options})
			if options.is_empty():
				break
			var selected = options[rng.randi_range(0,options.size()-1)]
			p = p.after(selected)
			check(not p.in_check(-p.turn),"random move preserves own king safety")
			var count = p.board.filter(func(v): return v != 0).size()
			for side in [1,-1]:
				for kind in range(1,8):
					count += p.hands[side][kind]
			check(count == 40,"random move conserves 40 pieces")
	var directory = ProjectSettings.globalize_path("res://../review/app")
	DirAccess.make_dir_recursive_absolute(directory)
	var fixture_file = FileAccess.open(directory+"/rule-fixtures.json",FileAccess.WRITE)
	fixture_file.store_string(JSON.stringify(fixtures))
	fixture_file.close()
	var report = {"checks":checks,"failures":failures,"elapsed_ms":Time.get_ticks_msec()-started,"oracle_positions":fixtures.size(),"ai":answer}
	var report_file = FileAccess.open(directory+"/rules-tests.json",FileAccess.WRITE)
	report_file.store_string(JSON.stringify(report,"  "))
	report_file.close()
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
