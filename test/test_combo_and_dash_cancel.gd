extends Node

func _ready() -> void:
	print("--- RUNNING 3-HIT COMBO & DASH CANCEL TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Player = level.get_node("Player") as Player
	var dummy: CollisionObject3D = (level.get_node_or_null("Enemy") if level.has_node("Enemy") else level.get_node_or_null("StaticBody3D")) as CollisionObject3D
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	var initial_health: float = health_comp.current_health
	print("Dummy initial health: ", initial_health)
	
	# Wait for player to settle on floor in PlayerRun
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
	
	# =========================================================================
	# PART 1: FULL 3-HIT COMBO & DAMAGE SCALING (Slash -> Stab -> Spin)
	# =========================================================================
	print("\n>>> PART 1: Testing Full 3-Hit Combo (Slash -> Stab -> Spin)")
	
	# 1. Trigger Attack 1 (Slash)
	var click := InputEventAction.new()
	click.action = "click"
	click.pressed = true
	sm._unhandled_input(click)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not enter PlayerAttack.")
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack (Attack 1: Slash)")
	
	# Wait for Attack 1 to hit
	for i: int in range(30):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 8.0:
			break
	if health_comp.current_health != initial_health - 8.0:
		printerr("TEST FAILED: Attack 1 damage mismatch. Expected: ", initial_health - 8.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 1 hit confirmed! Dummy health: ", health_comp.current_health, " (-8.0 damage)")
	
	# Queue Attack 2
	sm._unhandled_input(click)
	
	# Wait for transition to PlayerAttack2 (Stab)
	var in_attack2 := false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack2":
			in_attack2 = true
			break
	if not in_attack2:
		printerr("TEST FAILED: Did not transition to PlayerAttack2.")
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack2 (Attack 2: Stab)")
	
	# Wait for Attack 2 to hit
	for i: int in range(30):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 22.0:
			break
	if health_comp.current_health != initial_health - 22.0:
		printerr("TEST FAILED: Attack 2 damage mismatch. Expected: ", initial_health - 22.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 2 hit confirmed! Dummy health: ", health_comp.current_health, " (-14.0 damage)")
	
	# Queue Attack 3 (Spin)
	sm._unhandled_input(click)
	
	# Wait for transition to PlayerAttack3 (Spin)
	var in_attack3 := false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack3":
			in_attack3 = true
			break
	if not in_attack3:
		printerr("TEST FAILED: Did not transition to PlayerAttack3.")
		get_tree().quit(1)
		return
	print("Entered state: PlayerAttack3 (Attack 3: Spin)")
	
	# Wait for Attack 3 to hit
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 32.0:
			break
	if health_comp.current_health != initial_health - 32.0:
		printerr("TEST FAILED: Attack 3 damage mismatch. Expected: ", initial_health - 32.0, ", got: ", health_comp.current_health)
		get_tree().quit(1)
		return
	print("Attack 3 hit confirmed! Dummy health: ", health_comp.current_health, " (-10.0 damage)")
	
	# Wait for Attack 3 to finish and return to PlayerRun
	var back_to_run := false
	for i: int in range(120):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after combo finish.")
		get_tree().quit(1)
		return
	print("Combo completed! Successfully returned to PlayerRun.")
	
	# =========================================================================
	# PART 2: DASH CANCEL ON ATTACK 1 (dash_cancel = true)
	# =========================================================================
	print("\n>>> PART 2: Testing Dash Cancel on Attack 1 (dash_cancel = true)")
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Press movement key so player has movement direction required by can_dash()
	Input.action_press("move_forward")
	await get_tree().physics_frame
	
	# Trigger Attack 1
	sm._unhandled_input(click)
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not enter PlayerAttack for dash cancel test.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Entered PlayerAttack...")
	
	# Immediately send dash input
	var dash_event := InputEventAction.new()
	dash_event.action = "dash"
	dash_event.pressed = true
	sm._unhandled_input(dash_event)
	
	if sm.state.name != "PlayerDash":
		printerr("TEST FAILED: Dash cancel did not transition to PlayerDash! State: ", sm.state.name)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Dash cancel SUCCESS! Interrupted PlayerAttack directly into PlayerDash.")
	
	# Wait for dash to finish and return to PlayerRun
	back_to_run = false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after dash.")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Dash completed and returned to PlayerRun.")
	
	# Wait for dash cooldown so player can dash again
	for i: int in range(60):
		await get_tree().physics_frame
		if player.can_dash():
			break
			
	# =========================================================================
	# PART 3: NO DASH CANCEL ON ATTACK 3 (dash_cancel = false / committed)
	# =========================================================================
	print("\n>>> PART 3: Testing Dash Cancel Forbidden on Attack 3 (Spin Attack)")
	
	# Chain to Attack 3 while still pressing move_forward
	var c1 := InputEventAction.new()
	c1.action = "click"
	c1.pressed = true
	sm._unhandled_input(c1) # Trigger Attack 1
	for i: int in range(20):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack":
			break
			
	var c2 := InputEventAction.new()
	c2.action = "click"
	c2.pressed = true
	sm._unhandled_input(c2) # Queue Attack 2
	
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack2":
			break
			
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	var c3 := InputEventAction.new()
	c3.action = "click"
	c3.pressed = true
	sm._unhandled_input(c3) # Queue Attack 3
	
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerAttack3":
			break
			
	if sm.state.name != "PlayerAttack3":
		printerr("TEST FAILED: Could not reach PlayerAttack3 for commitment test. Current state: ", sm.state.name)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Entered PlayerAttack3 (SpinAttack)...")
	
	# Send dash input during SpinAttack (movement is held, so can_dash() is true, but dash_cancel is false)
	sm._unhandled_input(dash_event)
	await get_tree().physics_frame
	
	# Verify that the player is STILL in PlayerAttack3 and was NOT allowed to dash
	if sm.state.name == "PlayerDash":
		printerr("TEST FAILED: Player was able to dash cancel out of PlayerAttack3!")
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	if sm.state.name != "PlayerAttack3":
		printerr("TEST FAILED: Unexpected state during spin attack: ", sm.state.name)
		Input.action_release("move_forward")
		get_tree().quit(1)
		return
	print("Commitment verified! Dash cancel was correctly rejected during SpinAttack.")
	Input.action_release("move_forward")
	
	# Wait for spin to finish cleanly
	back_to_run = false
	for i: int in range(120):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			back_to_run = true
			break
	if not back_to_run:
		printerr("TEST FAILED: Did not return to PlayerRun after final spin.")
		get_tree().quit(1)
		return
		
	print("\n====================================================================")
	print("  ALL 3-HIT COMBO & DASH CANCEL TESTS PASSED!                      ")
	print("  1. Combo Damage: 100 -> 92 (Slash: 8) -> 78 (Stab: 14) -> 68 (Spin: 10)")
	print("  2. Dash Cancel on Attack 1: Cancelled into PlayerDash successfully")
	print("  3. Dash Cancel on Attack 3: Correctly blocked / committed to spin")
	print("  4. State recovery: Clean return to PlayerRun in all scenarios     ")
	print("====================================================================")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(0)
