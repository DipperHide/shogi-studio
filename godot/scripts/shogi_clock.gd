class_name ShogiClock
extends RefCounted
## Main time plus a fresh Japanese byoyomi period on every move.
const PRESETS = [
	{"name": "不限时", "main": 0, "period": 0},
	{"name": "5 分钟 + 每手 30 秒", "main": 300, "period": 30},
	{"name": "10 分钟 + 每手 30 秒", "main": 600, "period": 30},
	{"name": "10 分钟 + 每手 60 秒", "main": 600, "period": 60},
	{"name": "每手 10 秒", "main": 0, "period": 10},
	{"name": "每手 30 秒", "main": 0, "period": 30},
]
var preset: int = 0
var remaining: Dictionary = {1: 0, -1: 0}
var period_ms: int = 0
var period_left: int = 0
var turn: int = 1
var expired_side: int = 0
var paused: bool = true
var stamp: int = Time.get_ticks_msec()

func configure(index: int, now: int = -1) -> void:
	preset = clampi(index, 0, PRESETS.size()-1)
	remaining = {1: PRESETS[preset].main * 1000, -1: PRESETS[preset].main * 1000}
	period_ms = PRESETS[preset].period * 1000
	period_left = period_ms
	turn = 1
	expired_side = 0
	paused = true
	stamp = Time.get_ticks_msec() if now < 0 else now

func tick(pause: bool, now: int = -1) -> void:
	var current = Time.get_ticks_msec() if now < 0 else now
	var elapsed = maxi(0, current - stamp)
	stamp = current
	# Resume starts a new interval. Pausing accounts for time already spent.
	if preset != 0 and not paused and expired_side == 0:
		var main_spent = mini(remaining[turn], elapsed)
		remaining[turn] -= main_spent
		elapsed -= main_spent
		if remaining[turn] == 0:
			period_left = maxi(0, period_left - elapsed)
			if period_left == 0:
				expired_side = turn
	paused = pause or expired_side != 0

func finish_turn(side: int, now: int = -1) -> void:
	turn = side
	period_left = period_ms
	stamp = Time.get_ticks_msec() if now < 0 else now

func text_for(side: int, estimate: bool = false) -> String:
	if preset == 0: return ""
	var main: int = remaining[side]
	var period = period_left if side == turn else period_ms
	if estimate and not paused and side == turn and expired_side == 0:
		var elapsed = maxi(0, Time.get_ticks_msec() - stamp)
		var used = mini(main, elapsed)
		main -= used
		period = maxi(0, period - (elapsed-used))
	if main > 0:
		var seconds = ceili(main / 1000.0)
		return "%02d:%02d" % [seconds / 60, seconds % 60]
	return "%d 秒" % ceili(period / 1000.0)

func to_data() -> Dictionary:
	return {"preset": preset, "sente": remaining[1], "gote": remaining[-1], "period": period_left, "turn": turn, "expired": expired_side, "paused": paused}

static func from_data(data: Variant) -> ShogiClock:
	if not data is Dictionary or not data.get("paused") is bool:
		return null
	for field in ["preset", "sente", "gote", "period", "turn", "expired"]:
		var value = data.get(field)
		if (not value is int and not value is float) or not is_finite(float(value)) or value != int(value): return null
	if int(data.preset) < 0 or int(data.preset) >= PRESETS.size() or int(data.turn) not in [1,-1] or int(data.expired) not in [0,1,-1]: return null
	var clock = ShogiClock.new()
	clock.configure(int(data.preset))
	if data.sente < 0 or data.gote < 0 or data.sente > clock.remaining[1] or data.gote > clock.remaining[-1] or data.period < 0 or data.period > clock.period_ms: return null
	clock.remaining = {1: int(data.sente), -1: int(data.gote)}
	clock.turn = int(data.turn)
	clock.period_left = int(data.period)
	clock.expired_side = int(data.expired)
	clock.paused = data.paused
	if clock.expired_side != 0 and (clock.preset == 0 or clock.expired_side != clock.turn or clock.remaining[clock.turn] > 0 or clock.period_left > 0): return null
	return clock
