## Packs Floormap/Wallmap cell lists into a temp scene so the exact GridMap
## `data` serialization can be extracted for assemble_level.py.
## (GridMap cell arrays use an engine-internal packed encoding: never
## hand-write them, always round-trip through this tool.)
##
## Cell files use the dump_cells.gd format: "x,y,z,item,orientation" lines
## (FLOOR/WALL section headers are accepted and ignored).
##
## Usage:
##   python run_scratch.py tools/levels/pack_cells.gd -- --floor=/tmp/floor.txt --wall=/tmp/wall.txt --out=/tmp/cells.tscn
extends SceneTree


func _init() -> void:
	var floor_path: String = ""
	var wall_path: String = ""
	var out_path: String = "res://tools/levels/packed_cells.tscn"
	var floor_lib_path: String = "res://Levels/Gridmap/floormap.tres"
	var wall_lib_path: String = "res://Levels/Gridmap/wall_map.tres"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--floor="):
			floor_path = arg.trim_prefix("--floor=").strip_edges()
		elif arg.begins_with("--wall="):
			wall_path = arg.trim_prefix("--wall=").strip_edges()
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=").strip_edges()
		elif arg.begins_with("--floor-lib="):
			floor_lib_path = arg.trim_prefix("--floor-lib=").strip_edges()
		elif arg.begins_with("--wall-lib="):
			wall_lib_path = arg.trim_prefix("--wall-lib=").strip_edges()
	if floor_path.is_empty() or wall_path.is_empty():
		printerr("[pack_cells] ERROR: --floor= and --wall= cell files are required")
		quit(1)
		return
	floor_path = _resolve(floor_path)
	wall_path = _resolve(wall_path)
	out_path = _resolve(out_path)
	floor_lib_path = _resolve(floor_lib_path)
	wall_lib_path = _resolve(wall_lib_path)
	if floor_path.is_empty() or wall_path.is_empty() or out_path.is_empty():
		quit(1)
		return
	if not _ensure_dir(out_path.get_base_dir()):
		quit(1)
		return

	var root_node: Node3D = Node3D.new()
	root_node.name = "TmpCells"
	var floor_gm: GridMap = GridMap.new()
	floor_gm.name = "Floormap"
	floor_gm.mesh_library = load(floor_lib_path) as MeshLibrary
	floor_gm.cell_size = Vector3(4, 0.5, 4)
	root_node.add_child(floor_gm)
	var wall_gm: GridMap = GridMap.new()
	wall_gm.name = "Wallmap"
	wall_gm.mesh_library = load(wall_lib_path) as MeshLibrary
	wall_gm.cell_size = Vector3(2, 4, 2)
	wall_gm.cell_center_x = false
	wall_gm.cell_center_z = false
	root_node.add_child(wall_gm)
	_fill_cells(floor_gm, floor_path)
	_fill_cells(wall_gm, wall_path)
	print("[pack_cells] floor used=", floor_gm.get_used_cells().size(), " wall used=", wall_gm.get_used_cells().size())
	root.add_child(root_node)
	floor_gm.owner = root_node
	wall_gm.owner = root_node
	var packed: PackedScene = PackedScene.new()
	if packed.pack(root_node) != OK:
		printerr("[pack_cells] ERROR: pack failed")
		quit(1)
		return
	if ResourceSaver.save(packed, out_path) != OK:
		printerr("[pack_cells] ERROR: save failed for ", out_path)
		quit(1)
		return
	print("[pack_cells] saved ", out_path)
	quit(0)


## res:///user:// pass through; anything else is project-relative.
## Absolute OS paths do not work with FileAccess.
func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	if path.begins_with("/"):
		printerr("[pack_cells] ERROR: absolute OS paths are not usable: ", path)
		return ""
	return "res://" + path.trim_prefix("./").trim_prefix("/")


func _ensure_dir(dir: String) -> bool:
	if dir == "res://" or dir == "user://" or dir.is_empty():
		return true
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("[pack_cells] ERROR: cannot create dir ", dir)
		return false
	return true


func _fill_cells(gm: GridMap, path: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("[pack_cells] ERROR: cannot open ", path)
		return
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty() or line == "FLOOR" or line == "WALL":
			continue
		var p: PackedStringArray = line.split(",")
		gm.set_cell_item(Vector3i(int(p[0]), int(p[1]), int(p[2])), int(p[3]), int(p[4]))
	f.close()
