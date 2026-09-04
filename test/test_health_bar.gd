extends Node

func _ready() -> void:
	print("--- RUNNING HEALTH BAR TEST ---")
	
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Player = player_scene.instantiate() as Player
	add_child(player)
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# ---------------------------------------------------------
	# PART 1: Node & Component Setup Verification on Player
	# ---------------------------------------------------------
	print("\n>>> PART 1: Verifying HealthBar Node on Player")
	var health_bar: HealthBar = player.get_node_or_null("HealthBar") as HealthBar
	if health_bar == null:
		printerr("TEST FAILED: HealthBar node not found on Player.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("HealthBar found on Player.")
	
	# Check health_component assignment
	if health_bar.health_component != player.health_component:
		printerr("TEST FAILED: HealthBar health_component not assigned to Player.HealthComponent.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("HealthBar health_component assignment verified.")
	
	# ---------------------------------------------------------
	# PART 2: Scene Internal Structure & Properties
	# ---------------------------------------------------------
	print("\n>>> PART 2: Verifying SubViewport, ProgressBar, and Sprite3D")
	var sub_viewport: SubViewport = health_bar.get_node_or_null("SubViewport") as SubViewport
	if sub_viewport == null:
		printerr("TEST FAILED: SubViewport not found under HealthBar.")
		player.queue_free()
		get_tree().quit(1)
		return
	if sub_viewport.size.x <= 0 or sub_viewport.size.y <= 0:
		printerr("TEST FAILED: SubViewport has non-positive size: ", sub_viewport.size)
		player.queue_free()
		get_tree().quit(1)
		return
	print("SubViewport valid dimensions verified.")
	
	var progress_bar: ProgressBar = health_bar.front_progress_bar
	if progress_bar == null:
		printerr("TEST FAILED: front_progress_bar reference is null.")
		player.queue_free()
		get_tree().quit(1)
		return
	if progress_bar.show_percentage != false:
		printerr("TEST FAILED: Expected show_percentage == false on FrontProgressBar.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("ProgressBar show_percentage disabled verified.")
	
	var sprite: Sprite3D = health_bar.get_node_or_null("Sprite3D") as Sprite3D
	if sprite == null:
		printerr("TEST FAILED: Sprite3D not found under HealthBar.")
		player.queue_free()
		get_tree().quit(1)
		return
	if sprite.billboard != BaseMaterial3D.BILLBOARD_ENABLED:
		printerr("TEST FAILED: Expected Sprite3D billboard == BILLBOARD_ENABLED (1), got: ", sprite.billboard)
		player.queue_free()
		get_tree().quit(1)
		return
	print("Sprite3D billboard enabled verified.")
	
	if not (sprite.texture is ViewportTexture):
		printerr("TEST FAILED: Expected Sprite3D texture to be ViewportTexture, got: ", sprite.texture)
		player.queue_free()
		get_tree().quit(1)
		return
	print("Sprite3D ViewportTexture verified.")
	
	# ---------------------------------------------------------
	# PART 3: Dynamic Health Component Synchronization
	# ---------------------------------------------------------
	print("\n>>> PART 3: Testing Real-time Health Percentage Updates")
	# Player max_health is 60.0
	# Deal 15 damage -> current 45.0 (75%)
	player.health_component.take_damage(15.0)
	await get_tree().process_frame
	print("After 15.0 damage, current_health: ", player.health_component.current_health, ", progress_bar value: ", progress_bar.value)
	if not is_equal_approx(progress_bar.value, 75.0):
		printerr("TEST FAILED: Expected progress_bar value == 75.0, got: ", progress_bar.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("75% health bar update verified!")
	
	# Deal another 15 damage -> current 30.0 (50%)
	player.health_component.take_damage(15.0)
	await get_tree().process_frame
	print("After another 15.0 damage, current_health: ", player.health_component.current_health, ", progress_bar value: ", progress_bar.value)
	if not is_equal_approx(progress_bar.value, 50.0):
		printerr("TEST FAILED: Expected progress_bar value == 50.0, got: ", progress_bar.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("50% health bar update verified!")
	
	# Test standalone calculation with 15.0 health (15 / 60 * 100 = 25%)
	health_bar.update_health_value(15.0)
	print("After 15.0 hp update, progress_bar.value: ", progress_bar.value)
	if not is_equal_approx(progress_bar.value, 25.0):
		printerr("TEST FAILED: Standalone update calculation failed. Expected 25.0, got: ", progress_bar.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("Arbitrary health value calculation verified!")
	
	print("\n====================================================================")
	print("  ALL HEALTH BAR TESTS PASSED!                                      ")
	print("  1. HealthBar instantiated and connected to Player.HealthComponent ")
	print("  2. SubViewport and Sprite3D configured with billboard enabled     ")
	print("  3. FrontProgressBar show_percentage disabled                      ")
	print("  4. Signal connection updates health percentage accurately in real time")
	print("====================================================================")
	
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
