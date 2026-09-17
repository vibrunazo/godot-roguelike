## Actual Player input-driven traversal of both baked Level 13 stairways.
## No body teleport, jump, velocity override or replacement collision is used.
extends Node3D

var player: Character = null
var resting_offset: float = 0.0

func _ready() -> void:
	var level: Node3D = (load("res://Levels/level_13.tscn") as PackedScene).instantiate() as Node3D
	# Strip the wave script before _ready can allocate/spawn enemies.
	var wave: Node = level.find_child("WaveObjective", true, false)
	wave.set_script(null)
	add_child(level)
	player = level.get_node("Player") as Character
	# Save the authored collider pose before physics can eject an overlapping
	# spawn. Shrink slightly to ignore intended contact with the floor.
	var spawn_collider: CollisionShape3D = player.get_node("CollisionShape3D") as CollisionShape3D
	var spawn_pose: Transform3D = spawn_collider.global_transform
	var spawn_shape: CapsuleShape3D = spawn_collider.shape.duplicate() as CapsuleShape3D
	spawn_shape.radius *= 0.95
	spawn_shape.height *= 0.95
	# Navigation regions register asynchronously; iteration_id alone turns
	# non-zero on the first empty-map sync, so poll for actual region data
	# (same primitive the rotation suite uses) before any nav query.
	var nav_map: RID = get_world_3d().get_navigation_map()
	var nav_ready: bool = false
	for frame: int in range(120):
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
			continue
		if NavigationServer3D.map_get_closest_point(nav_map, player.global_position) != Vector3.ZERO:
			nav_ready = true
			break
	if not nav_ready:
		printerr("TEST FAILED: navigation region never registered in dedicated scene")
		get_tree().quit(1)
		return
	var spawn_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	spawn_query.shape = spawn_shape
	spawn_query.transform = spawn_pose
	spawn_query.collision_mask = player.collision_mask
	spawn_query.exclude = [player.get_rid()]
	var overlaps: Array[Dictionary] = get_world_3d().direct_space_state.intersect_shape(spawn_query)
	if not overlaps.is_empty():
		printerr("TEST FAILED: authored spawn intersects geometry: ", overlaps)
		get_tree().quit(1)
		return
	print("Authored spawn collider is clear before settling")
	for frame: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor():
			break
	resting_offset = player.global_position.y
	# Approach from the authored spawn, climb north flight, descend south flight.
	var targets: Array[Vector3] = [Vector3(-6, 0, 2), Vector3(-6, 0, -6), Vector3(6, 2, -6), Vector3(-6, 0, -6), Vector3(-6, 0, 10), Vector3(6, 2, 10), Vector3(-6, 0, 10)]
	for target: Vector3 in targets:
		if not await _walk_to(target):
			get_tree().quit(1)
			return
	print("LEVEL 13 STAIRS TEST PASSED: actual Player climbed to upper floor and descended via second flight")
	get_tree().quit(0)

## Drives ordinary movement actions in camera space; production states do physics.
func _walk_to(target: Vector3) -> bool:
	var start: Vector3 = player.global_position
	for frame: int in range(360):
		var offset: Vector3 = target - player.global_position
		offset.y = 0.0
		_release()
		if offset.length() < 0.25 and player.is_on_floor():
			if absf(player.global_position.y - resting_offset - target.y) < 0.2:
				print("Player reached ", target, " at ", player.global_position, " delta=", player.global_position - start)
				return true
			break
		var camera: Camera3D = get_viewport().get_camera_3d()
		var direction: Vector3 = offset.normalized()
		if camera != null:
			direction = direction.rotated(Vector3.UP, -camera.global_rotation.y)
		Input.action_press("move_right" if direction.x > 0.0 else "move_left", absf(direction.x))
		Input.action_press("move_back" if direction.z > 0.0 else "move_forward", absf(direction.z))
		await get_tree().physics_frame
	_release()
	printerr("TEST FAILED: Player blocked target=", target, " actual=", player.global_position, " delta=", player.global_position - start, " velocity=", player.velocity)
	for index: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		printerr(" collision pos=", collision.get_position(), " normal=", collision.get_normal(), " collider=", collision.get_collider())
		var gm: GridMap = collision.get_collider() as GridMap
		if gm != null and gm.mesh_library != null:
			for cell: Vector3i in gm.get_used_cells():
				var item: int = gm.get_cell_item(cell)
				var mesh: Mesh = gm.mesh_library.get_item_mesh(item)
				var transform: Transform3D = gm.global_transform * Transform3D(gm.get_cell_item_basis(cell), gm.map_to_local(cell)) * gm.mesh_library.get_item_mesh_transform(item)
				var box: AABB = transform * mesh.get_aabb()
				if box.grow(0.5).has_point(collision.get_position()):
					printerr(" blocker cell=", cell, " item=", item, " world mesh AABB=", box)
	return false

func _release() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(action)
