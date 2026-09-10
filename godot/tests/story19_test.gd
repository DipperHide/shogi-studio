extends "res://tests/story15_test.gd"
const PhaseStory=preload("res://scripts/shogi_report_phase_story.gd")
var branch_cases=[]

func side_data(accuracy: float) -> Dictionary:
	return {"overall":{"accuracy":accuracy,"has_accuracy":true},"phases":[],"relevant":{},"inaccuracies":0,"first_advantage":-1,"minimum_after_advantage":2147483647,"better_phases":0}

func phase_data(kind: int,score: float,mistakes: int=0,blunders: int=0,missed: int=0) -> Dictionary:
	return {"type":kind,"name":Metrics.PHASE_NAMES[kind],"stats":{"accuracy":score,"has_accuracy":true,"counts":{"失误":mistakes,"漏着":blunders,"错失胜机":missed}}}

func base() -> Dictionary:
	return {"sample_count":20,"sides":{"1":side_data(80),"-1":side_data(79)},"phase_gap":{},"both_solid":false}

func branch(data: Dictionary,closed: bool,winner: int,expected: String,label: String) -> void:
	# Supply consistent per-phase scores so the independent DEX runner can derive
	# the same gap itself rather than accepting our precomputed phase selection.
	if not data.phase_gap.is_empty():
		var favored=int(data.phase_gap.side)
		var wins_left=int(data.sides[str(favored)].better_phases)-1
		var other_left=int(data.sides[str(-favored)].better_phases)
		data.sides["1"].phases=[]; data.sides["-1"].phases=[]
		for kind in [1,2,3]:
			var difference=0.0
			if kind==data.phase_gap.type: difference=data.phase_gap.gap*favored
			elif wins_left>0: difference=5*favored; wins_left-=1
			elif other_left>0: difference=-5*favored; other_left-=1
			data.sides["1"].phases.append(phase_data(kind,80+difference))
			data.sides["-1"].phases.append(phase_data(kind,80))
	var result=PhaseStory.describe(data,closed,winner)
	check(result.kind==expected,label+" → "+expected)
	branch_cases.append({"label":label,"context":data.duplicate(true),"closed":closed,"winner":winner,"result":result})

func _initialize() -> void:
	for winner in [1,-1]:
		for dominant in [false,true]:
			for profile in range(6):
				var data=base()
				var winning=data.sides[str(winner)]
				var loser=data.sides[str(-winner)]
				if dominant: winning.first_advantage=4; winning.minimum_after_advantage=-99
				if profile==1: loser.inaccuracies=2
				if profile==2: loser.relevant={"失误":1}; loser.phases=[phase_data(2,70,1)]
				if profile==3: loser.relevant={"失误":2}
				if profile==4: loser.relevant={"漏着":1}; loser.phases=[phase_data(3,40,0,1)]
				if profile==5: loser.relevant={"漏着":1,"错失胜机":1}
				var prefix="dominant_win" if dominant else "steady_win"
				var expected="gave_away_repeatedly" if profile==5 else prefix+{0:"",1:"_slips",2:"_one_mistake",3:"_mistakes",4:"_blunder"}[profile]
				branch(data,true,winner,expected,"outcome side=%d profile=%d dominant=%s"%[winner,profile,dominant])
		for profile in [0,1,3]:
			var data=base()
			data.phase_gap={"type":2,"name":"中局","side":winner,"gap":10}
			data.sides[str(winner)].better_phases=2
			if profile==1: data.sides[str(-winner)].inaccuracies=1
			if profile==3: data.sides[str(-winner)].relevant={"失误":2}
			branch(data,true,winner,"phase_win_all"+{0:"",1:"_slips",3:"_mistakes"}[profile],"multiple cleaner phases")
		for solid in [false,true]:
			var data=base()
			data.both_solid=solid
			if solid: data.sides["1"].overall.accuracy=85; data.sides["-1"].overall.accuracy=85
			data.phase_gap={"type":3,"name":"终局","side":winner,"gap":7}
			data.sides[str(winner)].better_phases=1
			branch(data,true,winner,"phase_win" if solid else "phase_win_plain","one decisive phase")
			data.sides[str(winner)].better_phases=2
			data.sides[str(-winner)].better_phases=1
			branch(data,true,winner,"phase_win" if solid else "phase_win_plain","other side also cleaner in one phase prevents all-phase claim")
			branch(data,true,-winner,"phase_steady_win" if solid else "steady_win","cleaner phase belongs to actual loser")
			branch(data,true,0,"phase_draw" if solid else "phase_draw_plain","completed draw phase")
			branch(data,false,0,"phase_neutral","unfinished phase has no result language")
	var data=base()
	data.sides["1"].first_advantage=10
	data.sides["1"].minimum_after_advantage=-99
	branch(data,true,1,"dominant_win","advantage starts exactly halfway")
	data.sides["1"].minimum_after_advantage=-100
	branch(data,true,1,"steady_win","touching minus100 breaks early control condition")
	data.sides["1"].first_advantage=11
	data.sides["1"].minimum_after_advantage=500
	branch(data,true,1,"steady_win","advantage starts beyond halfway")
	data=base()
	data.sides["-1"].relevant={"错失胜机":1,"失误":3}
	data.sides["-1"].inaccuracies=2
	branch(data,true,1,"steady_win","single missed win does not become a repeated-mistake profile")
	data=base()
	data.sides["-1"].relevant={"失误":1}
	data.sides["-1"].phases=[phase_data(1,80,1),phase_data(3,70,1)]
	branch(data,true,1,"steady_win","errors in two phases cannot be described as one phase")
	branch(base(),false,0,"default_no_moment","no measured phase gap means no invented phase claim")
	# Context boundaries use actual aggregation input shape, explicitly synthetic scores.
	var rows=[]
	var scores=[0,10,20,200,50,-199,-200,-201,0]
	for i in range(8):
		var side=1 if i%2==0 else -1
		rows.append({"ply":i+1,"side":side,"category":"失误","label":"分支测试数据","metrics":Metrics.move_metrics({"score":scores[i]*Metrics.CP_SCALE},{"score":scores[i+1]*Metrics.CP_SCALE},side,false,false,30)})
	var phases=[{"type":1,"name":"开局","start":1,"end":4},{"type":2,"name":"中局","start":5,"end":8},{"type":3,"name":"终局","start":9,"end":20}]
	var context=PhaseStory.context(scores,rows,phases)
	check(context.sides["1"].first_advantage==3 and context.sides["1"].minimum_after_advantage==-201,"early-control context examines all following positions")
	check(context.sides["1"].relevant["失误"]==3,"errors at exactly -200 are excluded from relevant mistake counts")
	check(context.sides["1"].phases.size()==2 and context.sides["-1"].phases.size()==2,"future unanalysed phases absent from narrative inputs")
	var prefix=PhaseStory.context(scores.slice(0,5),rows.slice(0,4),phases)
	check(prefix.sides["1"].minimum_after_advantage==50 and prefix.sides["1"].phases.size()==1,"partial phase context never examines future scores")
	var gap_rows=[]
	for i in range(4):
		gap_rows.append({"ply":i+1,"side":1 if i%2==0 else -1,"category":"最佳","metrics":{"accuracy":[90,85,85,90][i],"book":false,"weight":1,"cpl":0,"wpl":0,"before_chance":50,"after_chance":50}})
	var gap_phases=[{"type":1,"name":"开局","start":1,"end":2},{"type":2,"name":"中局","start":3,"end":4}]
	var gap_context=PhaseStory.context([0,0,0,0,0],gap_rows,gap_phases)
	check(gap_context.phase_gap.type==1 and gap_context.phase_gap.side==1 and gap_context.sides["-1"].better_phases==1,"equal five-point gaps keep earlier phase and count both sides")
	gap_rows[0].metrics.accuracy=89.9
	gap_context=PhaseStory.context([0,0,0,0,0],gap_rows,gap_phases)
	check(gap_context.phase_gap.type==2 and gap_context.sides["1"].better_phases==0,"gap below five never becomes a phase advantage")
	gap_rows[3].metrics.book=true; gap_rows[3].metrics.weight=0
	gap_context=PhaseStory.context([0,0,0,0,0],gap_rows,gap_phases)
	check(gap_context.phase_gap.is_empty(),"one unscored side makes a phase incomparable")
	gap_rows[0].metrics.accuracy=8.2; gap_rows[1].metrics.accuracy=3.2
	gap_context=PhaseStory.context([0,0,0,0,0],gap_rows,gap_phases)
	check(gap_context.phase_gap.type==1 and gap_context.phase_gap.gap==5,"displayed five-point decimal difference is not lost to binary rounding")
	for code in ["timeout","resign","other"]:
		var story=fixture_story([0,10,20],["最佳","最佳"],2,true,1,code)
		check(story.summary_kind=="equal_end_"+{"timeout":"time","resign":"resigned","other":"result"}[code],"balanced final board has specific result reason "+code)
	var unfinished=fixture_story([0,300],["最佳"],2,false,-1)
	check(unfinished.summary_kind=="unknown_winning_end" and not unfinished.closed and unfinished.winner==0 and not unfinished.summary.contains("获胜"),"partial winning evaluation does not borrow future winner")
	var output=ProjectSettings.globalize_path("res://../review/app/chessis20" if "--chessis20-regression" in OS.get_cmdline_user_args() else "res://../review/app/chessis19")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("story-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":branch_cases,"context_fixture":{"scores":scores,"rows":rows,"phases":phases,"actual":context},"synthetic_score_tests":true},"  "))
	print("STORY 19: ",checks," checks; ",failures)
	quit(0 if failures.is_empty() else 1)
