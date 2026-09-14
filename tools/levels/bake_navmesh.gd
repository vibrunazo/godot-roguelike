## Bakes a level's NavigationRegion3D mesh at runtime (headless-safe) and
## exports the baked mesh as a snippet file, ready to splice into the level
## .tscn (same format as generate_navmesh.py output).
##
## This replaces the manual editor bake step: the bake parses the instanced
## level's static colliders with the mesh's agent settings, exactly like the
## editor's NavigationRegion3D > Bake button.
##
## Usage:
##   python run_scratch.py tools/levels/bake_navmesh.gd -- --level=Levels/level_5.tscn --out=tools/levels/out/l5/navmesh_baked.txt
extends SceneTree


func _init() -> void:
	var level_path: String = "res://Levels/level_5.tscn"
	var out_path: String = "res://tools/levels/out/navmesh_baked.txt"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level_path = arg.trim_prefix("--level=").strip_edges()
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=").strip_edges()
	level_path = _resolve(level_path)
	out_path = _resolve(out_path)
	if level_path.is_empty() or out_path.is_empty() or not _ensure_dir(out_path.get_base_dir()):
		quit(1)
		return

	var packed: PackedScene = load(level_path) as PackedScene
	if packed == null:
		printerr("[bake_navmesh] ERROR: cannot load ", level_path)
		quit(1)
		return
	var level: Node3D = packed.instantiate() as Node3D
	root.add_child(level)
	# SceneTree scripts await the loop's own signals (get_tree() is Node-only).
	await physics_frame
	await physics_frame

	var region: NavigationRegion3D = level.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		printerr("[bake_navmesh] ERROR: NavigationRegion3D/mesh missing")
		quit(1)
		return
	var mesh: NavigationMesh = region.navigation_mesh
	NavigationMeshGenerator.bake(mesh, level)
	print("[bake_navmesh] baked: ", mesh.get_polygon_count(), " polygons, ",
		mesh.get_vertices().size(), " vertices")

	var out: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		printerr("[bake_navmesh] ERROR: cannot open ", out_path)
		quit(1)
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
	print("[bake_navmesh] wrote ", out_path)
	quit(0)


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
