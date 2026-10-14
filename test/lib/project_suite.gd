## This project's base for every suite: the kit harness plus this game's own
## fixtures and helpers. Every suite extends it by path:
##     extends "res://test/lib/project_suite.gd"
## (the test folder is .gdignore'd, so class_name would not register).
##
## - load_arena(): the shared flat arena (test/fixtures/arena.tscn) with spawn
##   markers, so level redesigns never break mechanics tests,
## - arena_floor_top() and wait_for_navigation() for spawning and pathing on it,
## - disable_ai(): stop an AI mind so only the test drives the character.
extends "res://addons/godot_kit/harness/test_suite.gd"

## Scene loaded by load_arena(): flat floor, baked navmesh, light, spawn markers.
const ARENA_SCENE_PATH: String = "res://test/fixtures/arena.tscn"


## Loads the shared test arena (flat floor with a baked navmesh, a light, and
## PlayerSpawn/EnemySpawn markers; no enemies, no wave, no GI) under the suite
## and registers it for teardown. Use it for mechanics tests instead of real
## levels so level redesigns never break them. Regenerate it with
## test/fixtures/build_arena.gd, never by hand.
func load_arena() -> Node3D:
	return spawn(load(ARENA_SCENE_PATH) as PackedScene) as Node3D


## World height of the arena floor's top surface.
func arena_floor_top(arena: Node3D) -> float:
	var floor_shape: CollisionShape3D = arena.get_node("NavigationRegion3D/Floor/CollisionShape3D") as CollisionShape3D
	return floor_shape.global_position.y + (floor_shape.shape as BoxShape3D).size.y * 0.5


## Waits until the navigation map answers queries on the arena's navmesh.
## The region joins the map asynchronously after the arena enters the tree,
## and the map builds its polygons on a later sync; until then navmesh
## queries return zero vectors. Call this before anything that queries the
## navmesh (spawning on it, pathing).
func wait_for_navigation(arena: Node3D) -> bool:
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D") as NavigationRegion3D
	var nav_map: RID = arena.get_world_3d().navigation_map
	var probe: Vector3 = region.global_position + Vector3(0.0, 5.0, 0.0)
	var queryable: Callable = func() -> bool:
		if not NavigationServer3D.map_get_regions(nav_map).has(region.get_rid()):
			return false
		# Queried before the map's first sync, the server reports an error.
		if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
			return false
		return not NavigationServer3D.map_get_closest_point(nav_map, probe).is_zero_approx()
	return await wait_until(queryable, "the arena navmesh should be queryable on the navigation map", 60)


## Stops a character's AI mind so only the test drives it.
func disable_ai(character: Character) -> void:
	if character != null and character.ai_state_machine != null:
		character.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
