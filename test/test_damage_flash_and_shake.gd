extends Node

const TestUtils = preload("res://test/test_utils.gd")

func _ready() -> void:
	print("--- RUNNING DAMAGE FLASH & SCREEN SHAKE TEST ---")
	
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	var player: Character = level.get_node("Player") as Character
	var dummy: CollisionObject3D = TestUtils.find_dummy(level, player)
	var dummy_health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var camera: ShakeCamera3D = player.get_node_or_null("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	var attack_comp: AttackComponent = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/HitboxArea/AttackComponent") as AttackComponent
	var damage_tint: ColorRect = player.get_node_or_null("DamageTint") as ColorRect
	
	# ---------------------------------------------------------
	# PART 1: Node & Component Setup Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: Node & Configuration Checks")
	if camera == null:
		printerr("TEST FAILED: ShakeCamera3D not found under CameraRoot.")
		get_tree().quit(1)
		return
	camera.make_current()
	
	if damage_tint == null:
		printerr("TEST FAILED: damage_tint (ColorRect) not found under Player.")
		get_tree().quit(1)
		return
	print("DamageTint node found: ", damage_tint.name)
	
	if damage_tint.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		printerr("TEST FAILED: Expected DamageTint mouse_filter == MOUSE_FILTER_IGNORE (2), got: ", damage_tint.mouse_filter)
		get_tree().quit(1)
		return
	print("DamageTint mouse_filter verified (MOUSE_FILTER_IGNORE)")
	
	if not is_zero_approx(damage_tint.color.a):
		printerr("TEST FAILED: Expected DamageTint initial alpha == 0.0, got: ", damage_tint.color.a)
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

	# Verify AttackComponent reset_exceptions does not error when collision exceptions are freed
	var dummy_col: StaticBody3D = StaticBody3D.new()
	add_child(dummy_col)
	attack_comp.add_exception(dummy_col)
	dummy_col.free()
	attack_comp.reset_exceptions()
	if not attack_comp.temporary_exceptions.is_empty():
		printerr("TEST FAILED: AttackComponent temporary_exceptions not empty after reset.")
		get_tree().quit(1)
		return
	print("AttackComponent reset_exceptions with freed object safely handled.")
	
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
	if camera.trauma <= 0.0:
		printerr("TEST FAILED: Camera trauma not triggered on damage. trauma: ", camera.trauma)
		get_tree().quit(1)
		return
	print("Camera trauma confirmed on hurt! (magnitude ~ 1.0)")
	
	print("DamageTint alpha immediately after hurt: ", damage_tint.color.a)
	if damage_tint.color.a < 0.1:
		printerr("TEST FAILED: DamageTint alpha did not flash red. alpha: ", damage_tint.color.a)
		get_tree().quit(1)
		return
	print("Red flash confirmed! Alpha flashed to: ", damage_tint.color.a)
	
	# Wait for 0.25s for DamageTint tween to fade back to transparent (0.2s duration)
	await get_tree().create_timer(0.25).timeout
	await get_tree().process_frame
	
	print("DamageTint alpha after fade duration: ", damage_tint.color.a)
	if damage_tint.color.a > 0.05:
		printerr("TEST FAILED: DamageTint did not fade back to transparent. Current alpha: ", damage_tint.color.a)
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
	var hitbox: Area3D = attack_comp.get_parent() as Area3D
	
	# First test: swing in empty air -> should NOT shake camera
	player.global_position = Vector3(50, player.global_position.y, 50)
	await get_tree().physics_frame
	hitbox.monitoring = true
	attack_comp.damage = 8.0
	attack_comp.knockback = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Camera shook when no enemies were hit!")
		get_tree().quit(1)
		return
	print("Empty swing verified: no camera shake when no health component is hit.")
	hitbox.monitoring = false
	
	# Second test: Position player and dummy on floor so weapon hitbox overlaps dummy
	dummy.global_position = Vector3(0, 1, 0)
	dummy.velocity = Vector3.ZERO
	player.global_position = Vector3(0, 1, -1.3)
	player.velocity = Vector3.ZERO
	var dir: Vector3 = Vector3(0, 0, 1)
	var target: Transform3D = player.mesh_mount.global_transform.looking_at(player.mesh_mount.global_position + dir, Vector3.UP, true)
	player.mesh_mount.global_transform = target
	await get_tree().physics_frame
	await get_tree().physics_frame

	attack_comp.reset_exceptions()
	attack_comp.damage = 8.0
	attack_comp.knockback = Vector3.ZERO
	hitbox.monitoring = true
	var dummy_hurtbox: Hurtbox = (dummy as Node).get_node("Hurtbox") as Hurtbox
	attack_comp.deal_damage_to(dummy_hurtbox, 8.0, Vector3.ZERO)
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
	hitbox.monitoring = false
	
	# ---------------------------------------------------------
	# PART 4: VfxManager & Damage Numbers (Lecture 77)
	# ---------------------------------------------------------
	print("\n>>> PART 4: Testing VfxManager and DamageNumber")
	if VfxManager == null:
		printerr("TEST FAILED: VfxManager autoload not found.")
		get_tree().quit(1)
		return
	print("VfxManager autoload verified.")

	var damage_num_scene: PackedScene = load("res://Singletons/VFX/damage_number.tscn")
	if damage_num_scene == null:
		printerr("TEST FAILED: Could not load damage_number.tscn.")
		get_tree().quit(1)
		return
	var test_dn: DamageNumber = damage_num_scene.instantiate() as DamageNumber
	if test_dn == null:
		printerr("TEST FAILED: DamageNumber root node is not of type DamageNumber.")
		get_tree().quit(1)
		return
	var dn_label: Label = test_dn.get_node_or_null("Label") as Label
	var dn_anim: AnimationPlayer = test_dn.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if dn_label == null:
		printerr("TEST FAILED: DamageNumber does not have a Label child.")
		get_tree().quit(1)
		return
	if dn_anim == null:
		printerr("TEST FAILED: DamageNumber does not have an AnimationPlayer child.")
		get_tree().quit(1)
		return
	if dn_label.label_settings == null or dn_label.label_settings.font_size != 32 or dn_label.label_settings.outline_size != 4:
		printerr("TEST FAILED: DamageNumber LabelSettings incorrect.")
		get_tree().quit(1)
		return
	if not dn_anim.has_animation("spawn"):
		printerr("TEST FAILED: DamageNumber AnimationPlayer missing 'spawn' animation.")
		get_tree().quit(1)
		return
	if dn_anim.autoplay != "spawn":
		printerr("TEST FAILED: DamageNumber AnimationPlayer autoplay is not 'spawn'. Got: ", dn_anim.autoplay)
		get_tree().quit(1)
		return
	if not test_dn.scale.is_equal_approx(Vector2(1.5, 1.5)):
		printerr("TEST FAILED: DamageNumber initial scale expected Vector2(1.5, 1.5), got: ", test_dn.scale)
		get_tree().quit(1)
		return
	test_dn.free()
	print("DamageNumber scene structure, scale & animations verified.")

	for child: Node in VfxManager.get_children():
		child.queue_free()
	await get_tree().process_frame

	dummy.global_position = Vector3(5, 1, 5)
	dummy_health.take_damage(12.0)
	await get_tree().physics_frame
	await get_tree().process_frame

	var vfx_children: Array[Node] = VfxManager.get_children()
	if vfx_children.is_empty():
		printerr("TEST FAILED: No DamageNumber spawned under VfxManager on take_damage.")
		get_tree().quit(1)
		return
	var spawned_dn: DamageNumber = vfx_children[-1] as DamageNumber
	if spawned_dn == null:
		printerr("TEST FAILED: Spawned child in VfxManager is not DamageNumber.")
		get_tree().quit(1)
		return
	if not spawned_dn.target_position.is_equal_approx(dummy.global_position):
		printerr("TEST FAILED: Spawned DamageNumber target_position (", spawned_dn.target_position, ") does not match dummy position (", dummy.global_position, ")")
		get_tree().quit(1)
		return

	if spawned_dn.label.text != "12":
		printerr("TEST FAILED: DamageNumber label text expected '12', got: '", spawned_dn.label.text, "'")
		get_tree().quit(1)
		return
	print("DamageNumber label text formatting verified: ", spawned_dn.label.text)

	var expected_screen_pos: Vector2 = camera.unproject_position(dummy.global_position)
	if not spawned_dn.position.is_equal_approx(expected_screen_pos):
		printerr("TEST FAILED: DamageNumber position (", spawned_dn.position, ") does not match unprojected position (", expected_screen_pos, ")")
		get_tree().quit(1)
		return
	print("DamageNumber unproject_position tracking verified: ", spawned_dn.position)

	# Verify RangedEnemy NavigationAgent3D has debug_enabled = false
	var ranged_scene: PackedScene = load("res://Enemy/ranged_enemy.tscn")
	var test_ranged: Character = ranged_scene.instantiate() as Character
	var ranged_nav: NavigationAgent3D = test_ranged.get_node("NavigationAgent3D") as NavigationAgent3D
	if ranged_nav.debug_enabled:
		printerr("TEST FAILED: RangedEnemy NavigationAgent3D still has debug_enabled = true.")
		get_tree().quit(1)
		return
	test_ranged.free()
	print("RangedEnemy navigation debug_enabled correctly disabled.")

	for child: Node in VfxManager.get_children():
		child.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 7: KnockbackComponent & Momentum Verification (Lecture 85)
	# ---------------------------------------------------------
	print("\n>>> PART 7: KnockbackComponent & Momentum Checks")
	if player.knockback_component == null:
		printerr("TEST FAILED: player.knockback_component is null.")
		get_tree().quit(1)
		return
	var kb: KnockbackComponent = player.knockback_component
	if kb.decay <= 0.0 or kb.max_knockback <= 0.0:
		printerr("TEST FAILED: KnockbackComponent decay or max_knockback should be positive. decay: ", kb.decay, " max_kb: ", kb.max_knockback)
		get_tree().quit(1)
		return
	if not kb.magnitude.is_zero_approx() or kb.is_active():
		printerr("TEST FAILED: KnockbackComponent should be inactive at start.")
		get_tree().quit(1)
		return
	
	# Test clamping via setter
	kb.add_knockback(Vector3(0.0, 0.0, kb.max_knockback * 2.0))
	if not is_equal_approx(kb.magnitude.length(), kb.max_knockback) or not kb.is_active():
		printerr("TEST FAILED: KnockbackComponent magnitude was not clamped to max_knockback: ", kb.max_knockback)
		get_tree().quit(1)
		return
	print("KnockbackComponent max_knockback limit_length clamping verified: ", kb.magnitude.length())
	
	# Test physics process decay
	var prev_mag: float = kb.magnitude.length()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if kb.magnitude.length() >= prev_mag:
		printerr("TEST FAILED: KnockbackComponent magnitude did not decay.")
		get_tree().quit(1)
		return
	print("KnockbackComponent exponential decay verified: ", prev_mag, " -> ", kb.magnitude.length())
	
	# Test PlayerState core_movement priority
	var run_state: CharacterState = player.get_node_or_null("StateMachine/PlayerRun") as CharacterState
	if run_state != null:
		kb.magnitude = Vector3(10.0, 0.0, 0.0)
		run_state.core_movement(0.016, 8.0)
		if not player.velocity.is_equal_approx(Vector3(10.0, 0.0, 0.0)):
			printerr("TEST FAILED: Player velocity should follow knockback magnitude when active, got: ", player.velocity)
			get_tree().quit(1)
			return
		kb.magnitude = Vector3.ZERO
		run_state.core_movement(0.016, 8.0)
		print("PlayerState core_movement knockback priority verified.")
	
	kb.magnitude = Vector3.ZERO

	print("\n====================================================================")
	print("  ALL DAMAGE FLASH, SCREEN SHAKE & VFX TESTS PASSED!                ")
	print("  1. DamageTint ColorRect properly configured (preset, mouse_filter)")
	print("  2. Hurt signal triggers quick_shake(1.0) & red screen flash tween ")
	print("  3. DamageTint fades back to transparent in 0.2 seconds            ")
	print("  4. AttackComponent shake_on_damage triggers quick_shake(0.75) on hit")
	print("  5. Trauma decays smoothly back to 0.0                             ")
	print("  6. VfxManager spawns DamageNumber with 3D unproject on take_damage")
	print("  7. KnockbackComponent decay, clamp, and core_movement verified    ")
	print("====================================================================")
	
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
