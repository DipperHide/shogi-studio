extends RefCounted
## Reference categories and score logic, with explicit shogi unit conversion.
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
const Tactics = preload("res://scripts/shogi_report_tactics.gd")
const NAMES = ["", "定式", "妙手", "锐利", "最佳", "优秀", "好棋", "不精确", "失误", "漏着", "错失胜机"]
const COLORS = ["8d6e63", "8d6e63", "24a993", "409bc5", "afde4d", "abda4d", "96af8b", "f7c045", "e48f2a", "c93431", "fe0000"]
const ICONS = ["", "ic_book_move", "ic_brilliant_move", "ic_great_move", "ic_bestmove", "ic_excellent_move", "ic_good_move", "ic_inaccuracy", "ic_mistake", "ic_blunder_icon", "ic_missed_win"]
const BAD = ["不精确", "失误", "漏着", "错失胜机"]
const MODEL = "shogi-classification-14-reference-adapted"
const EXPLANATIONS = {
	"定式": "与内置将棋开局示例匹配的理论着手，不计入准确率。",
	"妙手": "包含新出现的非步子力牺牲，经双候选复核仍是首选，且与第二选择有充分差距。",
	"锐利": "关键战术着，经双候选复核明显优于第二选择；当前识别新形成的多子攻击和子力牺牲。",
	"最佳": "与本次引擎分析的首选着手一致。",
	"优秀": "与最佳选择的评价差距很小，或后续深入搜索发现局面优于先前估计。",
	"好棋": "可行的选择，评价损失处于该局面的较小范围。",
	"不精确": "可以下得更好。严重程度结合行棋前后的优势和胜率损失判断。",
	"失误": "较明显的评价损失，或仍处优势时错过、送掉了可核实的子力。",
	"漏着": "严重失误，可能改变胜负走向；大优或大劣局面会结合胜率变化调整。",
	"错失胜机": "原有明显取胜优势或詰み机会，着手后未能维持。"
}

static func score(sample: Dictionary, side: int) -> float:
	var value = float(sample.score) * side
	if sample.get("mate", false): return signf(value) * (100000 - mini(49, absi(int(sample.get("mate_distance", 1)))))
	return value / Metrics.CP_SCALE

static func candidate_score(candidate: Dictionary) -> float:
	var value = float(candidate.get("score", 0))
	return signf(value) * (100000 - mini(49, absi(int(value)))) if candidate.get("score_type") == "mate" else value / Metrics.CP_SCALE

static func mate_distance(value: float) -> int:
	var distance = 100000 - absi(roundi(value))
	return signi(roundi(value)) * distance if distance >= 0 and distance < 50 else 0

static func mate_change(delta: int, before_distance: int) -> int:
	if absi(delta) > 100000: return 5
	if before_distance <= 3 and absi(delta) > 3: return 7
	return 5 if delta < 0 else 6

static func lost_mate(after: float, distance: int, winning: bool) -> int:
	if winning:
		if after < 500:
			if after > 200: return 8
			return 8 if distance <= 3 else 10
	elif after > -500:
		if after <= 0: return 8 if distance <= 3 else 10
		return 9 if distance > 3 else 8
	return 7

static func score_category(before: float, after: float, endgame: bool = false) -> int:
	# Verified against the APK's e2/m.N0 DEX branches. Mate sentinels are adapted
	# from USI's signed distance, rather than feeding them to centipawn thresholds.
	var loss = before - after
	var a = absf(before)
	var b = absf(after)
	var am = mate_distance(before)
	var bm = mate_distance(after)
	var category = 0
	if loss < 0: category = 5
	elif loss < 20:
		if bm == 0 and am != 0 and signf(before) == signf(after) and b >= 500: category = 7
		elif am == 0 and bm == 0: category = 5
		else: category = mate_change(bm - am, absi(am))
	elif before >= 500 and after <= 200: category = 10
	elif am > 0 and bm > 0: category = mate_change(bm - am, am)
	elif am > 0 and bm == 0: category = lost_mate(after, am, true)
	elif am < 0 and bm == 0: category = lost_mate(after, absi(am), false)
	elif am > 0 and bm < 0: category = 10
	elif am < 0 and bm < 0: category = mate_change(bm - am, absi(am))
	elif am == 0 and bm < 0: category = 7 if before <= -500 else 9
	else:
		var good: float
		var inaccurate: float
		var mistake: float
		if a <= 150:
			good = 60
			inaccurate = 90
			mistake = 180 if before < 0 else 220
		elif a <= 500:
			good = 60 - 0.05 * (a - 150)
			inaccurate = 120 + 0.18 * (a - 150)
			mistake = 220
		else:
			good = (a - 500) * 0.25 + 150
			inaccurate = maxf(80, 0.12 * a) + good
			mistake = maxf(140, 0.15 * a) + inaccurate
		if a > 150 and before < 0 and a > (200 if endgame else 300):
			good *= 1.6
			inaccurate *= 2
			mistake *= 3.5
		if loss <= good: category = 6
		elif loss <= inaccurate:
			category = 7
			if before > 150 and loss >= maxf(good, maxf(90, a * (0.25 if b <= 100 else 0.3))): category = 8
			elif before < -150 and after < before and (loss / a >= 0.35 if a > 180 else loss >= 110): category = 8
		elif loss <= mistake: category = 8
		else: category = 9
		if category < 8 and endgame and a <= 50 and loss >= 50 and after <= -100: category = 8
	if category in [8, 9] and (after >= 300 or (endgame and after >= 200)): category -= 1
	if category in [8, 9]:
		var lost_chance = Metrics.chance(before * Metrics.CP_SCALE) - Metrics.chance(after * Metrics.CP_SCALE)
		if lost_chance < 3: category = 7
		elif lost_chance < 8: category = 8
	return category

static func classify(game, ply: int, before: Dictionary, after: Dictionary, metrics: Dictionary, reached_endgame: bool = false) -> Dictionary:
	var position = game.positions[ply - 1]
	var move: Dictionary = game.moves[ply - 1]
	var played = Codec.move_name(move)
	var best = str(before.pv[0]) if not before.get("pv", []).is_empty() else ""
	var is_best = best == played
	var forced: bool = int(before.get("legal_count", 0)) == 1
	var a = score(before, position.turn)
	var b = score(after, position.turn)
	var endgame: bool = reached_endgame or before.get("mate", false) or after.get("mate", false) or Metrics.king_pressure(position) >= 4
	var category = 1 if metrics.book else 4 if is_best or forced else score_category(a, b, endgame)
	var evidence = {"model": MODEL, "before_cp": a, "after_cp": b, "endgame": endgame, "forced": forced,
		"best_match": is_best, "base_category": NAMES[category], "tactics": {}, "verification": {}}
	if category == 4 and not forced:
		evidence.tactics = Tactics.candidate(game, ply)
	# The reference retains explicit tactical mistakes even when the position is
	# still winning. Shogi exchange values include both the lost piece and its hand value.
	if category in [6, 7] and (b >= 300 or (endgame and b >= 200)):
		var tactical = Tactics.missed_material(position, move, best)
		evidence.tactics = tactical
		if before.get("mate", false) and absi(int(before.get("mate_distance", 0))) == 1 and a > 0: category = 8
		elif tactical.loss >= 2 * Metrics.CP_SCALE * 100: category = 8
		elif tactical.loss > 0 and (tactical.allowed > 0 or a - b >= 60): category = maxi(category, 7)
	return {"category": NAMES[category], "category_id": category, "forced": forced, "classification": evidence}

static func verify_best(row: Dictionary, candidates: Dictionary) -> Dictionary:
	var proof = {"accepted": false, "reason": "没有足够的候选线路"}
	if not candidates.has(1) or not candidates.has(2): return proof
	var first: Dictionary = candidates[1]
	var second: Dictionary = candidates[2]
	proof.candidates = [first.duplicate(true), second.duplicate(true)]
	if first.get("pv", []).is_empty() or second.get("pv", []).is_empty(): return proof
	if first.pv[0] != row.best or second.pv[0] == first.pv[0]: proof.reason = "复核首选与原着不一致"; return proof
	if first.get("bound", "") != "" or second.get("bound", "") != "": proof.reason = "候选评分只有界限"; return proof
	var a = candidate_score(first)
	var b = candidate_score(second)
	var gap = a - b
	var tactics: Dictionary = row.classification.tactics
	var sacrifice: bool = tactics.get("sacrifice", false)
	var threshold = 5.0 if sacrifice else maxf(100, roundf(absf(a) * 0.3)) if absf(a) < 400 else maxf(160, roundf(absf(a) * 0.2)) if absf(a) <= 800 else maxf(240, roundf(absf(a) * 0.24))
	proof.merge({"gap_cp": gap, "required_cp": threshold, "before_cp": a, "alternative_cp": b})
	if a <= -300 or gap < threshold or (not sacrifice and score_category(a, b, row.classification.endgame) not in [7, 8, 9, 10]):
		proof.reason = "优势、候选差距或战术条件不足"
		return proof
	proof.accepted = true
	proof.category_id = 2 if sacrifice and a > -200 and gap >= 40 else 3
	proof.reason = "牺牲子力后仍保持首选，复核候选差距充分" if proof.category_id == 2 else "关键战术着，经双候选复核仍明显优于第二选择"
	return proof
