## Boss arena 1 and boss routing:
## - a WaveObjective with boss_resources spawns exactly those bosses, even at
##   a difficulty where the regular pool would never offer them,
## - Boss Arena 1 pins exactly one boss on its wave, has baked GI, and a
##   navigation path from the player spawn to the exit,
## - the arena is registered in GlobalVars.dungeons as a boss arena: reaching
##   its dungeon level routes the run there with no planned enemies, and
##   regular dungeon selection never picks it.
## Difficulties are test-owned; the arena's layout is the designers' choice.
extends "res://test/lib/test_suite.gd"

const ARENA_PATH: String = "res://Levels/boss_arena_1.tscn"
const ARENA_SCENE: PackedScene = preload("res://Levels/boss_arena_1.tscn")
const BOSS_SCENE: PackedScene = preload("res://Enemy/akira_boss.tscn")


func after_each() -> void:
	ProgressionState.reset_run()


func test_a_boss_wave_spawns_its_boss_even_where_the_regular_pool_would_not() -> void:
	var boss: EnemyResource = GlobalVars.get_enemy_resource(BOSS_SCENE)
	if not check(boss != null and boss.minimum_spawn_difficulty > 0, "setup: the boss should be registered and gated from low-difficulty pools"):
		return
	var wave: WaveObjective = autofree(WaveObjective.new()) as WaveObjective
	var low: int = boss.minimum_spawn_difficulty - 1
	var pool: Dictionary = ProgressionState.build_difficulty_pool(GlobalVars.enemies, low)
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
	var arena: DungeonResource = null
	var regular: DungeonResource = null
	for dungeon: DungeonResource in GlobalVars.dungeons:
		if dungeon.scene != null and dungeon.scene.resource_path == ARENA_PATH:
			arena = dungeon
		elif regular == null and not dungeon.is_boss_arena():
			regular = dungeon
	if not check(arena != null and arena.is_boss_arena(), "Boss Arena 1 should be registered in GlobalVars.dungeons as a boss arena"):
		return
	if not check(regular != null, "setup: a regular dungeon should be registered"):
		return
	# A plan left over from an earlier encounter must not leak into the arena.
	ProgressionState.current_planned_enemies = ProgressionState.generate_wave_plan()
	ProgressionState.dungeon_level = arena.boss_at_level
	check(ProgressionState.prepare_next_encounter() == arena, "reaching the arena's dungeon level should route the run to it")
	check(ProgressionState.current_planned_enemies.is_empty(), "the arena brings its own bosses, so no enemies should be planned")
	# Selection prefers dungeons not visited recently; marking the regular one
	# recent makes a selection that forgot to exclude arenas pick the arena
	# every time instead of by chance.
	ProgressionState.recently_visited_dungeons.append(regular)
	var offered: Array[DungeonResource] = [arena, regular]
	check(ProgressionState.select_dungeon_for_encounter(0, offered) == regular, "regular dungeon selection must never pick a boss arena")
