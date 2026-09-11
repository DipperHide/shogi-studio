extends "res://tests/chessis23_test.gd"
const Model = preload("res://scripts/shogi_archive_model.gd")
var archive
var original_review
var original_data
var path: String
var id: String
var motions = []

class Picker extends RefCounted:
	signal analysis_record_imported(request: int, text: String, error: String)
	var request = 0
	func pickAnalysisRecord(value: int) -> void: request=value

func ready_list() -> void:
	check(await until(func(): return app.ui.page_name=="analysis-recent" and not archive.indexing and not archive.busy,8),"personal archive finishes background work")
	await settle()

func unchanged(label: String) -> void:
	preserve(label)
	check(app.review_game==original_review and app.replay_index==2 and original_review.to_data()==original_data,label+" preserves active replay")

func run(instance) -> void:
	app=instance; output=ProjectSettings.globalize_path("res://../review/app/chessis33/ui")
	DirAccess.make_dir_recursive_absolute(output)
	app.records.root=output.path_join("records-"+str(Time.get_ticks_usec())); app.save_path=output.path_join("active.json"); app.ui.tutorial.progress_path=output.path_join("learning.json")
	app.get_tree().create_timer(240).timeout.connect(func(): app.get_tree().quit(2))
	await resize(Vector2i(393,852))
	app._start_match("local",1,2,"basic"); app.ui.close()
	live=app.game; saved_live=live.to_data().duplicate(true); practice=app.ui.practice
	var source=app.Game.new(); source.mode="local"
	check(source.set_initial("k8/9/4p4/4R4/9/9/9/9/8K b P 1"),"preview fixture legal")
	for move in ["5d5c+","9a8a","P*5d","8a9a"]: check(source.play(app.Codec.parse_move(move,source.position)),"capture, promotion and drop fixture "+move)
	source.metadata={"先手":"藤井聡太","後手":"豊島将之","棋戦":"研究棋谱","開始日時":"2026/09/08"}; source.comments["2"]="需要保留的注释"
	original_review=app.Game.from_data(source.to_data()); original_data=original_review.to_data().duplicate(true)
	app.review_game=original_review; app.replay_index=2; app._refresh()
	path=app.records.archive(source,"升变与打入",{"favorite":false,"tags":["研究"],"created":500})
	id=path.get_file().sha256_text().left(12)
	for i in range(24): app.records.archive(source,"棋谱 %02d"%i,{"favorite":false,"tags":["其他"],"created":i})
	app.ui.show_import_analysis(0); app.ui.analysis_import.set_source("position startpos moves 7g7f")
	await capture("archive-entry")
	await press("AnalysisRecent"); archive=app.ui.archive_view; await ready_list()
	if not is_instance_valid(archive.list):
		print("Archive entry failed; page=",app.ui.page_name); await capture("archive-entry-failure"); await finish(); return
	check(archive.entries.size()==25 and archive.list.find_children("ArchiveRow_*","PanelContainer",false,false).size()==20,"personal library pages 20 of 25 records")
	await press("ArchiveMore"); check(archive.list.find_children("ArchiveRow_*","PanelContainer",false,false).size()==25,"load more reveals remaining records")
	await press("ArchiveFavorite_"+id); await settle()
	check(app.records.document(path).archive.favorite,"touch favorite persists to disk")
	await press("ArchiveInfo_"+id); await settle()
	check(not app.ui.page.find_child("ArchiveInfo_"+id,true,false).visible,"info expands once")
	await press("ArchiveMasterGames")
	check(app.ui.page_name=="tournament-archive" and not is_instance_valid(archive.fab),"master tab hides personal import action")
	await press("OfflineTournaments"); check(app.ui.tournament_view.rows.size()==195,"unified master tab retains complete offline library")
	await press("ArchiveMyGames"); await ready_list()
	check(archive.entries.filter(func(item): return item.path==path)[0].favorite,"favorite survives tab reload")
	for mode in ["dark","light"]:
		app.set_preference("color_mode",mode)
		for dimensions in [Vector2i(360,760),Vector2i(393,852),Vector2i(852,393),Vector2i(1100,800)]:
			await resize(dimensions); await settle()
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()) and app.ui.page.size==app.safe_rect().size,"personal list fills safe area "+str(dimensions))
			check(app.safe_rect().encloses(archive.fab.get_global_rect()) and archive.fab.size==Vector2(56,56),"import circle remains visible and square")
			var title=app.ui.page.find_child("ArchiveTitle",true,false)
			check(title.get_theme_font_size("font_size")==18 and title.size.y<45,"reference compact header")
			await capture("archive-%s-%d"%[mode,dimensions.x])
			await press("ArchiveFilter")
			check(await until(func(): return archive.reveal==1,4),"filter entrance paints to completion")
			check(app.safe_rect().encloses(app.ui.page.get_global_rect()),"personal filter fits window")
			var apply=app.ui.page.find_child("ArchiveFilterApply",true,false)
			check(app.ui.page.get_global_rect().encloses(apply.get_global_rect()),"apply action remains outside scrolling content")
			archive.draft.query="cancelled"; await press("ArchiveFilterClose"); await ready_list()
			check(archive.filters.query.is_empty(),"closing filter discards draft")
	await resize(Vector2i(393,852)); await press("ArchiveFilter")
	check(await until(func(): return archive.reveal==1,4),"filter reopened")
	archive.draft.favorites=1; archive.draft.tags=["研究"]; archive.draft.sfen=app.Codec.sfen(source.positions[3])
	await press("ArchiveFilterApply"); await ready_list()
	check(archive.rows.size()==1 and archive.rows[0].path==path,"favorites, tags and intermediate SFEN combine")
	await capture("archive-filtered")
	await press("ArchiveEdit_"+id)
	check(await until(func(): return app.ui.page_name=="archive-edit",8),"edit parses private record")
	var title=app.ui.page.find_child("ArchiveEditTitle",true,false); title.text="保存的新名称"
	app.ui.page.find_child("ArchiveEditTags",true,false).text="研究，升变，升变"
	await press("ArchiveEditSave"); await ready_list()
	check(app.records.document(path).title=="保存的新名称" and app.records.document(path).archive.tags==["研究","升变"],"editor persists title and normalized tags")
	check(app.records.read(path).comments["2"]=="需要保留的注释","metadata editor preserves annotations")
	await press("ArchivePreview_"+id)
	check(await until(func(): return app.ui.page_name=="archive-preview",8),"preview parses privately")
	var preview=archive.preview; var preview_data=preview.game.to_data().duplicate(true)
	check(preview.ply==0 and preview.game.metadata["棋戦"]=="研究棋谱","record preview starts at initial position and retains event")
	for dimensions in [Vector2i(360,760),Vector2i(852,393),Vector2i(1100,800)]:
		await resize(dimensions); await settle()
		check(app.ui.page_scroll.get_global_rect().encloses(preview.board.get_global_rect()),"preview board and hands fit scroll viewport "+str(dimensions))
		check(app.safe_rect().encloses(preview.footer.get_global_rect()),"preview load controls stay on screen")
		await capture("preview-%d"%dimensions.x)
	await resize(Vector2i(393,852))
	for target in [1,2,3]:
		await press("OpeningNext")
		var frames=[]; var deadline=Time.get_ticks_msec()+5000
		while Time.get_ticks_msec()<deadline:
			await RenderingServer.frame_post_draw; frames.append(preview.board.motion)
			if preview.board.motion==1: break
		check(frames.any(func(value): return value>0 and value<1) and frames[-1]==1,"preview paints intermediate frames at ply "+str(target))
		motions.append(frames)
	check(preview.game.to_data()==preview_data,"preview navigation does not mutate game data")
	unchanged("preview and metadata operations")
	await capture("preview-promoted-drop")
	await press("ArchiveLoadPreview"); await settle()
	check(app.ui.page==null and app.replay_index==3 and app.review_path==path and app.review_game.positions[3].board[app.Codec.parse_square("5c")]==15,"load preview retains chosen ply and promoted rook")
	check(app.ui.continue_button.visible,"loaded preview offers continuation from current position")
	preserve("loading independent preview")
	# Backup includes archive metadata; invalid metadata must fail before any writes.
	var service=preload("res://scripts/shogi_backup.gd").new(); var bundle=service.collect(app,app.ui.tutorial)
	var row=bundle.records.filter(func(item): return item.title=="保存的新名称")[0]
	check(row.archive.favorite and row.archive.tags==["研究","升变"],"backup contains favorites and tags")
	var invalid=bundle.duplicate(true); invalid.records[0].archive.tags=[42]
	var count_before=app.records.list_all().size()
	check(service.restore(app,app.ui.tutorial,invalid,false,false)==-1 and app.records.list_all().size()==count_before,"invalid metadata rejects whole backup before writes")
	var small={"shogi_backup":1,"records":[row]}
	check(service.restore(app,app.ui.tutorial,small,false,false)==1,"valid archive metadata restores")
	var restored=app.records.list_all().filter(func(item): return item.title=="保存的新名称")
	check(restored.size()==2 and restored.all(func(item): return item.favorite and item.tags==["研究","升变"] and item.created==500),"restored records retain favorites, tags and creation time")
	var old=row.duplicate(true); old.erase("archive")
	check(service.restore(app,app.ui.tutorial,{"shogi_backup":1,"records":[old]},false,false)==1,"old backup without archive metadata remains compatible")
	# Closing an in-flight parse cannot steal a different page.
	app.ui.show_archives(); archive.filters=Model.defaults(); archive.scan(); await ready_list()
	archive.open_entry(archive.rows[0],"load"); var held=app.review_game
	app.ui.show_openings(""); check(await until(func(): return not archive.busy,8),"dismissed parser finishes")
	check(app.ui.page_name=="openings" and app.review_game==held,"late parser result cannot replace later navigation")
	# Archive folder import only writes after valid complete parse.
	app.ui.show_archives(); await ready_list(); count_before=app.records.list_all().size()
	var picker=Picker.new(); app.ui.platform=picker; app.ui.analysis_import.initialize(app.ui)
	await press("ArchiveImportFile"); picker.analysis_record_imported.emit(picker.request,"","")
	check(app.records.list_all().size()==count_before,"cancelled archive file picker writes nothing")
	app.ui.show_archives(); await ready_list(); await press("ArchiveImportFile")
	picker.analysis_record_imported.emit(picker.request,"bad record","")
	check(await until(func(): return not app.ui.analysis_import.busy,8),"invalid archive import finishes")
	check(app.records.list_all().size()==count_before and app.review_game==held,"invalid file preserves library and current replay")
	app.ui.show_archives(); await ready_list(); await press("ArchiveImportFile")
	picker.analysis_record_imported.emit(picker.request,"position startpos moves 7g7f","")
	check(await until(func(): return not app.ui.analysis_import.busy,8),"valid archive import finishes")
	check(app.records.list_all().size()==count_before+1 and not app.review_path.is_empty() and app.review_game.moves.size()==1,"valid folder import archives then loads")
	app.ui.platform=null; app.ui.live_enabled=false; app._pause_search()
	FileAccess.open(output.path_join("preview-motion.json"),FileAccess.WRITE).store_string(JSON.stringify(motions))
	await finish()
