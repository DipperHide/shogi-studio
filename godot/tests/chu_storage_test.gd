extends SceneTree
const V=preload("res://scripts/shogi_variant.gd")
const B=preload("res://scripts/shogi_backup.gd")
const E=preload("res://scripts/shogi_exchange.gd")
class FakeApp extends RefCounted:
	const Preferences=preload("res://scripts/shogi_preferences.gd")
	var preferences=Preferences.new()
	var game=preload("res://scripts/shogi_game.gd").new()
	var records=preload("res://scripts/shogi_records.gd").new()
	var testing=true
class Progress extends RefCounted:
	var data={}
class Tutorial extends RefCounted:
	var progress=Progress.new()
	func _ensure_loaded() -> void: pass
var checks=0
var failures:Array=[]
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text); push_error(text)
func _initialize() -> void:
	var app=FakeApp.new(); var tutorial=Tutorial.new(); var service=B.new()
	app.records.root=ProjectSettings.globalize_path("res://../review/app/chu37/storage-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(app.records.root)
	service.chu_path=app.records.root.path_join("active-chu-session")
	var chu=V.Chu.new(); chu.play(chu.position.legal_moves()[0]); chu.comments["1"]="中将棋记录"
	check(chu.save_to(service.chu_path)==OK,"separate active Chu save")
	var path=app.records.archive(chu,"中将棋测试")
	check(not path.is_empty(),"archive Chu")
	var loaded=app.records.read(path)
	check(loaded!=null and V.is_chu(loaded) and loaded.state_key()==chu.state_key(),"archive route and full replay")
	var entry=app.records.list_all()[0]
	check(entry.variant=="chu" and entry.variant_label=="中将棋" and "中将棋" in entry.search,"archive label/search")
	var standard=app.game.to_data(); standard.erase("variant"); standard.erase("rules_id")
	check(V.from_data(standard)!=null,"legacy missing variant remains standard")
	standard.variant="unknown"; check(V.from_data(standard)==null,"unknown variant fails closed")
	var exchange=E.new()
	check(V.is_chu(exchange.parse(JSON.stringify(chu.to_data()))),"JSON import routing")
	for format in ["KIF","CSA","USI","SFEN"]: check(E.export_game(chu,format).is_empty(),"cannot masquerade as "+format)
	var bundle=service.collect(app,tutorial)
	check(bundle.shogi_backup==2 and bundle.chu_active!=null,"backup v2 includes both current games")
	check(service.restore(app,tutorial,JSON.parse_string(JSON.stringify(bundle)),false,false)==3,"v2 roundtrip all records plus both current games")
	var count=app.records.list_all().size()
	for field in ["variant","rules_id"]:
		var invalid=bundle.duplicate(true); invalid.records[0].game[field]="unknown"
		check(service.restore(app,tutorial,invalid,false,false)==-1 and app.records.list_all().size()==count,"bad "+field+" rejects before writes")
	var broken=bundle.duplicate(true); broken.records[0].game.moves[0].path=[999]
	check(service.restore(app,tutorial,broken,false,false)==-1 and app.records.list_all().size()==count,"damaged replay rejects whole backup")
	var legacy={"shogi_backup":1,"records":[{"title":"旧棋谱","game":app.game.to_data()}]}
	check(service.restore(app,tutorial,JSON.parse_string(JSON.stringify(legacy)),false,false)==1,"version 1 still restores")
	print("CHU_STORAGE_RESULT "+JSON.stringify({"checks":checks,"failures":failures})); quit(0 if failures.is_empty() else 1)
