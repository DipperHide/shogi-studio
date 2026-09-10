extends SceneTree
const Story = preload("res://scripts/shogi_report_story.gd")
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
const Game = preload("res://scripts/shogi_game.gd")
var checks = 0
var failures: Array = []
var results: Array = []

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures.append(title); printerr("STORY FAIL: ", title)

func _initialize() -> void:
	# Synthetic score fixtures exercise summary branches; none are engine measurements.
	for fixture in [[400,-400,1,"漏着",false,1], [600,50,1,"错失胜机",false,2], [350,90,1,"失误",false,3], [0,-400,1,"失误",false,4], [200,350,1,"妙手",false,5], [180,-180,1,"失误",true,6], [0,-150,1,"失误",true,6], [0,-150,1,"失误",false,0], [-400,-1500,1,"漏着",false,0], [700,350,1,"失误",false,0], [0,10,1,"最佳",false,0], [0,500,1,"锐利",false,0], [-400,400,-1,"漏着",false,1]]:
		var event = Story.event_type(fixture[0],fixture[1],fixture[2],fixture[3],fixture[4])
		check(event.get("kind",0) == fixture[5], "reference DEX event fixture " + str(fixture))
		results.append({"input": fixture, "actual": event})
	check(Story.reason(moment(20,-99999,1,6)).contains("一步詰み"), "allowed mate in one is explicit")
	check(Story.reason(moment(99995,300,1,2)).contains("错过了强制"), "missed forced mate is explicit")
	check(Story.reason(moment(500,20,1,2)).contains("均势"), "winning to equal explained")
	check(Story.reason(moment(-400,400,-1,1)).contains("先手"), "gote turn explains correct beneficiary")
	check(not Story.held([0,500,100,800],1,1), "equal return invalidates held advantage")
	check(Story.held([0,200,101,800],1,1), "held advantage checks every remaining sample")
	var events = [moment(400,-800,1,1,3), moment(0,-350,1,4,9), moment(0,400,1,5,11)]
	check(Story.primary(events,-1).ply == 9, "actual winner prioritizes latest decisive opponent mistake")
	events.sort_custom(Story.ranked)
	check(events[0].ply == 3, "remaining events use reference event priority")
	var full = fixture_story([0,0,400,-600,-650], ["最佳","漏着","漏着","最佳"], 4, true, -1)
	check(full.closed and full.winner == -1 and full.summary_kind == "both_had_chances", "finished volatile game reflects both chances and actual winner")
	var partial = fixture_story([0,0,400], ["最佳","漏着"], 4, false, -1)
	check(not partial.closed and partial.winner == 0 and partial.summary.contains("2 / 4") and not partial.summary.contains("获胜"), "partial analysis cannot borrow future result")
	var verifying = fixture_story([0,0,400,-600,-650], ["最佳","漏着","漏着","最佳"], 4, false, -1)
	check(not verifying.closed and not verifying.complete, "pending tactical verification remains incomplete")
	var draw = fixture_story([0,10,20], ["优秀","最佳"], 2, true, 0)
	check(draw.summary_kind == "clean_draw" and draw.moments.is_empty(), "quiet drawn game never invents key moments")
	var ongoing = fixture_story([0,10,20], ["优秀","最佳"], 2, true, 0, "")
	check(not ongoing.closed and not ongoing.summary.contains("和棋结束"), "unfinished game never described as a draw")
	var timeout = fixture_story([0,500,600], ["最佳","最佳"], 2, true, -1, "timeout")
	check(timeout.summary_kind == "board_result_difference" and timeout.summary.contains("超时"), "board advantage and timeout result distinguished")
	var scores: Array = [0]
	var categories: Array = []
	for i in range(14): scores.append(600 if i % 2 == 0 else -600); categories.append("漏着")
	var many = fixture_story(scores, categories, 14, true, 1)
	check(many.candidate_count == 14 and many.moments.size() == 10, "expanded summary capped at ten actual candidates")
	var ids = {}
	for entry in many.moments: ids[entry.ply] = true
	check(ids.size() == many.moments.size(), "primary moment never duplicated in remainder")
	check(Story.build(Game.new(),[],[],[],false).summary.is_empty(), "empty analysis has no fabricated narrative")
	var output = ProjectSettings.globalize_path("res://../review/app/chessis15")
	if "--chessis19-regression" in OS.get_cmdline_user_args(): output=ProjectSettings.globalize_path("res://../review/app/chessis19/story-regression")
	if "--chessis20-regression" in OS.get_cmdline_user_args(): output = ProjectSettings.globalize_path("res://../review/app/chessis20/story15_test")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("story-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"reference_fixtures":results,"synthetic_score_tests":true},"  "))
	print("STORY 15: ", checks, " checks; ", failures)
	quit(0 if failures.is_empty() else 1)

func moment(a: float,b: float,side: int,kind: int,ply: int=1) -> Dictionary:
	return {"before_cp":a,"after_cp":b,"side":side,"kind":kind,"endgame":false,"ply":ply,"category":"妙手" if kind==5 else "漏着","priority":{1:1000,2:850,3:820,4:700,5:650,6:500}[kind],"weight":absf(b-a)}

func fixture_story(scores: Array,categories: Array,total: int,complete: bool,winner: int,result_code: String="resign") -> Dictionary:
	var game = Game.new()
	for i in range(total): game.moves.append({})
	game.winner = winner
	game.result = "synthetic outcome fixture" if not result_code.is_empty() else ""
	game.result_code = result_code
	var samples: Array = []
	for value in scores: samples.append({"score":value*Metrics.CP_SCALE,"mate":false})
	var rows: Array = []
	for i in range(categories.size()): rows.append({"side":1 if i%2==0 else -1,"category":categories[i],"label":"synthetic fixture","ply":i+1})
	return Story.build(game,samples,rows,[{"name":"中局","start":1,"end":total}],complete)
