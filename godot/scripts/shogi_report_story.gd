extends RefCounted
## Reference a2/p.i, S, k, l, r and y, with the shared shogi scoring scale.
const Classification = preload("res://scripts/shogi_move_classification.gd")
const PhaseStory = preload("res://scripts/shogi_report_phase_story.gd")
const MODEL = "shogi-story-19-reference-adapted"
const BAD = ["失误", "漏着", "错失胜机"]

static func side_name(side: int) -> String:
	return "先手" if side == 1 else "后手"

static func state(value: float, threshold: float = 300) -> int:
	return 1 if value >= threshold else -1 if value <= -threshold else 0

static func balanced(value: float) -> bool:
	return absf(value) <= 100

static func mate_for(value: float, side: int) -> bool:
	return value * side > 90000 and value * side < 100000

static func event_type(before: float, after: float, side: int, category: String, endgame: bool) -> Dictionary:
	# DEX i: 00ab..0168. Do not use the inverted branches in the Java decompile.
	var loss = (before - after) * side
	var difference = absf(after - before)
	if category == "妙手": return {"kind": 5, "priority": 650, "weight": difference}
	if category not in BAD: return {}
	var a = before * side
	var b = after * side
	var first = state(before)
	var last = state(after)
	if first != 0 and last != 0 and first != last: return {"kind": 1, "priority": 1000, "weight": 0}
	if category == "错失胜机" and a >= 300 and b <= 100: return {"kind": 2, "priority": 850, "weight": loss}
	if a >= 300 and b <= 100: return {"kind": 3, "priority": 820, "weight": loss}
	if balanced(before) and last != 0 and difference >= 300: return {"kind": 4, "priority": 700, "weight": difference}
	var endgame_drop = endgame and loss >= 100 and balanced(before) and b <= -100
	if loss < 150 and not endgame_drop: return {}
	var threshold = 150 if endgame else 200
	if category != "错失胜机" and state(b, threshold) >= state(a, threshold): return {}
	# An already decisively losing position becoming still worse isn't a turning point.
	if first != 0 and first == last and first != side and absf(after) > absf(before): return {}
	return {"kind": 6, "priority": 500, "weight": loss}

static func reason(moment: Dictionary) -> String:
	var a: float = moment.before_cp
	var b: float = moment.after_cp
	var side: int = moment.side
	var name = side_name(side)
	var other = side_name(-side)
	if mate_for(b, -side) and not mate_for(a, -side):
		return name + ("让对方获得一步詰み。" if absi(Classification.mate_distance(b)) == 1 else "让对方获得强制詰み线路。")
	if mate_for(a, side) and not mate_for(b, side):
		return name + ("错过了一步詰み。" if absi(Classification.mate_distance(a)) == 1 else "错过了强制詰み线路。")
	if moment.kind == 5: return name + "找到了经引擎复核的妙手。"
	var previous_side = 0 if balanced(a) else int(signf(a))
	if previous_side != 0 and state(b) == -previous_side:
		return name + "扭转了局势。" if state(b) == side else name + "让局势倒向了" + other + "。"
	if a * side >= 300 and b * side <= 100:
		return name + ("让胜势回到了均势。" if balanced(b) else "失去了原有胜势。")
	if a * side >= 300 and b * side < 200: return name + "让较大优势明显缩水。"
	if balanced(a) and state(b) != 0:
		return name + "打破均势，取得胜势。" if state(b) == side else name + "让均势变成了" + other + "的胜势。"
	if a * side >= 200 and balanced(b): return name + "让局面回到了均势。"
	if moment.kind == 2: return name + "错过了取胜机会。"
	if b * side <= -200 and a * side > -100:
		return name + "让" + other + ("取得了终局胜势。" if moment.endgame else "取得了胜势。" if b * side <= -300 else "取得了较好局面。")
	if balanced(b): return name + "让局面回到了均势。"
	if b * side > 0: return name + "让较大优势明显缩水。"
	return name + "让" + other + ("取得了终局胜势。" if moment.endgame and b * side <= -100 else "取得了胜势。" if b * side <= -300 else "取得了较好局面。")

static func ranked(a: Dictionary, b: Dictionary) -> bool:
	if a.priority != b.priority: return a.priority > b.priority
	if a.weight != b.weight: return a.weight > b.weight
	return a.ply > b.ply

static func decisive_ranked(a: Dictionary, b: Dictionary) -> bool:
	if (a.category in BAD) != (b.category in BAD): return a.category in BAD
	if a.category in BAD and a.ply != b.ply: return a.ply > b.ply
	return ranked(a, b)

static func primary(events: Array, winner: int) -> Dictionary:
	if events.is_empty(): return {}
	var eligible: Array = []
	if winner != 0:
		eligible = events.filter(func(e): return e.side == -winner and e.category in BAD and e.after_cp * winner > 100)
		if eligible.is_empty(): eligible = events.filter(func(e): return e.side == -winner and e.category in BAD and e.after_cp * winner >= -100)
	if eligible.is_empty(): eligible = events.filter(func(e): return e.category in BAD)
	if eligible.is_empty(): eligible = events.filter(func(e): return e.category == "妙手" and (winner == 0 or e.side == winner))
	if eligible.is_empty(): eligible = events.duplicate()
	eligible.sort_custom(decisive_ranked)
	return eligible[0]

static func facts(scores: Array, rows: Array) -> Dictionary:
	var data = {"peak_sente": 0.0, "peak_gote": 0.0, "state_changes": 0, "reversals": 0,
		"first_decisive": -1, "prior_peak": 0.0, "returned_to_balance": false, "last_cp": scores.back(),
		"sente_bad": 0, "gote_bad": 0, "sente_relevant_bad": 0, "gote_relevant_bad": 0}
	for i in range(scores.size()):
		var value: float = scores[i]
		data.peak_sente = maxf(data.peak_sente, value)
		data.peak_gote = maxf(data.peak_gote, -value)
		if data.first_decisive < 0:
			if absf(value) >= 300: data.first_decisive = i
			else: data.prior_peak = maxf(data.prior_peak, absf(value))
		elif balanced(value): data.returned_to_balance = true
		if i == 0: continue
		var row: Dictionary = rows[i - 1]
		if row.category in BAD:
			var key = "sente" if row.side == 1 else "gote"
			data[key + "_bad"] += 1
			if scores[i - 1] * row.side > -200: data[key + "_relevant_bad"] += 1
		if row.category != "妙手" and absf(value - scores[i - 1]) >= 300 and state(value) != state(scores[i - 1]):
			data.state_changes += 1
			if state(value) != 0 and state(scores[i - 1]) != 0: data.reversals += 1
	return data

static func held(scores: Array, from_ply: int, side: int) -> bool:
	return scores.slice(from_ply).all(func(value): return value * side > 100)

static func describe(data: Dictionary, scores: Array, events: Array, chosen: Dictionary, closed: bool, winner: int, result_code: String, phase_data: Dictionary={}) -> Dictionary:
	var final_score: float = scores.back()
	var balanced_game: bool = maxf(data.peak_sente, data.peak_gote) < 300 and data.sente_bad + data.gote_bad == 0
	if closed and winner == 0 and balanced_game:
		return {"kind": "clean_draw", "text": "双方没有给出明显的取胜机会，局面保持接近，最终以和棋结束。"}
	if closed and winner != 0 and final_score * winner <= -300:
		return {"kind": "board_result_difference", "text": side_name(-winner) + "在棋盘上仍有胜势，" + ("但因超时告负。" if result_code == "timeout" else "但本局结果由" + side_name(winner) + "获胜。")}
	if closed and winner!=0 and balanced(final_score):
		var ending="但"+side_name(-winner)+"超时告负。" if result_code=="timeout" else "但"+side_name(-winner)+"认输了。" if result_code=="resign" else "但最终由"+side_name(winner)+"获胜。"
		return {"kind":"equal_end_"+("time" if result_code=="timeout" else "resigned" if result_code=="resign" else "result"),"text":"结束时棋盘局面仍接近均势，"+ending}
	if not closed and absf(final_score)>=300:
		return {"kind":"unknown_winning_end","text":side_name(int(signf(final_score)))+"在最新已分析局面中有胜势，尚无可确认的终局结果。"}
	if chosen.is_empty() and not phase_data.is_empty():
		return PhaseStory.describe(phase_data,closed,winner)
	if data.sente_bad > 0 and data.gote_bad > 0 and data.peak_sente >= 200 and data.peak_gote >= 200 and (data.state_changes >= 2 or data.reversals >= 1):
		var ending = "最终以和棋结束。" if closed and winner == 0 else "最终" + side_name(winner) + "获胜。" if closed else "目前仍可从关键着手回顾双方错过的机会。"
		return {"kind": "both_had_chances", "text": "局势多次变化，双方都曾获得机会。" + ending}
	if not chosen.is_empty():
		if chosen.kind == 5:
			return {"kind": "brilliant", "text": side_name(chosen.side) + "在第 %d 手找到了妙手，是本次分析的重要亮点。" % chosen.ply}
		var name = side_name(chosen.side)
		if closed and winner != 0:
			var prior_loser_peak: float = data.peak_gote if winner == 1 else data.peak_sente
			if prior_loser_peak >= 500 and chosen.side == -winner and chosen.kind in [1, 2, 3]:
				return {"kind": "comeback", "text": side_name(-winner) + "曾有胜势，但第 %d 手的%s让优势流失，" % [chosen.ply, chosen.category] + side_name(winner) + "最终逆转获胜。"}
			if chosen.side == -winner and final_score * winner > 100:
				var follow = "此后没有再回到均势。" if held(scores, chosen.ply, winner) else "此后局面仍有反复。"
				return {"kind": "turning_point", "text": name + "第 %d 手的%s是关键转折，" % [chosen.ply, chosen.category] + side_name(winner) + "最终将机会转化为胜利，" + follow}
		var outcome = "最终" + side_name(winner) + "获胜。" if closed and winner != 0 else "最终以和棋结束。" if closed else ""
		return {"kind": "advantage_change", "text": "第 %d 手是本次分析的关键转折：" % chosen.ply + reason(chosen) + outcome}
	if balanced_game:
		return {"kind": "balanced", "text": "已分析局面总体接近，没有发现单一的重大转折。" + (side_name(winner) + "最终获胜。" if closed and winner != 0 else "")}
	if closed and winner != 0:
		var first = -1
		for i in range(scores.size()):
			if scores[i] * winner >= 200: first = i; break
		if first >= 0 and held(scores, first, winner):
			return {"kind": "held_advantage", "text": side_name(winner) + "从第 %d 手起保持优势，直到最终获胜。" % first}
		return {"kind": "steady_result", "text": "本次分析未找到单一的重大转折，" + side_name(winner) + "最终获胜。"}
	if closed: return {"kind": "draw", "text": "局面曾有优势变化，最终以和棋结束。"}
	var side = state(final_score, 200)
	return {"kind": "current_position", "text": (side_name(side) + "在最新已分析局面中占优。" if side != 0 else "最新已分析局面接近均势。") + "尚无终局结果。"}

static func build(game, samples: Array, rows: Array, phases: Array, analysis_complete: bool) -> Dictionary:
	var count = mini(rows.size(), maxi(0, samples.size() - 1))
	var result = {"model": MODEL, "summary": "", "summary_kind": "empty", "moments": [], "facts": {}, "analyzed_plies": count, "complete": false, "closed": false}
	if game == null or count < 1: return result
	var scores: Array = []
	for sample in samples.slice(0, count + 1): scores.append(roundi(Classification.score(sample, 1)))
	var events: Array = []
	for i in range(count):
		var row: Dictionary = rows[i]
		var ply: int = i + 1
		var phase = "中局"
		for segment in phases:
			if ply >= segment.start and ply <= segment.end: phase = segment.name; break
		var candidate = event_type(scores[i], scores[ply], int(row.side), row.category, phase == "终局")
		if candidate.is_empty(): continue
		candidate.merge({"ply": ply, "side": row.side, "category": row.category, "label": row.label, "phase": phase,
			"endgame": phase == "终局", "before_cp": scores[i], "after_cp": scores[ply], "before": samples[i].duplicate(true), "after": samples[ply].duplicate(true)})
		if candidate.kind == 1: candidate.weight = ply
		candidate.reason = reason(candidate)
		events.append(candidate)
	var complete: bool = analysis_complete and count == game.moves.size()
	var closed: bool = complete and not game.result.is_empty()
	var winner: int = game.winner if closed else 0
	var data = facts(scores, rows.slice(0, count))
	var chosen = primary(events, winner)
	var ordered: Array = []
	if not chosen.is_empty(): ordered.append(chosen)
	var ranked_events = events.duplicate()
	ranked_events.sort_custom(ranked)
	for entry in ranked_events:
		if ordered.size() >= 10: break
		if chosen.is_empty() or entry.ply != chosen.ply: ordered.append(entry)
	var phase_data=PhaseStory.context(scores,rows.slice(0,count),phases)
	var summary = describe(data, scores, events, chosen, closed, winner, game.result_code,phase_data)
	# Never borrow a full game's known winner to describe an unfinished analysis prefix.
	var prefix = "已分析 %d / %d 手，以下仅概括已分析部分。" % [count, game.moves.size()] if not complete else ""
	if closed and summary.kind == "clean_draw": ordered.clear()
	result.merge({"summary": prefix + summary.text, "summary_kind": summary.kind, "moments": ordered,
		"facts": data, "phase_context":phase_data,"summary_reference":summary.get("reference",""),
		"summary_phase":summary.get("phase_type",0),"summary_phase_side":summary.get("phase_side",0),
		"complete": complete, "closed": closed, "winner": winner, "candidate_count": events.size()}, true)
	return result
