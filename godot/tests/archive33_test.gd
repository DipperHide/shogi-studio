extends SceneTree
const Records = preload("res://scripts/shogi_records.gd")
const Model = preload("res://scripts/shogi_archive_model.gd")
const Job = preload("res://scripts/shogi_archive_job.gd")
const Codec = preload("res://scripts/shogi_usi_codec.gd")
var checks = 0
var failures = []
var output = ProjectSettings.globalize_path("res://../review/app/chessis33")

func check(value: bool, title: String) -> void:
	checks+=1
	if not value: failures.append(title); push_error(title)

func _initialize() -> void: run.call_deferred()

func scan(directory: String, filters: Dictionary) -> Dictionary:
	var job=Job.new(); root.add_child(job)
	check(job.begin_index(directory,filters)==OK,"background scan starts")
	return await job.completed

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var store=Records.new(); store.root=output.path_join("core-records-"+str(Time.get_ticks_usec()))
	var game=Records.Game.new(); game.mode="local"
	check(game.play(Codec.parse_move("7g7f",game.position)),"fixture first move")
	check(game.play(Codec.parse_move("3c3d",game.position)),"fixture second move")
	game.metadata={"先手":"藤井聡太","後手":"豊島将之","棋戦":"王位戦","開始日時":"2026/09/08"}; game.comments["2"]="注释保留"
	var snapshot=game.to_data().duplicate(true)
	var path=store.archive(game,"夏季研究",{"favorite":true,"tags":["研究"," 升变 ","研究"],"created":100})
	check(not path.is_empty(),"record with metadata writes")
	var entry=store.list_all()[0]
	check(entry.favorite and entry.tags==["研究","升变"] and entry.created==100,"tags trim and deduplicate; creation time persists")
	check(entry.names=="藤井聡太 vs 豊島将之" and entry.event=="王位戦" and entry.plies==2,"Japanese metadata populates rows")
	check(store.read(path).to_data()==snapshot,"archive metadata leaves full game unchanged")
	var original_hash=entry.sha256
	check(store.update_metadata(path,{"favorite":false,"tags":["研究"],"created":100},original_hash),"favorite persists atomically")
	var new_hash=FileAccess.get_sha256(path)
	check(new_hash!=original_hash and not store.update_metadata(path,entry.archive,original_hash),"stale metadata write is rejected")
	check(FileAccess.get_sha256(path)==new_hash and not FileAccess.file_exists(path+".tmp"),"stale write preserves newer data and removes temporary file")
	check(store.rename_record(path,"重新命名"),"rename remains available")
	check(store.list_all()[0].created==100 and not store.list_all()[0].favorite,"rename keeps archive metadata")
	check(store.write(path,game,"再保存"),"normal game save succeeds")
	check(store.list_all()[0].tags==["研究"],"normal game save retains tags")
	for invalid in [null,[],{"favorite":1},{"tags":"a"},{"tags":[1]},{"tags":["a".repeat(61)]},{"created":-1},{"created":0.5},{"created":"12"},{"created":INF}]:
		check(Model.metadata(invalid).is_empty(),"malformed metadata rejected: "+str(invalid))
	var tags=[]
	for i in range(33): tags.append(str(i))
	check(Model.metadata({"tags":tags}).is_empty(),"tag count bounded")
	var before=FileAccess.get_sha256(path)
	check(not store.update_metadata(path,{"tags":[1]},before) and FileAccess.get_sha256(path)==before,"invalid metadata never changes file")
	check(not store.update_metadata(path.get_base_dir().path_join("../outside.json"),{},""),"metadata writes stay in archive directory")
	var oversized=store.document(path); oversized.title="a".repeat(Records.Game.MAX_SAVE_BYTES)
	check(not store.write_document(path,oversized) and FileAccess.get_sha256(path)==before,"oversized serialized record rejected before replacement")
	var raw_path=store.root.path_join("legacy.json")
	FileAccess.open(raw_path,FileAccess.WRITE).store_string(JSON.stringify(game.to_data()))
	var legacy=store.list_all().filter(func(item): return item.path==raw_path)[0]
	check(legacy.readable and not legacy.favorite and legacy.tags.is_empty(),"legacy raw game receives default archive metadata")
	check(store.update_metadata(raw_path,{"favorite":true,"tags":["旧版"],"created":200},legacy.sha256),"legacy raw game upgrades on favorite")
	check(store.read(raw_path).to_data()==snapshot,"legacy upgrade preserves comments and game")
	var second=store.archive(game,"春季対局",{"favorite":false,"tags":["実戦"],"created":300})
	var entries=store.list_all(); var filters=Model.defaults()
	check(Model.select(entries,filters)[0].path==second,"default order uses creation time")
	filters.oldest=true
	check(Model.select(entries,filters)[0].path==path,"oldest order ignores modification timestamps")
	filters.favorites=1
	check(Model.select(entries,filters).size()==1 and Model.select(entries,filters)[0].path==raw_path,"favorites filter")
	filters.favorites=2
	check(Model.select(entries,filters).size()==2,"non-favorites filter")
	filters=Model.defaults(); filters.tags=["旧版","実戦"]
	check(Model.select(entries,filters).size()==2,"selected tags use union")
	filters.query="藤井 王位"
	check(Model.select(entries,filters).size()==2,"query words combine with tag filter")
	filters.query="不存在"
	check(Model.select(entries,filters).is_empty(),"no-match search")
	check(Model.all_tags(entries)==["実戦","旧版","研究"],"tag facets are unique and sorted")
	filters=Model.defaults(); filters.sfen=Codec.sfen(game.positions[1])
	var result=await scan(store.root,filters)
	check(result.error.is_empty() and result.rows.size()==3,"SFEN search matches an intermediate position")
	filters.sfen=Codec.sfen(game.positions[1]).replace(" w "," b ")
	result=await scan(store.root,filters)
	check(result.error.is_empty() and result.rows.is_empty(),"position search includes side to move")
	filters.sfen="invalid"
	result=await scan(store.root,filters)
	check(not result.error.is_empty() and result.rows.is_empty(),"invalid SFEN shows an error")
	FileAccess.open(store.root.path_join("broken.json"),FileAccess.WRITE).store_string('{"title":"损坏棋谱","game":{"version":1,"moves":[{}]}}')
	filters=Model.defaults(); filters.sfen=Codec.sfen(game.positions[0])
	result=await scan(store.root,filters)
	check(result.rows.size()==3 and result.entries.size()==4,"position search excludes illegally replayed records")
	var cancelled=Job.new(); root.add_child(cancelled); cancelled.cancel()
	check(cancelled.begin_index(store.root,Model.defaults())==OK,"cancelled worker starts safely")
	result=await cancelled.completed
	check(result.rows.is_empty(),"cancelled scan reads no files")
	FileAccess.open(output.path_join("archive-core.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("Archive core: %d checks, %d failures"%[checks,failures.size()]); quit(0 if failures.is_empty() else 1)
