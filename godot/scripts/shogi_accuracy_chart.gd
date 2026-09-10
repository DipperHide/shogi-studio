extends Control
## Reference AccuracyDeviationChartView: 13 px per scored move, 144 px high.
signal point_selected(index: int)
const Classification = preload("res://scripts/shogi_move_classification.gd")
var points: Array = []
var overall: float = 0
var active_ply: int = -1
var down: bool = false
var dragged: bool = false
var origin: Vector2
var origin_scroll: int

func _ready() -> void:
	focus_mode=Control.FOCUS_ALL
	mouse_filter=Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	custom_minimum_size=Vector2(maxf(280,44+points.size()*13),144)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tooltip_text="点击查看每手准确率；横向拖动查看后续着手。左右方向键切换，Home / End 到首尾。"

func point_for(index: int) -> Vector2:
	return Vector2(34+index*13+6.5,10+(100-clampf(points[index].accuracy,0,100))*(size.y-32)/100)

func _draw() -> void:
	if points.is_empty(): return
	var font=get_theme_default_font()
	var right=size.x-6
	for mark in [100,50,0]:
		var y=10+(100-mark)*(size.y-32)/100.0
		draw_line(Vector2(34,y),Vector2(right,y),Color("f8f1e633"),1)
		draw_string(font,Vector2(0,y+3),str(mark)+"%",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("d9cab4"))
	var base=10+(100-clampf(overall,0,100))*(size.y-32)/100
	draw_dashed_line(Vector2(34,base),Vector2(right,base),Color("58a6ff"),1.5,5)
	for i in range(points.size()):
		var point=points[i]
		var pos=point_for(i)
		var top=Vector2(pos.x,10)
		if point.ply==active_ply:
			draw_line(top,pos,Color("f8f1e6"),9,true)
			draw_circle(pos,5,Color("f8f1e6"))
		var color=Color(Classification.COLORS[maxi(0,Classification.NAMES.find(point.category))])
		draw_line(top,pos,color,5,true)
		draw_circle(pos,3,color)
		# Shogi numbers each ply, including gote-first SFEN games.
		if i==0 or i==points.size()-1 or (i+1)%5==0:
			var caption=str(point.ply)
			var width=font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x
			draw_string(font,Vector2(pos.x-width/2,size.y-6),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("d9cab4"))

func choose(index: int) -> void:
	if points.is_empty(): return
	index=clampi(index,0,points.size()-1)
	active_ply=points[index].ply
	queue_redraw()
	point_selected.emit(index)

func _gui_input(event: InputEvent) -> void:
	if points.is_empty(): return
	if event is InputEventKey and event.pressed:
		var index=0
		for i in range(points.size()):
			if points[i].ply==active_ply: index=i; break
		match event.keycode:
			KEY_LEFT: choose(index-1)
			KEY_RIGHT: choose(index+1)
			KEY_HOME: choose(0)
			KEY_END: choose(points.size()-1)
			_: return
		accept_event()
	elif (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT) or event is InputEventScreenTouch:
		var at: Vector2=global_position+event.position
		if event.pressed:
			down=true; dragged=false; origin=at
			origin_scroll=get_parent().scroll_horizontal
			grab_focus()
		elif down:
			down=false
			if not dragged and origin.distance_to(at)<=10:
				choose(int((event.position.x-34)/13))
				accept_event()
	elif down and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		var delta: Vector2=global_position+event.position-origin
		if delta.length()>10: dragged=true
		if dragged and absf(delta.x)>absf(delta.y):
			get_parent().scroll_horizontal=origin_scroll-roundi(delta.x)
			accept_event()
