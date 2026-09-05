extends Node

func _ready() -> void:
	print("--- RUNNING QUEUED ATTACK (ATTACK CHAINING) TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Player = level.get_node("Player") as Player
	var dummy: CollisionObject3D = (level.get_node_or_null("Enemy") if level.has_node("Enemy") else level.get_node_or_null("StaticBody3D")) as CollisionObject3D
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	var initial_health: float = health_comp.current_health
	print("Dummy initial health: ", initial_health)
	
	# Wait for player to settle in PlayerRun on the floor
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
			
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Player did not enter PlayerRun.")
		get_tree().quit(1)
		return
		
	# Position player facing dummy
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.player_root.global_transform.looking_at(player.player_root.global_position + dir, Vector3.UP, true)
	player.player_root.global_transform = target
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# 1. Trigger first attack (SlashAttack)
	print("\n--- 1. Triggering First Attack (PlayerAttack / SlashAttack) ---")
	var click1 := InputEventAction.new()
	click1.action = "click"
	click1.pressed = true
	sm._unhandled_input(click1)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not transition to PlayerAttack. State: ", sm.state.name)
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack (SlashAttack)")
	
	# 2. Wait a few frames for slash attack to hit dummy
	for i: int in range(30):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 8.0:
			break
			
	if health_comp.current_health != initial_health - 8.0:
		printerr("TEST FAILED: First attack did not damage dummy to expected value. Health: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("First attack hit confirmed! Dummy health: ", health_comp.current_health)
	
	# 3. Queue the second attack by clicking during the queued_attack_time window
	print("\n--- 2. Sending click during queued_attack_time window ---")
	var click2 := InputEventAction.new()
	click2.action = "click"
	click2.pressed = true
	sm._unhandled_input(click2)
	
	# 4. Wait for the 0.5s timer to trigger transition to PlayerAttack2 (StabAttack)
	print("Waiting for queued attack timer to trigger transition to PlayerAttack2...")
	var transitioned_to_attack2 := false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack2":
			transitioned_to_attack2 = true
			print("Successfully transitioned to PlayerAttack2 at frame ", i)
			break
			
	if not transitioned_to_attack2:
		printerr("TEST FAILED: Did not transition to PlayerAttack2. State: ", sm.state.name)
		get_tree().quit(1)
		return
		
	# 5. Wait for second attack (StabAttack) to deal damage
	print("Waiting for second attack (StabAttack) to hit dummy...")
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 22.0:
			break
			
	if health_comp.current_health != initial_health - 22.0:
		printerr("TEST FAILED: Second attack did not damage dummy to expected value. Health: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Second attack (StabAttack) hit confirmed! Dummy health: ", health_comp.current_health)
	
	# 6. Wait for PlayerAttack2 to finish and return to PlayerRun
	print("Waiting for PlayerAttack2 animation to finish and return to PlayerRun...")
	var returned_to_run := false
	for i: int in range(100):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			returned_to_run = true
			print("Attack chain finished! Returned to PlayerRun at frame ", i)
			break
			
	if not returned_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after PlayerAttack2. State: ", sm.state.name)
		get_tree().quit(1)
		return
		
	print("\n====================================================================")
	print("  QUEUED ATTACK TEST PASSED: Attack chain transitioned & recovered! ")
	print("  Initial Health: 100.0 -> Slash: 92.0 -> Stab: 78.0                ")
	print("  Successfully returned to PlayerRun state!                         ")
	print("====================================================================")
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
