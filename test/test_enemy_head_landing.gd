## Regression suite: enemy tops are never usable floors for the player.
##
## Mechanism: the player's states move via `Character.move_character()`, which
## retries any enemy-top floor contact in floating mode, so landing on a head
## can never report `is_on_floor()`, transition to PlayerRun, or launch the
## player (wall-like contact; momentum preserved, steering off the crown stripped,
## drift banked as distance). Uses the real Player and melee enemy scenes to exercise the live wiring.
extends Node3D

const PlayerRun := preload("res://StateMachine/PlayerStates/player_run.gd")
const MeleeEnemyScene := preload("res://Enemy/melee_enemy.tscn")
const LEVEL_PATH: String = "res://Levels/level_template.tscn"
## Drop height above the enemy capsule top, in meters.
const DROP_HEIGHT: float = 1.0
## Horizontal offset from the enemy center for the drop, in meters, so the
## contact starts on the dome slope instead of the degenerate apex point.
const DROP_OFFSET: float = 0.25
## Physics frames to wait for a landing after the drop starts.
const LANDING_FRAMES: int = 240
## Upper bound for horizontal speed during the enemy contact (no spring).
const MAX_SLIDE_SPEED: float = 3.5

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if condition:
		print("  ok: ", message)
	else:
		failures += 1
		printerr("TEST FAILED: ", message)


## Freeze an enemy's AI so it stands still for deterministic geometry.
func freeze_ai(enemy: Character) -> void:
	if enemy.ai_state_machine != null:
		enemy.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED


## Spawns a real melee enemy under the level, freezes it, and waits for it to
## settle on the floor. Returns null if it never settles.
func spawn_settled_enemy(level: Node3D, position: Vector3) -> Character:
	var enemy: Character = MeleeEnemyScene.instantiate() as Character
	level.add_child(enemy)
	enemy.global_position = position
	enemy.velocity = Vector3.ZERO
	freeze_ai(enemy)
	for frame: int in range(60):
		await get_tree().physics_frame
		if enemy.is_on_floor():
			return enemy
	return null


func _ready() -> void:
	print("--- RUNNING ENEMY HEAD LANDING REGRESSION TEST ---")
	var level: Node3D = (load(LEVEL_PATH) as PackedScene).instantiate() as Node3D
	add_child(level)
	var player: Character = level.get_node("Player") as Character
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	var run_state: PlayerRun = sm.get_node("PlayerRun") as PlayerRun

	# PART 1: Baseline landing on real terrain still works.
	print("\n>>> PART 1: Baseline terrain landing (unchanged behavior)")
	player.move_direction = Vector3.ZERO
	for frame: int in range(30):
		await get_tree().physics_frame
		if sm.state == run_state and player.is_on_floor():
			break
	check(sm.state == run_state and player.is_on_floor(), "Player is grounded in PlayerRun on level floor")
	var terrain_y: float = player.global_position.y
	var spawn_xz: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	player.global_position = player.global_position + Vector3(0.0, 1.0, 0.0)
	player.velocity = Vector3.ZERO
	var baseline_landed: bool = false
	for frame: int in range(LANDING_FRAMES):
		await get_tree().physics_frame
		if player.is_on_floor() and player.global_position.y <= terrain_y + 0.2 and sm.state == run_state:
			baseline_landed = true
			break
	check(baseline_landed, "Player lands on terrain from a 1m drop and returns to PlayerRun")
	for frame: int in range(10):
		await get_tree().physics_frame

	# PART 2: Dropping onto an enemy head: wall-like, never a floor, no launch.
	print("\n>>> PART 2: Player drop onto enemy head")
	var anchor: Vector2 = spawn_xz
	var enemy: Character = await spawn_settled_enemy(level, Vector3(anchor.x, player.global_position.y + 1.0, anchor.y))
	check(enemy != null, "Melee enemy spawned and settled on the floor")
	if enemy == null:
		get_tree().quit(1)
		return
	var enemy_top: float = enemy.global_position.y + 1.0
	var ever_floor: bool = false
	var max_horizontal: float = 0.0
	var landed_on_terrain: bool = false
	player.global_position = Vector3(anchor.x + DROP_OFFSET, enemy_top + DROP_HEIGHT, anchor.y)
	player.velocity = Vector3.ZERO
	for frame: int in range(LANDING_FRAMES):
		await get_tree().physics_frame
		var over_enemy: bool = Vector2(player.global_position.x - enemy.global_position.x, player.global_position.z - enemy.global_position.z).length() < 1.0 and player.global_position.y > terrain_y + 0.5
		if player.is_on_floor() and over_enemy:
			ever_floor = true
		max_horizontal = maxf(max_horizontal, Vector2(player.velocity.x, player.velocity.z).length())
		if player.is_on_floor() and player.global_position.y <= terrain_y + 0.2 and sm.state == run_state:
			landed_on_terrain = true
			break
	check(not ever_floor, "Enemy top never reports floor contact for the player")
	check(landed_on_terrain, "Player slides off the enemy and lands on terrain")
	check(max_horizontal < MAX_SLIDE_SPEED, "Top contact is wall-like, no spring launch (max horizontal %.2f m/s < %.1f)" % [max_horizontal, MAX_SLIDE_SPEED])
	for frame: int in range(10):
		await get_tree().physics_frame

	# PART 3: Enemy body still blocks ground-level side movement.
	print("\n>>> PART 3: Side approach is still blocked (no pass-through)")
	var side_start: Vector3 = enemy.global_position + Vector3(2.0, 0.0, 0.0)
	side_start.y = player.global_position.y
	player.global_position = side_start
	player.velocity = Vector3.ZERO
	var input_comp: PlayerInputComponent = player.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null:
		input_comp.set_physics_process(false)
	var closest_radial: float = INF
	player.move_direction = Vector3.LEFT
	for frame: int in range(60):
		await get_tree().physics_frame
		var offset: Vector3 = player.global_position - enemy.global_position
		closest_radial = minf(closest_radial, Vector2(offset.x, offset.z).length())
	player.move_direction = Vector3.ZERO
	if input_comp != null:
		input_comp.set_physics_process(true)
	var p_rad: float = (player.collision_shape_3d.shape as CapsuleShape3D).radius if player.collision_shape_3d.shape is CapsuleShape3D else 0.375
	var e_rad: float = (enemy.collision_shape_3d.shape as CapsuleShape3D).radius if enemy.collision_shape_3d.shape is CapsuleShape3D else 0.375
	var min_blocking_dist: float = (p_rad + e_rad) * 0.8
	check(closest_radial < 1.9, "Player actually approaches the enemy (closest radial %.2fm)" % closest_radial)
	check(closest_radial > min_blocking_dist, "Player cannot walk through the enemy body (closest radial %.2fm > %.2fm)" % [closest_radial, min_blocking_dist])

	# PART 5: Centered neutral drop onto the crown: the apex is never a perch.
	print("\n>>> PART 5: Centered neutral drop (apex perch)")
	player.global_position = Vector3(enemy.global_position.x, enemy_top + DROP_HEIGHT, enemy.global_position.z)
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	var ever_head_floor5: bool = false
	var ever_head_run5: bool = false
	var landed5: bool = false
	var run_streak5: int = 0
	for frame: int in range(LANDING_FRAMES):
		await get_tree().physics_frame
		var head5: bool = Vector2(player.global_position.x - enemy.global_position.x, player.global_position.z - enemy.global_position.z).length() < 1.0 and player.global_position.y > terrain_y + 0.5
		if player.is_on_floor() and head5:
			ever_head_floor5 = true
		var perched5: bool = Vector2(player.global_position.x - enemy.global_position.x, player.global_position.z - enemy.global_position.z).length() < 1.0 and player.global_position.y > terrain_y + 0.5
		if perched5 and sm.state == run_state:
			run_streak5 += 1
			if run_streak5 >= 5:
				ever_head_run5 = true
		else:
			run_streak5 = 0
		if player.is_on_floor() and player.global_position.y <= terrain_y + 0.2 and sm.state == run_state:
			landed5 = true
			break
	check(not ever_head_floor5, "Apex never supports the player as a floor")
	check(not ever_head_run5, "Player never enters the grounded run state while over the enemy crown")
	check(landed5, "Player slides off the crown and lands on terrain")
	for frame: int in range(10):
		await get_tree().physics_frame

	# PART 6: Insistent drop while steering back onto the crown every frame.
	print("\n>>> PART 6: Centered drop while steering onto the crown")
	if input_comp != null:
		input_comp.set_physics_process(false)
	player.global_position = Vector3(enemy.global_position.x, enemy_top + DROP_HEIGHT, enemy.global_position.z)
	player.velocity = Vector3.ZERO
	var ever_head_floor6: bool = false
	var ever_head_run6: bool = false
	var landed6: bool = false
	var run_streak6: int = 0
	for frame: int in range(LANDING_FRAMES):
		var to_enemy6: Vector3 = enemy.global_position - player.global_position
		to_enemy6.y = 0.0
		if to_enemy6.is_zero_approx():
			player.move_direction = Vector3.ZERO
		else:
			player.move_direction = to_enemy6.normalized()
		await get_tree().physics_frame
		var head6: bool = Vector2(player.global_position.x - enemy.global_position.x, player.global_position.z - enemy.global_position.z).length() < 1.0 and player.global_position.y > terrain_y + 0.5
		if player.is_on_floor() and head6:
			ever_head_floor6 = true
		var perched6: bool = Vector2(player.global_position.x - enemy.global_position.x, player.global_position.z - enemy.global_position.z).length() < 1.0 and player.global_position.y > terrain_y + 0.5
		if perched6 and sm.state == run_state:
			run_streak6 += 1
			if run_streak6 >= 5:
				ever_head_run6 = true
		else:
			run_streak6 = 0
		if player.is_on_floor() and player.global_position.y <= terrain_y + 0.2 and sm.state == run_state:
			landed6 = true
			break
	player.move_direction = Vector3.ZERO
	if input_comp != null:
		input_comp.set_physics_process(true)
	check(not ever_head_floor6, "Steering onto the crown never makes it a floor")
	check(not ever_head_run6, "Steering onto the crown never enters the grounded run state")
	check(landed6, "Insistent player still slides off and lands on terrain")
	for frame: int in range(10):
		await get_tree().physics_frame

	# PART 4: Enemies still treat other enemies as floors (regression guard).
	print("\n>>> PART 4: Enemy-to-enemy standing is unaffected")
	var rider: Character = await spawn_settled_enemy(level, Vector3(anchor.x, enemy_top + 0.5, anchor.y))
	check(rider != null, "Second enemy spawned above the first")
	if rider != null:
		check(rider.is_on_floor(), "Enemy lands and rests on another enemy's capsule (is_on_floor true)")

	if failures > 0:
		printerr("ENEMY HEAD LANDING TEST FAILED with %d failure(s)" % failures)
		get_tree().quit(1)
		return
	print("ALL ENEMY HEAD LANDING TESTS PASSED")
	get_tree().quit(0)

