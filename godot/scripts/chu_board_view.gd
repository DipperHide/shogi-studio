extends Control
## Input previews never mutate the game. A two-finger gesture cancels selection.
const C = preload("res://scripts/chu_catalog.gd")
var screen
var zoom = 1.0
var pan = Vector2.ZERO
var touches: Dictionary = {}
var origin_touch = Vector2.ZERO
var down_square = -1
var moved = false
var held = 0
var suppressed = false
var board_rect = Rect2()
var cell = 20.0

func _ready() -> void:
	clip_contents=true; mouse_filter=Control.MOUSE_FILTER_STOP
	resized.connect(func(): cancel_input(); reset_view())
func reset_view() -> void: zoom=1.0; pan=Vector2.ZERO; queue_redraw()
func cancel_input() -> void:
	touches.clear(); down_square=-1; held=0; suppressed=true
	if screen!=null: screen.clear_pending()
func _geometry() -> void:
	var edge=maxf(36,minf(size.x-20,size.y-20))*zoom
	cell=edge/12.0
	pan.x=clampf(pan.x,-maxf(0,(edge-size.x)/2+12),maxf(0,(edge-size.x)/2+12))
	pan.y=clampf(pan.y,-maxf(0,(edge-size.y)/2+12),maxf(0,(edge-size.y)/2+12))
	board_rect=Rect2((size-Vector2.ONE*edge)/2+pan,Vector2.ONE*edge)
func square_at(point: Vector2) -> int:
	_geometry()
	if not board_rect.has_point(point): return -1
	var v=(point-board_rect.position)/cell; var square=int(v.y)*12+int(v.x)
	return 143-square if screen.flipped else square
func center(square: int) -> Vector2:
	var index=143-square if screen.flipped else square
	return board_rect.position+Vector2(index%12+0.5,index/12+0.5)*cell
func _draw() -> void:
	if screen==null: return
	_geometry()
	var p=screen.app.palette(); var pos=screen.display_position()
	draw_rect(Rect2(Vector2.ZERO,size),p.background)
	draw_rect(board_rect,p.board)
	for square in screen.highlight_squares():
		draw_rect(Rect2(center(square)-Vector2.ONE*cell/2,Vector2.ONE*cell),p.selected)
	for i in range(13):
		draw_line(board_rect.position+Vector2(i*cell,0),board_rect.position+Vector2(i*cell,12*cell),p.board_line,1)
		draw_line(board_rect.position+Vector2(0,i*cell),board_rect.position+Vector2(12*cell,i*cell),p.board_line,1)
	for target in screen.targets(): draw_circle(center(target),maxf(2,cell*0.12),p.accent)
	for square in range(144):
		var piece:int=pos.board[square]
		if piece==0: continue
		var rotation=PI if (piece<0)!=screen.flipped else 0.0
		draw_set_transform(center(square),rotation)
		var shape=PackedVector2Array([Vector2(-0.38,0.39),Vector2(-0.31,-0.30),Vector2(0,-0.43),Vector2(0.31,-0.30),Vector2(0.38,0.39)])
		for i in range(shape.size()): shape[i]*=cell
		draw_colored_polygon(shape,p.piece)
		var font_size=maxi(10,int(cell*0.61)); var value:String=C.SHORT[C.kind(piece)]
		var extent=screen.app.text_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		draw_string(screen.app.text_font,Vector2(-extent.x/2,cell*0.22),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("a3262e") if C.promoted(piece) else p.piece_ink)
		draw_set_transform(Vector2.ZERO)
	if screen.selected>=0:
		var last=center(screen.selected)
		for square in screen.path:
			var next=center(square); draw_line(last,next,p.danger,maxf(2,cell*0.07),true); draw_circle(next,cell*0.20,Color(p.danger,0.4)); last=next
	if zoom>1: draw_string(screen.app.text_font,Vector2(8,size.y-6),"%.1f×"%zoom,HORIZONTAL_ALIGNMENT_LEFT,-1,13,p.ink)
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled: cancel_input(); return
		if event.pressed:
			touches[event.index]=event.position
			if touches.size()==1: _down(event.position)
			else: suppressed=true; held=0; screen.clear_pending()
		else:
			if touches.size()==1 and not suppressed: _up(event.position)
			touches.erase(event.index)
			if touches.is_empty(): suppressed=false
		accept_event()
	elif event is InputEventScreenDrag and touches.has(event.index):
		if touches.size()>=2:
			var ids=touches.keys(); var old_a:Vector2=touches[ids[0]]; var old_b:Vector2=touches[ids[1]]
			touches[event.index]=event.position
			var a:Vector2=touches[ids[0]]; var b:Vector2=touches[ids[1]]
			var old_zoom=zoom; zoom=clampf(zoom*a.distance_to(b)/maxf(1,old_a.distance_to(old_b)),1,3)
			var old_mid=(old_a+old_b)/2; var mid=(a+b)/2
			pan=mid-size/2-(old_mid-size/2-pan)*(zoom/old_zoom)
			queue_redraw()
		else: touches[event.index]=event.position; _drag(event.position,event.relative)
		accept_event()
	elif event is InputEventMouseButton and event.device!=InputEvent.DEVICE_ID_EMULATION:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom=clampf(zoom+(0.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -0.2),1,3); screen.clear_pending(); queue_redraw()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: suppressed=false; _down(event.position)
			else: _up(event.position)
		accept_event()
	elif event is InputEventMouseMotion and event.device!=InputEvent.DEVICE_ID_EMULATION and event.button_mask&MOUSE_BUTTON_MASK_LEFT: _drag(event.position,event.relative)
func _down(point: Vector2) -> void:
	origin_touch=point; down_square=square_at(point); moved=false; held=Time.get_ticks_msec(); suppressed=false
func _drag(point: Vector2, delta: Vector2) -> void:
	if point.distance_to(origin_touch)>10: moved=true; held=0
	if moved and zoom>1: pan+=delta; suppressed=true; screen.clear_pending(); queue_redraw()
func _up(point: Vector2) -> void:
	held=0
	if suppressed: down_square=-1; return
	var target=square_at(point)
	if moved:
		if zoom<=1 and down_square>=0 and target>=0 and target!=down_square:
			screen.choose(down_square); screen.choose(target)
	elif target>=0: screen.choose(target)
	down_square=-1
func _process(_delta: float) -> void:
	if held>0 and Time.get_ticks_msec()-held>=500:
		held=0; suppressed=true
		if down_square>=0 and screen.display_position().board[down_square]!=0: screen.piece_help(screen.display_position().board[down_square])
