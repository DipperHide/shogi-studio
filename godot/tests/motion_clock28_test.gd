extends SceneTree
const Clock = preload("res://scripts/shogi_motion_clock.gd")
var checks = 0
var failures = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func _initialize() -> void:
	var clock = Clock.new()
	clock.begin(0.22)
	check(clock.step(9000000) == 0, "startup delay cannot advance an unseen animation")
	clock.drawn(9500000)
	check(is_equal_approx(clock.step(9516000), 0.016), "first advance uses time since the first displayed pose")
	check(clock.step(9532000) == 0, "multiple process callbacks cannot advance without another displayed frame")
	clock.drawn(9900000)
	check(is_equal_approx(clock.step(9916000), 0.22 / 9.0), "400 ms render stall advances at most one ninth of normal motion")
	clock.drawn(9920000)
	check(is_equal_approx(clock.step(9932000), 0.016), "stalled time debt is discarded rather than leaking into later frames")
	clock.suspend()
	check(clock.step(99000000) == 0, "paused or hidden time cannot advance motion")
	clock.drawn(100000000)
	check(is_equal_approx(clock.step(100016000), 0.016), "resume starts from a newly presented pose")
	clock.drawn(100020000)
	check(clock.step(99999000) == 0, "backward clock samples never rewind animation")
	for duration in [0.12, 0.22, 0.4, 0.5]:
		clock.begin(duration)
		var elapsed = 0.0
		var now = 1000000
		clock.drawn(now)
		var steps = 0
		while elapsed + 0.000001 < duration:
			now += 400000
			elapsed += clock.step(now)
			steps += 1
			clock.drawn(now)
		check(steps >= 9, "even repeated stalls preserve multiple visible poses at speed " + str(duration))
		check(steps <= 16, "slow devices still make bounded progress at speed " + str(duration))
	clock.begin(0)
	clock.drawn(100)
	check(clock.step(1000000) == 0, "disabled animation has no timed movement")
	var output = ProjectSettings.globalize_path("res://../review/app/chessis28")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("motion-clock-core.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	print("MOTION CLOCK 28: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)
