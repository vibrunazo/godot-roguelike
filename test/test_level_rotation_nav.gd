## Rotation integrity test: every level in `SceneTransition.levels` must load,
## expose its core nodes (Player, ExitPoint, WaveObjective, VoxelGI with baked
## data), and provide a valid navigation path from player spawn to the exit
## with a VoxelGI volume that covers the floor footprint.
extends Node3D


func _ready() -> void:
	print("====================================================")
	print("  STARTING LEVEL ROTATION NAV TEST")
	print("====================================================")

	var st_scene: PackedScene = load("res://Singletons/scene_transition.tscn") as PackedScene
	if st_scene == null:
		printerr("TEST FAILED: Could not load scene_transition.tscn")
		get_tree().quit(1)
		return
	var st: Node = st_scene.instantiate()
	add_child(st)
	var level_paths: Array = st.get("levels") as Array
	print("Rotation levels: ", level_paths)
	if level_paths.is_empty():
		printerr("TEST FAILED: level rotation list is empty")
		get_tree().quit(1)
		return

	var failed: bool = false
	for path_variant: Variant in level_paths:
		var level_path: String = str(path_variant)
		if not await _verify_level(level_path):
			failed = true
		# Settle so the freed region unregisters before the next level loads.
		await get_tree().physics_frame
		await get_tree().physics_frame
		await get_tree().physics_frame

	st.queue_free()
	if failed:
		printerr("LEVEL ROTATION NAV TEST FAILED")
		get_tree().quit(1)
	else:
		print("LEVEL ROTATION NAV TEST PASSED")
		get_tree().quit(0)


## Verifies a single level scene. Returns true on success.
func _verify_level(level_path: String) -> bool:
	print("--- Verifying ", level_path, " ---")
	if not ResourceLoader.exists(level_path):
		printerr("TEST FAILED: missing level scene: ", level_path)
		return false
	var packed: PackedScene = load(level_path) as PackedScene
	if packed == null:
		printerr("TEST FAILED: could not load: ", level_path)
		return false
	var level: Node3D = packed.instantiate() as Node3D
	add_child(level)

	# Silence the wave spawner so no enemies interfere with the check.
	var wave_obj: Node = level.find_child("WaveObjective", true, false)
	if wave_obj == null:
		printerr("TEST FAILED: WaveObjective missing in ", level_path)
		level.queue_free()
		return false
	wave_obj.set_script(null)
	for c: Node in wave_obj.get_children():
		c.queue_free()

	# The navigation server registers regions asynchronously; poll until the
	# player spawn snaps onto the navmesh (or time out).
	var synced: bool = false
	for i: int in range(120):
		await get_tree().physics_frame
		var probe: Node3D = level.find_child("Player", true, false) as Node3D
		if probe != null:
			var snap: Vector3 = NavigationServer3D.map_get_closest_point(
				get_world_3d().get_navigation_map(),
				Vector3(probe.global_position.x, 1.0, probe.global_position.z))
			if snap != Vector3.ZERO:
				synced = true
				break
	if not synced:
		printerr("TEST FAILED: navmesh never synced in ", level_path)
		level.queue_free()
		return false

	var ok: bool = true
	var player: Node3D = level.find_child("Player", true, false) as Node3D
	var exit_point: Node3D = level.find_child("ExitPoint", true, false) as Node3D
	if player == null:
		printerr("TEST FAILED: Player missing in ", level_path)
		ok = false
	if exit_point == null:
		printerr("TEST FAILED: ExitPoint missing in ", level_path)
		ok = false

	var gi: VoxelGI = level.find_child("VoxelGI", true, false) as VoxelGI
	if gi == null:
		printerr("TEST FAILED: VoxelGI missing in ", level_path)
		ok = false
	elif gi.data == null:
		printerr("TEST FAILED: VoxelGI data not baked in ", level_path)
		ok = false

	if ok:
		if not _verify_navmesh_covers_level(level, level_path):
			ok = false
		if not _verify_path(player.global_position, exit_point.global_position, level_path):
			ok = false

	level.queue_free()
	if ok:
		print("OK: ", level_path)
	return ok


## Checks the navmesh spans the level footprint and the VoxelGI volume covers it.
func _verify_navmesh_covers_level(level: Node3D, level_path: String) -> bool:
	var region: NavigationRegion3D = level.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		printerr("TEST FAILED: NavigationRegion3D/mesh missing in ", level_path)
		return false
	var nav_aabb: AABB = AABB()
	var first_vert: bool = true
	for v: Vector3 in region.navigation_mesh.get_vertices():
		# Vertices are stored in the region's local space.
		var world_v: Vector3 = region.to_global(v)
		if first_vert:
			nav_aabb = AABB(world_v, Vector3.ZERO)
			first_vert = false
		else:
			nav_aabb = nav_aabb.expand(world_v)
	var floor_box: AABB = AABB()
	var has_floor: bool = false
	for gm_node: Node in level.find_children("*", "GridMap", true, false):
		var gm: GridMap = gm_node as GridMap
		if gm == null or gm.name != "Floormap":
			continue
		for cell: Vector3i in gm.get_used_cells():
			var world_pos: Vector3 = gm.to_global(gm.map_to_local(cell))
			var pad: Vector3 = gm.cell_size * 0.5
			var box: AABB = AABB(world_pos - pad, gm.cell_size)
			if not has_floor:
				floor_box = box
				has_floor = true
			else:
				floor_box = floor_box.merge(box)
	if not has_floor:
		printerr("TEST FAILED: Floormap has no cells in ", level_path)
		return false
	# Navmesh is baked slightly above the floor; compare horizontal extents,
	# allowing half a floor tile of wall-adjacent inset.
	var margin: float = 2.0
	if nav_aabb.position.x > floor_box.position.x + margin or nav_aabb.end.x < floor_box.end.x - margin:
		printerr("TEST FAILED: navmesh X span ", nav_aabb, " misses floor ", floor_box, " in ", level_path)
		return false
	if nav_aabb.position.z > floor_box.position.z + margin or nav_aabb.end.z < floor_box.end.z - margin:
		printerr("TEST FAILED: navmesh Z span ", nav_aabb, " misses floor ", floor_box, " in ", level_path)
		return false
	var gi: VoxelGI = level.find_child("VoxelGI", true, false) as VoxelGI
	var gi_box: AABB = AABB(gi.global_position - gi.size * 0.5, gi.size)
	if gi_box.position.x > floor_box.position.x or gi_box.end.x < floor_box.end.x:
		printerr("TEST FAILED: VoxelGI X span misses floor in ", level_path)
		return false
	if gi_box.position.z > floor_box.position.z or gi_box.end.z < floor_box.end.z:
		printerr("TEST FAILED: VoxelGI Z span misses floor in ", level_path)
		return false
	print("navmesh + VoxelGI cover floor footprint in ", level_path)
	return true


## Checks a navigation path exists between two points on the level.
func _verify_path(from_pos: Vector3, to_pos: Vector3, level_path: String) -> bool:
	var nav_map: RID = get_world_3d().get_navigation_map()
	var from_point: Vector3 = Vector3(from_pos.x, 1.0, from_pos.z)
	var to_point: Vector3 = Vector3(to_pos.x, 1.0, to_pos.z)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from_point, to_point, true, 1)
	if path.size() < 2:
		printerr("TEST FAILED: no nav path from ", from_point, " to ", to_point, " in ", level_path)
		return false
	print("nav path OK (", path.size(), " points) in ", level_path)
	return true
