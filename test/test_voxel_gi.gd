extends Node

func _ready() -> void:
	print("--- RUNNING VOXEL GI TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	# 1. Verify VoxelGI node exists in LevelTemplate
	var voxel_gi: VoxelGI = level.get_node_or_null("VoxelGI") as VoxelGI
	if voxel_gi == null:
		printerr("TEST FAILED: VoxelGI node not found in LevelTemplate.tscn")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("VoxelGI node found at position: ", voxel_gi.position, " with size: ", voxel_gi.size)
	
	# 2. Verify VoxelGIData resource is assigned and contains baked bounds
	if voxel_gi.data == null:
		printerr("TEST FAILED: VoxelGI has no VoxelGIData assigned.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
		
	var baked_bounds: AABB = voxel_gi.data.get_bounds()
	if baked_bounds.size == Vector3.ZERO:
		printerr("TEST FAILED: VoxelGIData has zero bounds (not baked).")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("VoxelGIData verified with baked bounds: ", baked_bounds)
	
	# Check baked file size on disk
	var file_path := "res://Levels/GlobalIlluminationData/level_template_voxel_gi_data.tres"
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		printerr("TEST FAILED: Cannot open baked VoxelGIData file at: ", file_path)
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	var file_length: int = file.get_length()
	file.close()
	if file_length < 50000:
		printerr("TEST FAILED: Baked file is unexpectedly small: ", file_length, " bytes")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Baked VoxelGIData file size verified on disk: ", file_length, " bytes")
	
	# 3. Verify VoxelGI bounds enclose the extended level template
	var vgi_box := AABB(voxel_gi.position - voxel_gi.size * 0.5, voxel_gi.size)
	print("VoxelGI bounding volume: ", vgi_box)
	var spawn_point := Vector3(0, 1, 0)
	var pit_point := Vector3(0, -2, -16)
	var far_point := Vector3(0, 0, -40)
	var dummy_point := Vector3(0, 1.7, 4.0)
	for pt: Vector3 in [spawn_point, pit_point, far_point, dummy_point]:
		if not vgi_box.has_point(pt):
			printerr("TEST FAILED: VoxelGI volume does not enclose level point: ", pt)
			level.queue_free()
			await get_tree().physics_frame
			get_tree().quit(1)
			return
	print("VoxelGI volume successfully encloses spawn, pit, dummy, and far level bounds!")
	
	# 4. Verify dynamic mesh nodes have GI mode disabled (gi_mode == 0)
	if level.has_node("StaticBody3D/MeshInstance3D"):
		var dummy_mesh: MeshInstance3D = level.get_node("StaticBody3D/MeshInstance3D") as MeshInstance3D
		if dummy_mesh.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
			printerr("TEST FAILED: Dummy enemy MeshInstance3D gi_mode is not disabled.")
			level.queue_free()
			await get_tree().physics_frame
			get_tree().quit(1)
			return
		print("Dummy enemy MeshInstance3D gi_mode correctly disabled (gi_mode = 0).")
	
	var player: Player = level.get_node("Player") as Player
	var sword_mesh: MeshInstance3D = player.get_node("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/LazerSword") as MeshInstance3D
	var handle_mesh: MeshInstance3D = player.get_node("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/Handle") as MeshInstance3D
	if sword_mesh.gi_mode != GeometryInstance3D.GI_MODE_DISABLED or handle_mesh.gi_mode != GeometryInstance3D.GI_MODE_DISABLED:
		printerr("TEST FAILED: Player weapon mesh gi_mode is not disabled.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Player weapon meshes gi_mode correctly disabled (gi_mode = 0).")
	
	# 5. Verify import settings for mannequin have light_baking disabled
	var import_file := FileAccess.open("res://Assets/KayKit_Assets/KayKit_GameDevTV_Free_Sample_Pack_1.0/Character/GamedevTV_Mannequin_Medium.glb.import", FileAccess.READ)
	if import_file != null:
		var content: String = import_file.get_as_text()
		import_file.close()
		if "meshes/light_baking=0" not in content:
			printerr("TEST FAILED: Mannequin import file does not have meshes/light_baking=0.")
			level.queue_free()
			await get_tree().physics_frame
			get_tree().quit(1)
			return
		print("Mannequin import config confirmed (meshes/light_baking=0).")
	
	print("\n====================================================================")
	print("  ALL VOXEL GI TESTS PASSED!                                        ")
	print("  1. VoxelGI node added with appropriate dimensions                 ")
	print("  2. Baked VoxelGIData present and valid on disk                    ")
	print("  3. Bounds enclose spawn, pit, dummy, and extended level geometry   ")
	print("  4. Dynamic meshes (weapons, dummy, mannequin) excluded from GI    ")
	print("====================================================================")
	
	level.queue_free()
	await get_tree().physics_frame
	get_tree().quit(0)
