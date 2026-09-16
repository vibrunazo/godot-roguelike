## Automated test verifying:
## 1. DungeonResource eligibility matching (difficulty and enemy count bounds).
## 2. ProgressionState enemy-first wave planning and dungeon selection with fallback & history.
## 3. RoomSpawnArea enemy assignment, room-bounded wandering, and player alert trigger.
## 4. ObjectiveTrail3D generic objective navigation and ExitPoint integration.
extends Node

var test_passed: bool = true


func _assert(condition: bool, message: String) -> void:
	if not condition:
		printerr("ASSERTION FAILED: ", message)
		test_passed = false
	else:
		print("PASS: ", message)


func _ready() -> void:
	print("====================================================")
	print("  STARTING DUNGEON PROGRESSION & TRAIL TEST")
	print("====================================================")

	_test_dungeon_resource_matching()
	_test_progression_state_selection()
	await _test_room_spawn_area_and_ai()
	await _test_objective_trail_and_exit()

	if test_passed:
		print("====================================================")
		print("  ALL DUNGEON PROGRESSION & TRAIL TESTS PASSED!")
		print("====================================================")
		get_tree().quit(0)
	else:
		printerr("TEST FAILED: One or more assertions failed.")
		get_tree().quit(1)


func _test_dungeon_resource_matching() -> void:
	print("--- Testing DungeonResource Matching ---")
	var dungeon: DungeonResource = DungeonResource.new()
	dungeon.name = "Test Arena"
	dungeon.min_difficulty = 3
	dungeon.max_difficulty = 8
	dungeon.min_enemies = 4
	dungeon.max_enemies = 8

	# In-bounds match
	_assert(dungeon.matches(5, 6), "Difficulty 5 and 6 enemies matches bounds [3..8, 4..8].")

	# Difficulty lower out of bounds
	_assert(not dungeon.matches(2, 6), "Difficulty 2 rejected when min_difficulty is 3.")

	# Difficulty upper out of bounds
	_assert(not dungeon.matches(9, 6), "Difficulty 9 rejected when max_difficulty is 8.")

	# Enemy count lower out of bounds
	_assert(not dungeon.matches(5, 3), "Enemy count 3 rejected when min_enemies is 4.")

	# Enemy count upper out of bounds
	_assert(not dungeon.matches(5, 10), "Enemy count 10 rejected when max_enemies is 8.")

	# Unlimited bounds (0)
	var open_dungeon: DungeonResource = DungeonResource.new()
	open_dungeon.min_difficulty = 0
	open_dungeon.max_difficulty = 0
	open_dungeon.min_enemies = 0
	open_dungeon.max_enemies = 0
	_assert(open_dungeon.matches(100, 100), "0 bounds allow any difficulty and enemy count.")


func _test_progression_state_selection() -> void:
	print("--- Testing ProgressionState Selection ---")
	var small_d: DungeonResource = DungeonResource.new()
	small_d.name = "Small Room"
	small_d.min_difficulty = 1
	small_d.max_difficulty = 4
	small_d.min_enemies = 2
	small_d.max_enemies = 4

	var big_d: DungeonResource = DungeonResource.new()
	big_d.name = "Huge Sanctuary"
	big_d.min_difficulty = 6
	big_d.max_difficulty = 0
	big_d.min_enemies = 8
	big_d.max_enemies = 0

	var pool: Array[DungeonResource] = [small_d, big_d]

	# Test low difficulty & low enemies: small_d MUST be chosen
	ProgressionState.difficulty_level = 3
	var picked_early: DungeonResource = ProgressionState.select_dungeon_for_encounter(3, pool)
	_assert(picked_early == small_d, "Difficulty 3 with 3 enemies selects Small Room over Huge Sanctuary.")

	# Test high difficulty & high enemies: big_d MUST be chosen
	ProgressionState.difficulty_level = 9
	var picked_late: DungeonResource = ProgressionState.select_dungeon_for_encounter(10, pool)
	_assert(picked_late == big_d, "Difficulty 9 with 10 enemies selects Huge Sanctuary over Small Room.")

	# Test fallback when no dungeon strictly matches
	ProgressionState.difficulty_level = 20
	var fallback_d: DungeonResource = ProgressionState.select_dungeon_for_encounter(2, pool)
	_assert(fallback_d != null, "Fallback returns a candidate when no strict match exists.")


func _test_room_spawn_area_and_ai() -> void:
	print("--- Testing RoomSpawnArea and AI Aggro ---")
	var area: RoomSpawnArea = RoomSpawnArea.new()
	area.room_name = "Test Chamber"
	add_child(area)

	var enemy_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	var enemy: Character = enemy_scene.instantiate() as Character
	add_child(enemy)
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Assign enemy to untriggered room
	area.assign_enemy(enemy)
	_assert(enemy.home_spawn_area == area, "Enemy assigned to RoomSpawnArea receives home_spawn_area reference.")
	_assert(not enemy.is_alerted, "Enemy assigned to untriggered RoomSpawnArea starts un-alerted.")

	# Trigger area: alerts assigned enemies
	var alert_box: Array[bool] = [false]
	enemy.alerted.connect(func() -> void: alert_box[0] = true)

	area.alert_enemies()
	_assert(area.is_triggered, "alert_enemies sets is_triggered = true on RoomSpawnArea.")
	_assert(enemy.is_alerted, "alert_enemies sets is_alerted = true on assigned enemy.")
	_assert(alert_box[0], "Enemy emitted alerted signal upon room trigger.")

	area.queue_free()
	enemy.queue_free()
	await get_tree().physics_frame


func _test_objective_trail_and_exit() -> void:
	print("--- Testing ObjectiveTrail3D and ExitPoint ---")
	var trail: ObjectiveTrail3D = ObjectiveTrail3D.new()
	add_child(trail)

	var target_marker: Marker3D = Marker3D.new()
	add_child(target_marker)
	target_marker.global_position = Vector3(10.0, 0.0, 10.0)

	# Set target
	trail.set_target(target_marker, Color.YELLOW)
	_assert(trail.is_active, "ObjectiveTrail3D is_active is true after set_target.")
	_assert(trail.target_node == target_marker, "ObjectiveTrail3D correctly stores target_node.")

	# Clear target
	trail.clear_target()
	_assert(not trail.is_active, "ObjectiveTrail3D is_active is false after clear_target.")
	_assert(trail.target_node == null, "ObjectiveTrail3D target_node is null after clear_target.")

	# Test ExitPoint integration
	var exit_scene: PackedScene = load("res://Levels/exit_point.tscn") as PackedScene
	var exit_point: ExitPoint = exit_scene.instantiate() as ExitPoint
	add_child(exit_point)
	await get_tree().physics_frame

	exit_point.unlock()
	_assert(not exit_point.locked, "ExitPoint unlocked successfully.")
	_assert(trail.is_active, "ExitPoint.unlock() activated ObjectiveTrail3D.")
	_assert(trail.target_node == exit_point, "ObjectiveTrail3D target_node points to ExitPoint.")

	trail.queue_free()
	target_marker.queue_free()
	exit_point.queue_free()
	await get_tree().physics_frame
