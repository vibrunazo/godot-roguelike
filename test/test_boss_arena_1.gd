## Boss arena 1 and boss routing:
## - a WaveObjective with boss_resources spawns exactly those bosses, even at
##   a difficulty where the regular pool would never offer them,
## - Boss Arena 1 pins exactly one boss on its wave, has baked GI, and a
##   navigation path from the player spawn to the exit,
## - SceneTransition routes some dungeon level to the arena, every boss route
##   points at an existing scene, and arenas never enter the regular rotation.
## Difficulties are test-owned; the arena's layout is the designers' choice.
extends "res://test/lib/test_suite.gd"

const ARENA_PATH: String = "res://Levels/boss_arena_1.tscn"
const ARENA_SCENE: PackedScene = preload("res://Levels/boss_arena_1.tscn")
const BOSS_SCENE: PackedScene = preload("res://Enemy/akira_boss.tscn")


func test_a_boss_wave_spawns_its_boss_even_where_the_regular_pool_would_not() -> void:
	var boss: EnemyResource = GlobalVars.get_enemy_resource(BOSS_SCENE)
	if not check(boss != null and boss.minimum_spawn_difficulty > 0, "setup: the boss should be registered and gated from low-difficulty pools"):
		return
	var wave: WaveObjective = autofree(WaveObjective.new()) as WaveObjective
	var low: int = boss.minimum_spawn_difficulty - 1
	var pool: Dictionary = wave.build_difficulty_pool(GlobalVars.enemies, low)
	for tier: Variant in pool.values():
		check(not (tier as Array).has(boss), "setup: the regular pool at difficulty %d should not offer the boss" % low)
	var bosses: Array[EnemyResource] = [boss]
	wave.boss_resources = bosses
	var spawned: Array[Character] = wave.generate_wave_enemies()
	for enemy: Character in spawned:
		autofree(enemy)
	if check_eq(spawned.size(), 1, "a boss wave should spawn exactly its boss"):
		check_eq(spawned[0].scene_file_path, BOSS_SCENE.resource_path, "the spawned enemy should be the boss")


func test_the_arena_pins_one_boss_and_is_completable() -> void:
	var arena: Node3D = spawn(ARENA_SCENE) as Node3D
	var wave: WaveObjective = arena.find_child("WaveObjective", true, false) as WaveObjective
	check_eq(wave.boss_resources.size(), 1, "the arena should pin exactly one boss")
	wave.stop_spawning()
	var gi: VoxelGI = arena.find_child("VoxelGI", true, false) as VoxelGI
	check(gi != null and gi.data != null, "the arena should have baked GI")
	var player: Node3D = arena.find_child("Player", true, false) as Node3D
	var exit_point: Node3D = arena.find_child("ExitPoint", true, false) as Node3D
	var nav_map: RID = arena.get_world_3d().navigation_map
	var from: Vector3 = Vector3(player.global_position.x, 1.0, player.global_position.z)
	if not await wait_until(func() -> bool: return NavigationServer3D.map_get_iteration_id(nav_map) != 0 and not NavigationServer3D.map_get_closest_point(nav_map, from).is_zero_approx(), "the arena navmesh should register", 120):
		return
	var to: Vector3 = Vector3(exit_point.global_position.x, 1.0, exit_point.global_position.z)
	check(NavigationServer3D.map_get_path(nav_map, from, to, true, 1).size() >= 2, "there should be a navigation path from the player spawn to the exit")


func test_the_arena_is_routed_to_and_kept_out_of_the_rotation() -> void:
	check(SceneTransition.boss_arenas.values().has(ARENA_PATH), "some dungeon level should route to Boss Arena 1")
	for level: Variant in SceneTransition.boss_arenas:
		var path: String = str(SceneTransition.boss_arenas[level])
		check(ResourceLoader.exists(path), "the boss route for dungeon level %s should point at an existing scene (%s)" % [level, path])
		check(not SceneTransition.levels.has(path), "boss arena %s must not be in the regular rotation" % path)
