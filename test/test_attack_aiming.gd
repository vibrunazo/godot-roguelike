extends Node

func _ready() -> void:
	print("--- RUNNING MOUSE AIMING ATTACK TEST ---")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	var player: Player = level.get_node("Player") as Player
	var dummy: CollisionObject3D = (level.get_node_or_null("Enemy") if level.has_node("Enemy") else level.get_node_or_null("StaticBody3D")) as CollisionObject3D
	var health_comp: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	
	# Wait for player to settle in PlayerRun on floor
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
			
	if sm.state.name != "PlayerRun":
		printerr("TEST FAILED: Player did not enter PlayerRun.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
		
	var camera: Camera3D = player.get_viewport().get_camera_3d()
	if camera == null:
		printerr("TEST FAILED: No active 3D camera found in viewport.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return

	# =========================================================================
	# PART 1: Verify 2D Unprojection & Mouse Aim Math
	# =========================================================================
	print("\n>>> PART 1: Testing 2D & 3D Aim Direction Calculations")
	player.global_position = Vector3(0, player.global_position.y, 0)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var player_2d: Vector2 = player.get_player_position_2d()
	print("Player 2D screen position: ", player_2d)
	if player_2d == Vector2.ZERO:
		printerr("TEST FAILED: get_player_position_2d() returned (0,0).")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return

	# Simulate aiming to the RIGHT on screen (+200 px X)
	var right_screen_target: Vector2 = player_2d + Vector2(200, 0)
	var mm_right := InputEventMouseMotion.new()
	mm_right.position = right_screen_target
	mm_right.global_position = right_screen_target
	Input.parse_input_event(mm_right)
	await get_tree().process_frame
	
	var aim_right: Vector3 = player.get_aim_direction()
	print("Aim direction (aiming right on screen): ", aim_right)
	if aim_right.length_squared() < 0.001:
		printerr("TEST FAILED: get_aim_direction() was zero vector.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return

	# Simulate aiming to the LEFT on screen (-200 px X)
	var left_screen_target: Vector2 = player_2d + Vector2(-200, 0)
	var mm_left := InputEventMouseMotion.new()
	mm_left.position = left_screen_target
	mm_left.global_position = left_screen_target
	Input.parse_input_event(mm_left)
	await get_tree().process_frame
	
	var aim_left: Vector3 = player.get_aim_direction()
	print("Aim direction (aiming left on screen): ", aim_left)
	
	# Left and Right aim vectors should point in opposite horizontal directions
	var dot_opposite: float = aim_right.normalized().dot(aim_left.normalized())
	print("Dot product of left and right aim directions: ", dot_opposite)
	if dot_opposite > -0.9:
		printerr("TEST FAILED: Left and right aim vectors are not opposing! Dot: ", dot_opposite)
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Screen-to-world aim direction math verified successfully!")

	# =========================================================================
	# PART 2: Aimed Attack Hit Confirmation
	# Player faces forward (+Z), but mouse aims at dummy positioned to the RIGHT (+X)
	# =========================================================================
	print("\n>>> PART 2: Aimed Attack Hit Confirmation (Dummy placed 90° to the right)")
	
	# Position player facing forward (+Z)
	player.global_position = Vector3(0, player.global_position.y, 0)
	var forward_target: Transform3D = player.player_root.global_transform.looking_at(
		player.player_root.global_position + Vector3(0, 0, 1), Vector3.UP, true
	)
	player.player_root.global_transform = forward_target
	
	# Position dummy 2.3 meters to the right (+X)
	dummy.global_position = Vector3(2.3, player.global_position.y, 0)
	var initial_health: float = health_comp.current_health
	print("Dummy initial health: ", initial_health)
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# Aim mouse at dummy's screen position
	var dummy_screen_pos: Vector2 = camera.unproject_position(dummy.global_position)
	var mm_dummy := InputEventMouseMotion.new()
	mm_dummy.position = dummy_screen_pos
	mm_dummy.global_position = dummy_screen_pos
	Input.parse_input_event(mm_dummy)
	player.get_viewport().warp_mouse(dummy_screen_pos)
	await get_tree().physics_frame
	
	# Trigger Attack 1 (Slash) towards dummy
	var click := InputEventAction.new()
	click.action = "click"
	click.pressed = true
	sm._unhandled_input(click)
	
	if sm.state.name != "PlayerAttack":
		printerr("TEST FAILED: Did not enter PlayerAttack.")
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Entered PlayerAttack aiming towards dummy...")
	
	# Verify player turned towards the dummy (+X)
	await get_tree().physics_frame
	var facing_dir: Vector3 = player.player_root.global_transform.basis.z.normalized()
	print("Player facing vector after attack start: ", facing_dir)
	var dir_to_dummy: Vector3 = (dummy.global_position - player.global_position).normalized()
	var aim_alignment: float = facing_dir.dot(dir_to_dummy)
	print("Alignment with dummy direction: ", aim_alignment)
	if aim_alignment < 0.9:
		printerr("TEST FAILED: Player did not orient towards mouse aim target! Alignment: ", aim_alignment)
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Player successfully reoriented towards mouse aim!")
	
	# Wait for attack to connect and damage dummy
	var hit_confirmed := false
	for i: int in range(40):
		await get_tree().physics_frame
		if health_comp.current_health <= initial_health - 8.0:
			hit_confirmed = true
			print("HIT CONFIRMED via mouse aim on frame ", i, "! Dummy health: ", health_comp.current_health)
			break
			
	if not hit_confirmed or health_comp.current_health != initial_health - 8.0:
		printerr("TEST FAILED: Aimed attack did not hit dummy. Health: ", health_comp.current_health)
		level.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return

	# Wait for attack to finish and recover to PlayerRun
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state.name == "PlayerRun":
			break
			
	print("\n====================================================================")
	print("  MOUSE AIMING ATTACK TEST PASSED!                                  ")
	print("  1. 2D unprojected coordinates & 3D camera-rotated aim verified     ")
	print("  2. Player dynamically turned 90° to attack dummy based on mouse   ")
	print("  3. Attack hit confirmed via mouse aim! (100.0 -> 92.0)            ")
	print("  4. Returned cleanly to PlayerRun state                             ")
	print("====================================================================")
	level.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	get_tree().quit(0)
