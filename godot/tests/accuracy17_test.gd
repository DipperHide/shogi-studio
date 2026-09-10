extends SceneTree
const Insight=preload("res://scripts/shogi_accuracy_insight.gd")
const Report=preload("res://scripts/shogi_report.gd")
const Game=preload("res://scripts/shogi_game.gd")
const Metrics=preload("res://scripts/shogi_report_metrics.gd")
var checks=0
var failures: Array=[]

func check(value: bool, title: String) -> void:
	checks+=1
	if not value: failures.append(title); printerr("ACCURACY 17 FAIL: ",title)

func sample(cp: float) -> Dictionary: return {"score":cp*Metrics.CP_SCALE,"mate":false}

func _initialize() -> void:
	var report=Report.new()
	report.game=Game.new()
	report.game.metadata={"先手":"样例先手","后手":"样例后手"}
	check(Insight.build(report,1).points.is_empty() and not Insight.build(report,1).overall.has_accuracy,"empty report has no invented points or accuracy")
	for i in range(8): report.samples.append(sample([0,20,30,10,-400,-350,-350,-200][i]))
	for ply in range(1,8):
		var side=1 if ply%2==1 else -1
		var book=ply==1
		var metrics=Metrics.move_metrics(report.samples[ply-1],report.samples[ply],side,ply==5,book,1 if ply==3 else 30)
		report.rows.append({"ply":ply,"side":side,"category":"定式" if book else "漏着" if ply==4 else "最佳","label":"合成着手 %d" % ply,"metrics":metrics})
	var before_rows=report.rows.duplicate(true)
	var sente=Insight.build(report,1)
	var gote=Insight.build(report,-1)
	check(sente.player=="样例先手" and gote.player=="样例后手","actual metadata names and side retained")
	check(sente.points.map(func(p):return p.ply)==[5,7],"book and forced moves excluded without renumbering plies")
	check(gote.points.map(func(p):return p.ply)==[2,4,6],"gote points use original even plies")
	check(sente.overall==report.summary(1) and gote.overall==report.summary(-1),"hero and baseline exactly match main report aggregation")
	for point in gote.points:
		check(point.before==report.samples[point.ply-1] and point.after==report.samples[point.ply],"before and after preserve absolute score at ply "+str(point.ply))
	check(report.rows==before_rows,"leave-one-out impact does not mutate report rows")
	var preserved=float(sente.points[0].before.score)
	report.samples[4].score=12345
	check(sente.points[0].before.score==preserved,"open insight snapshot owns its score data")
	report.samples[4]=sample(-400)
	var original=report.samples.duplicate(true)
	report.samples=report.samples.slice(0,4)
	var partial=Insight.build(report,-1)
	check(partial.points.size()==1 and partial.points[0].ply==2,"missing or unfinished later positions do not make chart points")
	check(partial.impact.is_empty(),"one scored move cannot have a leave-one-out impact")
	report.samples=original
	for entry in [[-600,"后手胜势"],[-599,"后手明显占优"],[-250,"后手明显占优"],[-249,"后手略优"],[-50,"后手略优"],[-49,"大致均势"],[0,"大致均势"],[49,"大致均势"],[50,"先手略优"],[249,"先手略优"],[250,"先手明显占优"],[599,"先手明显占优"],[600,"先手胜势"]]:
		check(Insight.state_label(sample(entry[0]))==entry[1],"reference insight threshold "+str(entry[0]))
	check(Insight.state_label({"score":-30000,"mate":true,"mate_distance":-3})=="后手胜势","mate state uses correct beneficiary")
	check(Insight.engine_label({"before":{"score":125,"mate":false},"after":{"score":-30000,"mate":true,"mate_distance":-3}}).contains("+1.25") and Insight.engine_label({"before":sample(0),"after":{"score":-30000,"mate":true,"mate_distance":-3}}).contains("−#3"),"selected card displays native score and mate distance")
	for category in ["不精确","失误","漏着","错失胜机"]:
		check(Insight.accuracy_label({"accuracy":100,"category":category}).begins_with("不适用"),"decisive-position exception for "+category)
	check(Insight.accuracy_label({"accuracy":99.99,"category":"失误"})=="99.9","sub-100 move never rounds to perfect")
	check(Insight.accuracy_label({"accuracy":100,"category":"最佳"})=="100.0","actual best move keeps perfect accuracy")
	var b={"gain":2.0,"accuracy":20.0,"ply":5}
	check(Insight.prefers({"gain":2.1,"accuracy":90,"ply":9},b),"impact gain has first priority")
	check(Insight.prefers({"gain":2.0,"accuracy":19,"ply":9},b),"equal gain prefers lower move accuracy")
	check(Insight.prefers({"gain":2.0,"accuracy":20,"ply":3},b),"final impact tie prefers earlier ply")
	check(not Insight.prefers({"gain":1.9,"accuracy":0,"ply":1},b),"bad raw move does not replace larger measured contribution")
	var output=ProjectSettings.globalize_path("res://../review/app/chessis17")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("accuracy-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"synthetic_score_fixtures":true},"  "))
	report.free()
	print("ACCURACY 17: ",checks," checks; ",failures)
	quit(0 if failures.is_empty() else 1)
