## Bake-scene root: sanity-checks a level's navigation, then bakes its
## VoxelGI data to a .res file.
##
## Args (Godot user args):
##   --level=   level scene to bake (default res://Levels/level_4.tscn)
##   --gi-out=  destination VoxelGIData path (default res://Levels/GlobalIlluminationData/level_4_voxel_gi_data.res)
##
## Must run WITH the display server (like capture.py), because VoxelGI baking
## needs the renderer. Run it through a watchdogged launcher, e.g.:
##   python -c "import shutil, subprocess; ..."
## (see tools/levels/README.md). Bake scenes always quit() explicitly.
extends Node3D

var level_path: String = "res://Levels/level_4.tscn"
var gi_out: String = "res://Levels/GlobalIlluminationData/level_4_voxel_gi_data.res"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_path = arg.trim_prefix("--level=").strip_edges()
		elif arg.begins_with("--gi-out="):
			gi_out = arg.trim_prefix("--gi-out=").strip_edges()
	level_path = _resolve(level_path)
	gi_out = _resolve(gi_out)
	if level_path.is_empty() or gi_out.is_empty():
		get_tree().quit(1)
		return

	var packed: PackedScene = load(level_path) as PackedScene
	if packed == null:
		printerr("[BakeGI] ERROR: cannot load ", level_path)
		get_tree().quit(1)
		return
	var level: Node3D = packed.instantiate() as Node3D
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not await _check_navmesh(level):
		get_tree().quit(1)
		return
	_bake_gi(level)
	get_tree().quit(0)


## res:///user:// pass through; anything else is project-relative.
## Absolute OS paths do not work with FileAccess/ResourceSaver.
func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	if path.begins_with("/"):
		printerr("[BakeGI] ERROR: absolute OS paths are not usable: ", path)
		return ""
	return "res://" + path.trim_prefix("./").trim_prefix("/")


## Verifies a navigation path exists across the level before baking GI.
func _check_navmesh(level: Node3D) -> bool:
	var player: Node3D = level.find_child("Player", true, false) as Node3D
	var exit_point: Node3D = level.find_child("ExitPoint", true, false) as Node3D
	if player == null or exit_point == null:
		printerr("[BakeGI] ERROR: Player/ExitPoint missing")
		return false
	for i: int in range(120):
		await get_tree().physics_frame
		var snap: Vector3 = NavigationServer3D.map_get_closest_point(
			get_world_3d().get_navigation_map(),
			Vector3(player.global_position.x, 1.0, player.global_position.z))
		if snap != Vector3.ZERO:
			break
	var nav_map: RID = get_world_3d().get_navigation_map()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		nav_map, Vector3(player.global_position.x, 1.0, player.global_position.z),
		Vector3(exit_point.global_position.x, 1.0, exit_point.global_position.z), true, 1)
	print("[BakeGI] nav path points: ", path.size())
	if path.size() < 2:
		printerr("[BakeGI] ERROR: empty navigation path, fix the navmesh first")
		return false
	return true


func _bake_gi(level: Node3D) -> void:
	var gi: VoxelGI = level.find_child("VoxelGI", true, false) as VoxelGI
	if gi == null:
		printerr("[BakeGI] ERROR: VoxelGI node not found")
		get_tree().quit(1)
		return
	print("[BakeGI] VoxelGI size=", gi.size, " pos=", gi.global_position)
	var data: VoxelGIData = VoxelGIData.new()
	gi.data = data
	gi.bake()
	print("[BakeGI] bake done, saving to ", gi_out)
	if ResourceSaver.save(data, gi_out) != OK:
		printerr("[BakeGI] ERROR: saving GI data failed")
		get_tree().quit(1)
		return
	print("[BakeGI] GI data saved")
