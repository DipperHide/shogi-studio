extends SceneTree
const Session = preload("res://scripts/shogi_match_session.gd")
var failures: Array[String] = []
var checks: int = 0
var host
var guest

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): check(false,"timeout"); finish())
	call_deferred("run")

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("NETWORK CLOCK FAIL: ", title)

func until(predicate: Callable) -> bool:
	var deadline = Time.get_ticks_msec()+4000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func run() -> void:
	host = Session.new()
	guest = Session.new()
	root.add_child(host)
	root.add_child(guest)
	check(host.host_tcp(19323,1,"123456","127.0.0.1",1)==OK,"timed host opens")
	check(guest.join_tcp("127.0.0.1",19323,"123456")==OK,"timed guest joins")
	check(await until(func(): return host.connected_ready and guest.connected_ready),"timed handshake")
	check(guest.game.clock.preset==1 and not guest.game.clock_authority,"guest receives agreed time control without clock authority")
	await create_timer(.08).timeout
	check(host.game.clock.remaining[1]<300000 and host.game.clock.remaining[-1]==300000,"host clock runs only first player's time")
	check(host.request("draw"),"start timed negotiation")
	check(await until(func(): return not guest.offer.is_empty() and host.game.clock.paused),"negotiation pauses clock")
	var saved_time: int = host.game.clock.remaining[1]
	await create_timer(.12).timeout
	check(host.game.clock.remaining[1]==saved_time,"negotiation time is not charged")
	check(guest.answer(false),"decline timed negotiation")
	check(await until(func(): return host.offer.is_empty() and not host.game.clock.paused),"clock resumes after offer")
	guest.link.disconnect_peer()
	check(await until(func(): return not host.connected_ready and host.game.clock.paused),"disconnect pauses host clock")
	saved_time=host.game.clock.remaining[1]
	await create_timer(.12).timeout
	check(host.game.clock.remaining[1]==saved_time,"disconnected duration is not charged")
	check(guest.reconnect()==OK,"timed reconnect")
	check(await until(func(): return host.connected_ready and guest.connected_ready and not host.game.clock.paused),"clock resumes after authenticated reconnect")
	guest.link.send({"v":1,"type":"clock","match":guest.match_id,"ply":0,"key":guest._key(),"clock":{"preset":1,"sente":0,"gote":0,"period":0,"turn":1,"expired":1,"paused":true}})
	await create_timer(.08).timeout
	check(host.game.result.is_empty() and host.game.clock.expired_side==0,"guest cannot forge host timeout")
	host.game.clock.remaining[1]=0
	host.game.clock.period_left=80
	host.game.clock.stamp=Time.get_ticks_msec()
	check(await until(func(): return not host.game.result.is_empty() and not guest.game.result.is_empty()),"authoritative timeout reaches both clients")
	check(host.game.result==guest.game.result and "后手获胜" in guest.game.result,"timeout winner agrees")
	check(not guest.can_move(),"timeout disables moves")
	host.offer_received.connect(func(_action,local): if not local: host.answer(true))
	check(guest.request("rematch"),"request timed rematch")
	check(await until(func(): return guest.game.result.is_empty() and guest.local_side==1),"timed rematch swaps seats")
	check(host.game.clock.preset==1 and guest.game.clock.preset==1 and host.game.clock.remaining[-1]==300000,"rematch retains preset and replenishes clocks")
	finish()

func finish() -> void:
	var report = {"checks":checks,"failures":failures,"transport":"real TCP loopback, two match nodes"}
	var file=FileAccess.open(ProjectSettings.globalize_path("res://../review/app/complete/network-clock-tests.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	if host!=null: host.link.stop()
	if guest!=null: guest.link.stop()
	print("NETWORK CLOCK TESTS: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
