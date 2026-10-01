extends Control
const Game = preload("res://scripts/chu_game.gd")
const C = preload("res://scripts/chu_catalog.gd")
const Design = preload("res://scripts/shogi_design.gd")
const Session = preload("res://scripts/chu_session.gd")
const ACTIVE = "user://chu-active-game.json"
const NETWORK = "user://chu-network-game.json"
var app
var game=Game.new()
var session
var board
var header: HBoxContainer
var panel: VBoxContainer
var controls_scroll: ScrollContainer
var status: Label
var clock_label: Label
var move_scroll: ScrollContainer
var move_strip: HBoxContainer
var ribbon=preload("res://scripts/shogi_move_ribbon.gd").new()
var selected=-1
var path: Array=[]
var candidates: Array=[]
var return_mode=false
var flipped=false
var replay=-1
var editing=false
var edit_position
var edit_piece=C.PAWN
var editor_selector: OptionButton
var promotion: CheckBox
var confirm: Button
var finish: Button
var preview_text: Label
var modal: PanelContainer
var active=true
var imported=false
var ribbon_signature=""
var file_dialog: FileDialog
var bt_devices: VBoxContainer
var bt_addresses: Array=[]
var last_save=0
var pending_offer_dialog=false

func _ready() -> void:
	name="ChuShogi"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=app.ui.root.theme
	var bg=ColorRect.new(); bg.color=app.palette().background; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); bg.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(bg)
	header=HBoxContainer.new(); add_child(header)
	header.add_child(button("‹ 本将棋",func(): app.close_chu()))
	var title=label("中将棋",18); title.autowrap_mode=TextServer.AUTOWRAP_OFF; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; header.add_child(title)
	header.add_child(button("菜单",show_menu))
	move_scroll=ScrollContainer.new(); move_scroll.name="ChuHistory"; move_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(move_scroll)
	move_strip=HBoxContainer.new(); move_strip.add_theme_constant_override("separation",3); move_scroll.add_child(move_strip)
	ribbon.ui=self
	board=preload("res://scripts/chu_board_view.gd").new(); board.screen=self; add_child(board)
	controls_scroll=ScrollContainer.new(); controls_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(controls_scroll)
	panel=VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_theme_constant_override("separation",4); controls_scroll.add_child(panel)
	status=label("",14); panel.add_child(status)
	clock_label=label("",13); panel.add_child(clock_label)
	var nav=HBoxContainer.new(); panel.add_child(nav)
	for entry in [["|‹",0],["‹",-2],["›",-3],["›|",-1]]:
		var target:int=entry[1]
		nav.add_child(button(entry[0],func(): show_history(maxi(0,replay-1) if target==-2 and replay>=0 else maxi(0,game.moves.size()-1) if target==-2 else mini(game.moves.size(),replay+1) if target==-3 else game.moves.size() if target==-1 else target)))
	var row=HBoxContainer.new(); panel.add_child(row)
	row.add_child(button("翻转",func(): flipped=not flipped; clear_pending(); board.queue_redraw()))
	row.add_child(button("复位",func(): board.cancel_input(); board.reset_view()))
	row.add_child(button("居食 / 往返",func():
		if selected<0: preview_text.text="先选择狮子、飞鹫或角鹰。"; return
		path.clear(); return_mode=true; preview_text.text="选择经过的相邻格，再确认返回原处。"; board.queue_redraw()
	))
	preview_text=label("点击选子，长按查看走法；双指缩放和平移。",13); panel.add_child(preview_text)
	var actions=HBoxContainer.new(); panel.add_child(actions)
	promotion=CheckBox.new(); promotion.text="升变"; actions.add_child(promotion)
	finish=button("结束",_finish_first); actions.add_child(finish)
	confirm=button("确认",_confirm); actions.add_child(confirm)
	actions.add_child(button("取消",clear_pending))
	resized.connect(_layout)
	if not imported and not app.testing:
		var saved=Game.load_from(ACTIVE)
		if saved!=null: game=saved
	if app.ui.platform!=null: app.ui.platform.bluetooth_device.connect(_bluetooth_device)
	_refresh(true); _layout(); show_menu()

func label(text: String, font_size: int=15) -> Label:
	var item=Label.new(); item.text=text; item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; item.add_theme_font_override("font",app.text_font); item.add_theme_font_size_override("font_size",font_size); item.add_theme_color_override("font_color",app.palette().ink); return item
func button(text: String, action: Callable) -> Button:
	var item=Button.new(); item.text=text; item.custom_minimum_size.y=40; item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var p=app.palette()
	item.add_theme_stylebox_override("normal",Design.box(p.surface,6,6)); item.add_theme_stylebox_override("hover",Design.box(p.soft,6,6)); item.add_theme_stylebox_override("pressed",Design.box(p.selected,6,6))
	item.add_theme_color_override("font_color",p.ink)
	item.add_theme_font_override("font",app.text_font); item.add_theme_font_size_override("font_size",15); item.pressed.connect(action); return item
func compact_button(text: String, action: Callable, height: int) -> Button:
	var item=button(text,action); item.custom_minimum_size.y=height; return item
func _layout() -> void:
	if board==null: return
	board.cancel_input()
	var safe:Rect2=app.safe_rect(); safe.position+=Vector2(6,4); safe.size-=Vector2(12,8)
	header.position=safe.position; header.size=Vector2(safe.size.x,42)
	move_scroll.position=safe.position+Vector2(0,46); move_scroll.size=Vector2(safe.size.x,42)
	var wide=safe.size.x>safe.size.y
	var body=Rect2(safe.position+Vector2(0,92),safe.size-Vector2(0,92))
	if wide:
		var width=minf(270,body.size.x*0.43)
		board.position=body.position; board.size=Vector2(body.size.x-width-6,body.size.y)
		controls_scroll.position=Vector2(board.position.x+board.size.x+6,body.position.y); controls_scroll.size=Vector2(width,body.size.y)
	else:
		var height=minf(216,body.size.y*0.43)
		board.position=body.position; board.size=Vector2(body.size.x,maxf(80,body.size.y-height))
		controls_scroll.position=Vector2(body.position.x,board.position.y+board.size.y); controls_scroll.size=Vector2(body.size.x,height)
	if is_instance_valid(modal): modal.position=safe.position; modal.size=safe.size
	ribbon.refresh()
func display_position(): return edit_position if editing else game.positions[replay] if replay>=0 else game.position
func highlight_squares() -> Array:
	if selected>=0: return [selected]+path
	var ply=game.moves.size() if replay<0 else replay
	return [game.moves[ply-1].from]+game.moves[ply-1].path if ply>0 and not editing else []
func targets() -> Array:
	var out: Array=[]
	for move in candidates:
		if path.size()<move.path.size() and move.path.slice(0,path.size())==path:
			if move.path[path.size()] not in out: out.append(move.path[path.size()])
	return out
func clear_pending() -> void:
	selected=-1; path.clear(); candidates.clear(); return_mode=false
	if promotion!=null: promotion.visible=false; promotion.button_pressed=false; confirm.disabled=true; finish.disabled=true
	if preview_text!=null: preview_text.text="编辑局面" if editing else "点击选子，长按查看走法；双指缩放和平移。"
	if board!=null: board.queue_redraw()
func choose(square: int) -> void:
	if modal!=null or square<0 or square>=144: return
	if editing:
		edit_position.board[square]=edit_piece; board.queue_redraw(); return
	if replay>=0 or not game.result.is_empty() or (session!=null and not session.can_move()): return
	if selected<0 or (path.is_empty() and game.position.board[square]*game.position.turn>0 and square!=selected):
		if game.position.board[square]*game.position.turn<=0: return
		selected=square; path.clear(); candidates=game.position.legal_moves(square); return_mode=false
		preview_text.text=C.title(game.position.board[square])+" · 选择落点"; board.queue_redraw(); return
	var proposed=path+[square]
	if return_mode and path.is_empty(): proposed=[square,selected]
	if not candidates.any(func(move): return move.path.slice(0,proposed.size())==proposed): return
	path=proposed; _preview()
	var multi=not C.motion(C.kind(game.position.board[selected])).twice.is_empty()
	if not multi and not app.preferences.confirm_move and not promotion.visible: _confirm()
func _preview() -> void:
	var complete=candidates.filter(func(move): return move.path==path)
	confirm.disabled=complete.is_empty(); finish.disabled=complete.is_empty() or path.size()!=1
	promotion.visible=complete.any(func(move): return move.promote); promotion.button_pressed=promotion.visible
	var names: Array=[]
	for square in game.position.captures(selected,path): names.append(C.NAMES[C.kind(game.position.board[square])])
	preview_text.text="路径 "+C.square(selected)+" → "+" → ".join(path.map(func(s): return C.square(s)))+(" · 吃 "+"、".join(names) if not names.is_empty() else "")+(" · 可选第二落点或结束" if path.size()==1 and candidates.any(func(move): return move.path.size()==2 and move.path[0]==path[0]) else " · 确认后落子")
	board.queue_redraw()
func _finish_first() -> void:
	if path.size()!=1: return
	candidates=candidates.filter(func(move): return move.path==path); _preview()
func _confirm() -> void:
	if selected<0 or path.is_empty(): return
	var move={"from":selected,"path":path.duplicate(),"promote":promotion.visible and promotion.button_pressed}
	var ok=session.submit(move) if session!=null else game.play(move)
	if ok: clear_pending(); _refresh(true); _save()
	else: preview_text.text=game.error if not game.error.is_empty() else "当前不能落子。"
func _refresh(reveal: bool=false) -> void:
	if session!=null: game=session.game
	status.text="自由摆局" if editing else game.result if not game.result.is_empty() else ("▲ 先手" if display_position().turn==1 else "△ 后手")+"行棋"+(" · 回放 %d / %d"%[replay,game.moves.size()] if replay>=0 else " · 第 %d 手"%(game.moves.size()+1))
	var key=str([game.moves, replay,editing])
	if key!=ribbon_signature:
		ribbon_signature=key; var entries=[{"labels":["起局"],"ids":[0],"study":false}]
		for i in range(game.labels.size()): entries.append({"labels":[str(i+1)+" "+game.labels[i]],"ids":[i+1],"study":false})
		ribbon.configure(entries,game.moves.size() if replay<0 else replay,reveal)
	board.queue_redraw()
func show_history(ply: int) -> void:
	if editing: return
	clear_pending(); replay=clampi(ply,0,game.moves.size()); _refresh(true)
func _save() -> void:
	if app.testing or editing or imported: return
	if session==null:
		if game.save_to(ACTIVE)!=OK: status.text="保存中将棋失败，请导出棋谱。"
	else:
		var data=JSON.stringify(session.to_data()); var file=FileAccess.open(NETWORK+".tmp",FileAccess.WRITE)
		if file!=null:
			file.store_string(data); file.flush(); var code=file.get_error(); file.close()
			if code==OK: DirAccess.rename_absolute(NETWORK+".tmp",NETWORK)
func _process(_delta: float) -> void:
	if session==null:
		var before=game.result_code; game.clock.tick(not active or modal!=null or replay>=0 or editing or not game.result.is_empty())
		if game.clock.expired_side!=0 and before.is_empty(): game.update_result(); _refresh(); _save()
	ribbon.refresh()
	clock_label.text="▲ "+game.clock.text_for(1,session!=null)+"    △ "+game.clock.text_for(-1,session!=null) if game.clock.preset>0 else "不限时 · 无引擎"
	var now=Time.get_ticks_msec()
	if now-last_save>10000: last_save=now; _save()
func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		active=false
		if board!=null: board.cancel_input(); _save()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		active=true
		if board!=null: board.cancel_input()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready(): back()
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: back(); get_viewport().set_input_as_handled()
func back() -> void:
	if modal!=null: close_modal()
	elif selected>=0: clear_pending()
	elif replay>=0: replay=-1; _refresh(true)
	elif board.zoom>1: board.reset_view()
	else: show_menu()
func _page(title: String) -> VBoxContainer:
	close_modal(); clear_pending()
	modal=PanelContainer.new(); modal.name="ChuMenu"; modal.add_theme_stylebox_override("panel",Design.box(app.palette().background,8,12)); add_child(modal)
	var outer=VBoxContainer.new(); modal.add_child(outer)
	var top=HBoxContainer.new(); outer.add_child(top); var heading=label(title,20); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; top.add_child(heading); top.add_child(button("返回棋盘",close_modal))
	var scroll=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; outer.add_child(scroll)
	var column=VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",8); scroll.add_child(column)
	_layout(); return column
func close_modal() -> void:
	if pending_offer_dialog and session!=null:
		pending_offer_dialog=false; session.answer_offer(false)
	bt_devices=null
	if modal!=null: remove_child(modal); modal.queue_free(); modal=null
func show_menu() -> void:
	if editing: show_editor_tools(); return
	var column=_page("中将棋")
	column.add_child(label("12 × 12 · 同机双人 / IP / 安卓蓝牙\n二维棋盘，不使用引擎。",15))
	column.add_child(button("继续对局",func():
		if imported: continue_replay()
		else: replay=-1; close_modal(); _refresh(true)
	))
	column.add_child(button("新对局",show_setup))
	column.add_child(button("自由摆局",start_editor))
	column.add_child(button("IP 直连",show_network))
	column.add_child(button("安卓蓝牙",show_bluetooth))
	if session!=null:
		column.add_child(label("房间码："+session.room_code+" · "+("房主" if session.is_host else "客人")))
		column.add_child(button("重新连接",func(): session.reconnect(); close_modal()))
		column.add_child(button("退出联机，保留本地棋局",func(): game=session.game; _stop_session(); imported=false; _save(); close_modal(); _refresh(true)))
	elif FileAccess.file_exists(NETWORK): column.add_child(button("恢复上次中将棋联机",restore_network))
	column.add_child(button("保存到棋谱库",func():
		var saved=app.records.archive(game,"中将棋 "+Time.get_datetime_string_from_system())
		message("已保存到棋谱库。" if not saved.is_empty() else app.records.error)
	))
	column.add_child(button("棋谱库",func(): app.close_chu(); app.ui.show_archives()))
	column.add_child(button("导入 / 导出 JSON",show_exchange))
	column.add_child(button("悔棋",func():
		if imported: message("请先从查看局面继续对局。"); return
		if session!=null: session.request_offer("undo")
		else: game.undo(); imported=false; _save()
		replay=-1; close_modal(); clear_pending(); _refresh(true)
	))
	column.add_child(button("和棋",func():
		if imported: message("请先从查看局面继续对局。"); return
		if session!=null: session.request_offer("draw"); close_modal()
		else: decision("双方同意和棋？",func(): game.agreed_draw=true; game.update_result(); _save(); _refresh())
	))
	column.add_child(button("认输",func():
		if imported: message("请先从查看局面继续对局。"); return
		decision("确认本方认输？",func():
			if session!=null: session.resign()
			else: game.resign(); _save(); _refresh()
		)
	))
	if session!=null: column.add_child(button("请求再来一局",func(): session.request_offer("rematch"); close_modal()))
	if replay>=0 and session==null: column.add_child(button("从查看局面继续",continue_replay))
	column.add_child(button("规则说明",show_rules))
	column.add_child(button("返回本将棋",func(): app.close_chu()))
func message(text: String) -> void: _page("中将棋").add_child(label(text))
func decision(text: String, action: Callable) -> void:
	var column=_page(text); column.add_child(button("确定",func(): close_modal(); action.call())); column.add_child(button("取消",close_modal))
func piece_help(piece: int) -> void: _page(C.title(piece)).add_child(label(C.help(piece),18))
func show_rules() -> void:
	var column=_page("中将棋规则")
	column.add_child(label("采用日本中将棋连盟 2019 规则及补充解释。各模式统一允许香车在最后一段再次选择升变。\n\n吃掉的棋子不再使用，没有持驹或打入。棋子最多升变一次；成仲人不能再成为太子。\n\n狮子、飞鹫、角鹰可分段移动，先选第一落点，再选第二落点或结束，最后确认。居食吃掉邻格棋子后返回；往返须经空格。\n\n远隔狮子不能吃有保护的狮子；相邻狮子、先狮子及付食有特殊优先级，由程序校验。\n\n玉将与太子均失去才算王被吃。允许将王暴露给对手；重复局面必须由负有责任的一方变着，不按本将棋千日手自动和棋。双方可以协商和棋。\n\n双指缩放至 3 倍并平移，复位恢复全盘。长按棋子查看走法。"))
	for url in ["https://www.chushogi-renmei.com/kouza/rule2007.htm","https://www.chushogi-renmei.com/kouza/rule_hosoku2004.htm"]:
		column.add_child(button("打开连盟"+("补充解释" if "hosoku" in url else "2019 规则"),func(): OS.shell_open(url)))
func choice(column: VBoxContainer, values: Array, chosen: int=0) -> OptionButton:
	var select=OptionButton.new(); select.custom_minimum_size.y=42
	for value in values: select.add_item(str(value))
	select.select(chosen); column.add_child(select); return select
func show_setup() -> void:
	if session!=null: message("请先退出当前联机对局。"); return
	var column=_page("新中将棋对局")
	var times=choice(column,Game.Clock.PRESETS.map(func(v): return v.name))
	column.add_child(label("当前棋局会先保存到棋谱库。"))
	column.add_child(button("开始同机双人",func():
		if not _archive_before_replace(): return
		game=Game.new(); game.clock.configure(times.selected); imported=false; editing=false; replay=-1; close_modal(); board.reset_view(); _refresh(true); _save()
	))
func _archive_before_replace() -> bool:
	var current=Game.load_from(ACTIVE) if imported and not app.testing else game
	if current==null or current.moves.is_empty() or app.testing: return true
	if app.records.archive(current,"中将棋 · 替换前保存").is_empty(): message(app.records.error); return false
	return true
func continue_replay() -> void:
	if replay<0 or session!=null: return
	if not _archive_before_replace(): return
	var data=game.to_data(); data.moves=data.moves.slice(0,replay); data.resigned_side=0; data.agreed_draw=false
	data.comments={}; var clock=Game.Clock.new(); clock.configure(game.clock.preset); clock.finish_turn(game.positions[replay].turn); data.clock=clock.to_data()
	var next=Game.from_data(data)
	if next==null: message("无法继续这个局面。"); return
	game=next; imported=false; replay=-1; close_modal(); _refresh(true); _save()
func start_editor() -> void:
	if session!=null: message("请先退出联机对局。"); return
	edit_position=display_position().copy(); edit_position.immunity.clear(); editing=true; close_modal(); clear_pending(); _refresh(true)
	show_editor_tools()
func show_editor_tools() -> void:
	var column=_page("自由摆局")
	column.add_child(label("选择棋子后返回棋盘点击摆放；菜单可再次打开这些工具。允许死子，不允许超出原始棋子数量。"))
	var values=["擦除"]; var codes=[0]
	for side in [1,-1]:
		for base in range(1,22):
			values.append(("先手 " if side==1 else "后手 ")+C.NAMES[base]); codes.append(side*base)
			if C.PROMOTES.has(base): values.append(("先手 " if side==1 else "后手 ")+C.title(side*(base+32))); codes.append(side*(base+32))
	editor_selector=choice(column,values,maxi(0,codes.find(edit_piece)))
	editor_selector.item_selected.connect(func(index): edit_piece=codes[index])
	var turn=choice(column,["先手行棋","后手行棋"],0 if edit_position.turn==1 else 1)
	turn.item_selected.connect(func(index): edit_position.turn=1 if index==0 else -1; _refresh())
	column.add_child(button("清空棋盘",func(): edit_position=Game.Rules.new(false); close_modal(); board.queue_redraw()))
	column.add_child(button("初始摆放",func(): edit_position=Game.Rules.new(); close_modal(); board.queue_redraw()))
	column.add_child(button("按此局面开始",func():
		var next=Game.new()
		if not next.set_initial(edit_position): message(next.error); return
		if not _archive_before_replace(): return
		game=next; imported=false; editing=false; replay=-1; close_modal(); clear_pending(); _refresh(true); _save()
	))
	column.add_child(button("取消摆局",func(): editing=false; close_modal(); _refresh(true)))
func show_exchange() -> void:
	var column=_page("中将棋 JSON")
	column.add_child(label("仅支持中将棋 JSON，包含完整移动路径、升变及规则标识。"))
	var text=TextEdit.new(); text.custom_minimum_size.y=160; text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; column.add_child(text)
	column.add_child(button("导入上述 JSON",func(): import_text(text.text)))
	column.add_child(button("从文件导入",func():
		if app.ui.platform!=null: app.ui.platform.pickRecord()
		else: _file(false,func(file):
			var input=FileAccess.open(file,FileAccess.READ)
			if input!=null and input.get_length()<=Game.MAX_SAVE_BYTES: import_text(input.get_as_text())
		)
	))
	column.add_child(button("复制当前棋谱 JSON",func(): text.text=JSON.stringify(game.to_data(),"\t"); DisplayServer.clipboard_set(text.text)))
	column.add_child(button("导出 JSON 文件",func():
		var source=JSON.stringify(game.to_data(),"\t")
		if app.ui.platform!=null: app.ui.platform.exportRecord(source)
		else: _file(true,func(file):
			var output=FileAccess.open(file,FileAccess.WRITE)
			if output!=null: output.store_string(source); message("已导出中将棋 JSON。")
		)
	))
func import_text(text: String) -> void:
	if session!=null: message("请先退出联机对局。"); return
	if text.to_utf8_buffer().size()>Game.MAX_SAVE_BYTES: message("文件过大。"); return
	var parser=JSON.new()
	var value=parser.data if parser.parse(text)==OK else null
	var next=Game.from_data(value.get("game",value) if value is Dictionary else null)
	if next==null: message("中将棋棋谱无效、规则不匹配或含有非法着手，当前对局未修改。"); return
	if not _archive_before_replace(): return
	game=next; imported=false; editing=false; replay=game.moves.size(); close_modal(); _refresh(true); _save()
func _file(save: bool, callback: Callable) -> void:
	if is_instance_valid(file_dialog): file_dialog.queue_free()
	file_dialog=FileDialog.new(); file_dialog.access=FileDialog.ACCESS_FILESYSTEM; file_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.add_filter("*.json","中将棋 JSON"); file_dialog.current_file="chu-shogi.json" if save else ""; file_dialog.file_selected.connect(callback); add_child(file_dialog); file_dialog.popup_centered_ratio(0.8)
func _attach_session() -> void:
	_stop_session(); session=Session.new(); add_child(session)
	session.changed.connect(func(): game=session.game; clear_pending(); _refresh(true); _save())
	session.status_changed.connect(func(text): status.text=text)
	session.offer_received.connect(func(action,local):
		if local: status.text="等待对手确认"; return
		var names={"undo":"悔棋","draw":"和棋","rematch":"再来一局"}; var column=_page("对手请求"+str(names.get(action,action)))
		pending_offer_dialog=true
		column.add_child(button("同意",func(): pending_offer_dialog=false; close_modal(); session.answer_offer(true)))
		column.add_child(button("拒绝",func(): pending_offer_dialog=false; close_modal(); session.answer_offer(false)))
	)
	imported=false; editing=false; replay=-1
func _stop_session() -> void:
	if session!=null: session.link.disconnect_peer(); remove_child(session); session.queue_free(); session=null
func field(column: VBoxContainer, hint: String, value: String) -> LineEdit:
	column.add_child(label(hint)); var item=LineEdit.new(); item.text=value; item.custom_minimum_size.y=42; column.add_child(item); return item
func show_network() -> void:
	var column=_page("中将棋 IP 直连")
	column.add_child(label("两端都需兼容中将棋规则。默认端口 9232。"))
	var host=field(column,"房主 IP","127.0.0.1"); var code=field(column,"加入时填写房间码","")
	var port_field=field(column,"端口","9232"); var seat=choice(column,["房主先手","房主后手"])
	var clock=choice(column,Game.Clock.PRESETS.map(func(v): return v.name))
	column.add_child(button("创建房间",func():
		if not port_field.text.is_valid_int() or int(port_field.text)<1 or int(port_field.text)>65535: return
		if not _archive_before_replace(): return
		_attach_session(); session.host_tcp(int(port_field.text),1 if seat.selected==0 else -1,"","*",clock.selected); game=session.game; close_modal(); _refresh(); status.text="房间码 "+session.room_code+" · 等待加入"; _save()
	))
	column.add_child(button("加入房间",func():
		if not port_field.text.is_valid_int() or int(port_field.text)<1 or int(port_field.text)>65535: return
		if not _archive_before_replace(): return
		_attach_session(); session.join_tcp(host.text,int(port_field.text),code.text); close_modal(); status.text="正在连接…"
	))
func restore_network() -> void:
	var file=FileAccess.open(NETWORK,FileAccess.READ)
	if file==null or file.get_length()>Game.MAX_SAVE_BYTES+4096: message("上次联机记录不可读取。"); return
	var data=JSON.parse_string(file.get_as_text()); var check=Session.new()
	if not check.restore(data): check.free(); message("上次联机记录损坏。"); return
	check.free(); _attach_session(); session.restore(data); game=session.game; session.reconnect(); close_modal(); _refresh(true)
func show_bluetooth() -> void:
	var column=_page("中将棋蓝牙")
	var platform=app.ui.platform
	if platform==null or not platform.bluetoothSupported(): column.add_child(label("此设备不支持安卓蓝牙，请使用 IP 直连。")); return
	column.add_child(label("双方使用兼容版本。尚未完成双手机蓝牙实测。"))
	column.add_child(button("允许附近设备权限",func(): platform.requestBluetoothPermissions()))
	column.add_child(button("开启蓝牙",func(): platform.enableBluetooth()))
	var seat=choice(column,["房主先手","房主后手"]); var clock=choice(column,Game.Clock.PRESETS.map(func(v): return v.name))
	column.add_child(button("创建蓝牙房间",func():
		if not platform.bluetoothPermissionsGranted(): platform.requestBluetoothPermissions(); return
		if not _archive_before_replace(): return
		var side=1 if seat.selected==0 else -1; var preset=clock.selected
		platform.makeDiscoverable(); _attach_session(); session.host_bluetooth(side,preset); game=session.game; close_modal(); _refresh(); _save()
	))
	column.add_child(button("搜索设备",func(): platform.scanDevices()))
	column.add_child(button("停止搜索",func(): platform.stopScan()))
	bt_addresses.clear(); bt_devices=VBoxContainer.new(); column.add_child(bt_devices)
	var paired=JSON.parse_string(platform.pairedDevices())
	if paired is Array:
		for device in paired: _bluetooth_device(JSON.stringify(device))
func _bluetooth_device(text: String) -> void:
	if not is_instance_valid(bt_devices): return
	var device=JSON.parse_string(text)
	if not device is Dictionary or not device.get("address") is String or device.address in bt_addresses: return
	bt_addresses.append(device.address)
	bt_devices.add_child(button(str(device.get("name","设备"))+" · "+device.address,func():
		if not _archive_before_replace(): return
		app.ui.platform.stopScan(); _attach_session(); session.join_bluetooth(device.address); close_modal(); status.text="正在连接…"
	))
