extends RefCounted
## The reference selected-move card's state labels and optional transition text.
const Classification = preload("res://scripts/shogi_move_classification.gd")
const Story = preload("res://scripts/shogi_report_story.gd")
const SUFFIX = {"妙手": "!!", "锐利": "!", "失误": "?", "漏着": "??", "错失胜机": "???"}

static func normalized(sample: Dictionary) -> int:
	return roundi(Classification.score(sample, 1))

static func state_label(sample: Dictionary) -> String:
	var value = normalized(sample)
	if Story.balanced(value): return "均势"
	return Story.side_name(int(signi(value))) + ("胜势" if absi(value) >= 300 else "占优")

static func score_label(sample: Dictionary) -> String:
	if sample.get("mate", false): return ("#" if sample.score > 0 else "−#") + str(absi(int(sample.get("mate_distance", 0))))
	return "%+.2f" % (float(sample.score) / 100)

static func transition(before: Dictionary, after: Dictionary, side: int) -> String:
	# a2/p.r returns no text for ordinary moves without a meaningful state change.
	var a = normalized(before)
	var b = normalized(after)
	var meaningful = (Story.mate_for(b, -side) and not Story.mate_for(a, -side)) or (Story.mate_for(a, side) and not Story.mate_for(b, side))
	var previous_side = 0 if Story.balanced(a) else signi(a)
	meaningful = meaningful or (previous_side != 0 and Story.state(b) == -previous_side)
	meaningful = meaningful or (a * side >= 300 and b * side < 200)
	meaningful = meaningful or (Story.balanced(a) and Story.state(b) != 0)
	meaningful = meaningful or (a * side >= 200 and Story.balanced(b))
	meaningful = meaningful or (b * side <= -200 and a * side > -100)
	if not meaningful: return ""
	return Story.reason({"before_cp": a, "after_cp": b, "side": side, "kind": 0, "endgame": false})
