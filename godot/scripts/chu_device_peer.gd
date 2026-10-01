extends RefCounted
## Debug package probe: two physical runtimes, real TCP, isolated from user games.
var app
var session
var checks=0
var failures:Array=[]
var phase="moves"
var goal=8
var did_disconnect=false
var reconnecting=false
var finished=false
var config:Dictionary={}
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func until(predicate: Callable, seconds: float=20.0) -> bool:
	var start=Time.get_ticks_msec()
	while Time.get_ticks_msec()-start<seconds*1000:
		if predicate.call(): return true
		await app.get_tree().process_frame
	return false
func run(owner) -> void:
	app=owner
	if OS.get_name()=="Android":
		config=JSON.parse_string(FileAccess.get_file_as_string("user://chu-peer.request")); DirAccess.remove_absolute("user://chu-peer.request")
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--peer-config="): config=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--peer-config=")))
	app.open_chu(); var screen=app.chu_screen; screen.close_modal(); screen._attach_session(); session=screen.session
	session.offer_received.connect(func(_action,local):
		if not local: screen.pending_offer_dialog=false; screen.close_modal(); session.answer_offer.call_deferred(true)
	)
	session.link.received.connect(func(message):
		if message.get("type")=="probe_phase": phase=str(message.phase); goal=int(message.get("goal",8))
		if message.get("type")=="probe_done": _finish.call_deferred()
	)
	session.link.closed.connect(func():
		if not session.is_host and not finished: _reconnect.call_deferred()
	)
	if config.get("host",false): check(session.host_tcp(int(config.get("port",19637)),1,"370058")==OK,"device host bind")
	else: check(session.join_tcp(str(config.get("address","127.0.0.1")),int(config.get("port",19637)),"370058")==OK,"device guest connect")
	check(await until(func(): return session.connected_ready,40),"physical TCP handshake")
	if not session.connected_ready: await _finish(); return
	app.get_tree().process_frame.connect(_tick)
	if not session.is_host:
		if not await until(func(): return finished,100): check(false,"host scenario completed"); await _finish()
		return
	check(await until(func(): return session.game.moves.size()==8),"eight atomic moves")
	phase="wait"; session.send("probe_phase",{"phase":phase}); check(session.request_offer("undo"),"physical undo requested")
	check(await until(func(): return session.connected_ready and session.game.moves.size()==7),"physical undo confirmed")
	var key=session.game.state_key(); did_disconnect=true; session.link.disconnect_peer()
	check(await until(func(): return session.connected_ready),"physical reconnection")
	check(session.game.state_key()==key,"reconnect preserves complete position")
	check(session.request_offer("rematch"),"physical rematch request")
	check(await until(func(): return session.connected_ready and session.game.moves.is_empty()),"physical rematch swaps seats")
	goal=4; phase="moves"; session.send("probe_phase",{"phase":phase,"goal":goal})
	check(await until(func(): return session.game.moves.size()==4),"swapped seats play")
	phase="wait"; session.send("probe_phase",{"phase":phase})
	check(session.request_offer("draw"),"physical draw request")
	check(await until(func(): return session.connected_ready and session.game.result_code=="draw"),"physical draw agreed")
	session.send("probe_done"); await app.get_tree().create_timer(0.5).timeout
	await _finish()
func _tick() -> void:
	if finished or session==null: return
	if phase=="moves" and session.game.moves.size()<goal and session.can_move():
		var moves=session.game.position.legal_moves()
		if not moves.is_empty(): session.submit(moves[0])
func _reconnect() -> void:
	if reconnecting: return
	reconnecting=true
	await app.get_tree().create_timer(0.5).timeout
	if not finished: session.reconnect()
	reconnecting=false
func _finish() -> void:
	if finished: return
	finished=true
	check(app.usi==null or app.usi.phase in ["stopped","idle","failed"],"device Chu engine isolation")
	var report={"platform":OS.get_name(),"host":session.is_host,"checks":checks,"failures":failures,"key":session.game.state_key(),"plies":session.game.moves.size(),"sequence":session.sequence,"result":session.game.result_code,"transport":"tcp-lan"}
	var file=FileAccess.open("user://chu-peer.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("CHU_DEVICE_PEER "+JSON.stringify(report))
	# Let the guest's scenario waiter return before freeing its script resource.
	for i in range(3): await app.get_tree().process_frame
	app.get_tree().quit(0 if failures.is_empty() else 1)
