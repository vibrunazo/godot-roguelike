## Scene-based navmesh bake runner (plain Node in bake_navmesh_scene.tscn).
##
## Performs the exact same bake as bake_navmesh.gd (parse + bake_from on a
## duplicated region mesh, same snippet format), but runs as a scene instead
## of a -s SceneTree script: level scripts reference autoload singletons
## (SceneTransition, GlobalVars, ProgressionState, UI, ...) that do not
## resolve in -s runs, so the -s bake cannot load template-inheriting levels.
## Scene runs (like run_tests.py uses) resolve them normally.
##
## Usage:
##   godot --headless --path . tools/levels/bake_navmesh_scene.tscn --
##       --level=Levels/boss_arena_1.tscn --out=tools/levels/out/boss1proof/navmesh_baked.txt
extends Node


var _level_path: String = ""
var _out_path: String = ""
var _exit_code: int = 1


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			_level_path = arg.trim_prefix("--level=").strip_edges()
		elif arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=").strip_edges()
	_level_path = _resolve(_level_path)
	_out_path = _resolve(_out_path)
	if _level_path.is_empty() or _out_path.is_empty() or not _ensure_dir(_out_path.get_base_dir()):
		get_tree().quit(1)
		return
	_bake.call_deferred()


func _bake() -> void:
	var packed: PackedScene = load(_level_path) as PackedScene
	if packed == null:
		printerr("[bake_navmesh] ERROR: cannot load ", _level_path)
		get_tree().quit(1)
		return
	var level: Node3D = packed.instantiate() as Node3D
	add_child(level)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var region: NavigationRegion3D = level.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		printerr("[bake_navmesh] ERROR: NavigationRegion3D/mesh missing")
		get_tree().quit(1)
		return
	var mesh: NavigationMesh = region.navigation_mesh
	var pre: PackedVector3Array = mesh.get_vertices().duplicate()
	var fresh: NavigationMesh = mesh.duplicate() as NavigationMesh
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationMeshGenerator.parse_source_geometry_data(fresh, data, level)
	if not data.has_data():
		printerr("[bake_navmesh] ERROR: parse found no geometry; ",
			"the editor Bake button is required for this level")
		get_tree().quit(1)
		return
	NavigationMeshGenerator.bake_from_source_geometry_data(fresh, data)
	if fresh.get_vertices().is_empty():
		printerr("[bake_navmesh] ERROR: bake parsed no geometry (empty mesh); ",
			"the editor Bake button is required for this level")
		get_tree().quit(1)
		return
	if _same_verts(pre, fresh.get_vertices()):
		printerr("[bake_navmesh] ERROR: bake returned the input unchanged; ",
			"mesh was NOT baked (scaffold passthrough refused)")
		get_tree().quit(1)
		return
	mesh.clear_polygons()
	mesh.set_vertices(fresh.get_vertices())
	for i: int in range(fresh.get_polygon_count()):
		mesh.add_polygon(fresh.get_polygon(i))
	print("[bake_navmesh] baked: ", mesh.get_polygon_count(), " polygons, ",
		mesh.get_vertices().size(), " vertices")

	var out: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if out == null:
		printerr("[bake_navmesh] ERROR: cannot open ", _out_path)
		get_tree().quit(1)
		return
	var verts: PackedVector3Array = mesh.get_vertices()
	out.store_string("vertices = PackedVector3Array(")
	var parts: PackedStringArray = PackedStringArray()
	for v: Vector3 in verts:
		parts.append("%s, %s, %s" % [_fmt(v.x), _fmt(v.y), _fmt(v.z)])
	out.store_string(", ".join(parts))
	out.store_string(")\npolygons = [")
	var tris: PackedStringArray = PackedStringArray()
	for i: int in range(mesh.get_polygon_count()):
		var poly: PackedInt32Array = mesh.get_polygon(i)
		var idx: PackedStringArray = PackedStringArray()
		for v: int in poly:
			idx.append(str(v))
		tris.append("PackedInt32Array(" + ", ".join(idx) + ")")
	out.store_string(", ".join(tris))
	out.store_string("]\n")
	out.close()
	print("[bake_navmesh] wrote ", _out_path)
	get_tree().quit(0)


## True when two vertex arrays match exactly (bake changed nothing).
func _same_verts(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] != b[i]:
			return false
	return true


## Snaps floats to micrometers and trims noise so baked files stay readable
## (editor-style: integers print bare, e.g. -72 instead of -72.0).
func _fmt(f: float) -> String:
	var s: float = snappedf(f, 0.000001)
	if s == floor(s):
		return str(int(s))
	var t: String = "%0.6f" % s
	while t.ends_with("0"):
		t = t.trim_suffix("0")
	return t.trim_suffix(".")


func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	if path.begins_with("/"):
		printerr("[bake_navmesh] ERROR: absolute OS paths are not usable: ", path)
		return ""
	return "res://" + path.trim_prefix("./").trim_prefix("/")


func _ensure_dir(dir: String) -> bool:
	if dir == "res://" or dir == "user://" or dir.is_empty():
		return true
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		printerr("[bake_navmesh] ERROR: cannot create dir ", dir)
		return false
	return true
