## Generic 3D navigation trail system rendering animated breadcrumbs toward active objectives.
class_name ObjectiveTrail3D
extends Node3D

## Target Node3D to guide the player toward.
var target_node: Node3D = null

## Target world position when no target Node3D is specified.
var target_position: Vector3 = Vector3.ZERO

## Color of the glowing breadcrumb ribbon.
@export var trail_color: Color = Color(0.3, 0.85, 1.0, 0.85)

## Width of the ribbon in meters.
@export var ribbon_width: float = 0.35

## Dash length in meters.
@export var dash_length: float = 1.0

## Gap length between dashes in meters.
@export var gap_length: float = 0.5

## Elevation offset above the floor to avoid z-fighting with floor tiles.
@export var vertical_offset: float = 0.12

## Speed of the crawling forward animation in meters per second.
@export var crawl_speed: float = 2.5

## Minimum distance to objective before the trail fades out.
@export var arrive_distance: float = 2.5

## Whether the trail is actively navigating.
var is_active: bool = false

var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D
var _path_update_timer: float = 0.0
var _current_path: PackedVector3Array = PackedVector3Array()
var _anim_offset: float = 0.0


func _ready() -> void:
	add_to_group("objective_trail")
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.top_level = true

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = trail_color
	_mesh_instance.material_override = _material

	add_child(_mesh_instance)


## Sets a Node3D objective target and activates the trail.
func set_target(node: Node3D, color: Color = Color(0.3, 0.85, 1.0, 0.85)) -> void:
	target_node = node
	trail_color = color
	if _material != null:
		_material.albedo_color = trail_color
	is_active = true
	_path_update_timer = 0.0
	_recalculate_path()


## Sets a 3D coordinate target and activates the trail.
func set_target_position(pos: Vector3, color: Color = Color(0.3, 0.85, 1.0, 0.85)) -> void:
	target_node = null
	target_position = pos
	trail_color = color
	if _material != null:
		_material.albedo_color = trail_color
	is_active = true
	_path_update_timer = 0.0
	_recalculate_path()


## Deactivates and clears the breadcrumb trail.
func clear_target() -> void:
	target_node = null
	target_position = Vector3.ZERO
	is_active = false
	_current_path.clear()
	if _immediate_mesh != null:
		_immediate_mesh.clear_surfaces()


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	if target_node != null and is_instance_valid(target_node):
		target_position = target_node.global_position

	var player: Character = get_tree().get_first_node_in_group("player") as Character
	if player == null or not player.is_inside_tree():
		if _immediate_mesh != null:
			_immediate_mesh.clear_surfaces()
		return

	# If player reached objective, clear display
	var dist: float = player.global_position.distance_to(target_position)
	if dist <= arrive_distance:
		if _immediate_mesh != null:
			_immediate_mesh.clear_surfaces()
		return

	_path_update_timer -= delta
	if _path_update_timer <= 0.0:
		_path_update_timer = 0.3
		_recalculate_path()

	_anim_offset = wrapf(_anim_offset + delta * crawl_speed, 0.0, dash_length + gap_length)
	_render_trail()


func _recalculate_path() -> void:
	var player: Character = get_tree().get_first_node_in_group("player") as Character
	if player == null or not player.is_inside_tree():
		_current_path.clear()
		return

	var nav_map: RID = get_world_3d().navigation_map
	_current_path = NavigationServer3D.map_get_path(
		nav_map,
		player.global_position,
		target_position,
		true
	)


func _render_trail() -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()

	if _current_path.size() < 2:
		return

	var cycle_length: float = dash_length + gap_length
	var half_w: float = ribbon_width * 0.5
	var v_offset: Vector3 = Vector3(0.0, vertical_offset, 0.0)
	var surface_started: bool = false

	for i: int in range(_current_path.size() - 1):
		var p1: Vector3 = _current_path[i] + v_offset
		var p2: Vector3 = _current_path[i + 1] + v_offset
		var seg_vec: Vector3 = p2 - p1
		var seg_len: float = seg_vec.length()
		if seg_len < 0.01:
			continue

		var dir: Vector3 = seg_vec / seg_len
		var perp: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		if perp.is_zero_approx():
			perp = Vector3.RIGHT * half_w
		else:
			perp = perp.normalized() * half_w

		var dist_along: float = _anim_offset - cycle_length
		while dist_along < seg_len:
			var d_start: float = maxf(0.0, dist_along)
			var d_end: float = minf(dist_along + dash_length, seg_len)
			if d_end > d_start:
				if not surface_started:
					_immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
					surface_started = true

				var start_pt: Vector3 = p1 + dir * d_start
				var end_pt: Vector3 = p1 + dir * d_end

				var v0: Vector3 = start_pt - perp
				var v1: Vector3 = start_pt + perp
				var v2: Vector3 = end_pt + perp
				var v3: Vector3 = end_pt - perp

				# Quad as two triangles
				_immediate_mesh.surface_add_vertex(v0)
				_immediate_mesh.surface_add_vertex(v1)
				_immediate_mesh.surface_add_vertex(v2)

				_immediate_mesh.surface_add_vertex(v0)
				_immediate_mesh.surface_add_vertex(v2)
				_immediate_mesh.surface_add_vertex(v3)

			dist_along += cycle_length

	if surface_started:
		_immediate_mesh.surface_end()
