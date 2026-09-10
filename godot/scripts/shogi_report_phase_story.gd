extends RefCounted
## a2/p.c 0356..06e4, with helper I/N/p/j verified against the original DEX.
const Metrics=preload("res://scripts/shogi_report_metrics.gd")
const BAD=["失误","漏着","错失胜机"]
const TEXT={
	"dominant_win":"{winner}早早取得主动，此后没有给{loser}扳回局面的机会。",
	"dominant_win_slips":"{loser}没有明显失误，但细小的不精确让{winner}早早掌握主动并保持到终局。",
	"dominant_win_one_mistake":"{winner}利用{loser}在{phase}的一次失误取得主动，此后没有再放手。",
	"dominant_win_mistakes":"{winner}早早掌握主动，利用{loser}接连的失误将优势保持到终局。",
	"dominant_win_blunder":"{loser}在{phase}的一次漏着让{winner}取得主动，此后未能扳回。",
	"gave_away_repeatedly":"{loser}多次让优势流失，{winner}最终把机会转化为胜利。",
	"phase_win_all_mistakes":"{winner}在各阶段的表现持续优于{loser}，{loser}的失误最终决定了结果。",
	"phase_win_all_slips":"{winner}在各阶段的表现持续优于{loser}；{loser}虽无明显失误，却一直稍逊一筹。",
	"phase_win_all":"{winner}在各阶段的表现持续优于{loser}，并将优势转化为胜利。",
	"phase_win":"双方整体发挥稳健。{winner}在{phase}的表现优于{loser}，并最终获胜。",
	"phase_win_plain":"{winner}在{phase}的表现优于{loser}，{loser}此后未能完全恢复。",
	"phase_steady_win":"{winner}发挥稳健并最终获胜，全局没有单一的明显转折。",
	"phase_neutral":"{side}在{phase}的发挥更稳健。",
	"phase_draw":"双方整体发挥稳健。{side}在{phase}的表现更好，但{other}守住了均势。",
	"phase_draw_plain":"{side}在{phase}的表现更好，但{other}守住了均势。",
	"steady_win":"{winner}发挥稳健，最终获胜。",
	"steady_win_slips":"{winner}整体发挥更稳健，{loser}几次细小的不精确成了双方的差别。",
	"steady_win_one_mistake":"{winner}发挥稳健，抓住了{loser}在{phase}的一次失误。",
	"steady_win_mistakes":"{winner}保持稳健，{loser}的失误逐渐累积。",
	"steady_win_blunder":"{winner}保持稳健，抓住了{loser}在{phase}的一次漏着。",
	"default_no_moment":"局面总体接近，没有单一的重大转折。",
}

static func player(side: int) -> String: return "先手" if side==1 else "后手"

static func context(scores: Array, rows: Array, phases: Array) -> Dictionary:
	var result={"sample_count":scores.size(),"sides":{},"phase_gap":{},"both_solid":false}
	for side in [1,-1]:
		var data={"overall":Metrics.aggregate(rows,side),"phases":[],"relevant":{},"inaccuracies":0,
			"first_advantage":-1,"minimum_after_advantage":2147483647,"better_phases":0}
		for i in range(scores.size()):
			var value=float(scores[i])*side
			if data.first_advantage>=0: data.minimum_after_advantage=minf(data.minimum_after_advantage,value)
			elif value>=200: data.first_advantage=i
		for row in rows:
			if row.side!=side: continue
			if row.category=="不精确": data.inaccuracies+=1
			if row.category in BAD and row.ply>0 and row.ply<scores.size() and scores[row.ply-1]*side> -200:
				data.relevant[row.category]=int(data.relevant.get(row.category,0))+1
		for segment in phases:
			var stats=Metrics.aggregate(rows,side,segment.start,segment.end,false)
			if stats.count>0:
				data.phases.append({"type":segment.get("type",Metrics.PHASE_NAMES.find_key(segment.name)),"name":segment.name,"stats":stats})
		result.sides[str(side)]=data
	for phase_type in [1,2,3]:
		var a=phase_for(result,1,phase_type)
		var b=phase_for(result,-1,phase_type)
		if a.is_empty() or b.is_empty() or not a.stats.has_accuracy or not b.stats.has_accuracy: continue
		# Scores are stored at one decimal: compare their exact displayed tenths.
		var gap=(roundi(float(a.stats.accuracy)*10)-roundi(float(b.stats.accuracy)*10))/10.0
		if absf(gap)<5: continue
		var side=1 if gap>0 else -1
		result.sides[str(side)].better_phases+=1
		# Strict comparison: equally large phase gaps keep the earlier phase.
		if result.phase_gap.is_empty() or absf(gap)>result.phase_gap.gap:
			result.phase_gap={"type":phase_type,"name":a.name,"side":side,"gap":absf(gap)}
	result.both_solid=result.sides["1"].overall.has_accuracy and result.sides["-1"].overall.has_accuracy and result.sides["1"].overall.accuracy>=85 and result.sides["-1"].overall.accuracy>=85
	return result

static func phase_for(data: Dictionary,side: int,phase_type: int) -> Dictionary:
	for entry in data.sides[str(side)].phases:
		if entry.type==phase_type: return entry
	return {}

static func single_error_phase(data: Dictionary,severe: bool) -> Dictionary:
	var found={}
	for phase in data.phases:
		var counts=phase.stats.counts
		var amount=int(counts.get("漏着",0))+int(counts.get("错失胜机",0)) if severe else int(counts.get("失误",0))
		if amount<=0: continue
		if not found.is_empty(): return {}
		found=phase
	return found

static func error_profile(data: Dictionary) -> int:
	var blunders=int(data.relevant.get("漏着",0))
	var missed=int(data.relevant.get("错失胜机",0))
	var mistakes=int(data.relevant.get("失误",0))
	if blunders+missed>=2: return 5
	if missed==1: return 0
	if blunders==1: return 4 if not single_error_phase(data,true).is_empty() else 0
	if mistakes>=2: return 3
	if mistakes==1: return 2 if not single_error_phase(data,false).is_empty() else 0
	return 1 if data.inaccuracies>=1 else 0

static func phrase(kind: String,winner: int,side: int=0,phase: Dictionary={}) -> Dictionary:
	var arguments={"winner":player(winner),"loser":player(-winner),"side":player(side),"other":player(-side),"phase":str(phase.get("name",""))}
	return {"kind":kind,"text":TEXT[kind].format(arguments),"reference":"game_story_"+kind,"phase_type":phase.get("type",0),"phase_side":side}

static func outcome(data: Dictionary,winner: int,dominant: bool) -> Dictionary:
	var loser=data.sides[str(-winner)]
	var profile=error_profile(loser)
	if profile==5: return phrase("gave_away_repeatedly",winner)
	var suffix={0:"",1:"_slips",2:"_one_mistake",3:"_mistakes",4:"_blunder"}[profile]
	var phase=single_error_phase(loser,profile==4) if profile in [2,4] else {}
	return phrase(("dominant_win" if dominant else "steady_win")+suffix,winner,0,phase)

static func describe(data: Dictionary,closed: bool,winner: int) -> Dictionary:
	# Called only when no chosen key moment exists. Outcome checks run before it.
	if closed and winner!=0:
		var winning=data.sides[str(winner)]
		if winning.first_advantage>=0 and winning.first_advantage*2<=data.sample_count and winning.minimum_after_advantage> -100:
			return outcome(data,winner,true)
	var gap=data.phase_gap
	if winner!=0 and closed:
		if not gap.is_empty() and gap.side==winner:
			if data.sides[str(winner)].better_phases>=2 and data.sides[str(-winner)].better_phases==0:
				var profile=error_profile(data.sides[str(-winner)])
				return phrase("phase_win_all"+("_mistakes" if profile==3 else "_slips" if profile==1 else ""),winner,winner,gap)
			return phrase("phase_win" if data.both_solid else "phase_win_plain",winner,winner,gap)
		if data.both_solid: return phrase("phase_steady_win",winner)
		return outcome(data,winner,false)
	if not gap.is_empty():
		return phrase("phase_neutral" if not closed else "phase_draw" if data.both_solid else "phase_draw_plain",0,gap.side,gap)
	return phrase("default_no_moment",0)
