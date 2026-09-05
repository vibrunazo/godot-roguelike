extends Node

func _ready() -> void:
	print("--- RUNNING DAMAGE FLASH & SCREEN SHAKE TEST ---")
	
	var level_scene: PackedScene = load("res://Levels/LevelTemplate.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var player: Player = level.get_node("Player") as Player
	var dummy: CollisionObject3D = (level.get_node_or_null("Enemy") if level.has_node("Enemy") else level.get_node_or_null("StaticBody3D")) as CollisionObject3D
	var dummy_health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var camera: ShakeCamera3D = player.get_node_or_null("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	var attack_comp: AttackComponent = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/ShapeCast3D/AttackComponent") as AttackComponent
	
	# ---------------------------------------------------------
	# PART 1: Node & Component Setup Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: Node & Configuration Checks")
	if camera == null:
		printerr("TEST FAILED: ShakeCamera3D not found under CameraRoot.")
		get_tree().quit(1)
		return
	camera.make_current()
	
	if player.damage_tint == null:
		printerr("TEST FAILED: damage_tint (ColorRect) reference is null on Player.")
		get_tree().quit(1)
		return
	print("DamageTint node found: ", player.damage_tint.name)
	
	if player.damage_tint.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: Expected DamageTint mouse_filter == MOUSE_FILTER_IGNORE (2), got: ", player.damage_tint.mouse_filter)
		get_tree().quit(1)
		return
	print("DamageTint mouse_filter verified (MOUSE_FILTER_IGNORE)")
	
	if not is_zero_approx(player.damage_tint.color.a):
		printerr("TEST FAILED: Expected DamageTint initial alpha == 0.0, got: ", player.damage_tint.color.a)
		get_tree().quit(1)
		return
	print("DamageTint initial color verified (alpha 0.0)")
	
	if attack_comp == null:
		printerr("TEST FAILED: AttackComponent not found on player weapon.")
		get_tree().quit(1)
		return
	if attack_comp.shake_on_damage != true:
		printerr("TEST FAILED: Expected player AttackComponent.shake_on_damage == true, got: ", attack_comp.shake_on_damage)
		get_tree().quit(1)
		return
	print("Player AttackComponent shake_on_damage verified (true)")
	
	# ---------------------------------------------------------
	# PART 2: Player Taking Damage (Red Flash + 1.0 Magnitude Shake)
	# ---------------------------------------------------------
	print("\n>>> PART 2: Testing Player Hurt Flash & Shake")
	camera.trauma = 0.0
	var initial_health: float = player.health_component.current_health
	
	# Trigger damage programmatically via health_component
	player.health_component.take_damage(5.0)
	await get_tree().process_frame
	
	print("Health after damage: ", player.health_component.current_health, " (took 5.0 damage)")
	if player.health_component.current_health != initial_health - 5.0:
		printerr("TEST FAILED: Health not reduced as expected.")
		get_tree().quit(1)
		return
		
	print("Trauma immediately after damage: ", camera.trauma)
	if camera.trauma <= 0.5:
		printerr("TEST FAILED: Camera trauma not triggered on damage. trauma: ", camera.trauma)
		get_tree().quit(1)
		return
	print("Camera trauma confirmed on hurt! (magnitude ~ 1.0)")
	
	print("DamageTint alpha immediately after hurt: ", player.damage_tint.color.a)
	if player.damage_tint.color.a < 0.1:
		printerr("TEST FAILED: DamageTint alpha did not flash red. alpha: ", player.damage_tint.color.a)
		get_tree().quit(1)
		return
	print("Red flash confirmed! Alpha flashed to: ", player.damage_tint.color.a)
	
	# Wait for 0.25s for DamageTint tween to fade back to transparent (0.2s duration)
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	
	print("DamageTint alpha after fade duration: ", player.damage_tint.color.a)
	if player.damage_tint.color.a > 0.05:
		printerr("TEST FAILED: DamageTint did not fade back to transparent. Current alpha: ", player.damage_tint.color.a)
		get_tree().quit(1)
		return
	print("DamageTint successfully faded back to transparent!")
	
	# Wait for trauma decay (0.3s duration)
	await get_tree().create_timer(0.15).timeout
	await get_tree().physics_frame
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Camera trauma did not decay to 0.0. Current: ", camera.trauma)
		get_tree().quit(1)
		return
	print("Camera trauma successfully decayed to 0.0")
	
	# ---------------------------------------------------------
	# PART 3: Player Dealing Damage (Weapon Hit -> 0.75 Magnitude Shake)
	# ---------------------------------------------------------
	print("\n>>> PART 3: Testing Weapon Hit Shake (shake_on_damage = true)")
	camera.trauma = 0.0
	var shapecast: ShapeCast3D = attack_comp.get_parent() as ShapeCast3D
	
	# First test: swing in empty air -> should NOT shake camera
	player.global_position = Vector3(50, player.global_position.y, 50)
	await get_tree().physics_frame
	shapecast.enabled = true
	attack_comp.deal_damage(8.0, Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Camera shook when no enemies were hit!")
		get_tree().quit(1)
		return
	print("Empty swing verified: no camera shake when no health component is hit.")
	
	# Second test: Position player so weapon shapecast overlaps dummy -> should shake ONCE
	player.global_position = Vector3(dummy.global_position.x, player.global_position.y, dummy.global_position.z - 1.3)
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.player_root.global_transform.looking_at(player.player_root.global_position + dir, Vector3.UP, true)
	player.player_root.global_transform = target
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	shapecast.enabled = true
	attack_comp.deal_damage(8.0, Vector3.ZERO)
	# Wait for tween to begin and apply initial .from(0.75) value
	await get_tree().process_frame
	await get_tree().process_frame
	print("Trauma after weapon deal_damage: ", camera.trauma)
	if camera.trauma <= 0.4:
		printerr("TEST FAILED: Camera trauma not triggered on weapon hit. Current: ", camera.trauma)
		get_tree().quit(1)
		return
	print("Weapon hit screen shake verified! (magnitude ~ 0.75)")
	
	# Wait for trauma to decay
	await get_tree().create_timer(0.35).timeout
	await get_tree().physics_frame
	print("Trauma after hit decay: ", camera.trauma)
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Camera trauma did not decay to 0.0 after weapon hit.")
		get_tree().quit(1)
		return
	print("Camera trauma decayed back to 0.0 successfully!")
	
	print("\n====================================================================")
	print("  ALL DAMAGE FLASH & SCREEN SHAKE TESTS PASSED!                     ")
	print("  1. DamageTint ColorRect properly configured (preset, mouse_filter)")
	print("  2. Hurt signal triggers quick_shake(1.0) & red screen flash tween ")
	print("  3. DamageTint fades back to transparent in 0.2 seconds            ")
	print("  4. AttackComponent shake_on_damage triggers quick_shake(0.75) on hit")
	print("  5. Trauma decays smoothly back to 0.0                             ")
	print("====================================================================")
	
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
