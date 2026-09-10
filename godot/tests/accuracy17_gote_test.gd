extends SceneTree
const Report=preload("res://scripts/shogi_report.gd")
const Game=preload("res://scripts/shogi_game.gd")
const Codec=preload("res://scripts/shogi_usi_codec.gd")
const Rules=preload("res://scripts/shogi_rules.gd")
const Insight=preload("res://scripts/shogi_accuracy_insight.gd")
var checks=0
var failures: Array=[]

func _initialize() -> void: call_deferred("run")

func check(value: bool, title: String) -> void:
	checks+=1
	if not value: failures.append(title); printerr("GOTE INSIGHT FAIL: ",title)

func run() -> void:
	var source=Game.new()
	check(source.set_initial(Codec.sfen(Rules.new()).replace(" b "," w ")),"gote-first initial SFEN loads")
	for value in ["3c3d","7g7f"]:
		check(source.play(Codec.parse_move(value,source.position)),"actual legal gote-first move "+value)
	var report=Report.new()
	root.add_child(report)
	report.start(source,false,{"quick_mode":"depth","quick_depth":3},{"threads":1,"hash":32})
	var deadline=Time.get_ticks_msec()+15000
	while report.running and Time.get_ticks_msec()<deadline: await process_frame
	check(not report.running and report.error.is_empty() and report.samples.size()==3,"actual engine completes all gote-first positions")
	var gote=Insight.build(report,-1)
	var sente=Insight.build(report,1)
	check(gote.points.size()==1 and gote.points[0].ply==1,"gote keeps original ply one instead of even-number assumption")
	check(sente.points.size()==1 and sente.points[0].ply==2,"sente reply keeps original ply two")
	check(gote.points[0].before==report.samples[0] and gote.points[0].after==report.samples[1],"first gote point uses correct actual score pair")
	check(gote.impact.is_empty() and sente.impact.is_empty(),"single scored move has no counterfactual default highlight")
	var output=ProjectSettings.globalize_path("res://../review/app/chessis17/gote-core.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"source":source.to_data(),"samples":report.samples,"rows":report.rows,"gote":gote,"sente":sente},"  "))
	report.cancel()
	report.queue_free()
	await process_frame
	print("GOTE INSIGHT: ",checks," checks; ",failures)
	quit(0 if failures.is_empty() else 1)
