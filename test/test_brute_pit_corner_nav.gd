## Regression test verifying that tall enemies (Brute and Akira boss)
## negotiate pit corners without falling into pit voids during pursuit.
extends Node3D

var _failed: bool = false


func _ready() -> void:
	print("====================================================")
	print("  STARTING PIT CORNER NAVIGATION REGRESSION TEST")
	print("====================================================")

	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st != null:
		st.visible = false
		st.set("player_cache", null)

	var lvl_scene: PackedScene = load("res://Levels/level_2.tscn")
	if lvl_scene == null:
		_fail("Could not load Levels/level_2.tscn")
		return

	var level: Node3D = lvl_scene.instantiate() as Node3D
	add_child(level)

	# Disable WaveObjective to avoid extraneous enemy spawns
	var wave_obj: Node = level.find_child("WaveObjective", true, false)
	if wave_obj != null:
		wave_obj.set_script(null)
		for c in wave_obj.get_children():
			c.queue_free()

	# Remove litter props so pathing tests pure floor and pit edge navigation
	var litter: Node = level.find_child("Litter", true, false)
	if litter != null:
		litter.queue_free()

	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Character = level.find_child("Player", true, false) as Character
	if player == null:
		_fail("Player not found in Level 2")
		return

	# Prevent player reload on defeat
	if player.attribute_component != null and player.attribute_component.defeat.is_connected(player.reset_game_state):
		player.attribute_component.defeat.disconnect(player.reset_game_state)

	# Part 1: Brute rounding SE pit corner (Clockwise)
	await _test_brute_se_corner(level, player)
	if _failed:
		return

	# Part 2: Akira Boss rounding SE pit corner (Clockwise)
	await _test_akira_se_corner(level, player)
	if _failed:
		return

	# Part 3: Brute rounding SE pit corner in reverse (Counter-Clockwise)
	await _test_brute_counter_clockwise(level, player)
	if _failed:
		return

	print("====================================================")
	print("  ALL PIT CORNER NAVIGATION TESTS PASSED! (3/3)")
	print("====================================================")
	level.queue_free()
	get_tree().quit(0)


func _fail(msg: String) -> void:
	_failed = true
	printerr("TEST FAILED: ", msg)
	get_tree().quit(1)


func _wait_settle(enemy: Character) -> void:
	for _i in range(15):
		await get_tree().physics_frame
	while enemy.state_machine.state.name != "EnemyMove" or not enemy.is_on_floor():
		await get_tree().physics_frame


func _test_brute_se_corner(level: Node3D, player: Character) -> void:
	print("\n>>> PART 1: Brute navigating SE pit corner (Clockwise)")
	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn") as PackedScene
	if brute_scene == null:
		_fail("Could not load Enemy/enemy_brute.tscn")
		return

	var brute: Character = brute_scene.instantiate() as Character
	level.add_child(brute)
	brute.global_position = Vector3(1.5, 1.5, -20.0)

	player.global_position = Vector3(1.5, 1.0, -14.0)

	await _wait_settle(brute)

	var corner_negotiated: bool = false
	var target_dest: Vector3 = Vector3(-5.0, 1.0, -14.0)

	for frame in range(180):
		await get_tree().physics_frame

		# Move player toward target destination to lead brute around corner
		player.global_position = player.global_position.move_toward(target_dest, 0.05)

		# Verify brute remains grounded and on floor
		if brute.state_machine.state.name == "EnemyFall" or not brute.is_on_floor() or brute.global_position.y < 0.2:
			_fail("Brute fell into pit at frame %d! Pos: (%.2f, %.2f, %.2f) State: %s OnFloor: %s" % [
				frame, brute.global_position.x, brute.global_position.y, brute.global_position.z,
				brute.state_machine.state.name, str(brute.is_on_floor())
			])
			brute.queue_free()
			return

		# Check if brute safely rounded SE corner into the south corridor (X < -0.5, Z > -16.0)
		if brute.global_position.x < -0.5 and brute.global_position.z > -16.0:
			corner_negotiated = true
			print("Brute successfully rounded SE pit corner at frame %d! Pos: (%.2f, %.2f, %.2f)" % [
				frame, brute.global_position.x, brute.global_position.y, brute.global_position.z
			])
			break

	if not corner_negotiated:
		_fail("Brute did not round corner within time limit. Pos: (%.2f, %.2f, %.2f)" % [
			brute.global_position.x, brute.global_position.y, brute.global_position.z
		])

	brute.queue_free()
	await get_tree().physics_frame


func _test_akira_se_corner(level: Node3D, player: Character) -> void:
	print("\n>>> PART 2: Akira Boss navigating SE pit corner (Clockwise)")
	var akira_scene: PackedScene = load("res://Enemy/akira_boss.tscn") as PackedScene
	if akira_scene == null:
		_fail("Could not load Enemy/akira_boss.tscn")
		return

	var akira: Character = akira_scene.instantiate() as Character
	level.add_child(akira)
	akira.global_position = Vector3(1.5, 1.98, -20.0)

	player.global_position = Vector3(1.5, 1.0, -14.0)

	await _wait_settle(akira)

	var firebomb: Node = akira.find_child("AIFirebomb", true, false)
	if firebomb != null:
		firebomb.queue_free()
	var slam: Node = akira.find_child("AISlam", true, false)
	if slam != null:
		slam.queue_free()

	var corner_negotiated: bool = false
	var target_dest: Vector3 = Vector3(-5.0, 1.0, -14.0)

	for frame in range(200):
		await get_tree().physics_frame

		# Move player toward target destination to lead akira around corner
		player.global_position = player.global_position.move_toward(target_dest, 0.05)

		# Verify akira remains grounded and on floor
		if akira.state_machine.state.name == "EnemyFall" or not akira.is_on_floor() or akira.global_position.y < 0.2:
			_fail("Akira Boss fell into pit at frame %d! Pos: (%.2f, %.2f, %.2f) State: %s OnFloor: %s" % [
				frame, akira.global_position.x, akira.global_position.y, akira.global_position.z,
				akira.state_machine.state.name, str(akira.is_on_floor())
			])
			akira.queue_free()
			return

		# Check if akira safely rounded SE corner into the south corridor (X < -0.5, Z > -16.0)
		if akira.global_position.x < -0.5 and akira.global_position.z > -16.0:
			corner_negotiated = true
			print("Akira Boss successfully rounded SE pit corner at frame %d! Pos: (%.2f, %.2f, %.2f)" % [
				frame, akira.global_position.x, akira.global_position.y, akira.global_position.z
			])
			break

	if not corner_negotiated:
		_fail("Akira Boss did not round corner within time limit. Pos: (%.2f, %.2f, %.2f)" % [
			akira.global_position.x, akira.global_position.y, akira.global_position.z
		])

	akira.queue_free()
	await get_tree().physics_frame


func _test_brute_counter_clockwise(level: Node3D, player: Character) -> void:
	print("\n>>> PART 3: Brute navigating SE pit corner in reverse (Counter-Clockwise)")
	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn") as PackedScene
	if brute_scene == null:
		_fail("Could not load Enemy/enemy_brute.tscn")
		return

	var brute: Character = brute_scene.instantiate() as Character
	level.add_child(brute)
	brute.global_position = Vector3(-4.0, 1.5, -14.0)

	player.global_position = Vector3(1.5, 1.0, -14.0)

	await _wait_settle(brute)

	var corner_negotiated: bool = false
	var target_dest: Vector3 = Vector3(1.5, 1.0, -21.0)

	for frame in range(180):
		await get_tree().physics_frame

		# Move player north into the east corridor
		player.global_position = player.global_position.move_toward(target_dest, 0.05)

		# Verify brute remains grounded and on floor
		if brute.state_machine.state.name == "EnemyFall" or not brute.is_on_floor() or brute.global_position.y < 0.2:
			_fail("Brute fell into pit in counter-clockwise test at frame %d! Pos: (%.2f, %.2f, %.2f) State: %s OnFloor: %s" % [
				frame, brute.global_position.x, brute.global_position.y, brute.global_position.z,
				brute.state_machine.state.name, str(brute.is_on_floor())
			])
			brute.queue_free()
			return

		# Check if brute safely rounded SE corner into the east corridor (X > 0.0, Z < -17.0)
		if brute.global_position.x > 0.0 and brute.global_position.z < -17.0:
			corner_negotiated = true
			print("Brute successfully rounded SE pit corner into East corridor at frame %d! Pos: (%.2f, %.2f, %.2f)" % [
				frame, brute.global_position.x, brute.global_position.y, brute.global_position.z
			])
			break

	if not corner_negotiated:
		_fail("Brute did not round corner into corridor within time limit. Pos: (%.2f, %.2f, %.2f)" % [
			brute.global_position.x, brute.global_position.y, brute.global_position.z
		])

	brute.queue_free()
	await get_tree().physics_frame
