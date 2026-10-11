## Boss levels, boss pools and Boss Arena 1:
## - every registered boss (EnemyResource.boss_at_level > 0) is gated from
##   regular waves below its minimum spawn difficulty,
## - a planned boss spawns even where the regular pool would never offer it,
## - a level's boss pool holds exactly the bosses whose boss_at_level is that
##   level; reaching a boss level routes the run to a boss arena with exactly
##   one boss of that pool planned, and when several bosses share the level,
##   runs fight each of them,
## - Boss Arena 1 is a registered boss arena with baked GI and a navigation
##   path from the player spawn to the exit, and regular dungeon selection
##   never picks a boss arena.
## Levels and difficulties used by the mechanics are test-owned or read from
## the registered data; the arena's layout is the designers' choice.
extends "res://test/lib/test_suite.gd"

const ARENA_PATH: String = "res://Levels/boss_arena_1.tscn"
const ARENA_SCENE: PackedScene = preload("res://Levels/boss_arena_1.tscn")
const AKIRA_SCENE: PackedScene = preload("res://Enemy/akira_boss.tscn")
const SCOPE_CREEP_SCENE: PackedScene = preload("res://Enemy/scope_creep_boss.tscn")
## Test-owned boss levels and gate offset.
const TEST_BOSS_LEVEL: int = 7
const TEST_OTHER_BOSS_LEVEL: int = 8
const TEST_GATE_OFFSET: int = 5
## Runs prepared to see every boss of a shared pool come up (seeded).
const POOL_TRIES: int = 24
const POOL_SEED: int = 20261010

## GlobalVars.enemies as it was before a test swapped in its own registry.
var _registered_enemies: Array[EnemyResource] = []


func before_each() -> void:
	_registered_enemies = GlobalVars.enemies.duplicate()


func after_each() -> void:
	GlobalVars.enemies = _registered_enemies
	ProgressionState.reset_run()


func test_every_registered_boss_is_gated_from_regular_waves_below_its_minimum_difficulty() -> void:
	var bosses: Array[EnemyResource] = _registered_bosses()
	if not check(not bosses.is_empty(), "setup: GlobalVars.enemies should register at least one boss"):
		return
	for registered: EnemyResource in bosses:
		# Gate a copy with a test-owned minimum difficulty, so the check covers
		# the gating, not how the boss happens to be tuned.
		var gated: EnemyResource = registered.duplicate() as EnemyResource
		gated.minimum_spawn_difficulty = gated.difficulty_level + TEST_GATE_OFFSET
		var resources: Array[EnemyResource] = [gated]
		var tier: int = gated.difficulty_level
		var label: String = registered.scene.resource_path.get_file()
		check((ProgressionState.build_difficulty_pool(resources).get(tier, []) as Array).has(gated), "ungated, the pool should offer %s at its difficulty" % label)
		check(not (ProgressionState.build_difficulty_pool(resources, gated.minimum_spawn_difficulty - 1).get(tier, []) as Array).has(gated), "below its minimum difficulty %s must not appear in regular waves" % label)
		check((ProgressionState.build_difficulty_pool(resources, gated.minimum_spawn_difficulty).get(tier, []) as Array).has(gated), "at its minimum difficulty %s should join regular waves" % label)


func test_a_planned_boss_spawns_even_where_the_regular_pool_would_not() -> void:
	var boss: EnemyResource = GlobalVars.get_enemy_resource(AKIRA_SCENE)
	if not check(boss != null and boss.minimum_spawn_difficulty > 0, "setup: the boss should be registered and gated from low-difficulty pools"):
		return
	var low: int = boss.minimum_spawn_difficulty - 1
	var pool: Dictionary = ProgressionState.build_difficulty_pool(GlobalVars.enemies, low)
	for tier: Variant in pool.values():
		check(not (tier as Array).has(boss), "setup: the regular pool at difficulty %d should not offer the boss" % low)
	var planned: Array[EnemyResource] = [boss]
	ProgressionState.current_planned_enemies = planned
	var wave: WaveObjective = autofree(WaveObjective.new()) as WaveObjective
	var spawned: Array[Character] = wave.generate_wave_enemies()
	for enemy: Character in spawned:
		autofree(enemy)
	if check_eq(spawned.size(), 1, "a boss wave should spawn exactly its boss"):
		check_eq(spawned[0].scene_file_path, AKIRA_SCENE.resource_path, "the spawned enemy should be the boss")


func test_a_boss_pool_holds_exactly_the_bosses_of_its_level() -> void:
	var first: EnemyResource = _test_boss(AKIRA_SCENE, TEST_BOSS_LEVEL)
	var second: EnemyResource = _test_boss(SCOPE_CREEP_SCENE, TEST_BOSS_LEVEL)
	var other_level: EnemyResource = _test_boss(SCOPE_CREEP_SCENE, TEST_OTHER_BOSS_LEVEL)
	var regular: EnemyResource = _test_boss(AKIRA_SCENE, 0)
	var resources: Array[EnemyResource] = [first, regular, second, other_level]
	var pool: Array[EnemyResource] = ProgressionState.boss_pool(TEST_BOSS_LEVEL, resources)
	check(pool.size() == 2 and pool.has(first) and pool.has(second), "a level's pool should hold every boss of that level and nothing else")
	var other_pool: Array[EnemyResource] = ProgressionState.boss_pool(TEST_OTHER_BOSS_LEVEL, resources)
	check(other_pool.size() == 1 and other_pool[0] == other_level, "each level should have its own pool")
	check(ProgressionState.boss_pool(TEST_OTHER_BOSS_LEVEL + 1, resources).is_empty(), "a level no boss names should have no pool (a regular level)")


func test_each_registered_boss_level_routes_to_a_boss_arena_with_one_boss_of_its_pool() -> void:
	var levels: Array[int] = []
	for boss: EnemyResource in _registered_bosses():
		if not levels.has(boss.boss_at_level):
			levels.append(boss.boss_at_level)
	if not check(not levels.is_empty(), "setup: GlobalVars.enemies should register at least one boss"):
		return
	for level: int in levels:
		# A plan left over from an earlier encounter must not leak into the arena.
		ProgressionState.current_planned_enemies = ProgressionState.generate_wave_plan()
		ProgressionState.dungeon_level = level
		var dungeon: DungeonResource = ProgressionState.prepare_next_encounter()
		if not check(dungeon != null and dungeon.boss_arena, "reaching boss level %d should route the run to a boss arena" % level):
			continue
		var planned: Array[EnemyResource] = ProgressionState.current_planned_enemies
		if check_eq(planned.size(), 1, "boss level %d should plan exactly one boss" % level):
			check(ProgressionState.boss_pool(level).has(planned[0]), "the planned boss should come from boss level %d's pool" % level)


func test_bosses_sharing_a_level_each_come_up_as_its_boss() -> void:
	var first: EnemyResource = _test_boss(AKIRA_SCENE, TEST_BOSS_LEVEL)
	var second: EnemyResource = _test_boss(SCOPE_CREEP_SCENE, TEST_BOSS_LEVEL)
	var registry: Array[EnemyResource] = _registered_enemies.duplicate()
	registry.append(first)
	registry.append(second)
	GlobalVars.enemies = registry
	seed(POOL_SEED)
	var fought: Array[EnemyResource] = []
	for attempt: int in POOL_TRIES:
		ProgressionState.dungeon_level = TEST_BOSS_LEVEL
		ProgressionState.prepare_next_encounter()
		var planned: Array[EnemyResource] = ProgressionState.current_planned_enemies
		if not check_eq(planned.size(), 1, "a shared boss level should plan exactly one boss"):
			return
		check(planned[0] == first or planned[0] == second, "the planned boss should be one of the level's bosses")
		if not fought.has(planned[0]):
			fought.append(planned[0])
	check_eq(fought.size(), 2, "over %d runs, every boss sharing the level should come up" % POOL_TRIES)


func test_the_arena_is_a_completable_registered_boss_arena() -> void:
	var registered: DungeonResource = null
	for dungeon: DungeonResource in GlobalVars.dungeons:
		if dungeon != null and dungeon.scene != null and dungeon.scene.resource_path == ARENA_PATH:
			registered = dungeon
	check(registered != null and registered.boss_arena, "Boss Arena 1 should be registered in GlobalVars.dungeons as a boss arena")
	var arena: Node3D = spawn(ARENA_SCENE) as Node3D
	var wave: WaveObjective = arena.find_child("WaveObjective", true, false) as WaveObjective
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


func test_regular_dungeon_selection_never_picks_a_boss_arena() -> void:
	var arena: DungeonResource = null
	var regular: DungeonResource = null
	for dungeon: DungeonResource in GlobalVars.dungeons:
		if dungeon.boss_arena:
			arena = dungeon
		elif regular == null:
			regular = dungeon
	if not check(arena != null and regular != null, "setup: a boss arena and a regular dungeon should be registered"):
		return
	# Selection prefers dungeons not visited recently; marking the regular one
	# recent makes a selection that forgot to exclude arenas pick the arena
	# every time instead of by chance.
	ProgressionState.recently_visited_dungeons.append(regular)
	var offered: Array[DungeonResource] = [arena, regular]
	check(ProgressionState.select_dungeon_for_encounter(0, offered) == regular, "regular dungeon selection must never pick a boss arena")


## Every registered enemy that is a boss (boss_at_level > 0).
func _registered_bosses() -> Array[EnemyResource]:
	var bosses: Array[EnemyResource] = []
	for resource: EnemyResource in GlobalVars.enemies:
		if resource != null and resource.boss_at_level > 0:
			bosses.append(resource)
	return bosses


## A test-owned EnemyResource for scene, a boss of level (0: not a boss).
func _test_boss(scene: PackedScene, level: int) -> EnemyResource:
	var resource: EnemyResource = EnemyResource.new()
	resource.scene = scene
	resource.boss_at_level = level
	return resource
