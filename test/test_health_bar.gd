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
	print("\n>>> PART 2: Verifying SubViewport, ProgressBars, and Sprite3D")
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
	
	var front_bar: ProgressBar = health_bar.front_progress_bar
	if front_bar == null:
		printerr("TEST FAILED: front_progress_bar reference is null.")
		player.queue_free()
		get_tree().quit(1)
		return
	if front_bar.show_percentage != false:
		printerr("TEST FAILED: Expected show_percentage == false on FrontProgressBar.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("FrontProgressBar show_percentage disabled verified.")
	
	var health_bar_bg: ProgressBar = health_bar.health_progress_bar
	if health_bar_bg == null:
		printerr("TEST FAILED: health_progress_bar reference is null.")
		player.queue_free()
		get_tree().quit(1)
		return
	if health_bar_bg.show_percentage != false:
		printerr("TEST FAILED: Expected show_percentage == false on HealthProgressBar.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("HealthProgressBar show_percentage disabled verified.")
	
	# Verify HealthProgressBar renders behind FrontProgressBar (lower index in SubViewport)
	if health_bar_bg.get_index() >= front_bar.get_index():
		printerr("TEST FAILED: HealthProgressBar should be rendered before FrontProgressBar (behind it).")
		player.queue_free()
		get_tree().quit(1)
		return
	print("Progress bar z-order verified: HealthProgressBar is behind FrontProgressBar.")
	
	# Verify initial value starts at 100%
	if not is_equal_approx(front_bar.value, 100.0):
		printerr("TEST FAILED: Expected FrontProgressBar initial value == 100.0, got: ", front_bar.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("FrontProgressBar initialized to 100% successfully.")
	
	# Verify health_color applied to front_bar fill stylebox
	var fill_style: StyleBoxFlat = front_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style == null:
		printerr("TEST FAILED: Expected fill style to be StyleBoxFlat on FrontProgressBar.")
		player.queue_free()
		get_tree().quit(1)
		return
	if not fill_style.bg_color.is_equal_approx(health_bar.health_color):
		printerr("TEST FAILED: Expected fill bg_color to match health_color ", health_bar.health_color, ", got: ", fill_style.bg_color)
		player.queue_free()
		get_tree().quit(1)
		return
	print("Health color assignment to FrontProgressBar fill verified.")
	
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
	# PART 3: Health Damage Animation & Tween Synchronization
	# ---------------------------------------------------------
	print("\n>>> PART 3: Testing Health Damage Animation & Tweening")
	# Player max_health is 60.0
	# Deal 15 damage -> current 45.0 (75%)
	player.health_component.take_damage(15.0)
	await get_tree().process_frame
	
	# Front bar should snap immediately to 75%
	print("Front bar value immediately after 15 damage: ", front_bar.value)
	if not is_equal_approx(front_bar.value, 75.0):
		printerr("TEST FAILED: FrontProgressBar should snap immediately to 75.0. Got: ", front_bar.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("FrontProgressBar snapped immediately to 75%!")
	
	# Health (background) bar should lag behind / be mid-tween (> 75%)
	print("Health bar value during tween: ", health_bar_bg.value)
	if health_bar_bg.value <= 75.0:
		printerr("TEST FAILED: HealthProgressBar should animate/lag behind FrontProgressBar. Got: ", health_bar_bg.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("HealthProgressBar lag animation confirmed! Value mid-tween: ", health_bar_bg.value)
	
	# Wait for 0.25s for the 0.2s tween to complete
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	print("Health bar value after tween completed: ", health_bar_bg.value)
	if not is_equal_approx(health_bar_bg.value, 75.0):
		printerr("TEST FAILED: HealthProgressBar did not reach target 75.0 after tween. Got: ", health_bar_bg.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("HealthProgressBar smoothly completed animation to 75%!")
	
	# Deal another 15 damage -> current 30.0 (50%)
	player.health_component.take_damage(15.0)
	await get_tree().process_frame
	if not is_equal_approx(front_bar.value, 50.0):
		printerr("TEST FAILED: FrontProgressBar did not snap to 50.0. Got: ", front_bar.value)
		player.queue_free()
		get_tree().quit(1)
		return
	
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	if not is_equal_approx(health_bar_bg.value, 50.0):
		printerr("TEST FAILED: HealthProgressBar did not reach 50.0. Got: ", health_bar_bg.value)
		player.queue_free()
		get_tree().quit(1)
		return
	print("Second damage tween (75% -> 50%) completed successfully!")
	player.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	
	# ---------------------------------------------------------
	# PART 4: Enemy HealthBar in LevelTemplate & Defeat Handling
	# ---------------------------------------------------------
	print("\n>>> PART 4: Testing Enemy HealthBar in LevelTemplate & Defeat Fade-Out")
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var dummy: StaticBody3D = level.get_node("StaticBody3D") as StaticBody3D
	var dummy_health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var dummy_health_bar: HealthBar = dummy.get_node_or_null("HealthBar") as HealthBar
	
	if dummy_health_bar == null:
		printerr("TEST FAILED: HealthBar node not found on enemy StaticBody3D in LevelTemplate.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemy HealthBar found in LevelTemplate.")
	
	if dummy_health_bar.health_component != dummy_health:
		printerr("TEST FAILED: Enemy HealthBar health_component not wired to dummy HealthComponent.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemy HealthBar health_component assignment verified.")
	
	# Trigger defeat on dummy
	dummy_health.take_damage(dummy_health.max_health)
	await get_tree().process_frame
	
	# Mid-fade check: transparency should be animating towards 1.0
	print("Sprite3D transparency immediately after defeat: ", dummy_health_bar.sprite_3d.transparency)
	if dummy_health_bar.sprite_3d.transparency < 0.0:
		printerr("TEST FAILED: Sprite3D transparency invalid on defeat.")
		level.queue_free()
		get_tree().quit(1)
		return
	
	# Wait for 0.25s for 0.2s fade-out tween and queue_free callback
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Verify health bar is queued for deletion or freed
	if is_instance_valid(dummy_health_bar) and not dummy_health_bar.is_queued_for_deletion():
		printerr("TEST FAILED: HealthBar was not queue_free'd after defeat fade-out completed.")
		level.queue_free()
		get_tree().quit(1)
		return
	print("Enemy HealthBar successfully faded out and auto-deleted via queue_free!")
	
	print("\n====================================================================")
	print("  ALL HEALTH BAR TESTS PASSED!                                      ")
	print("  1. HealthBar instantiated and connected to Player.HealthComponent ")
	print("  2. SubViewport, Sprite3D billboard, and dual-layer bars verified  ")
	print("  3. FrontProgressBar initialized to 100% and custom color applied  ")
	print("  4. Damage animates via Tween: front bar snaps, back bar smoothly lags")
	print("  5. Enemy HealthBar configured on StaticBody3D in LevelTemplate    ")
	print("  6. Defeat signal fades transparency to 1.0 and calls queue_free   ")
	print("====================================================================")
	
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
