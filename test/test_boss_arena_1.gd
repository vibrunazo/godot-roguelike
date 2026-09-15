## Boss arena verification: the WaveObjective boss path, Boss Arena 1
## integrity, and the dungeon-level-10 boss routing.
##
## - A WaveObjective with boss_resources spawns exactly those bosses even
##   when the run difficulty is below their regular-spawn gate (the
##   level-10 exception: boss fight before regular unlock at 20).
## - Boss Arena 1 loads with its boss pinned, core nodes present, baked
##   VoxelGI data, and a valid nav path from player spawn to the exit.
## - SceneTransition.boss_arenas routes dungeon level 10 to the arena
##   without touching the regular levels rotation.
extends Node3D

const ARENA_PATH: String = "res://Levels/boss_arena_1.tscn"
const BOSS_SCENE_PATH: String = "res://Enemy/akira_boss.tscn"

var _passed: int = 0
var _failed: bool = false


func _ready() -> void:
	print("====================================================")
	print("  STARTING BOSS ARENA 1 VERIFICATION SUITE")
	print("====================================================")
	await _part1_boss_wave_bypasses_gate()
	if _failed:
		return
	await _part2_arena_integrity()
	if _failed:
		return
	_part3_level10_routing()
	if _failed:
		return
	print("====================================================")
	print("ALL BOSS ARENA 1 TESTS PASSED (%d checks)" % _passed)
	print("====================================================")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	_failed = true
	printerr("TEST FAILED: ", msg)
	get_tree().quit(1)


## Boss path spawns the boss while the regular pool gate stays shut.
func _part1_boss_wave_bypasses_gate() -> void:
	print("\n>>> PART 1: boss wave bypasses the regular-spawn gate")
	var boss_scene: PackedScene = load(BOSS_SCENE_PATH) as PackedScene
	if boss_scene == null:
		_fail("Could not load %s" % BOSS_SCENE_PATH)
		return
	var boss_res: EnemyResource = GlobalVars.get_enemy_resource(boss_scene)
	if boss_res == null:
		_fail("GlobalVars.enemies does not contain akira boss resource.")
		return
	# Sanity: at difficulty 15 (dungeon level 10) the gate is shut.
	var probe := WaveObjective.new()
	var gated: Dictionary = probe.build_difficulty_pool(GlobalVars.enemies, 15)
	probe.free()
	if gated.has(12) and (gated[12] as Array[EnemyResource]).has(boss_res):
		_fail("Gate setup broken: boss in regular pool at difficulty 15.")
		return
	var wave := WaveObjective.new()
	var bosses: Array[EnemyResource] = [boss_res]
	wave.boss_resources = bosses
	var spawned: Array[Character] = wave.generate_wave_enemies()
	if spawned.size() != 1:
		_fail("Boss wave must spawn exactly one boss, got %d." % spawned.size())
		wave.free()
		return
	if spawned[0].get_scene_file_path() != BOSS_SCENE_PATH:
		_fail("Spawned boss is not the akira scene: %s" % spawned[0].get_scene_file_path())
		spawned[0].queue_free()
		wave.free()
		return
	print("Boss wave spawns exactly the akira boss at gated difficulty.")
	spawned[0].queue_free()
	wave.free()
	_passed += 1
	await get_tree().process_frame


## Arena scene carries the boss and is a completable level.
func _part2_arena_integrity() -> void:
	print("\n>>> PART 2: Boss Arena 1 integrity")
	if not ResourceLoader.exists(ARENA_PATH):
		_fail("Missing arena scene: %s" % ARENA_PATH)
		return
	var packed: PackedScene = load(ARENA_PATH) as PackedScene
	if packed == null:
		_fail("Could not load %s" % ARENA_PATH)
		return
	var arena: Node3D = packed.instantiate() as Node3D
	add_child(arena)
	var wave: WaveObjective = arena.find_child("WaveObjective", true, false) as WaveObjective
	if wave == null:
		_fail("WaveObjective missing in arena.")
		arena.queue_free()
		return
	if wave.boss_resources.size() != 1:
		_fail("Arena must pin exactly one boss, got %d." % wave.boss_resources.size())
		arena.queue_free()
		return
	if (wave.boss_resources[0] as EnemyResource).scene.resource_path != BOSS_SCENE_PATH:
		_fail("Arena boss is not the akira scene.")
		arena.queue_free()
		return
	print("Arena pins the akira boss on its WaveObjective.")
	# Silence the spawner (read first: values are needed above) so the
	# staggered spawn tween cannot fire while the checks run.
	wave.set_script(null)
	for c: Node in wave.get_children():
		c.queue_free()
	var player: Node3D = arena.find_child("Player", true, false) as Node3D
	var exit_point: Node3D = arena.find_child("ExitPoint", true, false) as Node3D
	if player == null or exit_point == null:
		_fail("Player/ExitPoint missing in arena.")
		arena.queue_free()
		return
	var gi: VoxelGI = arena.find_child("VoxelGI", true, false) as VoxelGI
	if gi == null or gi.data == null:
		_fail("VoxelGI baked data missing in arena.")
		arena.queue_free()
		return
	# Edges follow regular rules: open south cliff (no walls of any tier on
	# the south band), north rim walled on the east half only (regular
	# low rims, so any tier counts). Wall cells are 2 m; the 9x9 arena
	# spans world 0..36, corner columns excluded.
	var wall_gm: GridMap = null
	for gm_node: Node in arena.find_children("*", "GridMap", true, false):
		var gm: GridMap = gm_node as GridMap
		if gm != null and gm.name == "Wallmap":
			wall_gm = gm
	if wall_gm == null:
		_fail("Wallmap missing in arena.")
		arena.queue_free()
		return
	var south_walls: int = 0
	var north_walls: int = 0
	for cell: Vector3i in wall_gm.get_used_cells():
		if cell.x < 2 or cell.x > 15:
			continue
		if cell.z >= 16:
			south_walls += 1
		elif cell.z <= 1:
			north_walls += 1
	if south_walls != 0:
		_fail("South rim must be fully open, found %d walls." % south_walls)
		arena.queue_free()
		return
	if north_walls == 0:
		_fail("North rim must carry some walls (east half).")
		arena.queue_free()
		return
	print("Arena edges OK (open south, %d north walls)." % north_walls)
	# Wait for the nav region to register, then prove spawn-to-exit pathing.
	var synced: bool = false
	for i: int in range(120):
		await get_tree().physics_frame
		var snap: Vector3 = NavigationServer3D.map_get_closest_point(
			get_world_3d().get_navigation_map(),
			Vector3(player.global_position.x, 1.0, player.global_position.z))
		if snap != Vector3.ZERO:
			synced = true
			break
	if not synced:
		_fail("Arena navmesh never synced.")
		arena.queue_free()
		return
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		get_world_3d().get_navigation_map(),
		Vector3(player.global_position.x, 1.0, player.global_position.z),
		Vector3(exit_point.global_position.x, 1.0, exit_point.global_position.z),
		true, 1)
	if path.size() < 2:
		_fail("No nav path from arena spawn to exit.")
		arena.queue_free()
		return
	print("Arena nav path OK (%d points), VoxelGI baked." % path.size())
	arena.queue_free()
	_passed += 1


## Dungeon level 10 detours to the arena; rotation is untouched.
func _part3_level10_routing() -> void:
	print("\n>>> PART 3: dungeon level 10 routes to the arena")
	var st_packed: PackedScene = load("res://Singletons/scene_transition.tscn") as PackedScene
	if st_packed == null:
		_fail("Could not load scene_transition.tscn.")
		return
	var st: Node = st_packed.instantiate()
	var arenas: Dictionary = st.get("boss_arenas") as Dictionary
	st.queue_free()
	if not arenas.has(10) or str(arenas[10]) != ARENA_PATH:
		_fail("boss_arenas must route dungeon level 10 to %s." % ARENA_PATH)
		return
	if not ResourceLoader.exists(str(arenas[10])):
		_fail("Routed arena scene does not exist.")
		return
	print("Dungeon level 10 routes to Boss Arena 1.")
	_passed += 1
