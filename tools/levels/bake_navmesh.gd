## Bakes a level's NavigationRegion3D mesh at runtime (headless-safe) and
## exports the baked mesh as a snippet file, ready to splice into the level
## .tscn (same format as generate_navmesh.py output).
##
## Headless replacement for the editor's NavigationRegion3D > Bake step:
## parses the instanced level's source geometry with the mesh's agent
## settings and bakes it. Uses the two-step parse + bake_from API because
## the one-step bake() returns an empty mesh in headless (-s) runs
## (verified); the parse stage's has_data() keeps any future empty result
## a loud failure instead of a scaffold passed off as baked.
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
	# Bake into a FRESH mesh first so an empty/unchanged result is detectable
	# (baking over the region mesh in place would silently keep the scaffold
	# and report success). The fresh mesh duplicates the region mesh's full
	# settings: baking with defaults instead (e.g. a different
	# region_min_size) silently changes the result, such as keeping walkable
	# islands on top of furniture that the configured min region size removes.
	var pre: PackedVector3Array = mesh.get_vertices().duplicate()
	# Duplicate keeps the region mesh's full bake settings (verified: baking
	# with defaults instead silently changes the result). No clearing needed:
	# bake_from_source_geometry_data() replaces the mesh contents, like the
	# editor Bake button does (verified: baking over uncleared data yields
	# the same clean result, nothing appended).
	var fresh: NavigationMesh = mesh.duplicate() as NavigationMesh
	# Two-step bake: the one-step bake() returns an empty mesh in headless
	# (-s) runs (verified), while parse + bake_from works. The parse stage
	# makes the failure visible through has_data() instead of silent empties.
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationMeshGenerator.parse_source_geometry_data(fresh, data, level)
	if not data.has_data():
		printerr("[bake_navmesh] ERROR: parse found no geometry; ",
			"the editor Bake button is required for this level")
		quit(1)
		return
	NavigationMeshGenerator.bake_from_source_geometry_data(fresh, data)
	if fresh.get_vertices().is_empty():
		printerr("[bake_navmesh] ERROR: bake parsed no geometry (empty mesh); ",
			"the editor Bake button is required for this level")
		quit(1)
		return
	if _same_verts(pre, fresh.get_vertices()):
		printerr("[bake_navmesh] ERROR: bake returned the input unchanged; ",
			"mesh was NOT baked (scaffold passthrough refused)")
		quit(1)
		return
	mesh.clear_polygons()
	mesh.set_vertices(fresh.get_vertices())
	for i: int in range(fresh.get_polygon_count()):
		mesh.add_polygon(fresh.get_polygon(i))
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
