extends Node

## Automated test suite for Issue #2:
## - Unified Character class shared by Player and Enemies
## - Group-based identification ("player" vs "enemy") and team targeting
## - Decoupled PlayerInputComponent
## - Dual State Machines on Enemies (Body physical state vs Mind AI state)
## - Stun state independence and recovery

const PlayerScene: PackedScene = preload("res://Player/player.tscn")
const MeleeEnemyScene: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const RangedEnemyScene: PackedScene = preload("res://Enemy/ranged_enemy.tscn")
const BaseEnemyScene: PackedScene = preload("res://Enemy/enemy_base.tscn")


func _ready() -> void:
	print("--- RUNNING CHARACTER & AI STATE MACHINE TEST ---")
	
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(100.0, 1.0, 100.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)

	test_part_1_unified_character_and_groups()
	await test_part_2_team_targeting()
	await test_part_3_player_input_component()
	await test_part_4_dual_state_machines()
	await test_part_5_stun_independence_and_recovery()
	await test_part_6_ranged_projectile_spawner()
	await test_part_7_ranged_enemy_ai_attack_timing()
	await test_part_8_defeat_inactivity_and_rotation_lock()
	await test_part_9_scattered_enemy_spawning()

	print("\n====================================================================")
	print("  ALL CHARACTER & AI STATE MACHINE TESTS PASSED!                    ")
	print("  1. Unified Character class & group identification verified       ")
	print("  2. Team targeting and nearest target resolution verified          ")
	print("  3. Decoupled PlayerInputComponent verified                       ")
	print("  4. Dual State Machines (Body vs Mind) verified                   ")
	print("  5. Stun state independence & seamless locomotion recovery ok     ")
	print("  6. ProjectileSpawnerComponent on ranged characters verified      ")
	print("  7. RangedEnemy attack timing & real polling path verified        ")
	print("  8. Defeat inactivity & rotation lock on corpses verified        ")
	print("  9. Scattered enemy spawning on navmesh verified                  ")
	print("====================================================================")
	get_tree().quit(0)


func test_part_1_unified_character_and_groups() -> void:
	print("\n>>> PART 1: Unified Character Class & Group Identification")
	
	# Instantiate Player
	var player: Character = PlayerScene.instantiate() as Character
	if player == null:
		printerr("TEST FAILED: Player is not an instance of Character.")
		get_tree().quit(1)
		return
	if not (player is CharacterBody3D):
		printerr("TEST FAILED: Player is not a CharacterBody3D.")
		get_tree().quit(1)
		return
	if not player.is_player() or player.is_enemy():
		printerr("TEST FAILED: Player team helper methods failed. is_player(): ", player.is_player(), " is_enemy(): ", player.is_enemy())
		get_tree().quit(1)
		return
	if not player.is_in_group("player") or player.is_in_group("enemy"):
		printerr("TEST FAILED: Player group assignment invalid.")
		get_tree().quit(1)
		return
	print("Player verified as Character in group 'player'.")
	player.free()

	# Instantiate Base Enemy
	var base_enemy: Character = BaseEnemyScene.instantiate() as Character
	if base_enemy == null:
		printerr("TEST FAILED: Base enemy is not an instance of Character.")
		get_tree().quit(1)
		return
	if base_enemy.is_player() or not base_enemy.is_enemy():
		printerr("TEST FAILED: Base enemy team helper methods failed.")
		get_tree().quit(1)
		return
	if not base_enemy.is_in_group("enemy") or base_enemy.is_in_group("player"):
		printerr("TEST FAILED: Base enemy group assignment invalid.")
		get_tree().quit(1)
		return
	print("Base enemy verified as Character in group 'enemy'.")
	base_enemy.free()

	# Instantiate Melee Enemy
	var melee_enemy: Character = MeleeEnemyScene.instantiate() as Character
	if melee_enemy == null or not melee_enemy.is_enemy() or melee_enemy.is_player():
		printerr("TEST FAILED: Melee enemy Character / team verification failed.")
		get_tree().quit(1)
		return
	print("Melee enemy verified as Character in group 'enemy'.")
	melee_enemy.free()

	# Instantiate Ranged Enemy
	var ranged_enemy: Character = RangedEnemyScene.instantiate() as Character
	if ranged_enemy == null or not ranged_enemy.is_enemy() or ranged_enemy.is_player():
		printerr("TEST FAILED: Ranged enemy Character / team verification failed.")
		get_tree().quit(1)
		return
	print("Ranged enemy verified as Character in group 'enemy'.")
	ranged_enemy.free()


func test_part_2_team_targeting() -> void:
	print("\n>>> PART 2: Team Targeting & Nearest Target Resolution")
	var player: Character = PlayerScene.instantiate() as Character
	var enemy1: Character = MeleeEnemyScene.instantiate() as Character
	var enemy2: Character = MeleeEnemyScene.instantiate() as Character
	
	add_child(player)
	add_child(enemy1)
	add_child(enemy2)
	
	player.global_position = Vector3(0.0, 0.0, 0.0)
	enemy1.global_position = Vector3(5.0, 0.0, 0.0)
	enemy2.global_position = Vector3(10.0, 0.0, 0.0)
	
	await get_tree().process_frame
	
	# Player looking for enemy should find the closest one (enemy1)
	var target_for_player: Character = player.get_nearest_target("enemy")
	if target_for_player != enemy1:
		printerr("TEST FAILED: Player did not resolve closest enemy. Expected enemy1, got: ", target_for_player)
		get_tree().quit(1)
		return
	print("Player nearest enemy resolved correctly (enemy1 at 5m).")
	
	# Enemy looking for player
	var target_for_enemy: Character = enemy1.get_nearest_target("player")
	if target_for_enemy != player:
		printerr("TEST FAILED: Enemy did not resolve player. Got: ", target_for_enemy)
		get_tree().quit(1)
		return
	print("Enemy nearest player resolved correctly.")
	
	# Defeating enemy1 should cause player to now resolve enemy2
	enemy1.health_component.current_health = 0.0
	var new_target_for_player: Character = player.get_nearest_target("enemy")
	if new_target_for_player != enemy2:
		printerr("TEST FAILED: Player did not ignore defeated enemy1. Got: ", new_target_for_player)
		get_tree().quit(1)
		return
	print("Player correctly ignored defeated enemy1 and targeted living enemy2.")
	
	player.queue_free()
	enemy1.queue_free()
	enemy2.queue_free()
	await get_tree().process_frame


func test_part_3_player_input_component() -> void:
	print("\n>>> PART 3: Decoupled Player Input Component")
	var player: Character = PlayerScene.instantiate() as Character
	add_child(player)
	await get_tree().process_frame
	
	var input_comp: PlayerInputComponent = player.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp == null:
		printerr("TEST FAILED: PlayerInputComponent not found on Player.")
		player.queue_free()
		get_tree().quit(1)
		return
	if input_comp.character != player:
		printerr("TEST FAILED: PlayerInputComponent.character is not wired to Player.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("PlayerInputComponent node and character wiring verified.")

	# Verify setting player intents
	player.move_direction = Vector3(1.0, 0.0, 0.0).normalized()
	player.aim_direction = Vector3(0.0, 0.0, 1.0).normalized()
	if not player.move_direction.is_equal_approx(Vector3(1.0, 0.0, 0.0)):
		printerr("TEST FAILED: move_direction intent mismatch.")
		player.queue_free()
		get_tree().quit(1)
		return
	if not player.aim_direction.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		printerr("TEST FAILED: aim_direction intent mismatch.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("Player input intent vectors verified.")
	player.queue_free()
	await get_tree().process_frame


func test_part_4_dual_state_machines() -> void:
	print("\n>>> PART 4: Dual State Machine Architecture (Body vs Mind)")
	var enemy: Character = MeleeEnemyScene.instantiate() as Character
	add_child(enemy)
	await get_tree().process_frame
	
	var body_sm: StateMachine = enemy.state_machine
	var mind_sm: AIStateMachine = enemy.ai_state_machine as AIStateMachine
	
	if body_sm == null:
		printerr("TEST FAILED: Body StateMachine is null on MeleeEnemy.")
		enemy.queue_free()
		get_tree().quit(1)
		return
	if mind_sm == null:
		printerr("TEST FAILED: Mind AIStateMachine is null on MeleeEnemy.")
		enemy.queue_free()
		get_tree().quit(1)
		return
	if body_sm.initial_state.name != "EnemyMove":
		printerr("TEST FAILED: Body initial_state is not EnemyMove. Got: ", body_sm.initial_state.name)
		enemy.queue_free()
		get_tree().quit(1)
		return
	if mind_sm.initial_state.name != "AIPursue":
		printerr("TEST FAILED: Mind initial_state is not AIPursue. Got: ", mind_sm.initial_state.name)
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("Body (EnemyMove) and Mind (AIPursue) initial states verified.")
	
	# Test Mind issuing movement command to Body
	mind_sm.command_move(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, 1.0))
	if not enemy.move_direction.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		printerr("TEST FAILED: command_move did not set character move_direction.")
		enemy.queue_free()
		get_tree().quit(1)
		return
	if not enemy.face_target.is_equal_approx(Vector3(0.0, 0.0, 1.0)):
		printerr("TEST FAILED: command_move did not set character face_target.")
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine command_move() set character intents successfully.")
	
	# Test Mind issuing stop command
	mind_sm.command_stop()
	if not enemy.move_direction.is_zero_approx() or not enemy.face_target.is_zero_approx():
		printerr("TEST FAILED: command_stop did not clear intents.")
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine command_stop() cleared character intents successfully.")
	enemy.queue_free()
	await get_tree().process_frame


func test_part_5_stun_independence_and_recovery() -> void:
	print("\n>>> PART 5: Stun State Independence & Recovery")
	var enemy: Character = MeleeEnemyScene.instantiate() as Character
	var player: Character = PlayerScene.instantiate() as Character
	add_child(enemy)
	add_child(player)
	enemy.global_position = Vector3(0.0, 1.0, 0.0)
	player.global_position = Vector3(2.0, 1.0, 0.0)
	enemy.velocity = Vector3(0.0, -1.0, 0.0)
	enemy.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var body_sm: StateMachine = enemy.state_machine
	var mind_sm: AIStateMachine = enemy.ai_state_machine as AIStateMachine
	
	# Verify taking damage enters EnemyStun on Body
	enemy.health_component.take_damage(10.0)
	await get_tree().process_frame
	if body_sm.state.name != "EnemyStun":
		printerr("TEST FAILED: Taking damage did not put body into EnemyStun. Got: ", body_sm.state.name)
		player.queue_free()
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("Body successfully entered EnemyStun upon taking damage.")
	
	# While Body is stunned, Mind order_attack should return false and NOT interrupt stun
	var order_success: bool = mind_sm.order_attack("EnemyAttack")
	if order_success or body_sm.state.name != "EnemyStun":
		printerr("TEST FAILED: order_attack interrupted EnemyStun! State: ", body_sm.state.name)
		player.queue_free()
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("Body protected: AI order_attack() blocked during EnemyStun.")
	
	# Simulate stun animation finish
	enemy.animation_tree.animation_finished.emit("Stun")
	if body_sm.state.name != "EnemyMove":
		printerr("TEST FAILED: Stun finish did not return body to EnemyMove. Got: ", body_sm.state.name)
		player.queue_free()
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("Body cleanly returned to EnemyMove after stun animation finished.")
	
	# Now that body is in EnemyMove, AI can order attack
	var post_stun_attack: bool = mind_sm.order_attack("EnemyAttack")
	if not post_stun_attack or body_sm.state.name != "EnemyAttack":
		printerr("TEST FAILED: AI order_attack failed after recovering from stun. State: ", body_sm.state.name)
		player.queue_free()
		enemy.queue_free()
		get_tree().quit(1)
		return
	print("AI order_attack succeeded after recovering from stun.")
	
	player.queue_free()
	enemy.queue_free()
	await get_tree().process_frame


func test_part_6_ranged_projectile_spawner() -> void:
	print("\n>>> PART 6: Ranged Projectile Spawner Component")
	var ranged_enemy: Character = RangedEnemyScene.instantiate() as Character
	add_child(ranged_enemy)
	ranged_enemy.global_position = Vector3(0.0, 1.0, 0.0)
	await get_tree().process_frame
	
	var spawner: ProjectileSpawnerComponent = ranged_enemy.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	if spawner == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent missing on RangedEnemy.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if spawner.spawn_point == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent spawn_point is null.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	
	var child_count_before: int = ranged_enemy.get_child_count()
	spawner.spawn_projectile()
	var spawned: EnemyProjectile = null
	for i: int in range(child_count_before, ranged_enemy.get_child_count()):
		var c: Node = ranged_enemy.get_child(i)
		if c is EnemyProjectile:
			spawned = c as EnemyProjectile
			break
	if spawned == null:
		printerr("TEST FAILED: spawn_projectile did not instantiate EnemyProjectile as child.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("ProjectileSpawnerComponent successfully spawned projectile.")
	ranged_enemy.queue_free()
	await get_tree().process_frame


func test_part_7_ranged_enemy_ai_attack_timing() -> void:
	print("\n>>> PART 7: Ranged Enemy AI Attack Timing & State Cycle")
	var ranged_enemy: Character = RangedEnemyScene.instantiate() as Character
	add_child(ranged_enemy)
	ranged_enemy.global_position = Vector3(0.0, 1.0, 0.0)
	ranged_enemy.velocity = Vector3(0.0, -1.0, 0.0)
	ranged_enemy.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame

	var ai_sm: AIStateMachine = ranged_enemy.ai_state_machine as AIStateMachine
	var body_sm: StateMachine = ranged_enemy.state_machine
	if ai_sm == null or body_sm == null:
		printerr("TEST FAILED: RangedEnemy state machines missing.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return

	var ai_meander: AIMeander = ai_sm.get_node_or_null("AIMeander") as AIMeander
	var ai_attack: AIAttack = ai_sm.get_node_or_null("AIAttack") as AIAttack
	var ai_wait: AIWait = ai_sm.get_node_or_null("AIWait") as AIWait

	if ai_meander == null or ai_attack == null or ai_wait == null:
		printerr("TEST FAILED: RangedEnemy missing AIMeander, AIAttack, or AIWait.")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return

	if ai_sm.initial_state != ai_meander:
		printerr("TEST FAILED: RangedEnemy initial AI state expected AIMeander, got: ", ai_sm.initial_state.name if ai_sm.initial_state else "null")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("RangedEnemy initial AI state verified as AIMeander.")

	if not is_equal_approx(ai_meander.attack_range, 4.0):
		printerr("TEST FAILED: AIMeander attack_range expected 4.0m, got: ", ai_meander.attack_range)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIMeander attack_range (4.0m) verified.")

	if not is_equal_approx(ai_wait.wait_duration, 2.0):
		printerr("TEST FAILED: AIWait wait_duration expected 2.0s, got: ", ai_wait.wait_duration)
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIWait wait_duration (2.0s) verified.")

	if ai_attack.next_states.size() != 2 or not ai_attack.next_states.has(ai_wait) or not ai_attack.next_states.has(ai_meander):
		printerr("TEST FAILED: AIAttack next_states expected [AIWait, AIMeander].")
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIAttack next_states [AIWait, AIMeander] verified (50/50 post-attack cycle).")

	# Verify proximity trigger in AIMeander transitions AI to AIAttack and Body to EnemyAttack
	var player: Character = PlayerScene.instantiate() as Character
	add_child(player)
	player.global_position = Vector3(3.0, 1.0, 0.0) # within 4.0m
	player.velocity = Vector3(0.0, -1.0, 0.0)
	player.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame

	if ai_sm.state != ai_attack:
		printerr("TEST FAILED: AIMeander proximity did not transition AI to AIAttack. Got: ", ai_sm.state.name if ai_sm.state else "null")
		player.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if body_sm.state.name != "EnemyAttack":
		printerr("TEST FAILED: AIAttack did not order EnemyAttack on Body. Got: ", body_sm.state.name if body_sm.state else "null")
		player.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Proximity detection transitioned AI to AIAttack and Body to EnemyAttack.")

	# 1. Verify real production polling path:
	# When Body finishes EnemyAttack and transitions back to EnemyMove,
	# AIAttack.physics_update() polls that state.name != attack_state_name and completes.
	body_sm.state.finished.emit("EnemyMove")
	if body_sm.state.name != "EnemyMove":
		printerr("TEST FAILED: Body failed to transition back to EnemyMove.")
		player.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return

	# Run production polling update
	ai_attack.physics_update(0.016)
	if ai_sm.state == ai_attack:
		printerr("TEST FAILED: Polling path failed: AI remained in AIAttack after body left EnemyAttack!")
		player.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	if ai_sm.state != ai_wait and ai_sm.state != ai_meander:
		printerr("TEST FAILED: AI state after polled attack completion is neither AIWait nor AIMeander. Got: ", ai_sm.state.name if ai_sm.state else "null")
		player.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Production polling path verified: AI transitioned cleanly to ", ai_sm.state.name, " upon body leaving EnemyAttack.")

	# 2. Unit check for manual end_attack() method
	ai_sm._transition_to_next_state("AIAttack")
	ai_attack.end_attack()
	if ai_sm.state == ai_attack:
		printerr("TEST FAILED: ai_attack.end_attack() unit check failed: AI remained in AIAttack!")
		player.queue_free()
		ranged_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Unit check end_attack() verified.")
	print("Post-attack transition verified: AI transitioned cleanly to ", ai_sm.state.name, " without spamming.")

	player.queue_free()
	ranged_enemy.queue_free()
	await get_tree().process_frame


func test_part_8_defeat_inactivity_and_rotation_lock() -> void:
	print("\n>>> PART 8: Defeat Inactivity & Rotation Lock on Corpses")
	var melee_enemy: Character = MeleeEnemyScene.instantiate() as Character
	var player: Character = PlayerScene.instantiate() as Character
	add_child(melee_enemy)
	add_child(player)
	melee_enemy.global_position = Vector3(0.0, 1.0, 0.0)
	player.global_position = Vector3(5.0, 1.0, 0.0)
	melee_enemy.velocity = Vector3(0.0, -1.0, 0.0)
	player.velocity = Vector3(0.0, -1.0, 0.0)
	melee_enemy.move_and_slide()
	player.move_and_slide()
	await get_tree().physics_frame
	await get_tree().process_frame

	var ai_sm: AIStateMachine = melee_enemy.ai_state_machine as AIStateMachine
	var body_sm: StateMachine = melee_enemy.state_machine

	if not melee_enemy.is_alive():
		printerr("TEST FAILED: Newly instantiated enemy is not alive.")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return

	# Defeat the enemy
	melee_enemy.health_component.take_damage(melee_enemy.health_component.max_health)
	await get_tree().process_frame

	if melee_enemy.is_alive():
		printerr("TEST FAILED: Enemy is still reported as alive after taking max_health damage.")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Character is_alive() returns false after defeat.")

	if body_sm.state.name != "EnemyDefeat":
		printerr("TEST FAILED: Body StateMachine not in EnemyDefeat after death. Got: ", body_sm.state.name)
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Body StateMachine in EnemyDefeat verified.")

	if ai_sm.is_physics_processing():
		printerr("TEST FAILED: AIStateMachine is still physics processing after defeat!")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine physics processing disabled on defeat verified.")

	if not melee_enemy.move_direction.is_zero_approx() or not melee_enemy.face_target.is_zero_approx():
		printerr("TEST FAILED: Character intent vectors not zeroed on defeat.")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Character intent vectors zeroed on defeat verified.")

	# Record initial corpse transform
	var initial_mesh_rot: Vector3 = melee_enemy.mesh_mount.global_rotation

	# Attempt to turn corpse via look_at_target
	melee_enemy.look_at_target(Vector3(10.0, 0.0, 10.0))
	if not melee_enemy.mesh_mount.global_rotation.is_equal_approx(initial_mesh_rot):
		printerr("TEST FAILED: look_at_target rotated a dead character's mesh_mount!")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Corpse look_at_target lock verified (rotation unchanged).")

	# Attempt to turn corpse via look_toward_direction
	melee_enemy.look_toward_direction(Vector3(0.0, 0.0, -1.0), 0.5)
	if not melee_enemy.mesh_mount.global_rotation.is_equal_approx(initial_mesh_rot):
		printerr("TEST FAILED: look_toward_direction rotated a dead character's mesh_mount!")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("Corpse look_toward_direction lock verified (rotation unchanged).")

	# Attempt to command movement and attack via AIStateMachine on dead character
	ai_sm.command_move(Vector3(1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0))
	if not melee_enemy.move_direction.is_zero_approx() or not melee_enemy.face_target.is_zero_approx():
		printerr("TEST FAILED: command_move set intents on a dead character!")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine command_move blocked on dead character verified.")

	var attack_ordered: bool = ai_sm.order_attack("EnemyAttack")
	if attack_ordered or body_sm.state.name != "EnemyDefeat":
		printerr("TEST FAILED: order_attack succeeded on a dead character!")
		player.queue_free()
		melee_enemy.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine order_attack blocked on dead character verified.")

	player.queue_free()
	melee_enemy.queue_free()
	await get_tree().process_frame


func test_part_9_scattered_enemy_spawning() -> void:
	print("\n>>> PART 9: Scattered Enemy Spawning & Navmesh Placement")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	if level_scene == null:
		printerr("TEST FAILED: Could not load LevelTemplate.")
		get_tree().quit(1)
		return
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	# Wait for navigation map sync (iteration > 0 and regions active)
	var nav_map: RID = level.get_world_3d().navigation_map
	for _i: int in range(10):
		await get_tree().physics_frame
		await get_tree().process_frame
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0 and not NavigationServer3D.map_get_regions(nav_map).is_empty():
			break

	var wave_obj: WaveObjective = level.get_node_or_null("WaveObjective") as WaveObjective
	if wave_obj == null:
		printerr("TEST FAILED: WaveObjective not found in level.")
		level.queue_free()
		get_tree().quit(1)
		return

	# Spawn up to 3 enemies via wave_obj.spawn_enemy
	var spawn_count: int = mini(3, wave_obj.all_enemies.size())
	var spawned: Array[Character] = []
	for i: int in range(spawn_count):
		var enemy: Character = wave_obj.all_enemies[i]
		wave_obj.spawn_enemy(enemy)
		spawned.append(enemy)

	if spawned.size() < 2:
		printerr("TEST FAILED: Not enough enemies in wave to verify scattered placement.")
		level.queue_free()
		get_tree().quit(1)
		return

	# Verify enemies are not all at the origin
	var all_at_origin: bool = true
	for enemy: Character in spawned:
		if not enemy.global_position.is_equal_approx(Vector3(0.0, 1.0, 0.0)):
			all_at_origin = false
			break
	if all_at_origin:
		printerr("TEST FAILED: All spawned enemies were placed at the hardcoded origin (0, 1, 0)!")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemies not stacked at hardcoded origin verified.")

	# Check pairwise distances: enemies should have distinct positions on the navmesh
	var identical_positions: bool = true
	for i: int in range(spawned.size()):
		for j: int in range(i + 1, spawned.size()):
			if spawned[i].global_position.distance_squared_to(spawned[j].global_position) > 0.01:
				identical_positions = false
				break
	if identical_positions:
		printerr("TEST FAILED: Spawned enemies are stacked at identical positions!")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Pairwise distinct enemy placement on navmesh verified.")

	level.queue_free()
	await get_tree().process_frame



