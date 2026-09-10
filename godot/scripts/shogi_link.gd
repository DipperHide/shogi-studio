class_name ShogiLink
extends Node
## Bounded newline-framed JSON over TCP or Android secure Bluetooth RFCOMM.

signal opened
signal closed
signal received(message: Dictionary)
signal failed(message: String)
signal status_changed(message: String)

var server: TCPServer
var peer: StreamPeerTCP
var bluetooth: Object
var kind: String = "tcp"
var connected: bool = false
var connecting: bool = false
var incoming = PackedByteArray()
var outgoing = PackedByteArray()
var connect_deadline: int = 0

func host_tcp(port: int, bind_address: String = "*") -> Error:
	stop()
	kind = "tcp"
	server = TCPServer.new()
	var error = server.listen(port, bind_address)
	if error != OK:
		server = null
		failed.emit("无法创建对局，请换一个端口")
	return error

func join_tcp(address: String, port: int) -> Error:
	stop()
	kind = "tcp"
	peer = StreamPeerTCP.new()
	var error = peer.connect_to_host(address, port)
	if error != OK:
		failed.emit("无法连接此地址")
		return error
	connecting = true
	connect_deadline = Time.get_ticks_msec() + 10000
	return OK

func use_bluetooth(host: bool, address: String = "") -> Error:
	stop()
	if not Engine.has_singleton("ShogiPlatform"):
		failed.emit("此版本尚未提供该设备的蓝牙连接组件")
		return ERR_UNAVAILABLE
	kind = "bluetooth"
	bluetooth = Engine.get_singleton("ShogiPlatform")
	if not bluetooth.bluetooth_status.is_connected(_bluetooth_status):
		bluetooth.bluetooth_status.connect(_bluetooth_status)
		bluetooth.bluetooth_message.connect(_bluetooth_message)
	if host:
		bluetooth.hostBluetooth()
	else:
		bluetooth.connectBluetooth(address)
	return OK

func send(message: Dictionary) -> bool:
	if not connected:
		return false
	if message.get("reason") is String:
		message = message.duplicate()
		message.reason_code = message.reason.sha256_text().left(16)
	var text = JSON.stringify(message)
	var bytes = (text + "\n").to_utf8_buffer()
	if bytes.size() > 65536:
		failed.emit("对局消息超出大小限制")
		return false
	if kind == "bluetooth":
		return bluetooth.sendBluetooth(text)
	if outgoing.size() + bytes.size() > 262144:
		_drop("网络发送积压，请重新连接")
		return false
	outgoing.append_array(bytes)
	return true

func _process(_delta: float) -> void:
	if kind != "tcp":
		return
	if server != null and server.is_connection_available():
		var candidate = server.take_connection()
		if peer == null:
			peer = candidate
			connecting = true
			connect_deadline = Time.get_ticks_msec() + 10000
		else:
			candidate.disconnect_from_host()
	if peer == null:
		return
	peer.poll()
	var state = peer.get_status()
	if state == StreamPeerTCP.STATUS_CONNECTED:
		if not connected:
			connected = true
			connecting = false
			peer.set_no_delay(true)
			opened.emit()
		if not outgoing.is_empty():
			var result = peer.put_partial_data(outgoing.slice(0, mini(16384, outgoing.size())))
			if result[0] not in [OK, ERR_BUSY]:
				_drop("连接已断开")
				return
			outgoing = outgoing.slice(result[1])
		var available = mini(peer.get_available_bytes(), 65536)
		if available > 0:
			var result = peer.get_data(available)
			if result[0] != OK:
				_drop("连接读取失败")
				return
			incoming.append_array(result[1])
		if incoming.size() > 131072:
			_drop("收到异常大小的消息")
			return
		var newline = incoming.find(10)
		var count = 0
		while newline >= 0 and count < 64:
			var line = incoming.slice(0, newline)
			incoming = incoming.slice(newline + 1)
			if line.size() > 65535:
				_drop("对局消息超出大小限制")
				return
			_decode(line.get_string_from_utf8())
			if peer == null:
				return
			newline = incoming.find(10)
			count += 1
	elif connected:
		_drop("")
	elif connecting and (state == StreamPeerTCP.STATUS_ERROR or Time.get_ticks_msec() > connect_deadline):
		_drop("连接失败或超时")

func _decode(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		_drop("对局消息格式无效")
		return
	received.emit(parsed)

func _bluetooth_message(message: String) -> void:
	if kind == "bluetooth" and connected:
		_decode(message)

func _bluetooth_status(state: String, message: String) -> void:
	if kind != "bluetooth":
		return
	status_changed.emit(message)
	if state == "connected":
		connected = true
		opened.emit()
	elif state in ["disconnected", "error", "permission_denied", "permission_required", "disabled", "unsupported"]:
		var was_connected = connected
		connected = false
		failed.emit(message)
		if was_connected:
			closed.emit()

func _drop(message: String) -> void:
	var was_connected = connected or connecting
	connected = false
	connecting = false
	if kind == "bluetooth" and bluetooth != null:
		bluetooth.disconnectBluetooth()
	if peer != null:
		peer.disconnect_from_host()
	peer = null
	incoming.clear()
	outgoing.clear()
	if not message.is_empty():
		failed.emit(message)
	if was_connected:
		closed.emit()

func disconnect_peer() -> void:
	_drop("")

func stop() -> void:
	disconnect_peer()
	if server != null:
		server.stop()
	server = null

func _exit_tree() -> void:
	stop()
	if bluetooth != null:
		if bluetooth.bluetooth_status.is_connected(_bluetooth_status):
			bluetooth.bluetooth_status.disconnect(_bluetooth_status)
			bluetooth.bluetooth_message.disconnect(_bluetooth_message)
