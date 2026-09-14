## Dumps a level's Floormap/Wallmap GridMap cells to a text file for inspection
## or as input to the tools/levels pipeline (validate, edit, re-pack).
##
## Usage:
##   python run_scratch.py tools/levels/dump_cells.gd -- --level=Levels/level_2.tscn --out=/tmp/level_2_cells.txt
##
## Output format (compatible with pack_cells.gd and validate_layout.py):
##   FLOOR
##   x,y,z,item,orientation   (one sorted line per used cell)
##   WALL
##   x,y,z,item,orientation
extends SceneTree


func _init() -> void:
	var level_path: String = "res://Levels/level_2.tscn"
	var out_path: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_path = arg.trim_prefix("--level=").strip_edges()
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=").strip_edges()
	level_path = _resolve(level_path)
	if level_path.is_empty():
		quit(1)
		return
	if out_path.is_empty():
		out_path = "res://tools/levels/out/%s_cells.txt" % level_path.get_file().get_basename()
	out_path = _resolve(out_path)
	if out_path.is_empty() or not _ensure_dir(out_path.get_base_dir()):
		quit(1)
		return

	var packed: PackedScene = load(level_path) as PackedScene
	if packed == null:
		printerr("[dump_cells] ERROR: cannot load ", level_path)
		quit(1)
		return
	var inst: Node3D = packed.instantiate() as Node3D
	root.add_child(inst)
	var floor_gm: GridMap = inst.find_child("Floormap", true, false) as GridMap
	var wall_gm: GridMap = inst.find_child("Wallmap", true, false) as GridMap
	if floor_gm == null or wall_gm == null:
		printerr("[dump_cells] ERROR: Floormap/Wallmap not found in ", level_path)
		quit(1)
		return

	var out: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		printerr("[dump_cells] ERROR: cannot open ", out_path)
		quit(1)
		return
	out.store_line("FLOOR")
	_dump_gridmap(out, floor_gm)
	out.store_line("WALL")
	_dump_gridmap(out, wall_gm)
	out.close()
	print("[dump_cells] wrote ", out_path)
	quit(0)


## Resolves a user-supplied path: res:///user:// pass through, anything else
## is treated as project-relative. Absolute OS paths (/tmp/...) do NOT work
## with FileAccess, so they are rejected here instead of failing silently.
func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	if path.begins_with("/"):
		printerr("[dump_cells] ERROR: absolute OS paths are not usable: ", path)
		return ""
	return "res://" + path.trim_prefix("./").trim_prefix("/")


func _ensure_dir(dir: String) -> bool:
	if dir == "res://" or dir == "user://" or dir.is_empty():
		return true
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("[dump_cells] ERROR: cannot create dir ", dir)
		return false
	return true


func _dump_gridmap(out: FileAccess, gm: GridMap) -> void:
	var cells: Array[Vector3i] = gm.get_used_cells()
	cells.sort()
	for c: Vector3i in cells:
		out.store_line("%d,%d,%d,%d,%d" % [c.x, c.y, c.z, gm.get_cell_item(c), gm.get_cell_item_orientation(c)])
	print("[dump_cells] ", gm.name, ": ", cells.size(), " cells")
