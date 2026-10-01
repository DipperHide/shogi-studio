extends SceneTree
const R = preload("res://scripts/chu_rules.gd")
const G = preload("res://scripts/chu_game.gd")
const C = preload("res://scripts/chu_catalog.gd")
var checks = 0
var failures: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func sq(file: int, rank: int) -> int: return (rank-1)*12+12-file
func m(origin: int, path: Array, promote: bool = false) -> Dictionary: return {"from":origin,"path":path,"promote":promote}
func empty() -> R: return R.new(false)
func kings(p) -> void: p.board[143] = C.KING; p.board[0] = -C.KING
func _initialize() -> void:
	var p = R.new()
	check(p.board.filter(func(v): return v>0).size()==46,"46 sente pieces")
	check(p.board.filter(func(v): return v<0).size()==46,"46 gote pieces")
	check(p.board[sq(7,11)]==C.KIRIN and p.board[sq(6,11)]==C.PHOENIX,"official initial centre")
	check(p.board[sq(7,12)]==C.KING and p.board[sq(6,12)]==C.ELEPHANT,"official royal positions")
	check(p.paths(sq(7,10)).all(func(path): return path.back()!=sq(7,10)),"blocked initial lion cannot pass")
	# Independent counts on an open central board: step/ray/jump geometry.
	var counts = {1:1,2:2,3:6,4:11,5:6,6:4,7:5,8:6,9:7,10:7,11:8,12:8,13:13,14:13,15:22,16:21,17:25,18:26,19:43,20:24,21:8,22:22,23:21,24:17,25:8,26:32,27:32,28:39,29:36}
	for kind in range(1,30):
		var code = kind
		if kind > 21:
			for base in C.PROMOTES:
				if C.PROMOTES[base]==kind: code=base+32; break
		p=empty(); p.board[78]=code
		var destinations: Array = []
		for path in p.paths(78):
			if path.size()==1 and path[0] not in destinations: destinations.append(path[0])
		check(destinations.size()==counts[kind],"open destinations %s expected %d got %d" % [C.NAMES[kind],counts[kind],destinations.size()])
		var reverse=empty(); reverse.turn=-1; reverse.board[65]=-code
		var reversed: Array=[]
		for path in reverse.paths(65):
			if path.size()==1: reversed.append(143-path[0])
		destinations.sort(); reversed.sort()
		check(destinations==reversed,"orientation "+C.NAMES[kind])
		for path in p.paths(78):
			check(p.valid_move(m(78,path)),"generated valid "+C.NAMES[kind])
			var after=p.after(m(78,path)); check(after.board[path.back()]==code,"piece identity "+C.NAMES[kind])
	p=empty(); p.board[78]=C.ROOK; p.board[66]=C.PAWN; p.board[80]=-C.PAWN
	check([54] not in p.paths(78) and [66] not in p.paths(78) and [80] in p.paths(78) and [81] not in p.paths(78),"ray blocking and capture")
	p.board[78]=C.KIRIN
	check([54] in p.paths(78),"kirin jumps own blocker")
	for base in C.PROMOTES:
		p=empty(); p.board[49]=base
		check(p.can_promote(49,[37]),"entry promotion "+str(base))
		p.board[49]=base+32
		check(not p.can_promote(49,[37]),"cannot promote twice "+str(base))
	p=empty(); p.board[37]=C.GOLD
	check(not p.can_promote(37,[25]),"declined no quiet zone promotion")
	p.board[25]=-C.PAWN
	check(p.can_promote(37,[25]),"capture in zone promotion")
	p.board[49]=-C.PAWN
	check(p.can_promote(37,[49]),"capture exiting zone promotion")
	for base in [C.PAWN,C.LANCE]:
		p=empty(); p.board[13]=base
		check(p.valid_move(m(13,[1],true)),"last rank rescue "+str(base))
		check(p.after(m(13,[1])).paths(1).is_empty(),"dead unpromoted allowed")
	p=empty(); p.board[13]=C.GO_BETWEEN
	check(not p.can_promote(13,[1]),"go-between no last-rank rescue")
	_lions(); _games()
	print("CHU_RULES_RESULT "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _lions() -> void:
	var p=empty(); var a=sq(3,3); var via=sq(2,2); var b=sq(1,2)
	p.board[a]=C.LION; p.board[b]=-C.LION; p.board[sq(2,1)]=-C.GOLD; p.board[sq(1,3)]=C.GOLD; p.board[via]=-C.GOLD
	check(p.valid_move(m(a,[via,b])),"supplement 1 tsukegui")
	var next=p.after(m(a,[via,b]))
	check(next.immunity.is_empty() and next.valid_move(m(sq(2,1),[b])),"supplement 1 may recapture defended lion")
	p.board[via]=-(C.KIRIN+32)
	check(p.valid_move(m(a,[via,b])),"supplement 2 two lions tsukegui")
	p=empty(); p.board[sq(1,4)]=C.ROOK; p.board[sq(1,1)]=-C.LION; p.board[sq(3,2)]=-(C.KIRIN+32); p.board[sq(4,3)]=C.SILVER; p.board[sq(5,4)]=C.LION; p.board[sq(5,6)]=C.VERTICAL
	next=p.after(m(sq(1,4),[sq(1,1)]))
	check(sq(5,4) in next.immunity,"supplement 3 sakijishi protected lion")
	check(not next.valid_move(m(sq(3,2),[sq(5,4)])),"sakijishi prohibits jump capture")
	check(next.valid_move(m(sq(3,2),[sq(4,3),sq(5,4)])),"supplement 3 tsukegui overrides sakijishi")
	p=empty(); p.board[sq(3,3)]=C.LION; p.board[sq(2,2)]=-C.GO_BETWEEN; p.board[sq(2,1)]=-C.LION
	check(not p.valid_move(m(sq(3,3),[sq(2,2),sq(2,1)])),"supplement 4 foot evaluated before first capture")
	p=empty(); p.board[78]=C.LION; p.board[65]=-C.LION; p.board[64]=-C.ROOK
	check(p.valid_move(m(78,[65])),"adjacent defended lion capture")
	p=empty(); p.board[78]=C.LION; p.board[52]=-C.LION; p.board[91]=-C.BISHOP
	check(not p.valid_move(m(78,[52])),"x-ray lion foot through attacker origin")
	p.board[91]=0
	check(p.valid_move(m(78,[52])),"unprotected distant lion capture")
	p.board[66]=-C.PAWN
	check(p.valid_move(m(78,[66,78])),"igui")
	next=p.after(m(78,[66,78])); check(next.board[66]==0 and next.board[78]==C.LION,"igui atomic board")
	check(p.valid_move(m(78,[77,78])),"empty pass")
	for code in [C.HORSE+32,C.DRAGON+32]:
		p=empty(); p.board[78]=code; var first=66 if code==C.HORSE+32 else 65
		check(p.valid_move(m(78,[first,78])),"falcon/eagle pass")
		check(not p.valid_move(m(78,[first,first+1])),"falcon/eagle cannot turn sideways")

func _games() -> void:
	var g=G.new(); var rng=RandomNumberGenerator.new(); rng.seed=37058
	for i in range(80):
		if not g.result.is_empty(): break
		var legal=g.position.legal_moves(); var move=legal[rng.randi_range(0,legal.size()-1)]
		check(g.play(move),"seeded game move "+str(i))
	var restored=G.from_data(JSON.parse_string(JSON.stringify(g.to_data())))
	if restored==null: print("RESTORE FAILED ",JSON.stringify(g.to_data()))
	check(restored!=null and restored.state_key()==g.state_key() and restored.position.key()==g.position.key(),"roundtrip complete history")
	var before=g.keys[-2]; g.undo(); check(g.position.key()==before,"undo board and special state")
	var broken=g.to_data(); broken.rules_id="unknown"; check(G.from_data(broken)==null,"unknown rules rejected")
	broken=g.to_data(); broken.moves[0].path=[999]; check(G.from_data(broken)==null,"illegal path rejected")
	var p=empty(); kings(p); p.board[100]=C.ELEPHANT+32; p.board[12]=C.ROOK
	g=G.new(); check(g.set_initial(p),"editor prince")
	check(g.play(m(12,[0])),"king captured with prince test move")
	check(g.result_code=="royal_capture","opponent last royal capture")
	p=empty(); kings(p); p.board[100]=C.ELEPHANT+32; p.board[80]=C.GOLD; p.board[131]=-C.ROOK; p.turn=-1
	g=G.new(); g.set_initial(p)
	check(g.play(m(131,[143])) and g.result.is_empty(),"king lost while prince survives")
	p=empty(); kings(p); p.board[78]=C.LION; p.board[26]=-C.LION
	g=G.new(); g.set_initial(p)
	check(g.play(m(78,[77,78])) and g.play(m(26,[25,26])),"both pass")
	check(not g.play(m(78,[79,78])),"first passer must change; alternative via does not evade")
	check(not g.error.is_empty(),"repetition explanation")
	p=empty(); kings(p); p.board[78]=C.ROOK; p.board[26]=-C.ROOK
	g=G.new(); g.set_initial(p)
	var cycle=[m(78,[79]),m(26,[27]),m(79,[78]),m(27,[26])]
	for i in range(8): check(g.play(cycle[i%4]),"repetition setup "+str(i))
	check(not g.play(cycle[0]),"responsible player must vary before fourth occurrence")
	check(g.result.is_empty(),"repetition is not automatic draw")
	p=empty(); kings(p); p.board[78]=C.PAWN
	g=G.new(); g.set_initial(p); check(g.result.is_empty(),"pawn not bare-king winning material")
	p.board[78]=C.GOLD; g.set_initial(p); check(g.result_code=="bare_king" and g.winner==1,"bare king result")
	p=empty(); p.board[143]=C.KING; p.board[0]=-C.KING; p.board[13]=C.GOLD; p.turn=-1
	g.set_initial(p); check(g.result.is_empty(),"bare king immediate recapture exception")
	p.board[13]=0; p.board[1]=C.LANCE
	g.set_initial(p); check(g.result.is_empty(),"dead lance excluded")
	# Continuous checks take precedence over the side-to-move fallback.
	p=empty(); kings(p); p.board[12]=C.ROOK; p.board[100]=C.PAWN; p.turn=-1
	g=G.new(); g.set_initial(p)
	cycle=[m(0,[1]),m(12,[13]),m(1,[0]),m(13,[12])]
	for i in range(8): check(g.play(cycle[i%4]),"checking cycle "+str(i))
	check(g.repetition_responsibility(4,8)==1,"continuous checker responsibility")
	check(g.play(cycle[0]) and not g.play(cycle[1]),"defender can repeat; checker must vary")
	# A one-sided attack on non-royal material has priority too.
	p=empty(); kings(p); p.board[78]=C.ROOK; p.board[6]=-C.GOLD; p.board[7]=-C.GOLD; p.turn=-1
	g=G.new(); g.set_initial(p)
	cycle=[m(0,[1]),m(78,[79]),m(1,[0]),m(79,[78])]
	for i in range(8): check(g.play(cycle[i%4]),"attacking cycle "+str(i))
	check(g.repetition_responsibility(4,8)==1,"one-sided piece attack responsibility")
	check(g.play(cycle[0]) and not g.play(cycle[1]),"attacker must vary")
	p=empty(); kings(p); p.board[26]=C.LION; p.board[100]=-C.PAWN; p.turn=-1
	g=G.new(); g.set_initial(p); check(g.result_code=="mate" and g.winner==1,"lion mate without king-capture turn")
	p=empty(); kings(p); p.board[131]=-C.ROOK; p.board[100]=C.PAWN
	g=G.new(); g.set_initial(p)
	check(g.play(m(100,[88])),"leaving own king attacked is legal in Chu")
	check(g.play(m(131,[143])) and g.result_code=="royal_capture","capture exposed king")
	p=empty(); p.board[132]=C.KING; p.board[143]=C.ELEPHANT+32; p.board[0]=-C.KING; p.board[120]=-C.ROOK; p.board[131]=-C.ROOK
	g=G.new(); g.set_initial(p)
	check(g.result.is_empty(),"separately attacked king and prince not automatically mate")
