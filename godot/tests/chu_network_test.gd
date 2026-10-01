extends SceneTree
const S=preload("res://scripts/chu_session.gd")
var checks=0
var failures:Array=[]
var host
var guest
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func until(predicate: Callable, timeout: int=6000) -> bool:
	var started=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<timeout:
		if predicate.call(): return true
		await process_frame
	return false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Engine.max_fps=120
	host=S.new(); guest=S.new(); root.add_child(host); root.add_child(guest)
	check(host.host_tcp(19537,1,"370058","127.0.0.1")==OK,"TCP host")
	check(guest.join_tcp("127.0.0.1",19537,"370058")==OK,"TCP join")
	check(await until(func(): return host.connected_ready and guest.connected_ready),"handshake complete")
	if not host.connected_ready or not guest.connected_ready:
		print("DEBUG ",host.outgoing.size()," / ",guest.incoming," / ",guest.match_id)
		quit(1); return
	check(host.game.state_key()==guest.game.state_key(),"initial state agrees")
	var move=host.game.position.legal_moves()[0]
	check(host.submit(move),"host submit")
	check(await until(func(): return guest.game.moves.size()==1),"host applied")
	move=guest.game.position.legal_moves()[0]
	var before=guest.game.state_key()
	check(guest.submit(move) and guest.game.state_key()==before,"guest waits acknowledgement")
	check(await until(func(): return guest.game.moves.size()==2 and not guest.pending_move),"guest ack")
	check(host.game.state_key()==guest.game.state_key(),"complete move agrees")
	var stale={"v":2,"variant":"chu","rules_id":S.C.RULES_ID,"match":host.match_id,"seq":0,"type":"move","before":before,"move":move}
	host._message(stale); check(host.game.moves.size()==2,"stale message ignored")
	check(host.request_offer("undo"),"request undo")
	check(await until(func(): return not guest.offer.is_empty()),"offer delivered")
	guest.answer_offer(true)
	check(await until(func(): return host.connected_ready and guest.connected_ready and guest.game.moves.size()==1),"confirmed undo synchronized")
	check(host.game.state_key()==guest.game.state_key(),"undo agrees")
	check(guest.request_offer("draw"),"guest draw request")
	check(await until(func(): return not host.offer.is_empty()),"draw offer delivered")
	host.answer_offer(false)
	check(await until(func(): return guest.offer.is_empty()),"draw rejected without mutation")
	check(guest.request_offer("rematch"),"rematch request")
	check(await until(func(): return not host.offer.is_empty()),"rematch offer delivered")
	host.answer_offer(true)
	check(await until(func(): return host.connected_ready and guest.connected_ready and guest.game.moves.is_empty()),"rematch synchronized")
	check(host.local_side==-1 and guest.local_side==1,"rematch swaps sides")
	check(guest.submit(guest.game.position.legal_moves()[0]),"guest now starts")
	check(await until(func(): return host.game.moves.size()==1 and guest.game.moves.size()==1),"swapped roles playing")
	var saved=guest.to_data(); var old=host.game.state_key()
	guest.link.disconnect_peer()
	check(await until(func(): return not host.connected_ready),"disconnection retains board")
	check(host.game.state_key()==old,"host retained")
	guest.queue_free(); await process_frame
	guest=S.new(); root.add_child(guest)
	check(guest.restore(JSON.parse_string(JSON.stringify(saved))),"restore complete session")
	check(guest.reconnect()==OK,"reconnect")
	check(await until(func(): return host.connected_ready and guest.connected_ready),"reconnected handshake")
	check(host.game.state_key()==guest.game.state_key(),"restored peer agrees")
	# Build a real long history without allowing terminal positions. Padding is
	# unnecessary: 1,600 atomic moves alone exceed a transport frame.
	var long_game=S.Game.new(); var rng=RandomNumberGenerator.new(); rng.seed=58
	for i in range(1600):
		var legal=long_game.position.legal_moves(); var found=false
		for attempt in range(mini(legal.size(),200)):
			var trial=long_game.fork()
			if trial.play(legal[(attempt+rng.randi_range(0,legal.size()-1))%legal.size()]) and trial.result.is_empty(): long_game=trial; found=true; break
		if not found: break
		if i%100==0: await process_frame
	check(long_game.moves.size()==1600,"long legal history generated")
	check(JSON.stringify(long_game.to_data()).to_utf8_buffer().size()>65536,"long history exceeds message cap")
	host.game=long_game; host.sequence+=1; host._snapshot()
	check(await until(func(): return host.connected_ready and guest.connected_ready and guest.game.moves.size()==1600,15000),"chunked long history synced")
	check(host.game.state_key()==guest.game.state_key(),"chunked state agrees")
	# Corrupt and incomplete snapshots never replace the accepted game.
	var key=guest.game.state_key(); var header={"v":2,"variant":"chu","rules_id":S.C.RULES_ID,"match":host.match_id,"seq":host.sequence,"type":"snapshot_begin","id":"bad","count":1,"bytes":2,"digest":"bad","side":guest.local_side,"resume":guest.resume_token}
	guest._message(header)
	var part=header.duplicate(); part.type="snapshot_part"; part.index=0; part.data=Marshalls.raw_to_base64("{}".to_utf8_buffer()); guest._message(part)
	part.type="snapshot_end"; guest._message(part)
	check(guest.game.state_key()==key,"corrupt snapshot preserves current game")
	host._snapshot(); check(await until(func(): return host.connected_ready and guest.connected_ready),"recovery after corrupt snapshot")
	guest.resign(); check(await until(func(): return not host.game.result.is_empty() and not guest.game.result.is_empty()),"resignation synchronized")
	check(host.game.winner==guest.game.winner,"result agrees")
	# Exercise identical protocol through the Bluetooth message adapter without
	# claiming physical RFCOMM coverage. ShogiLink's adapter is shared unchanged.
	var simulated=S.new(); root.add_child(simulated); simulated.transport="bluetooth"
	var invalid=saved.duplicate(true); invalid.rules_id="unknown"
	check(not simulated.restore(invalid),"unknown stored rules refused")
	check(simulated.restore(saved),"Bluetooth session persistence schema")
	simulated.transport="bluetooth"; check(simulated.to_data().transport=="bluetooth","Bluetooth routing saved")
	var forged=host.game.to_data(); forged.moves[0].path=[-1]
	check(S.Game.from_data(forged)==null,"illegal network path validation")
	host.queue_free(); guest.queue_free(); simulated.queue_free(); await process_frame
	print("CHU_NETWORK_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"long_plies":long_game.moves.size()}))
	quit(0 if failures.is_empty() else 1)
