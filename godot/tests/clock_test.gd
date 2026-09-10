extends SceneTree
const Clock = preload("res://scripts/shogi_clock.gd")
const Game = preload("res://scripts/shogi_game.gd")
var failures: Array[String] = []
var checks: int = 0

func check(value: bool, title: String) -> void:
	checks += 1
	if not value:
		failures.append(title)
		printerr("CLOCK FAIL: ", title)

func _initialize() -> void:
	var clock = Clock.new()
	clock.configure(1, 0)
	clock.tick(false, 0)
	clock.tick(false, 12500)
	check(clock.remaining[1] == 287500 and clock.remaining[-1] == 300000, "only active player's main time is spent")
	clock.tick(true, 13500)
	check(clock.remaining[1] == 286500, "pausing accounts for elapsed time before pause")
	clock.tick(false, 70000)
	check(clock.remaining[1] == 286500, "resuming does not charge paused duration")
	clock.tick(false, 360000)
	check(clock.remaining[1] == 0 and clock.period_left == 26500, "main time overflow enters byoyomi exactly")
	clock.finish_turn(-1, 360000)
	check(clock.period_left == 30000 and clock.turn == -1, "byoyomi resets at move boundary")
	clock.tick(false, 361000)
	check(clock.remaining[-1] == 299000, "next player's main time runs")
	clock.finish_turn(1, 361000)
	clock.tick(false, 390999)
	check(clock.expired_side == 0 and clock.period_left == 1, "one remaining millisecond is playable")
	clock.tick(false, 391000)
	check(clock.expired_side == 1 and clock.paused, "exact byoyomi boundary expires")
	clock.tick(false, 500000)
	check(clock.period_left == 0 and clock.expired_side == 1, "expiry remains terminal")
	var restored = Clock.from_data(JSON.parse_string(JSON.stringify(clock.to_data())))
	check(restored != null and restored.expired_side == 1, "expired clock round-trips")
	for preset in range(6):
		clock.configure(preset, 0)
		check(Clock.from_data(clock.to_data()) != null, "preset %d serialization" % preset)
	clock.configure(0, 0)
	clock.tick(false, 0)
	clock.tick(false, 99999999)
	check(clock.expired_side == 0, "unlimited games never flag")
	var data = clock.to_data()
	data.expired = 1
	check(Clock.from_data(data) == null, "unlimited clock cannot contain timeout")
	clock.configure(4, 0)
	data = clock.to_data()
	data.period = 10001
	check(Clock.from_data(data) == null, "excess byoyomi rejected")
	data = clock.to_data()
	data.sente = -1
	check(Clock.from_data(data) == null, "negative time rejected")
	data = clock.to_data()
	data.turn = 0
	check(Clock.from_data(data) == null, "invalid side rejected")
	data = clock.to_data()
	data.period = 1.25
	check(Clock.from_data(data) == null, "fractional milliseconds rejected")
	var game = Game.new()
	game.clock.configure(4, 0)
	game.clock.tick(false, 0)
	game.clock.tick(false, 10000)
	game.update_result()
	check("后手获胜" in game.result and "超时" in game.result, "timeout awards opponent the game")
	var loaded = Game.from_data(JSON.parse_string(JSON.stringify(game.to_data())))
	check(loaded != null and loaded.result == game.result, "game timeout survives storage")
	game.undo()
	check(game.result.is_empty() and game.clock.period_left == 10000, "undo from zero-move timeout resets period without adding main time")
	var output = FileAccess.open(ProjectSettings.globalize_path("res://../review/app/complete/clock-tests.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	output.close()
	print("CLOCK TESTS: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
