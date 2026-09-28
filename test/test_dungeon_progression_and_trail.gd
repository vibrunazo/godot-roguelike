## Dungeon progression and the objective trail:
## - DungeonResource.matches() accepts difficulties and enemy counts inside
##   its bounds, rejects them outside, and treats 0 bounds as unlimited,
## - ProgressionState picks the dungeon whose bounds fit the encounter and
##   falls back to a candidate when none fits,
## - RoomSpawnArea hands its enemies a home area, keeps them calm until the
##   room triggers, then alerts every one of them,
## - ObjectiveTrail3D follows set_target()/clear_target(); ExitPoint.unlock()
##   points the trail at the exit,
## - one exit's leave animation never changes another exit's wisp (each
##   instance owns its material),
## - the trail draws a path to a distant target, and draws nothing without an
##   engine error when the target sits straight above the player (the path
##   degenerates to a point).
## Every bound and difficulty here is test-owned.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const EXIT_SCENE: PackedScene = preload("res://Levels/exit_point.tscn")

var _saved_difficulty: int = 0


func before_each() -> void:
	_saved_difficulty = ProgressionState.difficulty_level


func after_each() -> void:
	ProgressionState.difficulty_level = _saved_difficulty


func test_a_dungeon_matches_only_encounters_inside_its_bounds() -> void:
	var dungeon: DungeonResource = _dungeon(3, 8, 4, 8)
	check(dungeon.matches(5, 6), "an encounter inside both bounds should match")
	check(not dungeon.matches(2, 6), "a difficulty below min_difficulty should not match")
	check(not dungeon.matches(9, 6), "a difficulty above max_difficulty should not match")
	check(not dungeon.matches(5, 3), "an enemy count below min_enemies should not match")
	check(not dungeon.matches(5, 9), "an enemy count above max_enemies should not match")
	check(_dungeon(0, 0, 0, 0).matches(100, 100), "0 bounds should allow any difficulty and enemy count")


func test_progression_picks_the_dungeon_that_fits_the_encounter() -> void:
	var small: DungeonResource = _dungeon(1, 4, 2, 4)
	var big: DungeonResource = _dungeon(6, 0, 8, 0)
	var pool: Array[DungeonResource] = [small, big]
	ProgressionState.difficulty_level = 3
	check(ProgressionState.select_dungeon_for_encounter(3, pool) == small, "a small early encounter should pick the small dungeon")
	ProgressionState.difficulty_level = 9
	check(ProgressionState.select_dungeon_for_encounter(10, pool) == big, "a big late encounter should pick the big dungeon")
	ProgressionState.difficulty_level = 20
	check(ProgressionState.select_dungeon_for_encounter(2, pool) != null, "with no dungeon fitting, a fallback should still be picked")


func test_a_room_keeps_its_enemies_calm_until_it_triggers() -> void:
	var arena: Node3D = load_arena()
	var area: RoomSpawnArea = autofree(RoomSpawnArea.new()) as RoomSpawnArea
	arena.add_child(area)
	var enemy: Character = spawn(MELEE_SCENE, arena, (arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	await wait_physics_frames(2)
	area.assign_enemy(enemy)
	check(enemy.home_spawn_area == area, "an assigned enemy should know its home area")
	check(not enemy.is_alerted, "an enemy in an untriggered room should start calm")
	var alerted: Array[bool] = [false]
	enemy.alerted.connect(func() -> void: alerted[0] = true)
	area.alert_enemies()
	check(area.is_triggered, "alerting should trigger the room")
	check(enemy.is_alerted and alerted[0], "alerting the room should alert its enemies")


func test_the_trail_follows_its_target_and_the_exit_claims_it_on_unlock() -> void:
	var arena: Node3D = load_arena()
	var trail: ObjectiveTrail3D = autofree(ObjectiveTrail3D.new()) as ObjectiveTrail3D
	arena.add_child(trail)
	var marker: Marker3D = autofree(Marker3D.new()) as Marker3D
	arena.add_child(marker)
	trail.set_target(marker)
	check(trail.is_active and trail.target_node == marker, "set_target() should activate the trail on the target")
	trail.clear_target()
	check(not trail.is_active and trail.target_node == null, "clear_target() should deactivate the trail")
	var exit_point: ExitPoint = spawn(EXIT_SCENE, arena) as ExitPoint
	await wait_physics_frames(1)
	exit_point.unlock()
	check(not exit_point.locked, "unlock() should unlock the exit")
	check(trail.is_active and trail.target_node == exit_point, "unlocking the exit should point the trail at it")


func test_one_exits_leave_animation_never_changes_another_exits_wisp() -> void:
	var arena: Node3D = load_arena()
	var first: ExitPoint = spawn(EXIT_SCENE, arena) as ExitPoint
	var second: ExitPoint = spawn(EXIT_SCENE, arena, Vector3(5.0, 0.0, 0.0)) as ExitPoint
	await wait_physics_frames(1)
	first.unlock()
	second.unlock()
	var before: float = _wisp_cutoff(second)
	first.animation_player.play("Exit")
	first.animation_player.seek(first.animation_player.current_animation_length, true)
	check(not is_equal_approx(_wisp_cutoff(first), before), "setup: the leave animation should change the wisp it plays on")
	check_approx(_wisp_cutoff(second), before, "another exit's wisp should be untouched")


func test_the_trail_draws_a_path_and_survives_a_target_straight_above_the_player() -> void:
	var arena: Node3D = load_arena()
	var player: Character = spawn(PLAYER_SCENE, arena, (arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	if not await wait_for_navigation(arena):
		return
	await wait_until(func() -> bool: return player.is_on_floor(), "setup: the player should land")
	var trail: ObjectiveTrail3D = autofree(ObjectiveTrail3D.new()) as ObjectiveTrail3D
	arena.add_child(trail)
	var ribbon: MeshInstance3D = trail.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	trail.set_target_position((arena.get_node("EnemySpawn") as Node3D).global_position + Vector3(0.0, 0.0, -10.0))
	await wait_until(func() -> bool: return ribbon.mesh.get_surface_count() > 0, "the trail should draw a path to a distant target")
	# Straight above, beyond the arrive distance: the path collapses to a point.
	trail.set_target_position(player.global_position + Vector3.UP * (trail.arrive_distance + 1.0))
	await wait_until(func() -> bool: return ribbon.mesh.get_surface_count() == 0, "a degenerate path should draw nothing")
	await wait_physics_frames(ceili(Engine.physics_ticks_per_second * 0.5))
	check_no_engine_errors("rendering a degenerate path should not report an error")


func _dungeon(min_difficulty: int, max_difficulty: int, min_enemies: int, max_enemies: int) -> DungeonResource:
	var dungeon: DungeonResource = DungeonResource.new()
	dungeon.min_difficulty = min_difficulty
	dungeon.max_difficulty = max_difficulty
	dungeon.min_enemies = min_enemies
	dungeon.max_enemies = max_enemies
	return dungeon


func _wisp_cutoff(exit_point: ExitPoint) -> float:
	return float((exit_point.wisp_mesh.material_override as ShaderMaterial).get_shader_parameter("Cuttoff"))
