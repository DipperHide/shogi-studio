class_name ChuSession
extends Node
signal changed
signal status_changed(message: String)
signal offer_received(action: String, from_local: bool)
const Game = preload("res://scripts/chu_game.gd")
const C = preload("res://scripts/chu_catalog.gd")
const Link = preload("res://scripts/shogi_link.gd")
const VERSION = 2
const CHUNK = 12000
var game = Game.new()
var link
var is_host = false
var local_side = 1
var connected_ready = false
var pending_move = false
var match_id = ""
var resume_token = ""
var room_code = ""
var address = ""
var port = 9232
var transport = "tcp"
var sequence = 0
var offer: Dictionary = {}
var outgoing: Array = []
var incoming: Dictionary = {}
var last_received = 0
var last_ping = 0
var last_clock = 0
var sync_digest = ""

func _ready() -> void:
	link = Link.new(); add_child(link)
	link.opened.connect(_opened); link.received.connect(_message)
	link.closed.connect(func(): connected_ready=false; pending_move=false; offer.clear(); incoming.clear(); outgoing.clear(); status_changed.emit("连接断开，棋局已保留，可重连。"); changed.emit())
	link.failed.connect(func(message): status_changed.emit(message))
	link.status_changed.connect(func(message): status_changed.emit(message))

func _token() -> String: return Crypto.new().generate_random_bytes(24).hex_encode()
func send(type: String, fields: Dictionary = {}) -> bool:
	var message = {"v":VERSION,"variant":"chu","rules_id":C.RULES_ID,"type":type,"match":match_id,"seq":sequence}
	message.merge(fields,true)
	return link.send(message)

func host_tcp(listen_port: int = 9232, side: int = 1, code: String = "", bind_address: String = "*", clock_preset: int = 0) -> Error:
	_setup(side,code,clock_preset); port=listen_port; transport="tcp"
	return link.host_tcp(port,bind_address)
func _setup(side: int, code: String, clock_preset: int) -> void:
	is_host=true; local_side=side; room_code=code if not code.is_empty() else str(randi_range(100000,999999))
	match_id=_token(); resume_token=""; sequence=0; connected_ready=false; pending_move=false; offer.clear()
	game=Game.new(); game.clock.configure(clock_preset)
func join_tcp(host_address: String, host_port: int, code: String) -> Error:
	is_host=false; local_side=-1; match_id=""; resume_token=""; room_code=code; address=host_address.strip_edges(); port=host_port; transport="tcp"
	game.clock_authority=false
	return link.join_tcp(address,port)
func host_bluetooth(side: int = 1, clock_preset: int = 0) -> Error:
	_setup(side,"bluetooth",clock_preset); transport="bluetooth"
	return link.use_bluetooth(true)
func join_bluetooth(device_address: String) -> Error:
	is_host=false; transport="bluetooth"; room_code="bluetooth"; address=device_address; match_id=""; resume_token=""; game.clock_authority=false
	return link.use_bluetooth(false,address)
func reconnect() -> Error:
	connected_ready=false; pending_move=false; incoming.clear(); outgoing.clear()
	if transport=="bluetooth": return link.use_bluetooth(is_host,address)
	return (link.host_tcp(port) if link.server==null else OK) if is_host else link.join_tcp(address,port)
func _opened() -> void:
	last_received=Time.get_ticks_msec(); connected_ready=false
	if not is_host: send("hello",{"code":room_code,"resume":resume_token})

func can_move() -> bool:
	return connected_ready and not pending_move and offer.is_empty() and game.result.is_empty() and game.position.turn==local_side
func submit(move: Dictionary) -> bool:
	if not can_move() or not game.valid_move(move): return false
	if is_host: return _apply(move)
	pending_move=send("move",{"before":game.state_key(),"move":move}); changed.emit()
	return pending_move
func _apply(move: Dictionary) -> bool:
	var before=game.state_key()
	if not game.play(move): send("reject",{"reason":game.error}); return false
	sequence+=1
	send("applied",{"before":before,"after":game.state_key(),"move":game.moves.back(),"clock":game.clock.to_data()})
	changed.emit(); return true

func _snapshot() -> void:
	connected_ready=false; outgoing.clear(); offer.clear()
	var bytes=JSON.stringify(game.to_data()).to_utf8_buffer()
	if bytes.size()>Game.MAX_SAVE_BYTES: status_changed.emit("棋谱超过同步大小限制。"); return
	sync_digest=bytes.hex_encode().sha256_text()
	var id=_token(); var count=ceili(bytes.size()/float(CHUNK))
	outgoing.append({"type":"snapshot_begin","id":id,"count":count,"bytes":bytes.size(),"digest":sync_digest,"side":-local_side,"resume":resume_token})
	for i in range(count): outgoing.append({"type":"snapshot_part","id":id,"index":i,"data":Marshalls.raw_to_base64(bytes.slice(i*CHUNK,mini(bytes.size(),(i+1)*CHUNK)))})
	outgoing.append({"type":"snapshot_end","id":id})

func _message(message: Dictionary) -> void:
	last_received=Time.get_ticks_msec()
	if message.get("type")=="denied": connected_ready=false; status_changed.emit(str(message.get("reason","对手拒绝连接"))); return
	if message.get("v")!=VERSION or message.get("variant")!="chu" or message.get("rules_id")!=C.RULES_ID:
		link.send({"v":message.get("v",1),"type":"denied","reason":"棋种或规则版本不一致：本房间需要中将棋 0.37 或兼容版本。"}); connected_ready=false
		status_changed.emit("对手版本、棋种或规则不兼容。"); return
	var type=str(message.get("type",""))
	if type=="hello" and is_host:
		if message.get("code")!=room_code or (not resume_token.is_empty() and message.get("resume")!=resume_token): send("denied",{"reason":"房间码错误，或已有其他对手。"}); return
		if resume_token.is_empty(): resume_token=_token()
		_snapshot(); return
	if type=="snapshot_begin" and not is_host:
		if not Game.Rules.integer(message.get("seq")) or int(message.seq)<0 or (not match_id.is_empty() and (message.get("match")!=match_id or message.seq<sequence)): return
		if not message.get("id") is String or not message.get("match") is String or not message.get("resume") is String or not Game.Rules.integer(message.get("side")) or int(message.side) not in [-1,1] or not message.get("digest") is String: return
		if not Game.Rules.integer(message.get("bytes")) or message.bytes<=0 or message.bytes>Game.MAX_SAVE_BYTES or not Game.Rules.integer(message.get("count")) or message.count!=ceili(message.bytes/float(CHUNK)): return
		incoming={"header":message.duplicate(true),"data":PackedByteArray(),"next":0}; connected_ready=false; return
	if type in ["snapshot_part","snapshot_end"] and not is_host:
		_receive_snapshot(message); return
	if message.get("match")!=match_id or not Game.Rules.integer(message.get("seq")): return
	if type=="snapshot_ack" and is_host:
		if message.seq==sequence and message.get("digest")==sync_digest:
			connected_ready=true; send("ready"); status_changed.emit("中将棋对手已连接"); changed.emit()
		return
	if type=="ready" and not is_host and message.seq==sequence and incoming.is_empty():
		connected_ready=true; status_changed.emit("中将棋对手已连接"); changed.emit(); return
	if type=="ping": send("pong"); return
	if type=="pong": return
	if type=="applied" and not is_host:
		if message.seq<=sequence: return
		if message.seq!=sequence+1 or message.get("before")!=game.state_key(): send("resync"); return
		var next=game.fork(); next.clock_authority=false
		var clock=Game.Clock.from_data(message.get("clock"))
		if not message.get("move") is Dictionary or not next.play(message.move) or message.get("after")!=next.state_key() or clock==null or clock.turn!=next.position.turn: send("resync"); return
		next.clock=clock; game=next; sequence=int(message.seq); pending_move=false; changed.emit(); return
	if type=="resync" and is_host: _snapshot(); return
	if message.seq!=sequence: return
	if type=="clock" and not is_host:
		var clock=Game.Clock.from_data(message.get("clock"))
		if clock!=null and clock.turn==game.position.turn: game.clock=clock
		return
	if not connected_ready: return
	match type:
		"move":
			if is_host and offer.is_empty() and game.position.turn==-local_side and message.get("before")==game.state_key() and message.get("move") is Dictionary: _apply(message.move)
			elif is_host: send("reject",{"reason":"此着手已过期或当前不能落子。"})
		"reject": pending_move=false; status_changed.emit(str(message.get("reason","着手被拒绝"))); changed.emit()
		"resign":
			if is_host and game.result.is_empty(): game.resign(-local_side); sequence+=1; _snapshot(); changed.emit()
		"request":
			if is_host: _offer(str(message.get("action","")),-local_side)
		"offer":
			if not is_host and message.get("action") in ["undo","draw","rematch"] and Game.Rules.integer(message.get("side")) and int(message.side) in [-1,1] and message.get("id") is String:
				offer={"action":message.action,"side":int(message.side),"id":message.id}; offer_received.emit(offer.action,offer.side==local_side); changed.emit()
		"answer":
			if is_host and message.get("accept") is bool and message.get("id")==offer.get("id") and offer.get("side")==local_side: _answer(message.accept)
		"offer_clear": offer.clear(); changed.emit()

func _receive_snapshot(message: Dictionary) -> void:
	if incoming.is_empty(): return
	var header: Dictionary=incoming.header
	if message.get("id")!=header.id or message.get("match")!=header.match or message.get("seq")!=header.seq: return
	if message.type=="snapshot_part":
		if message.get("index")!=incoming.next or not message.get("data") is String or message.data.length()>CHUNK*2: incoming.clear(); return
		var chunk=Marshalls.base64_to_raw(message.data)
		if chunk.is_empty() or chunk.size()>CHUNK or incoming.data.size()+chunk.size()>header.bytes: incoming.clear(); return
		incoming.data.append_array(chunk); incoming.next+=1; return
	if incoming.next!=header.count or incoming.data.size()!=header.bytes or incoming.data.hex_encode().sha256_text()!=header.digest: incoming.clear(); return
	var parsed=Game.from_data(JSON.parse_string(incoming.data.get_string_from_utf8()))
	if parsed==null: incoming.clear(); status_changed.emit("同步棋谱未通过逐手校验，原局面已保留。"); return
	game=parsed; game.clock_authority=false; match_id=header.match; resume_token=header.resume; local_side=int(header.side); sequence=int(header.seq)
	pending_move=false; offer.clear(); incoming.clear(); send("snapshot_ack",{"digest":header.digest}); changed.emit()

func request_offer(action: String) -> bool:
	if not connected_ready or not offer.is_empty() or action not in ["undo","draw","rematch"]: return false
	if is_host: _offer(action,local_side); return not offer.is_empty()
	return send("request",{"action":action})
func _offer(action: String, side: int) -> void:
	if not offer.is_empty() or action not in ["undo","draw","rematch"]: return
	if action=="undo" and game.moves.is_empty(): return
	if action=="draw" and not game.result.is_empty(): return
	offer={"action":action,"side":side,"id":_token()}
	send("offer",offer); offer_received.emit(action,side==local_side); changed.emit()
func answer_offer(accept: bool) -> void:
	if offer.is_empty() or offer.side==local_side: return
	if is_host: _answer(accept)
	else: send("answer",{"id":offer.id,"accept":accept})
func _answer(accept: bool) -> void:
	var action=str(offer.get("action","")); offer.clear()
	if not accept: send("offer_clear"); changed.emit(); return
	match action:
		"undo": game.undo()
		"draw": game.agreed_draw=true; game.update_result()
		"rematch":
			var preset=game.clock.preset; game=Game.new(); game.clock.configure(preset); local_side=-local_side
	sequence+=1; _snapshot(); changed.emit()
func resign() -> void:
	if not connected_ready or not game.result.is_empty(): return
	if is_host: game.resign(local_side); sequence+=1; _snapshot(); changed.emit()
	else: send("resign")

func _process(_delta: float) -> void:
	if link==null: return
	if not outgoing.is_empty() and link.connected:
		var item: Dictionary=outgoing.pop_front(); var type: String=item.type; item.erase("type")
		if not send(type,item): outgoing.clear()
	var now=Time.get_ticks_msec()
	if link.connected and now-last_received>30000: link.disconnect_peer(); return
	if link.connected and now-last_ping>5000: last_ping=now; send("ping")
	if is_host:
		var before=game.result_code
		game.clock.tick(not connected_ready or not offer.is_empty() or not game.result.is_empty())
		if game.clock.expired_side!=0 and before.is_empty(): game.update_result(); sequence+=1; _snapshot(); changed.emit()
		elif connected_ready and now-last_clock>1000: last_clock=now; send("clock",{"clock":game.clock.to_data()})

func to_data() -> Dictionary:
	return {"version":VERSION,"variant":"chu","rules_id":C.RULES_ID,"game":game.to_data(),"host":is_host,"side":local_side,"match":match_id,"resume":resume_token,"room":room_code,"address":address,"port":port,"transport":transport,"seq":sequence}
func restore(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=VERSION or data.get("variant")!="chu" or data.get("rules_id")!=C.RULES_ID or not data.get("host") is bool or not Game.Rules.integer(data.get("side")) or int(data.side) not in [-1,1]: return false
	if data.get("transport") not in ["tcp","bluetooth"] or not Game.Rules.integer(data.get("port")) or data.port<1 or data.port>65535 or not Game.Rules.integer(data.get("seq")) or data.seq<0: return false
	for key in ["match","resume","room","address"]:
		if not data.get(key) is String or data[key].length()>256: return false
	var parsed=Game.from_data(data.get("game"))
	if parsed==null: return false
	game=parsed; is_host=data.host; game.clock_authority=is_host; local_side=int(data.side); match_id=data.match; resume_token=data.resume; room_code=data.room; address=data.address; port=int(data.port); transport=data.transport; sequence=int(data.seq)
	return true
