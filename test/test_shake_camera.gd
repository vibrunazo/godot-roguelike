extends Node

func _ready() -> void:
	print("--- RUNNING SHAKE CAMERA TEST ---")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	player.position = Vector3(0.0, 3.0, 0.0)
	add_child(player)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# 1. Verify ShakeCamera3D node exists
	var camera: ShakeCamera3D = player.get_node_or_null("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	if camera == null:
		printerr("TEST FAILED: ShakeCamera3D not found under CameraRoot in player.tscn")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("ShakeCamera3D found with offset_scale: ", camera.offset_scale)
	
	# 2. Verify exported variables
	if camera.noise == null:
		printerr("TEST FAILED: ShakeCamera3D noise resource is null.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Noise resource verified: ", camera.noise.get_class(), " (type: ", camera.noise.noise_type, ")")
	
	if camera.offset_scale <= 0.0:
		printerr("TEST FAILED: Expected positive offset_scale, got: ", camera.offset_scale)
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Offset scale verified: ", camera.offset_scale)
	if not await _verify_camera_follow(player):
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	
	# 3. Verify zero trauma gives zero offsets
	camera.trauma = 0.0
	await get_tree().physics_frame
	if camera.h_offset != 0.0 or camera.v_offset != 0.0:
		printerr("TEST FAILED: Expected 0 offsets when trauma is 0. Got h: ", camera.h_offset, " v: ", camera.v_offset)
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Zero trauma test passed: h_offset = 0.0, v_offset = 0.0")

	# 3b. Verify physics processing is disabled while idle (TODO #3 optimization)
	if camera.is_physics_processing():
		printerr("TEST FAILED: Expected physics processing disabled at zero trauma.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Idle optimization verified: physics processing disabled at zero trauma.")

	# 3c. Verify direct trauma assignment gates physics processing via setter
	camera.trauma = 0.5
	if not camera.is_physics_processing():
		printerr("TEST FAILED: Setting trauma > 0 did not enable physics processing.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	camera.trauma = 0.0
	await get_tree().physics_frame
	if camera.is_physics_processing():
		printerr("TEST FAILED: Setting trauma to 0 did not disable physics processing.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	if camera.h_offset != 0.0 or camera.v_offset != 0.0:
		printerr("TEST FAILED: Setting trauma to 0 did not reset offsets.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Trauma setter gating verified: enabled above 0, disabled with offsets reset at 0.")
	
	# 4. Verify quick_shake sets trauma and applies offsets
	camera.quick_shake(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	print("After quick_shake(1.0), trauma: ", camera.trauma)
	if camera.trauma <= 0.0:
		printerr("TEST FAILED: quick_shake(1.0) did not increase trauma.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	if not camera.is_physics_processing():
		printerr("TEST FAILED: quick_shake(1.0) did not enable physics processing.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("quick_shake enabled physics processing for shake duration.")

	await get_tree().physics_frame
	await get_tree().physics_frame
	print("Offsets during shake: h_offset = ", camera.h_offset, ", v_offset = ", camera.v_offset)
	if camera.h_offset == 0.0 and camera.v_offset == 0.0:
		printerr("TEST FAILED: Offsets remained 0 during shake with active trauma.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Shake offsets active and fluctuating correctly!")
	
	# 5. Wait for tween to decay trauma back to 0.0 (0.3s duration)
	await get_tree().create_timer(0.35).timeout
	await get_tree().physics_frame
	print("Trauma after decay duration: ", camera.trauma)
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Trauma did not decay back to 0.0. Current: ", camera.trauma)
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Trauma successfully decayed to 0.0!")
	if camera.is_physics_processing():
		printerr("TEST FAILED: Physics processing still enabled after trauma decayed to 0.0.")
		player.queue_free()
		await get_tree().physics_frame
		get_tree().quit(1)
		return
	print("Physics processing disabled again after shake completed!")
	
	print("\n====================================================================")
	print("  ALL SHAKE CAMERA TESTS PASSED!                                    ")
	print("  1. ShakeCamera3D configured with FastNoiseLite and offset_scale   ")
	print("  2. Zero trauma results in zero camera offsets                     ")
	print("  3. quick_shake produces dynamic h_offset & v_offset via noise      ")
	print("  4. Trauma smoothly decays back to 0 via Tween                     ")
	print("  5. Physics processing disabled at idle, gated by trauma setter   ")
	print("  6. Camera follows upward but never below its initial Y          ")
	print("====================================================================")
	
	player.queue_free()
	await get_tree().physics_frame
	get_tree().quit(0)


func _verify_camera_follow(player: Character) -> bool:
	var camera_rig: Node3D = player.get_node("CameraRoot")
	var original_position: Vector3 = player.global_position
	var initial_camera_y: float = camera_rig.global_position.y
	player.process_mode = Node.PROCESS_MODE_DISABLED
	camera_rig.process_mode = Node.PROCESS_MODE_ALWAYS

	var lower_position: Vector3 = Vector3(original_position.x + 3.0, initial_camera_y - 4.0, original_position.z - 2.0)
	player.global_position = lower_position
	await get_tree().process_frame
	await get_tree().process_frame
	if not camera_rig.global_position.is_equal_approx(Vector3(lower_position.x, initial_camera_y, lower_position.z)):
		printerr("TEST FAILED: Camera left its initial Y floor or stopped following horizontally: ", camera_rig.global_position)
		player.process_mode = Node.PROCESS_MODE_INHERIT
		return false

	var upper_position: Vector3 = Vector3(original_position.x - 2.0, initial_camera_y + 4.0, original_position.z + 1.0)
	player.global_position = upper_position
	await get_tree().process_frame
	await get_tree().process_frame
	if not camera_rig.global_position.is_equal_approx(upper_position):
		printerr("TEST FAILED: Camera did not freely follow above its initial Y: ", camera_rig.global_position)
		player.process_mode = Node.PROCESS_MODE_INHERIT
		return false

	var second_lower_position: Vector3 = Vector3(original_position.x, initial_camera_y - 6.0, original_position.z)
	player.global_position = second_lower_position
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_equal_approx(camera_rig.global_position.y, initial_camera_y):
		printerr("TEST FAILED: Camera retained an upper high-water mark instead of using its initial Y floor: ", camera_rig.global_position.y)
		player.process_mode = Node.PROCESS_MODE_INHERIT
		return false

	player.global_position = original_position
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().process_frame
	print("Camera vertical follow verified: upward freely, downward clamped to initial Y.")
	return true
