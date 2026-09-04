extends Node

func _ready() -> void:
	print("--- RUNNING SHAKE CAMERA TEST ---")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Player = player_scene.instantiate() as Player
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
	
	print("\n====================================================================")
	print("  ALL SHAKE CAMERA TESTS PASSED!                                    ")
	print("  1. ShakeCamera3D configured with FastNoiseLite and offset_scale   ")
	print("  2. Zero trauma results in zero camera offsets                     ")
	print("  3. quick_shake produces dynamic h_offset & v_offset via noise      ")
	print("  4. Trauma smoothly decays back to 0 via Tween                     ")
	print("====================================================================")
	
	player.queue_free()
	await get_tree().physics_frame
	get_tree().quit(0)
