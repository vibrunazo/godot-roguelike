## Generates test/fixtures/arena.tscn: the shared minimal scene for mechanics
## tests (see TestSuite.load_arena()). Regenerate instead of hand-editing:
##     python run_scratch.py test/fixtures/build_arena.gd
##
## Contents: a flat 40 x 40 m static floor (top at y = 0) on the World physics
## layer, a NavigationRegion3D whose navmesh is baked here by the engine with
## the same parse settings as the levels (static colliders), a directional
## light and environment so capture.py recordings are readable, and
## PlayerSpawn / EnemySpawn markers. Deliberately absent: WaveObjective,
## enemies, exit, VoxelGI, pits, player (tests spawn exactly what they need).
extends SceneTree

const OUTPUT_PATH: String = "res://test/fixtures/arena.tscn"
const FLOOR_SIZE: float = 40.0
const FLOOR_THICKNESS: float = 1.0
## Matches the levels' NavigationMesh settings (level_template.tscn).
const NAV_REGION_MIN_SIZE: float = 6.0


func _initialize() -> void:
	# The navmesh bake parses the live tree, which only exists once the main
	# loop has started iterating.
	await process_frame
	var arena: Node3D = Node3D.new()
	arena.name = "Arena"
	root.add_child(arena)

	var nav_region: NavigationRegion3D = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh: NavigationMesh = NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.region_min_size = NAV_REGION_MIN_SIZE
	nav_region.navigation_mesh = nav_mesh
	_add(arena, nav_region, arena)

	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	_add(nav_region, floor_body, arena)

	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(FLOOR_SIZE, FLOOR_THICKNESS, FLOOR_SIZE)
	shape.shape = box
	_add(floor_body, shape, arena)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "FloorMesh"
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box.size
	mesh_instance.mesh = mesh
	_add(floor_body, mesh_instance, arena)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	light.shadow_enabled = true
	_add(arena, light, arena)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.1, 0.1, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	environment_node.environment = environment
	_add(arena, environment_node, arena)

	var player_spawn: Marker3D = Marker3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.position = Vector3(0.0, 1.0, 4.0)
	_add(arena, player_spawn, arena)

	var enemy_spawn: Marker3D = Marker3D.new()
	enemy_spawn.name = "EnemySpawn"
	enemy_spawn.position = Vector3(0.0, 1.0, -4.0)
	_add(arena, enemy_spawn, arena)

	nav_region.bake_navigation_mesh(false)
	if nav_mesh.get_polygon_count() == 0:
		printerr("build_arena: navmesh bake produced no polygons.")
		quit(1)
		return

	var packed: PackedScene = PackedScene.new()
	var pack_err: Error = packed.pack(arena)
	if pack_err != OK:
		printerr("build_arena: pack failed: ", error_string(pack_err))
		quit(1)
		return
	var save_err: Error = ResourceSaver.save(packed, OUTPUT_PATH)
	if save_err != OK:
		printerr("build_arena: save failed: ", error_string(save_err))
		quit(1)
		return
	print("build_arena: saved %s (%d navmesh polygons)" % [OUTPUT_PATH, nav_mesh.get_polygon_count()])
	arena.free()
	quit(0)


func _add(parent: Node, child: Node, scene_root: Node) -> void:
	parent.add_child(child)
	child.owner = scene_root
