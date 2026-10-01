extends SceneTree
const S=preload("res://scripts/chu_session.gd")
class Radio extends RefCounted:
	signal bluetooth_status(state: String, message: String)
	signal bluetooth_message(message: String)
	var remote
	var messages=0
	var max_bytes=0
	func sendBluetooth(text: String) -> bool:
		messages+=1; max_bytes=maxi(max_bytes,text.to_utf8_buffer().size())
		remote._bluetooth_message.call_deferred(text); return true
	func disconnectBluetooth() -> void: pass
var checks=0
var failures:Array=[]
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text); push_error(text)
func frames(n: int=15) -> void:
	for i in range(n): await process_frame
func _initialize() -> void: run.call_deferred()
func run() -> void:
	Engine.max_fps=120
	var host=S.new(); var guest=S.new(); root.add_child(host); root.add_child(guest)
	host._setup(1,"bluetooth",0); host.transport="bluetooth"
	guest.is_host=false; guest.room_code="bluetooth"; guest.transport="bluetooth"
	var radio_a=Radio.new(); var radio_b=Radio.new(); radio_a.remote=guest.link; radio_b.remote=host.link
	host.link.kind="bluetooth"; guest.link.kind="bluetooth"; host.link.bluetooth=radio_a; guest.link.bluetooth=radio_b
	host.link._bluetooth_status("connected",""); guest.link._bluetooth_status("connected","")
	await frames()
	check(host.connected_ready and guest.connected_ready,"Bluetooth adapter handshake")
	for i in range(12):
		var actor=host if i%2==0 else guest
		check(actor.submit(actor.game.position.legal_moves()[0]),"Bluetooth submit "+str(i)); await frames(3)
		check(host.game.state_key()==guest.game.state_key(),"Bluetooth atomic state "+str(i))
	guest.request_offer("undo"); await frames(3); host.answer_offer(true); await frames()
	check(host.game.moves.size()==11 and guest.game.moves.size()==11,"Bluetooth confirmed undo")
	host.request_offer("draw"); await frames(3); guest.answer_offer(true); await frames()
	check(host.game.result_code=="draw" and guest.game.result_code=="draw","Bluetooth agreed draw")
	host.request_offer("rematch"); await frames(3); guest.answer_offer(true); await frames()
	check(guest.local_side==1 and host.game.moves.is_empty(),"Bluetooth rematch")
	var previous=guest.game.state_key()
	guest.link._bluetooth_message(JSON.stringify({"v":1,"type":"hello"})); await frames(2)
	check(not guest.connected_ready and guest.game.state_key()==previous,"old peer rejected without mutation")
	check(radio_a.max_bytes<65536 and radio_b.max_bytes<65536,"Bluetooth message bound")
	check(radio_a.messages>10 and radio_b.messages>10,"real adapter serialized messages")
	host.queue_free(); guest.queue_free(); await frames(2)
	print("CHU_BLUETOOTH_RESULT "+JSON.stringify({"checks":checks,"failures":failures,"physical_two_phone_test":false}))
	quit(0 if failures.is_empty() else 1)
