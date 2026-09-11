extends RefCounted
const Model = preload("res://scripts/shogi_archive_model.gd")
const Job = preload("res://scripts/shogi_archive_job.gd")
const Motion = preload("res://scripts/shogi_rendered_tween.gd")
const PAGES = ["analysis-recent","archive-filter","archive-edit","archive-preview"]
var ui
var filters = Model.defaults()
var draft: Dictionary = {}
var entries: Array = []
var rows: Array = []
var limit = 20
var scroll = 0
var list: VBoxContainer
var status: Label
var count: Label
var fab: Button
var job
var indexing = false
var busy = false
var generation = 0
var request = 0
var error = ""
var expanded: Dictionary = {}
var preview
var preview_entry: Dictionary = {}
var return_to = ""
var reveal = 1.0
var closing = false
var sheet_motion

func active() -> bool: return ui.page_name=="analysis-recent"

func enter(personal: bool) -> void:
	if ui.page_name not in PAGES and ui.page_name not in ui.tournament_view.PAGES:
		return_to = "analysis-import" if ui.page_name=="analysis-import" else ""
	if personal: show()
	else: ui.tournament_view.show()

func leave_archive() -> void:
	if return_to=="analysis-import": ui.analysis_import.show(0)
	else: ui._board_keep()

func leaving(name: String) -> void:
	if active() and is_instance_valid(ui.page_scroll): scroll = ui.page_scroll.scroll_vertical
	request += 1
	if is_instance_valid(fab): fab.queue_free(); fab = null
	if is_instance_valid(preview): preview.stop(); preview = null
	if name not in PAGES and name not in ui.tournament_view.PAGES:
		generation += 1; indexing = false
		if is_instance_valid(job): job.cancel()

func text(value: String, size: int = 14) -> Label:
	var item = ui.label(value,size); item.add_theme_color_override("font_color",Color("f8f1e6") if size>=16 else Color("d4c8b5"))
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item

func action(value: String, callback: Callable, id: String, icon: String = "", height: int = 40) -> Button:
	var item = ui.compact_button(value,callback if callback.is_valid() else func(): pass,height); item.name=id; item.tooltip_text=value; item.accessibility_name=value
	if not icon.is_empty(): ui.set_reference_icon(item,icon)
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_button(item)
	return item

func style_button(item: Button) -> void:
	for key in ["font_color","font_hover_color","font_pressed_color","icon_normal_color","icon_hover_color","icon_pressed_color"]: item.add_theme_color_override(key,Color("f8f1e6"))
	for key in ["normal","hover","pressed","disabled"]: item.add_theme_stylebox_override(key,ui.Design.box(Color.TRANSPARENT if key in ["normal","disabled"] else Color("64543f"),4,5))
	item.add_theme_color_override("font_disabled_color",Color("a39784")); item.add_theme_color_override("icon_disabled_color",Color("a39784"))

func tabs(parent: Control, personal: bool) -> void:
	var row = HBoxContainer.new(); row.add_theme_constant_override("separation",0); parent.add_child(row)
	for index in [0,1]:
		var item = action("我的棋谱" if index==0 else "大师棋谱",show if index==0 else ui.tournament_view.show,"ArchiveMyGames" if index==0 else "ArchiveMasterGames")
		var selected = personal==(index==0)
		var box = ui.Design.box(Color.TRANSPARENT,0,5); box.border_width_bottom=2; box.border_color=Color("4285f4") if selected else Color.TRANSPARENT
		item.add_theme_stylebox_override("normal",box); item.add_theme_color_override("font_color",Color("4285f4") if selected else Color("bcb3a7"))
		row.add_child(item)

func show() -> void:
	var content = ui._page("所有棋谱","analysis-recent")
	var outer = ui.page.get_child(0); outer.add_theme_constant_override("separation",4)
	var header = outer.get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var heading = text("所有棋谱",18); heading.name="ArchiveTitle"; heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font)); header.add_child(heading)
	for spec in [["筛选",show_filter,"ArchiveFilter","ic_filter"],["关闭",leave_archive,"ArchiveClose","ic_close"]]:
		var item=action(spec[0],spec[1],spec[2],spec[3],44); item.size_flags_horizontal=Control.SIZE_SHRINK_END; header.add_child(item)
	var fixed=VBoxContainer.new(); outer.add_child(fixed); outer.move_child(fixed,1); tabs(fixed,true)
	status=text("",12); status.name="ArchiveStatus"; fixed.add_child(status)
	count=text("",12); count.name="ArchiveCount"; fixed.add_child(count)
	list=content; list.add_theme_constant_override("separation",0)
	fab=action("导入棋谱",import_file,"ArchiveImportFile","ic_folder",56); fab.size_flags_horizontal=Control.SIZE_SHRINK_END
	fab.add_theme_stylebox_override("normal",ui.Design.box(Color("4285f4"),28,12)); ui.root.add_child(fab)
	refresh(); layout(); scan()
	ui.page_scroll.set_deferred("scroll_vertical",scroll)

func import_file() -> void:
	ui.analysis_import.show(0); ui.analysis_import.choose_file(true)

func scan() -> void:
	generation += 1; var serial = generation
	if is_instance_valid(job): job.cancel()
	job=Job.new(); ui.add_child(job); indexing=true; error=""; refresh()
	job.completed.connect(func(result):
		if serial!=generation: return
		indexing=false; job=null; entries=result.entries; rows=result.rows; error=result.error
		if active(): refresh(); ui.page_scroll.set_deferred("scroll_vertical",scroll)
	)
	if job.begin_index(ui.app.records.root,filters)!=OK: indexing=false; job.queue_free(); job=null; error="无法读取棋谱列表，请重新打开。"; refresh()

func refresh() -> void:
	if not active() or not is_instance_valid(list): return
	for child in list.get_children(): list.remove_child(child); child.queue_free()
	status.text="正在校验棋谱…" if busy else "正在读取棋谱并搜索局面…" if indexing and not filters.sfen.is_empty() else "正在读取棋谱…" if indexing else error
	status.visible=not status.text.is_empty()
	count.text="%d 局" % rows.size() + (" · 已筛选" if filters!=Model.defaults() else "")
	if rows.is_empty() and not indexing: list.add_child(text("没有匹配的棋谱。可导入文件，或调整筛选。",14))
	for entry in rows.slice(0,limit): build_row(entry)
	if rows.size()>limit: list.add_child(action("显示更多棋谱",func(): limit+=20; refresh(),"ArchiveMore"))
	var spacer=Control.new(); spacer.custom_minimum_size.y=72; list.add_child(spacer)
	apply_theme()

func build_row(entry: Dictionary) -> void:
	var id: String=entry.path.get_file().sha256_text().left(12)
	var panel=PanelContainer.new(); panel.name="ArchiveRow_"+id; panel.add_theme_stylebox_override("panel",ui.Design.box(Color.TRANSPARENT,0,0)); list.add_child(panel)
	var load=action("载入 "+entry.names,func(): open_entry(entry,"load"),"ArchiveLoad_"+id,"",44); load.text=""; load.disabled=busy; panel.add_child(load)
	var margin=MarginContainer.new(); margin.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for spec in [["left",0],["right",5],["top",15],["bottom",15]]: margin.add_theme_constant_override("margin_"+spec[0],spec[1])
	panel.add_child(margin)
	var line=HBoxContainer.new(); line.add_theme_constant_override("separation",0); line.mouse_filter=Control.MOUSE_FILTER_IGNORE; margin.add_child(line)
	for spec in [["预览",func(): open_entry(entry,"preview"),"ArchivePreview_","ic_eye"],["取消收藏" if entry.favorite else "收藏",func(): favorite(entry),"ArchiveFavorite_","ic_favorite" if entry.favorite else "ic_favorite_border"]]:
		var item=action(spec[0],spec[1],spec[2]+id,spec[3],32); item.size_flags_horizontal=Control.SIZE_SHRINK_END; item.size_flags_vertical=Control.SIZE_SHRINK_CENTER; item.disabled=busy or indexing; line.add_child(item)
		if str(item.name).begins_with("ArchiveFavorite"): item.add_theme_color_override("icon_normal_color",Color("ff6c86") if entry.favorite else Color("bcb3a7"))
	var body=VBoxContainer.new(); body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; body.mouse_filter=Control.MOUSE_FILTER_IGNORE; body.add_theme_constant_override("separation",3); line.add_child(body)
	var title=text(ui.record_display_title(entry.names),16); title.add_theme_font_override("font",ui.Design.heading_font(ui.app.text_font)); body.add_child(title)
	body.add_child(text(entry.date.left(10)+( " | "+entry.event if not entry.event.is_empty() else "")+" · %d 手"%entry.plies,12))
	var metadata_row=HBoxContainer.new(); metadata_row.mouse_filter=Control.MOUSE_FILTER_IGNORE; body.add_child(metadata_row)
	var info=action("更多信息",func(): expanded[entry.path]=true; refresh(),"ArchiveInfo_"+id,"ic_info",28); info.size_flags_horizontal=Control.SIZE_SHRINK_END; info.visible=not expanded.has(entry.path); metadata_row.add_child(info)
	var tags=text(" · ".join(entry.tags) if not entry.tags.is_empty() else "无标签",12); tags.size_flags_horizontal=Control.SIZE_EXPAND_FILL; metadata_row.add_child(tags)
	if expanded.has(entry.path):
		var values=["名称："+entry.title]
		for key in entry.metadata: values.append(str(key)+"："+str(entry.metadata[key]))
		body.add_child(text("\n".join(values),12))
	var edit=action("编辑棋谱信息",func(): open_entry(entry,"edit"),"ArchiveEdit_"+id,"ic_edit",32); edit.size_flags_horizontal=Control.SIZE_SHRINK_END; edit.size_flags_vertical=Control.SIZE_SHRINK_CENTER; edit.disabled=busy; line.add_child(edit)
	list.add_child(HSeparator.new())

func favorite(entry: Dictionary) -> void:
	if indexing or busy: return
	var value: Dictionary=entry.archive.duplicate(true); value.favorite=not entry.favorite
	if not ui.app.records.update_metadata(entry.path,value,entry.sha256): error=ui.app.records.error; refresh(); return
	entry.archive=value; entry.favorite=value.favorite; entry.sha256=FileAccess.get_sha256(entry.path)
	rows=Model.select(entries,filters) if filters.sfen.is_empty() else rows.filter(func(item): return Model.select([item],filters).size()==1)
	error=""; refresh()

func open_entry(entry: Dictionary, mode: String) -> void:
	if busy: return
	if ui.app.session!=null: error="请先退出联机对局，再载入其他棋谱。"; refresh(); return
	var file=FileAccess.open(entry.path,FileAccess.READ)
	if file==null or file.get_length()>ui.app.Game.MAX_SAVE_BYTES: error="棋谱无法读取，原棋局已保留。"; refresh(); return
	var source=file.get_as_text(); var digest=source.sha256_text()
	var fresh = Model.describe(entry.path,JSON.parse_string(source),FileAccess.get_modified_time(entry.path),digest)
	request+=1; var token=request; busy=true; error=""; refresh()
	var parser=preload("res://scripts/shogi_import_job.gd").new(); ui.add_child(parser)
	parser.completed.connect(func(result):
		busy=false
		if token!=request or not active(): refresh(); return
		if result.game==null: error=result.error; refresh(); return
		if mode=="load": ui.analysis_import.open_game(result.game,fresh.path)
		elif mode=="preview": show_preview(fresh,result.game)
		else: show_edit(fresh,result.game)
	)
	if parser.begin(source)!=OK: parser.queue_free(); busy=false; error="无法启动棋谱校验，请重试。"; refresh()

func show_filter() -> void:
	draft=filters.duplicate(true); closing=false
	var content=ui._page("筛选棋谱","archive-filter")
	var header=ui.page.get_child(0).get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var heading=ui.label("筛选棋谱",18); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var close=ui.compact_button("",close_filter,44); close.name="ArchiveFilterClose"; ui.set_reference_icon(close,"ic_close"); close.size_flags_horizontal=Control.SIZE_SHRINK_END; header.add_child(close)
	var query=ui.field(content,"棋手、棋战、名称或标签",draft.query); query.name="ArchiveSearch"; query.text_changed.connect(func(value): draft.query=value)
	var favorite_choices: Array[String] = ["全部","已收藏","未收藏"]
	var order_choices: Array[String] = ["新的在前","旧的在前"]
	var favorites=ui.choice(content,"收藏",favorite_choices,int(draft.favorites)); favorites.name="ArchiveFavoritesFilter"; favorites.item_selected.connect(func(value): draft.favorites=value)
	var order=ui.choice(content,"按添加时间",order_choices,1 if draft.oldest else 0); order.name="ArchiveSort"; order.item_selected.connect(func(value): draft.oldest=value==1)
	var sfen=ui.field(content,"搜索经过此局面的棋谱（SFEN）",draft.sfen); sfen.name="ArchivePosition"; sfen.max_length=300; sfen.text_changed.connect(func(value): draft.sfen=value.strip_edges())
	content.add_child(ui.compact_button("填入当前棋盘局面",func(): sfen.text=ui.app.Codec.sfen(ui.app._display_position()); draft.sfen=sfen.text,38))
	content.add_child(ui.label("标签（可多选）",14)); var tags=HFlowContainer.new(); content.add_child(tags)
	for tag in Model.all_tags(entries):
		var item=CheckBox.new(); item.text=tag; item.custom_minimum_size.y=40; item.button_pressed=tag in draft.tags; tags.add_child(item)
		for selected in [false,true]: item.add_theme_icon_override("checked" if selected else "unchecked",ui.tournament_view.checkbox_icon(selected))
		item.toggled.connect(func(value):
			if value: draft.tags.append(tag)
			else: draft.tags.erase(tag)
		)
	var footer=HBoxContainer.new(); ui.page.get_child(0).add_child(footer)
	for spec in [["重置筛选","reset","ArchiveFilterReset"],["显示结果","apply","ArchiveFilterApply"]]:
		var mode: String=spec[1]; var item=ui.compact_button(spec[0],func(): close_filter(mode),46); item.name=spec[2]; footer.add_child(item)
	reveal=0; layout(); animate_filter(1)

func animate_filter(target: float, callback: Callable = Callable()) -> void:
	if is_instance_valid(sheet_motion): sheet_motion.kill()
	var panel=ui.page; var start=reveal
	sheet_motion=Motion.new(); panel.add_child(sheet_motion)
	sheet_motion.begin(panel,0.18 if ui.app.preferences.studio.animation>0 else 0,func(value):
		if ui.page==panel: reveal=lerpf(start,target,value); layout()
	,func():
		if ui.page==panel and callback.is_valid(): callback.call()
	)

func close_filter(mode: String = "cancel") -> void:
	if closing: return
	closing=true; var chosen=draft.duplicate(true)
	animate_filter(0,func():
		if mode!="cancel": filters=chosen if mode=="apply" else Model.defaults(); limit=20; scroll=0
		show()
	)

func detail_page(title: String, name: String) -> VBoxContainer:
	var content=ui._page(title,name); var outer=ui.page.get_child(0); outer.add_theme_constant_override("separation",6)
	var header=outer.get_child(0)
	for child in header.get_children(): header.remove_child(child); child.queue_free()
	var heading=text(title,18); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(heading)
	var close=action("返回列表",show,"ArchiveDetailClose","ic_close",44); close.size_flags_horizontal=Control.SIZE_SHRINK_END; header.add_child(close)
	return content

func show_preview(entry: Dictionary, game) -> void:
	var content=detail_page("棋谱预览","archive-preview"); preview_entry=entry
	preview=preload("res://scripts/shogi_opening_preview.gd").new(); content.add_child(preview)
	preview.build(self,{"record":true,"name":entry.names,"description":entry.date+" · "+entry.event,"summary":"%d 手 · "%game.moves.size()+ui.app.i18n.result(game)},game)
	preview.board.flipped=ui.app.flipped
	var footer=HBoxContainer.new(); ui.page.get_child(0).add_child(footer)
	footer.add_child(action("载入分析",load_preview,"ArchiveLoadPreview","",46))
	footer.add_child(action("返回列表",show,"ArchivePreviewBack","",46))
	preview.footer=footer; layout()

func load_preview() -> void:
	if not is_instance_valid(preview): return
	var game=preview.game; var ply: int=preview.ply; var flipped: bool=preview.board.flipped; var path: String=preview_entry.path
	if not ui.finish_study(true, func(): load_position(game, path, ply, flipped)): return
	load_position(game, path, ply, flipped)

func load_position(game, path: String, ply: int, flipped: bool) -> void:
	if ui.analysis_import.open_game(game,path): ui.app.flipped=flipped; ui.app._set_replay(ply)

func show_edit(entry: Dictionary, game) -> void:
	var content=detail_page("编辑棋谱信息","archive-edit")
	var title=ui.field(content,"棋谱名称",entry.title); title.name="ArchiveEditTitle"; title.max_length=100
	var tags=ui.field(content,"标签，用逗号分隔","，".join(entry.tags)); tags.name="ArchiveEditTags"
	var fields={}; var aliases={"后手":"後手","棋战":"棋戦","开始日時":"開始日時","场所":"場所"}
	for key in ["先手","后手","棋战","开始日時","场所"]:
		fields[key]=ui.field(content,key,str(game.metadata.get(key,game.metadata.get(aliases.get(key,key),""))))
		fields[key].max_length=1000
	var feedback=ui.label("",13); feedback.name="ArchiveEditError"; content.add_child(feedback)
	content.add_child(action("导出 / 删除",func(): ui.show_record_details(entry.path),"ArchiveRecordActions"))
	var footer=HBoxContainer.new(); ui.page.get_child(0).add_child(footer)
	footer.add_child(action("取消",show,"ArchiveEditCancel","",46))
	footer.add_child(action("保存",func():
		var next: Dictionary=entry.archive.duplicate(true); next.tags=Array(tags.text.replace("，",",").split(",",false)); next=Model.metadata(next,entry.created)
		if title.text.strip_edges().is_empty() or next.is_empty(): feedback.text="请输入名称；标签最多 32 个，每个不超过 60 字。"; return
		var metadata: Dictionary=game.metadata.duplicate(true)
		for key in fields:
			var alias: String=aliases.get(key,key)
			var actual: String=alias if metadata.has(alias) and not metadata.has(key) else key
			if metadata.has(actual) or not fields[key].text.is_empty(): metadata[actual]=fields[key].text
			if alias!=actual and metadata.has(alias): metadata[alias]=fields[key].text
		if metadata.size()>100: feedback.text="棋谱信息最多 100 项。"; return
		game.metadata=metadata
		var doc={"record_version":1,"title":title.text.strip_edges(),"game":game.to_data(),"archive":next}
		if ui.app.records.write_document(entry.path,doc,entry.sha256): show()
		else: feedback.text=ui.app.records.error
	,"ArchiveEditSave","",46))
	layout()

func layout() -> void:
	if ui.page==null or ui.page_name not in PAGES: return
	var safe: Rect2=ui.app.safe_rect(); safe.size.y=maxf(160,safe.size.y-ui.keyboard_height)
	if ui.page_name=="archive-filter":
		ui.page.size=Vector2(safe.size.x,minf(620,safe.size.y*0.94)); ui.page.position=Vector2(safe.position.x,safe.end.y-ui.page.size.y*reveal)
	else: ui.page.position=safe.position; ui.page.size=safe.size
	if is_instance_valid(fab): fab.size=Vector2(56,56); fab.position=safe.end-Vector2(76,76)
	if is_instance_valid(preview): preview.layout_preview()
	apply_theme()

func apply_theme() -> void:
	if ui.page==null or ui.page_name not in PAGES: return
	if ui.page_name=="archive-filter": ui.page.add_theme_stylebox_override("panel",ui.Design.box(ui.app.palette().background,0,10)); return
	var wood=StyleBoxTexture.new(); wood.texture=load("res://assets/reference-ui/wood_dark.png"); wood.set_content_margin_all(10); ui.page.add_theme_stylebox_override("panel",wood)
	for label in ui.page.find_children("*","Label",true,false): label.add_theme_color_override("font_color",Color("f8f1e6"))
