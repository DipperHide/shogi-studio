extends RefCounted
## Advance only after a displayed frame. Never replay a stalled frame's debt.
var step_limit = 1.0 / 30.0
var last_tick = -1
var presented = 0
var consumed = 0

func begin(duration: float) -> void:
	# A cubic ease advances less than 30% of its path over 1/9 of its time.
	step_limit = minf(1.0 / 30.0, maxf(0, duration) / 9.0)
	suspend()

func suspend() -> void:
	last_tick = -1
	presented = 0
	consumed = 0

func drawn(now: int) -> void:
	if last_tick < 0: last_tick = now
	presented += 1

func step(now: int) -> float:
	if last_tick < 0 or presented == consumed: return 0
	consumed = presented
	var delta = maxf(0, (now - last_tick) / 1000000.0)
	last_tick = now
	return minf(delta, step_limit)
