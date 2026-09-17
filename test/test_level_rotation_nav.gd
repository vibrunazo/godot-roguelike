## Rotation integrity test: every level in `SceneTransition.levels` must load,
## expose its core nodes (Player, ExitPoint, WaveObjective, VoxelGI with baked
## data), and provide a valid navigation path from player spawn to the exit
## with a VoxelGI volume that covers the floor footprint. Every interior floor
## hole (pit) must also be ringed with shaft walls below the rim so pits read
## as deep shafts instead of flat black stickers floating in the air. The
## template's giant abyss plane must be present and visible so every hole and
## cliff edge bottoms out into darkness (per-level pit quads are obsolete).
## Freestanding tall cover must also keep 3 m of clear floor (rect-to-rect)
## to every interior pit edge: tighter slots bake into sub-meter navmesh
## slivers that wedge enemies (Level 10's old pillar ring).
## The navmesh must be a real bake (erosion detail), not the generator
## scaffold, with no walkable islands above the floor (wrong min-region-size
## symptom).
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
		if NavigationServer3D.map_get_iteration_id(get_world_3d().get_navigation_map()) == 0:
			continue
		var probe: Node3D = level.find_child("Player", true, false) as Node3D
		if probe != null:
			var snap: Vector3 = NavigationServer3D.map_get_closest_point(
				get_world_3d().get_navigation_map(),
				probe.global_position)
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
		if not _verify_navmesh_is_baked(level, level_path):
			ok = false
		if not _verify_no_stray_islands(level, level_path):
			ok = false
		if not _verify_low_walls_ring_edges(level, level_path):
			ok = false
		if not _verify_pit_lining(level, level_path):
			ok = false
		if not _verify_cover_clearances(level, level_path):
			ok = false
		if not _verify_abyss_plane(level, level_path):
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
			var box: AABB = _floor_cell_box(gm, cell)
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


## Rejects unbaked scaffold meshes passed off as bakes. A real recast bake
## erodes the walkable area around walls/pits by the agent radius, which
## always leaves fractional-coordinate verts; the generator scaffold is an
## all-integer x/z tile-corner lattice and fails this check.
func _verify_navmesh_is_baked(level: Node3D, level_path: String) -> bool:
	var region: NavigationRegion3D = level.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		printerr("TEST FAILED: NavigationRegion3D/mesh missing in ", level_path)
		return false
	for v: Vector3 in region.navigation_mesh.get_vertices():
		if absf(v.x - roundf(v.x)) > 0.0001 or absf(v.z - roundf(v.z)) > 0.0001:
			print("navmesh shows bake erosion in ", level_path)
			return true
	printerr("TEST FAILED: navmesh is an unbaked integer lattice (scaffold, not a bake) in ", level_path)
	return false


## Low-tier (y=-1) walls top out flush with the floor, so they only read as
## architecture when they ring a hole or void edge. A y=-1 cell whose
## footprint (plus a 2 m margin) is fully covered by solid floor tiles is a
## buried freestanding stub — past mistake: whole colonnades emitted at y=-1
## that rendered as floor inlay. Cells stacked under a y=0 wall are exempt
## (foundations).
func _verify_low_walls_ring_edges(level: Node3D, level_path: String) -> bool:
	var floor: Dictionary = {}
	var tall: Dictionary = {}
	var low: Array[Vector2i] = []
	for gm_node: Node in level.find_children("*", "GridMap", true, false):
		var gm: GridMap = gm_node as GridMap
		if gm.name == "Floormap":
			for cell: Vector3i in gm.get_used_cells():
				floor[Vector2i(cell.x, cell.z)] = true
		elif gm.name == "Wallmap":
			for cell: Vector3i in gm.get_used_cells():
				if cell.y == 0:
					tall[Vector2i(cell.x, cell.z)] = true
				elif cell.y == -1:
					low.append(Vector2i(cell.x, cell.z))
	var ok: bool = true
	for w: Vector2i in low:
		if tall.has(w):
			continue
		var buried: bool = true
		for sx: int in range(w.x * 2 - 2, w.x * 2 + 5):
			for sz: int in range(w.y * 2 - 2, w.y * 2 + 5):
				if not _point_on_floor(sx, sz, floor):
					buried = false
					break
			if not buried:
				break
		if buried:
			printerr("TEST FAILED: buried y=-1 wall (fully floor-covered, rings no edge) at ", w, " in ", level_path)
			ok = false
	if ok:
		print("low-tier walls ring edges in ", level_path)
	return ok


## True when the world point (sx, sz) lies on a solid floor tile.
func _point_on_floor(sx: int, sz: int, floor: Dictionary) -> bool:
	for key: Vector2i in floor:
		if key.x * 4 <= sx and sx <= key.x * 4 + 4 and key.y * 4 <= sz and sz <= key.y * 4 + 4:
			return true
	return false


## Rejects furniture/unsupported nav islands relative to the floor beneath
## each vertex, not a global height ceiling. Preserve the original 1m margin
## above flat floor tops. Sloped stair cells need a collision surface probe:
## their AABB top alone would incorrectly bless islands over the low end.
func _verify_no_stray_islands(level: Node3D, level_path: String) -> bool:
	var region: NavigationRegion3D = level.find_child("NavigationRegion3D", true, false) as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		printerr("TEST FAILED: NavigationRegion3D/mesh missing in ", level_path)
		return false
	var floor: GridMap = level.find_child("Floormap", true, false) as GridMap
	if floor == null or floor.mesh_library == null:
		printerr("TEST FAILED: floor geometry missing in ", level_path)
		return false
	var boxes: Array[AABB] = []
	var stairs: Array[bool] = []
	for cell: Vector3i in floor.get_used_cells():
		boxes.append(_floor_cell_box(floor, cell))
		stairs.append(floor.mesh_library.get_item_name(floor.get_cell_item(cell)) == "Primitive_Stairs")
	for v: Vector3 in region.navigation_mesh.get_vertices():
		var world_v: Vector3 = region.to_global(v)
		var supported: bool = false
		for index: int in range(boxes.size()):
			var box: AABB = boxes[index]
			# Recast rasterization can place rim vertices one voxel outside a
			# mesh footprint (legacy level 4); never relax vertical rejection.
			var rim: float = region.navigation_mesh.cell_size + 0.01
			if world_v.x < box.position.x - rim or world_v.x > box.end.x + rim or world_v.z < box.position.z - rim or world_v.z > box.end.z + rim:
				continue
			var top: float = box.end.y
			if stairs[index]:
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(world_v.x, box.end.y + 0.1, world_v.z), Vector3(world_v.x, box.position.y - 0.1, world_v.z), floor.collision_layer)
				var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty() or hit.get("collider") != floor:
					continue
				top = (hit["position"] as Vector3).y
			if world_v.y >= top - 0.1 and world_v.y <= top + 1.0:
				supported = true
				break
		if not supported:
			printerr("TEST FAILED: nav vertex unsupported/above local walkable height ", world_v, " (stray island?) in ", level_path)
			return false
	print("no stray nav islands in ", level_path)
	return true


## Real world-space bounds include cell centering, orientation, cell scale,
## library item transform and the GridMap/parent transform (not cell pitch).
func _floor_cell_box(grid: GridMap, cell: Vector3i) -> AABB:
	var item: int = grid.get_cell_item(cell)
	var mesh: Mesh = grid.mesh_library.get_item_mesh(item)
	var cell_transform: Transform3D = Transform3D(grid.get_cell_item_basis(cell).scaled(Vector3.ONE * grid.cell_scale), grid.map_to_local(cell))
	return (grid.global_transform * cell_transform * grid.mesh_library.get_item_mesh_transform(item)) * mesh.get_aabb()


## Checks every interior floor hole is ringed with shaft walls. Each wall mesh
## spans a full 4m tile side from a single 2m cell, so every hole-tile side
## facing a floor tile needs at least one of its two straddling y=-1 wall
## cells present (orientations are cosmetic here, presence is the contract).
func _verify_pit_lining(level: Node3D, level_path: String) -> bool:
	var floor_gm: GridMap = null
	var wall_gm: GridMap = null
	for gm_node: Node in level.find_children("*", "GridMap", true, false):
		var gm: GridMap = gm_node as GridMap
		if gm.name == "Floormap":
			floor_gm = gm
		elif gm.name == "Wallmap":
			wall_gm = gm
	if floor_gm == null or wall_gm == null:
		printerr("TEST FAILED: Floormap/Wallmap missing in ", level_path)
		return false
	# Flood-fill each flat floor elevation independently. Flattening upper
	# terraces and stair bridges falsely closes the void beneath a bridge.
	var layers: Dictionary[int, Dictionary] = {}
	for cell: Vector3i in floor_gm.get_used_cells():
		if floor_gm.mesh_library.get_item_name(floor_gm.get_cell_item(cell)) == "Primitive_Stairs":
			continue
		if not layers.has(cell.y):
			layers[cell.y] = {}
		layers[cell.y][Vector2i(cell.x, cell.z)] = true
	var ok: bool = true
	for layer: int in layers:
		var floor: Dictionary = layers[layer]
		var lined_below: Dictionary = {}
		var floor_height: float = _floor_cell_box(floor_gm, Vector3i((floor.keys()[0] as Vector2i).x, layer, (floor.keys()[0] as Vector2i).y)).end.y
		for wall_node: Node in level.find_children("Wallmap*", "GridMap", true, false):
			var walls: GridMap = wall_node as GridMap
			for cell: Vector3i in walls.get_used_cells():
				# Shaft wall top is flush with this floor; supports translated
				# WallmapUpper too, without mistaking tall walls for lining.
				if absf(_floor_cell_box(walls, cell).end.y - floor_height) < 0.2:
					lined_below[Vector2i(cell.x, cell.z)] = true
		if not _verify_pit_layer(floor, lined_below, level_path + " layer " + str(layer)):
			ok = false
	return ok


## Original shaft-wall side gate, applied independently at each elevation.
func _verify_pit_layer(floor: Dictionary, lined_below: Dictionary, level_path: String) -> bool:
	var bad_sides: int = 0
	var checked_sides: int = 0
	for h: Vector2i in _interior_holes(floor):
		var sides: Array = [
			[Vector2i(h.x, h.y - 1), Vector2i(2 * h.x, 2 * h.y), Vector2i(2 * h.x + 1, 2 * h.y)],
			[Vector2i(h.x, h.y + 1), Vector2i(2 * h.x, 2 * h.y + 2), Vector2i(2 * h.x + 1, 2 * h.y + 2)],
			[Vector2i(h.x - 1, h.y), Vector2i(2 * h.x, 2 * h.y), Vector2i(2 * h.x, 2 * h.y + 1)],
			[Vector2i(h.x + 1, h.y), Vector2i(2 * h.x + 2, 2 * h.y), Vector2i(2 * h.x + 2, 2 * h.y + 1)],
		]
		for side: Array in sides:
			if not floor.has(side[0]):
				continue
			checked_sides += 1
			if not lined_below.has(side[1]) and not lined_below.has(side[2]):
				bad_sides += 1
				printerr("TEST FAILED: unlined pit side: hole tile ", h, " toward ", side[0], " in ", level_path)
	if bad_sides > 0:
		return false
	print("pit lining OK (", checked_sides, " hole-tile sides) in ", level_path)
	return true


## Freestanding tall (y=0) cover must keep COVER_CLEARANCE of clear floor to
## every interior pit edge, measured rect-to-rect between the wall mesh and
## the pit tile. Tighter slots bake into sub-meter navmesh slivers that wedge
## enemies (Level 10's old pillar ring left 1.5 m corner gaps). Cells whose
## meshes share an edge segment are one bonded mass (tiling runs, colonnades,
## blocks) and are exempt; only lone cells are measured, using mesh footprints
## (4 m x 1 m runs centered on the cell grid point, matching
## generate_walls.py). Pure corner proximity with 4 m+ diagonal clearance
## (Level 8's arena pillar) passes.
const COVER_CLEARANCE: float = 3.0


## World-space mesh footprint for a y=0 wall cell (see extents above).
func _cover_mesh_rect(cell: Vector2i, orient: int) -> Array[float]:
	var cx: float = float(cell.x) * 2.0
	var cz: float = float(cell.y) * 2.0
	if orient == 0 or orient == 10:
		return [cx - 2.0, cz - 0.5, cx + 2.0, cz + 0.5]
	if orient == 16 or orient == 22:
		return [cx - 0.5, cz - 2.0, cx + 0.5, cz + 2.0]
	return [cx, cz, cx + 2.0, cz + 2.0]


func _rects_share_edge(a: Array[float], b: Array[float]) -> bool:
	var ox: float = minf(a[2], b[2]) - maxf(a[0], b[0])
	var oz: float = minf(a[3], b[3]) - maxf(a[1], b[1])
	return (ox > 0.01 and oz > -0.01) or (oz > 0.01 and ox > -0.01)


func _verify_cover_clearances(level: Node3D, level_path: String) -> bool:
	var floor: Dictionary = {}
	var tall: Array[Vector2i] = []
	var orients: Dictionary = {}
	var floor_gm: GridMap = null
	var wall_gm: GridMap = null
	for gm_node: Node in level.find_children("*", "GridMap", true, false):
		var gm: GridMap = gm_node as GridMap
		if gm == null:
			continue
		if gm.name == "Floormap":
			floor_gm = gm
			for cell: Vector3i in gm.get_used_cells():
				floor[Vector2i(cell.x, cell.z)] = true
		elif gm.name == "Wallmap":
			wall_gm = gm
	if floor_gm == null or wall_gm == null:
		printerr("TEST FAILED: Floormap/Wallmap missing in ", level_path)
		return false
	for cell: Vector3i in wall_gm.get_used_cells():
		if cell.y == 0:
			var w := Vector2i(cell.x, cell.z)
			tall.append(w)
			orients[w] = wall_gm.get_cell_item_orientation(cell)
	var bonded_root: Dictionary = {}
	for w: Vector2i in tall:
		bonded_root[w] = w
	for i: int in range(tall.size()):
		var ra: Array[float] = _cover_mesh_rect(tall[i], int(orients[tall[i]]))
		for j: int in range(i + 1, tall.size()):
			var rb: Array[float] = _cover_mesh_rect(tall[j], int(orients[tall[j]]))
			if _rects_share_edge(ra, rb):
				bonded_root[tall[j]] = tall[i]
	var lone: Array[Vector2i] = []
	for w: Vector2i in tall:
		var members: int = 0
		for v: Vector2i in tall:
			if _bonded_find(bonded_root, v) == _bonded_find(bonded_root, w):
				members += 1
		if members == 1:
			lone.append(w)
	var holes: Array[Vector2i] = _interior_holes(floor)
	var ok: bool = true
	for w: Vector2i in lone:
		var r: Array[float] = _cover_mesh_rect(w, int(orients[w]))
		for h: Vector2i in holes:
			var hx0: float = float(h.x) * 4.0
			var hx1: float = hx0 + 4.0
			var hz0: float = float(h.y) * 4.0
			var hz1: float = hz0 + 4.0
			var dx: float = 0.0
			if hx1 < r[0]:
				dx = r[0] - hx1
			elif r[2] < hx0:
				dx = hx0 - r[2]
			var dz: float = 0.0
			if hz1 < r[1]:
				dz = r[1] - hz1
			elif r[3] < hz0:
				dz = hz0 - r[3]
			if sqrt(dx * dx + dz * dz) < COVER_CLEARANCE:
				printerr("TEST FAILED: freestanding cover at ", w, " pinches pit tile ", h, " in ", level_path)
				ok = false
	if ok:
		print("cover clearances OK (", lone.size(), " lone walls) in ", level_path)
	return ok


func _bonded_find(roots: Dictionary, w: Vector2i) -> Vector2i:
	var r: Vector2i = roots[w] as Vector2i
	while r != (roots[r] as Vector2i):
		r = roots[r] as Vector2i
	return r


## The template's giant abyss plane must be present, visible and large: it
## bottoms every hole and cliff edge, replacing per-level pit quads. A small
## quad (the old 8m size) or a hidden Pit means some hole shows grey void.
func _verify_abyss_plane(level: Node3D, level_path: String) -> bool:
	var pit: MeshInstance3D = level.find_child("Pit", true, false) as MeshInstance3D
	if pit == null:
		printerr("TEST FAILED: abyss Pit quad missing in ", level_path)
		return false
	if not pit.visible:
		printerr("TEST FAILED: abyss Pit quad hidden in ", level_path)
		return false
	var mesh: PlaneMesh = pit.mesh as PlaneMesh
	if mesh == null or minf(mesh.size.x, mesh.size.y) < 500.0:
		printerr("TEST FAILED: abyss Pit quad too small in ", level_path)
		return false
	print("abyss plane OK in ", level_path)
	return true


## Floor-grid gaps NOT connected to the outer void (i.e. pits).
func _interior_holes(floor: Dictionary) -> Array[Vector2i]:
	var keys: Array = floor.keys()
	var x0: int = keys[0].x - 1
	var x1: int = keys[0].x + 1
	var z0: int = keys[0].y - 1
	var z1: int = keys[0].y + 1
	for k: Vector2i in keys:
		x0 = mini(x0, k.x - 1)
		x1 = maxi(x1, k.x + 1)
		z0 = mini(z0, k.y - 1)
		z1 = maxi(z1, k.y + 1)
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for x: int in [x0, x1]:
		for z: int in range(z0, z1 + 1):
			var edge := Vector2i(x, z)
			if not floor.has(edge) and not seen.has(edge):
				seen[edge] = true
				queue.append(edge)
	for z: int in [z0, z1]:
		for x: int in range(x0, x1 + 1):
			var edge := Vector2i(x, z)
			if not floor.has(edge) and not seen.has(edge):
				seen[edge] = true
				queue.append(edge)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for n: Vector2i in [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]:
			if n.x < x0 or n.x > x1 or n.y < z0 or n.y > z1:
				continue
			if floor.has(n) or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	var holes: Array[Vector2i] = []
	for x: int in range(x0 + 1, x1):
		for z: int in range(z0 + 1, z1):
			var p := Vector2i(x, z)
			if not floor.has(p) and not seen.has(p):
				holes.append(p)
	return holes


## Allow the existing half-tile wall inset horizontally, but not wrong floors.
func _endpoint_close(authored: Vector3, snapped: Vector3) -> bool:
	return absf(authored.y - snapped.y) <= 1.0 and Vector2(authored.x - snapped.x, authored.z - snapped.z).length() <= 2.0


## Checks a navigation path exists between two points on the level.
func _verify_path(from_pos: Vector3, to_pos: Vector3, level_path: String) -> bool:
	var nav_map: RID = get_world_3d().get_navigation_map()
	var from_point: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, from_pos)
	var to_point: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, to_pos)
	# A nonempty path may be partial, or snap to a different storey. Keep
	# endpoints close in 3D, including Y (the old y=1 projection hid this).
	if not _endpoint_close(from_pos, from_point) or not _endpoint_close(to_pos, to_point):
		printerr("TEST FAILED: nav endpoints miss authored spawn/exit heights in ", level_path, ": ", from_pos, " -> ", from_point, "; ", to_pos, " -> ", to_point)
		return false
	var path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, from_point, to_point, true, 1)
	if level_path.ends_with("level_13.tscn"):
		print("Level13 endpoint diagnostic: spawn_world=", from_pos, " target_world=", to_pos, " snapped_spawn=", from_point, " snapped_target=", to_point, " returned_path=", path)
	if path.size() < 2:
		printerr("TEST FAILED: no nav path from ", from_point, " to ", to_point, " in ", level_path)
		return false
	if path[0].distance_to(from_point) > 0.1 or path[path.size() - 1].distance_to(to_point) > 0.1:
		printerr("TEST FAILED: partial nav path does not reach spawn/exit in ", level_path)
		return false
	print("nav path OK (", path.size(), " points) in ", level_path)
	return true
