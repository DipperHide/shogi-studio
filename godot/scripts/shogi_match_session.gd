class_name ShogiMatchSession
extends Node
## The hosting peer validates every move. Guests commit only acknowledged moves.

signal changed
signal status_changed(message: String)
signal rejected(message: String)
signal offer_received(action: String, from_local: bool)

const Game = preload("res://scripts/shogi_game.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Link = preload("res://scripts/shogi_link.gd")
const Messages = preload("res://scripts/shogi_messages.gd")
var game = Game.new()
var link: ShogiLink
var is_host: bool = false
var local_side: int = 1
var connected_ready: bool = false
var pending_move: bool = false
var room_code: String = ""
var match_id: String = ""
var resume_token: String = ""
var address: String = ""
var port: int = 9231
var transport: String = "tcp"
var last_received: int = 0
var last_ping: int = 0
var handshake_deadline: int = 0
var offer: Dictionary = {}
var offer_deadline: int = 0
var last_clock_send: int = 0

func _ready() -> void:
	link = Link.new()
	add_child(link)
	link.opened.connect(_opened)
	link.closed.connect(func(): connected_ready = false; pending_move = false; offer.clear(); status_changed.emit("连接已断开，棋局保留，可重新连接"); changed.emit())
	link.failed.connect(func(message): status_changed.emit(message))
	link.status_changed.connect(func(message): status_changed.emit(message))
	link.received.connect(_message)

func _random_token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

func host_tcp(listen_port: int = 9231, side: int = 1, code: String = "", bind_address: String = "*", clock_preset: int = 0) -> Error:
	_setup_host(side, code)
	game.clock.configure(clock_preset)
	transport = "tcp"
	port = listen_port
	var error = link.host_tcp(port, bind_address)
	if error == OK:
		status_changed.emit("等待对手加入，房间码 " + room_code)
	return error

func _setup_host(side: int, code: String) -> void:
	is_host = true
	local_side = side
	connected_ready = false
	pending_move = false
	room_code = code if not code.is_empty() else str(randi_range(100000, 999999))
	match_id = _random_token()
	resume_token = ""
	game = Game.new()
	game.mode = "local"
	game.human_side = local_side
	offer.clear()

func join_tcp(host_address: String, host_port: int, code: String) -> Error:
	is_host = false
	connected_ready = false
	resume_token = ""
	match_id = ""
	transport = "tcp"
	address = host_address.strip_edges()
	port = host_port
	room_code = code.strip_edges()
	status_changed.emit("正在连接对手…")
	return link.join_tcp(address, port)

func host_bluetooth(side: int = 1, clock_preset: int = 0) -> Error:
	_setup_host(side, "bluetooth")
	game.clock.configure(clock_preset)
	transport = "bluetooth"
	return link.use_bluetooth(true)

func join_bluetooth(device_address: String) -> Error:
	is_host = false
	connected_ready = false
	resume_token = ""
	match_id = ""
	transport = "bluetooth"
	room_code = "bluetooth"
	address = device_address
	return link.use_bluetooth(false, address)

func reconnect() -> Error:
	if connected_ready and link != null and link.connected: return OK
	connected_ready = false
	if is_host:
		if transport == "bluetooth":
			return link.use_bluetooth(true)
		return link.host_tcp(port) if link.server == null else OK
	return link.use_bluetooth(false, address) if transport == "bluetooth" else link.join_tcp(address, port)

func can_move() -> bool:
	return connected_ready and not pending_move and offer.is_empty() and game.result.is_empty() and game.position.turn == local_side

func submit(move: Dictionary) -> bool:
	if not can_move() or move not in game.position.legal_moves():
		return false
	if is_host:
		_apply(move)
	else:
		pending_move = link.send({"v": 1, "type": "move", "match": match_id, "ply": game.moves.size(), "before": _key(), "move": Codec.move_name(move)})
		return pending_move
	return true

func resign() -> bool:
	if not connected_ready or not game.result.is_empty():
		return false
	if is_host:
		_clear_offer()
		game.resign(local_side)
		_snapshot()
		changed.emit()
	else:
		return link.send({"v": 1, "type": "resign", "match": match_id})
	return true

func _key() -> String:
	return game.position.key().sha256_text()

func _opened() -> void:
	last_received = Time.get_ticks_msec()
	handshake_deadline = last_received + 10000
	if not is_host:
		link.send({"v": 1, "type": "hello", "code": room_code, "resume": resume_token})

func _snapshot() -> void:
	var moves: Array[String] = []
	for move in game.moves:
		moves.append(Codec.move_name(move))
	link.send({"v": 1, "type": "welcome", "match": match_id, "resume": resume_token, "side": -local_side, "moves": moves, "resigned": game.resigned, "resigned_side": game.resigned_side, "agreed_draw": game.agreed_draw, "declared_side": game.declared_side, "clock": game.clock.to_data(), "key": _key()})

func _message(message: Dictionary) -> void:
	last_received = Time.get_ticks_msec()
	if message.get("v") != 1 or not message.get("type") is String:
		link.disconnect_peer()
		return
	var type: String = message.type
	if type == "hello" and is_host:
		if message.get("code") != room_code or (not resume_token.is_empty() and message.get("resume") != resume_token):
			link.send({"v": 1, "type": "denied", "reason": "房间码不正确，或这局已有另一位对手"})
			return
		if resume_token.is_empty():
			resume_token = _random_token()
		connected_ready = true
		_snapshot()
		status_changed.emit("对手已连接")
		changed.emit()
		return
	if type == "denied":
		status_changed.emit(Messages.reason(message, "对手拒绝连接"))
		connected_ready = false
		return
	if type == "welcome" and not is_host:
		_accept_snapshot(message)
		return
	if not connected_ready or message.get("match") != match_id:
		return
	if type == "ping":
		link.send({"v": 1, "type": "pong", "match": match_id})
	elif type == "move" and is_host:
		if message.get("ply") != game.moves.size() or message.get("before") != _key() or game.position.turn == local_side or not offer.is_empty():
			_reject("局面已更新，已重新同步")
			return
		var value = message.get("move")
		var move = Codec.parse_move(value, game.position) if value is String else {}
		if move.is_empty() or not game.result.is_empty():
			_reject("非法着手")
			return
		_apply(move)
	elif type == "applied" and not is_host:
		_accept_move(message)
	elif type == "resign" and is_host:
		_clear_offer()
		game.resign(-local_side)
		_snapshot()
		changed.emit()
	elif type == "sync" and is_host:
		_snapshot()
	elif type == "declare" and is_host:
		if not offer.is_empty() or not game.declare_win(-local_side):
			_reject("当前不满足入玉宣言条件")
		else:
			_snapshot()
			changed.emit()
	elif type == "rejected":
		pending_move = false
		rejected.emit(Messages.reason(message, "着手未被接受"))
	elif type == "request" and is_host:
		_create_offer(str(message.get("action", "")), -local_side)
	elif type == "offer" and not is_host:
		if message.get("action") not in ["undo", "draw", "rematch"] or not message.get("id") is String or message.id.length() > 64:
			return
		var sender = message.get("sender")
		if sender != 1 and sender != -1:
			return
		offer = {"id": message.id, "action": message.action, "sender": int(sender)}
		offer_received.emit(offer.action, offer.sender == local_side)
		changed.emit()
	elif type == "answer" and is_host:
		if message.get("accepted") is bool:
			_answer(str(message.get("id", "")), message.accepted, -local_side)
	elif type == "offer_closed" and not is_host:
		offer.clear()
		status_changed.emit(Messages.reason(message, "请求结束"))
		changed.emit()
	elif type == "clock" and not is_host:
		if message.get("ply") == game.moves.size() and message.get("key") == _key():
			_accept_clock(message.get("clock"))

func _apply(move: Dictionary) -> void:
	var before = _key()
	var ply = game.moves.size()
	if not game.play(move):
		return
	link.send({"v": 1, "type": "applied", "match": match_id, "ply": ply, "before": before, "move": Codec.move_name(move), "after": _key(), "clock": game.clock.to_data()})
	changed.emit()

func _reject(reason: String) -> void:
	link.send({"v": 1, "type": "rejected", "match": match_id, "reason": reason})
	_snapshot()

func _accept_snapshot(message: Dictionary) -> void:
	if not message.get("moves") is Array or message.moves.size() > 2000 or not message.get("resigned", false) is bool or not message.get("agreed_draw", false) is bool:
		link.disconnect_peer()
		return
	var side = message.get("side", 0)
	if side != 1 and side != -1:
		link.disconnect_peer()
		return
	for field in ["match", "resume", "key"]:
		if not message.get(field) is String or message[field].length() > 128:
			link.disconnect_peer()
			return
	var restored = Game.new()
	restored.mode = "local"
	restored.human_side = int(side)
	for value in message.moves:
		if not value is String:
			link.disconnect_peer()
			return
		var move = Codec.parse_move(value, restored.position)
		if move.is_empty() or not restored.play(move):
			status_changed.emit("对手提供的棋谱无效")
			link.disconnect_peer()
			return
	if restored.position.key().sha256_text() != message.key:
		status_changed.emit("局面校验失败")
		link.disconnect_peer()
		return
	if message.get("resigned", false):
		var loser = message.get("resigned_side", 0)
		if loser != 1 and loser != -1:
			link.disconnect_peer()
			return
		restored.resign(int(loser))
	if message.get("agreed_draw", false):
		if not restored.result.is_empty():
			link.disconnect_peer()
			return
		restored.agreed_draw = true
		restored.update_result()
	var declaration = message.get("declared_side", 0)
	if declaration != 0:
		if (declaration != 1 and declaration != -1) or not restored.declare_win(int(declaration)):
			link.disconnect_peer()
			return
	game = restored
	game.clock_authority = false
	if message.has("clock") and not _accept_clock(message.clock, false):
		return
	local_side = int(side)
	match_id = message.match
	resume_token = message.resume
	connected_ready = true
	pending_move = false
	status_changed.emit("对局已同步")
	changed.emit()

func request(action: String) -> bool:
	if not connected_ready or pending_move or not offer.is_empty() or not _action_allowed(action):
		return false
	if is_host:
		return _create_offer(action, local_side)
	return link.send({"v": 1, "type": "request", "match": match_id, "action": action})

func declare_win() -> bool:
	if not can_move() or not game.position.declaration_status(local_side).valid:
		return false
	if not is_host:
		return link.send({"v": 1, "type": "declare", "match": match_id})
	if not game.declare_win(local_side):
		return false
	_snapshot()
	changed.emit()
	return true

func _action_allowed(action: String) -> bool:
	if action == "rematch":
		return not game.result.is_empty()
	if action == "undo":
		return game.result.is_empty() and not game.moves.is_empty()
	return action == "draw" and game.result.is_empty()

func _create_offer(action: String, sender: int) -> bool:
	if not offer.is_empty() or not _action_allowed(action):
		return false
	offer = {"id": _random_token(), "action": action, "sender": sender}
	offer_deadline = Time.get_ticks_msec() + 30000
	link.send({"v": 1, "type": "offer", "match": match_id, "id": offer.id, "action": action, "sender": sender})
	offer_received.emit(action, sender == local_side)
	changed.emit()
	return true

func answer(accepted: bool) -> bool:
	if not connected_ready or offer.is_empty() or offer.sender == local_side:
		return false
	if is_host:
		return _answer(offer.id, accepted, local_side)
	return link.send({"v": 1, "type": "answer", "match": match_id, "id": offer.id, "accepted": accepted})

func _answer(id: String, accepted: bool, sender: int) -> bool:
	if offer.is_empty() or offer.id != id or offer.sender == sender:
		return false
	var action: String = offer.action
	_clear_offer("对手已同意" if accepted else "对手未同意")
	if accepted:
		if action == "undo":
			game.undo()
		elif action == "draw":
			game.agreed_draw = true
			game.update_result()
		elif action == "rematch":
			var clock_preset: int = game.clock.preset
			game = Game.new()
			game.clock.configure(clock_preset)
			game.mode = "local"
			local_side = -local_side
			game.human_side = local_side
			match_id = _random_token()
		_snapshot()
	changed.emit()
	return true

func _clear_offer(reason: String = "请求已取消") -> void:
	if not offer.is_empty():
		link.send({"v": 1, "type": "offer_closed", "match": match_id, "reason": reason})
		offer.clear()
		status_changed.emit(reason)

func _accept_move(message: Dictionary) -> void:
	if message.get("ply") != game.moves.size() or message.get("before") != _key() or not message.get("move") is String:
		link.send({"v": 1, "type": "sync", "match": match_id})
		return
	var move = Codec.parse_move(message.move, game.position)
	if move.is_empty() or game.position.after(move).key().sha256_text() != message.get("after"):
		status_changed.emit("着手校验失败，正在重新同步")
		link.send({"v": 1, "type": "sync", "match": match_id})
		return
	if game.play(move):
		if message.has("clock") and not _accept_clock(message.clock, false):
			return
		pending_move = false
		changed.emit()

func _accept_clock(data: Variant, notify: bool = true) -> bool:
	var clock = Game.Clock.from_data(data)
	if clock == null or clock.turn != game.position.turn:
		link.disconnect_peer()
		return false
	if clock.expired_side != 0 and not game.result.is_empty() and game.clock.expired_side == 0:
		link.disconnect_peer()
		return false
	game.clock = clock
	if clock.expired_side != 0:
		game.update_result()
		if notify: changed.emit()
	return true

func _process(_delta: float) -> void:
	if is_host:
		game.clock.tick(not connected_ready or not offer.is_empty() or not game.result.is_empty())
		if game.clock.expired_side != 0 and game.result.is_empty():
			game.update_result()
			_snapshot()
			changed.emit()
	if link == null or not link.connected:
		return
	var now = Time.get_ticks_msec()
	if not connected_ready and now > handshake_deadline:
		link.disconnect_peer()
		status_changed.emit("对局握手超时")
	elif connected_ready:
		if is_host and game.clock.preset != 0 and now - last_clock_send > 1000:
			last_clock_send = now
			link.send({"v": 1, "type": "clock", "match": match_id, "ply": game.moves.size(), "key": _key(), "clock": game.clock.to_data()})
		if is_host and not offer.is_empty() and now > offer_deadline:
			_clear_offer("对手未及时回应，请求已取消")
			changed.emit()
		if now - last_ping > 10000:
			last_ping = now
			link.send({"v": 1, "type": "ping", "match": match_id})
		if now - last_received > 35000:
			link.disconnect_peer()
			status_changed.emit("对手连接超时，可重新连接")
