extends Node3D

func _ready() -> void:
	print("\n--- RUNNING FIRE TRAP HAZARD TEST ---")

	var trap_scene: PackedScene = load("res://Hazards/fire_trap.tscn")
	if trap_scene == null:
		printerr("TEST FAILED: Could not load res://Hazards/fire_trap.tscn")
		get_tree().quit(1)
		return

	# Floor for characters to stand on
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 1.0, 20.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	add_child(floor_body)

	var trap: FireTrap = trap_scene.instantiate() as FireTrap
	add_child(trap)
	trap.global_position = Vector3.ZERO

	await get_tree().physics_frame
	await get_tree().physics_frame

	# ---------------------------------------------------------
	# PART 1: Node & Configuration Checks
	# ---------------------------------------------------------
	print("\n>>> PART 1: Node & Configuration Checks")
	if trap.damage_hitbox == null:
		printerr("TEST FAILED: DamageHitbox node not found.")
		get_tree().quit(1)
		return

	if trap.damage_hitbox.collision_mask != 192:
		printerr("TEST FAILED: Expected DamageHitbox collision_mask == 192, got: ", trap.damage_hitbox.collision_mask)
		get_tree().quit(1)
		return

	if not trap.damage_hitbox.monitoring:
		printerr("TEST FAILED: DamageHitbox should be monitoring = true initially (always active).")
		get_tree().quit(1)
		return
	print("DamageHitbox mask (192) and always-active monitoring verified.")

	if trap.attack_component == null:
		printerr("TEST FAILED: AttackComponent not found on DamageHitbox.")
		get_tree().quit(1)
		return

	if trap.attack_component.damage != 5.0:
		printerr("TEST FAILED: Expected AttackComponent.damage == 5.0, got: ", trap.attack_component.damage)
		get_tree().quit(1)
		return

	if trap.attack_component.rehit_interval != 2.0:
		printerr("TEST FAILED: Expected AttackComponent.rehit_interval == 2.0, got: ", trap.attack_component.rehit_interval)
		get_tree().quit(1)
		return
	print("AttackComponent damage (5.0) and rehit_interval (2.0s) verified.")

	# ---------------------------------------------------------
	# PART 2: Dynamic Sizing Checks
	# ---------------------------------------------------------
	print("\n>>> PART 2: Dynamic Sizing Verification")
	trap.set_trap_size(Vector2(3.0, 2.0))
	var box_shape: BoxShape3D = trap.collision_shape.shape as BoxShape3D
	if box_shape.size != Vector3(3.0, 1.0, 2.0):
		printerr("TEST FAILED: CollisionShape size not updated properly. Got: ", box_shape.size)
		get_tree().quit(1)
		return

	var mesh_box: BoxMesh = trap.ground_mesh.mesh as BoxMesh
	if mesh_box.size != Vector3(3.0, 0.02, 2.0):
		printerr("TEST FAILED: GroundMesh size not updated properly. Got: ", mesh_box.size)
		get_tree().quit(1)
		return

	var part_mat: ParticleProcessMaterial = trap.particles.process_material as ParticleProcessMaterial
	if part_mat.emission_box_extents != Vector3(3.0 * 0.42, 0.05, 2.0 * 0.42):
		printerr("TEST FAILED: Particle emission extents not updated properly. Got: ", part_mat.emission_box_extents)
		get_tree().quit(1)
		return
	print("Dynamic sizing properly scaled hitbox, mesh, and particle emission volume.")

	# Reset back to default 1.0 x 1.0 for gameplay test
	trap.set_trap_size(Vector2(1.0, 1.0))

	# ---------------------------------------------------------
	# PART 3: Instant Contact Damage & Lingering Interval (Enemy)
	# ---------------------------------------------------------
	print("\n>>> PART 3: Instant Contact Damage & Lingering Re-Hit Interval (Enemy)")
	var enemy_scene: PackedScene = load("res://Enemy/melee_enemy.tscn")
	var enemy: Character = enemy_scene.instantiate() as Character
	add_child(enemy)
	enemy.global_position = Vector3(0.0, 1.0, 0.0)

	var enemy_health: HealthComponent = enemy.get_node("HealthComponent") as HealthComponent
	var initial_hp: float = enemy_health.current_health

	# Wait a couple physics frames for instant contact damage
	for i: int in range(3):
		await get_tree().physics_frame

	if enemy_health.current_health >= initial_hp:
		printerr("TEST FAILED: Enemy did not take immediate damage on contact with fire trap!")
		get_tree().quit(1)
		return
	print("Instant touch damage confirmed on first contact! HP: ", initial_hp, " -> ", enemy_health.current_health)

	# Verify enemy is not hit again within 0.5s (EnemyStun completes and enemy is free to move)
	var hp_after_first_hit: float = enemy_health.current_health
	for i: int in range(30): # ~0.5s at 60 FPS
		await get_tree().physics_frame
		if enemy_health.current_health < hp_after_first_hit:
			printerr("TEST FAILED: Enemy took premature lingering damage! Stunlock prevention violated.")
			get_tree().quit(1)
			return
	print("Stunlock prevention verified: No premature damage within 0.5s.")

	# Fast-forward / wait for 2.0s damage interval to trigger second tick
	# 2.0s = ~120 frames. We already waited ~30 frames. Wait another 100 frames (~1.65s).
	var second_hit := false
	for i: int in range(110):
		await get_tree().physics_frame
		if enemy_health.current_health < hp_after_first_hit:
			second_hit = true
			break

	if not second_hit:
		printerr("TEST FAILED: Lingering enemy did not receive second damage tick after 2.0s interval! HP: ", enemy_health.current_health)
		get_tree().quit(1)
		return
	print("Lingering re-hit tick confirmed after 2.0s interval! HP: ", hp_after_first_hit, " -> ", enemy_health.current_health)

	# Move enemy away
	enemy.global_position = Vector3(-20.0, 1.0, -20.0)

	# ---------------------------------------------------------
	# PART 4: Player Instant Touch Damage
	# ---------------------------------------------------------
	print("\n>>> PART 4: Player Instant Touch Damage")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)

	var player_health: HealthComponent = player.get_node("HealthComponent") as HealthComponent
	var initial_player_hp: float = player_health.current_health

	for i: int in range(3):
		await get_tree().physics_frame

	if player_health.current_health >= initial_player_hp:
		printerr("TEST FAILED: Player did not take instant contact damage from fire trap!")
		get_tree().quit(1)
		return
	print("Player instant touch damage confirmed! HP: ", initial_player_hp, " -> ", player_health.current_health)

	player.global_position = Vector3(20.0, 1.0, 20.0)

	# ---------------------------------------------------------
	# PART 5: Configurable Duration & Extinction
	# ---------------------------------------------------------
	print("\n>>> PART 5: Configurable Duration & Dynamic Extinction")
	var timed_trap: FireTrap = trap_scene.instantiate() as FireTrap
	timed_trap.duration = 0.2
	add_child(timed_trap)
	timed_trap.global_position = Vector3(5.0, 0.0, 5.0)

	await get_tree().create_timer(0.35).timeout

	if not timed_trap.is_extinguished():
		printerr("TEST FAILED: Timed trap did not extinguish after duration expired.")
		get_tree().quit(1)
		return

	if timed_trap.damage_hitbox.monitoring:
		printerr("TEST FAILED: Extinguished trap hitbox is still monitoring.")
		get_tree().quit(1)
		return

	if timed_trap.particles.emitting:
		printerr("TEST FAILED: Extinguished trap particles are still emitting.")
		get_tree().quit(1)
		return
	print("Dynamic duration expiration and extinction verified.")

	print("\n====================================================")
	print("  ALL FIRE TRAP HAZARD TESTS PASSED!")
	print("  1. Always-active monitoring & collision masks verified")
	print("  2. Dynamic sizing properly scales hitbox, mesh, and VFX")
	print("  3. Instant contact damage works immediately on touch")
	print("  4. 2.0s lingering interval prevents permanent stunlock")
	print("  5. Both players and enemies receive fire damage")
	print("  6. Configurable duration extinguishes dynamic spawns")
	print("====================================================")
	get_tree().quit(0)
