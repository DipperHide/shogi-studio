extends SceneTree
const Move = preload("res://scripts/shogi_report_move.gd")
const Metrics = preload("res://scripts/shogi_report_metrics.gd")
var checks = 0
var failures: Array = []

func check(value: bool, title: String) -> void:
	checks += 1
	if not value: failures.append(title); printerr("MOVE CARD FAIL: ", title)

func sample(cp: float) -> Dictionary:
	return {"score":cp*Metrics.CP_SCALE,"mate":false}

func _initialize() -> void:
	for entry in [[-301,"后手胜势"],[-299,"后手占优"],[-100,"均势"],[-99,"均势"],[0,"均势"],[100,"均势"],[101,"先手占优"],[299,"先手占优"],[300,"先手胜势"]]:
		check(Move.state_label(sample(entry[0]))==entry[1],"reference state threshold " + str(entry[0]))
	check(Move.transition(sample(20),sample(10),1).is_empty(),"ordinary best moves never get invented loss explanations")
	check(Move.transition(sample(-400),sample(-700),1).is_empty(),"already lost position has no invented new turning point")
	check(Move.transition(sample(400),sample(0),1).contains("均势"),"winning position becomes equal")
	check(Move.transition(sample(-400),sample(400),-1).contains("先手"),"gote gives away advantage to correct side")
	check(Move.transition(sample(0),sample(-200),1).contains("较好局面"),"equal game becomes opponent advantage")
	check(Move.transition(sample(300),sample(299),1).is_empty(),"state wording changes without inventing a serious error")
	var mate = {"score":-30000,"mate":true,"mate_distance":-3}
	check(Move.state_label(mate)=="后手胜势" and Move.score_label(mate)=="−#3","gote mate uses absolute orientation and compact distance")
	check(Move.transition(sample(0),mate,1).contains("强制詰み"),"new forced mate is explained")
	check(Move.score_label({"score":-251,"mate":false})=="-2.51","display retains native shogi units")
	var output=ProjectSettings.globalize_path("res://../review/app/chessis16")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("move-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"synthetic_score_tests":true},"  "))
	print("MOVE 16: ",checks," checks; ",failures)
	quit(0 if failures.is_empty() else 1)
