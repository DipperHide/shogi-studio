extends Node
## Real-time piece motion, with a visible start frame and bounded catch-up.
const Clock = preload("res://scripts/shogi_motion_clock.gd")
var clock = Clock.new()
var native: Tween
var canvas: CanvasItem
var complete_action: Callable
var paused = false
var active = false
var before_draw = false
var suspended = false

func begin(owner_canvas: CanvasItem, duration: float, update: Callable, complete: Callable = Callable(), curve: Tween.TransitionType = Tween.TRANS_CUBIC) -> void:
	canvas = owner_canvas
	complete_action = complete
	clock.begin(duration)
	process_priority = 100
	active = true
	if duration <= 0:
		update.call(1.0)
		_complete()
		return
	native = create_tween()
	native.tween_method(update, 0.0, 1.0, duration).set_trans(curve).set_ease(Tween.EASE_IN_OUT)
	native.tween_callback(_complete)
	# The engine's accumulated frame delta must not also advance this tween.
	native.pause()
	RenderingServer.frame_pre_draw.connect(_before_draw)
	RenderingServer.frame_post_draw.connect(_after_draw)

func visible() -> bool:
	return active and not paused and not suspended and is_instance_valid(canvas) and canvas.is_visible_in_tree() and get_window().visible and get_window().mode != Window.MODE_MINIMIZED and not get_tree().paused

func _before_draw() -> void:
	before_draw = visible()
	if not before_draw: clock.suspend()

func _after_draw() -> void:
	if before_draw and visible(): clock.drawn(Time.get_ticks_usec())
	before_draw = false

func _process(_delta: float) -> void:
	if not active: return
	if not visible(): clock.suspend(); return
	var elapsed: float = clock.step(Time.get_ticks_usec())
	if elapsed > 0: custom_step(elapsed)

func pause() -> void:
	paused = true
	clock.suspend()

func play() -> void:
	paused = false
	clock.suspend()

func custom_step(delta: float) -> bool:
	return native.custom_step(delta) if active and native != null and native.is_valid() else false

func disconnect_frames() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_before_draw): RenderingServer.frame_pre_draw.disconnect(_before_draw)
	if RenderingServer.frame_post_draw.is_connected(_after_draw): RenderingServer.frame_post_draw.disconnect(_after_draw)

func _complete() -> void:
	if not active: return
	active = false
	disconnect_frames()
	set_process(false)
	if complete_action.is_valid(): complete_action.call()
	complete_action = Callable()

func kill() -> void:
	active = false
	disconnect_frames()
	if native != null: native.kill()
	complete_action = Callable()
	queue_free()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED: suspended = true; clock.suspend()
	elif what == NOTIFICATION_APPLICATION_RESUMED: suspended = false; clock.suspend()

func _exit_tree() -> void:
	disconnect_frames()
	if native != null: native.kill()
	complete_action = Callable()
