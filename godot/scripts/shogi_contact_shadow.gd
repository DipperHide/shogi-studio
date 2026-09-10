extends MeshInstance3D
## Projected contact penumbra. Same identity/transform as the actual piece;
## updates only while its owner moves, including reverse and replay flights.
const Scene = preload("res://scripts/shogi_scene_layout.gd")
var body: Node3D
var footprint: Vector2
var fixed_surface = -1.0
var previous = Transform3D()
var first = true
var material: ShaderMaterial

func setup(owner_piece: Node3D, dimensions: Vector2, surface: float) -> void:
	body = owner_piece
	name = "PieceContact"
	footprint = dimensions
	fixed_surface = surface
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = preload("res://assets/materials/contact_shadow.gdshader")
	material.set_shader_parameter("clip_to_tabletop",surface<0)
	material.set_shader_parameter("table_layout",Vector4(Scene.data.board_width/2,Scene.data.board_depth/2,Scene.data.tray_x,Scene.data.tray_z))
	material.set_shader_parameter("tray_half_size",Vector2(Scene.data.tray_width/2,Scene.data.tray_depth/2))
	material_override = material
	mesh = PlaneMesh.new()
	mesh.size = Vector2.ONE

func _process(_delta: float) -> void:
	sync_pose()

func sync_pose() -> void:
	# Tweens run after _process; renderers call this after moving the owner.
	# A newly created top-level shadow must also receive its pose before drawing.
	if not is_inside_tree(): return
	if not first and body.global_transform == previous:
		return
	first = false
	previous = body.global_transform
	var surface = fixed_surface if fixed_surface >= 0 else Scene.data.board_top+0.006
	var scale_factor = body.global_basis.x.length()
	var gap = maxf(0,body.global_position.y-surface)
	var penumbra = 0.025*scale_factor+gap*0.095
	var dimensions = footprint*scale_factor
	var quad = dimensions+Vector2.ONE*(penumbra*5+0.14)
	global_position = Vector3(body.global_position.x+gap*0.48+0.045*scale_factor,surface,body.global_position.z+gap*0.16+0.025*scale_factor)
	global_rotation = Vector3(0,body.global_rotation.y,0)
	scale = Vector3(quad.x,1,quad.y)
	material.set_shader_parameter("footprint",dimensions)
	material.set_shader_parameter("quad_size",quad)
	material.set_shader_parameter("softness",penumbra)
	material.set_shader_parameter("opacity",0.40*exp(-gap*0.45))
