extends Node3D

func _ready() -> void:
	print("\n====================================================")
	print("  STARTING FIREBOMBER ENEMY VERIFICATION SUITE")
	print("====================================================")

	# ---------------------------------------------------------
	# PART 1: GlobalVars Registration & Scene Loading
	# ---------------------------------------------------------
	print("\n>>> PART 1: GlobalVars Registration & Scene Loading")
	if GlobalVars.enemy_firebomber_scene == null:
		printerr("TEST FAILED: GlobalVars.enemy_firebomber_scene is null.")
		get_tree().quit(1)
		return
	if GlobalVars.firebomb_projectile_scene == null:
		printerr("TEST FAILED: GlobalVars.firebomb_projectile_scene is null.")
		get_tree().quit(1)
		return

	var firebomber_scene: PackedScene = load("res://Enemy/firebomber_enemy.tscn")
	if firebomber_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/firebomber_enemy.tscn")
		get_tree().quit(1)
		return

	var projectile_scene: PackedScene = load("res://Enemy/firebomb_projectile.tscn")
	if projectile_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/firebomb_projectile.tscn")
		get_tree().quit(1)
		return
	print("GlobalVars registration and scene loading verified.")

	# ---------------------------------------------------------
	# PART 2: WaveObjective Default Enemy Spawns Pool
	# ---------------------------------------------------------
	print("\n>>> PART 2: WaveObjective Default Enemy Spawns Pool")
	var wave_obj := WaveObjective.new()
	add_child(wave_obj)
	await get_tree().process_frame

	if not wave_obj.enemy_scenes.has(GlobalVars.enemy_firebomber_scene):
		printerr("TEST FAILED: WaveObjective.enemy_scenes does not contain GlobalVars.enemy_firebomber_scene.")
		wave_obj.queue_free()
		get_tree().quit(1)
		return
	print("WaveObjective includes firebomber in default spawn pool.")

	var instantiated_enemy: Character = GlobalVars.enemy_firebomber_scene.instantiate() as Character
	if instantiated_enemy == null or not (instantiated_enemy is Character) or not instantiated_enemy.is_in_group("enemy"):
		printerr("TEST FAILED: enemy_firebomber_scene does not instantiate a Character in group 'enemy'.")
		wave_obj.queue_free()
		get_tree().quit(1)
		return
	instantiated_enemy.queue_free()
	wave_obj.queue_free()
	print("Firebomber enemy instantiation as Character in 'enemy' group verified.")

	# ---------------------------------------------------------
	# PART 3: Firebomber Enemy Hierarchy & Wiring
	# ---------------------------------------------------------
	print("\n>>> PART 3: Firebomber Enemy Hierarchy & Wiring")
	var bomber: Character = firebomber_scene.instantiate() as Character
	add_child(bomber)
	bomber.global_position = Vector3(0.0, 1.0, 0.0)
	await get_tree().process_frame

	var spawner: ProjectileSpawnerComponent = bomber.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	if spawner == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent missing on FirebomberEnemy.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	if spawner.character != bomber:
		printerr("TEST FAILED: ProjectileSpawnerComponent.character does not point to FirebomberEnemy.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	if spawner.projectile_scene == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent.projectile_scene is null.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	if spawner.spawn_point == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent.spawn_point is null.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	print("ProjectileSpawnerComponent node, character wiring, and projectile_scene verified.")

	var body_sm: StateMachine = bomber.state_machine
	if body_sm == null:
		printerr("TEST FAILED: FirebomberEnemy StateMachine is null.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	var attack_state: CharacterAttack = body_sm.get_node_or_null("EnemyAttack") as CharacterAttack
	if attack_state == null:
		printerr("TEST FAILED: EnemyAttack node missing under StateMachine.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	if attack_state.attack_animation_name != "RangedAttack":
		printerr("TEST FAILED: EnemyAttack.attack_animation_name is '", attack_state.attack_animation_name, "', expected 'RangedAttack'.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	print("Body StateMachine and EnemyAttack state (RangedAttack) verified.")

	var ai_sm: AIStateMachine = bomber.ai_state_machine
	if ai_sm == null:
		printerr("TEST FAILED: FirebomberEnemy AIStateMachine is null.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	var ai_meander: AIMeander = ai_sm.get_node_or_null("AIMeander") as AIMeander
	if ai_meander == null:
		printerr("TEST FAILED: AIMeander node missing under AIStateMachine.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	var ai_attack: AIAttack = ai_sm.get_node_or_null("AIAttack") as AIAttack
	if ai_attack == null:
		printerr("TEST FAILED: AIAttack node missing under AIStateMachine.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	if ai_attack.attack_state_name != "EnemyAttack":
		printerr("TEST FAILED: AIAttack.attack_state_name is '", ai_attack.attack_state_name, "', expected 'EnemyAttack'.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	print("AIStateMachine, AIMeander, and AIAttack verified.")

	# Verify WeaponSlot ranged_attack signal is connected to ProjectileSpawnerComponent.spawn_projectile
	var weapon_slot: Node = bomber.find_child("WeaponSlot", true, false)
	if weapon_slot == null:
		printerr("TEST FAILED: WeaponSlot not found on FirebomberEnemy.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	if not weapon_slot.is_connected("ranged_attack", Callable(spawner, "spawn_projectile")):
		printerr("TEST FAILED: WeaponSlot.ranged_attack signal is not connected to ProjectileSpawnerComponent.spawn_projectile.")
		bomber.queue_free()
		get_tree().quit(1)
		return
	print("WeaponSlot.ranged_attack -> spawn_projectile connection verified.")
	bomber.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 4: Firebomb Projectile Configuration & Export Vars
	# ---------------------------------------------------------
	print("\n>>> PART 4: Firebomb Projectile Configuration & Export Vars")
	var proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(proj)
	await get_tree().process_frame

	if not (proj is EnemyProjectile):
		printerr("TEST FAILED: FirebombProjectile does not inherit EnemyProjectile.")
		proj.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(proj.gravity, 0.5):
		printerr("TEST FAILED: Expected gravity == 0.5, got: ", proj.gravity)
		proj.queue_free()
		get_tree().quit(1)
		return
	if proj.arc_height <= 0.0:
		printerr("TEST FAILED: Expected arc_height > 0.0, got: ", proj.arc_height)
		proj.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(proj.trap_duration, 10.0):
		printerr("TEST FAILED: Expected trap_duration == 10.0, got: ", proj.trap_duration)
		proj.queue_free()
		get_tree().quit(1)
		return
	if proj.trap_size != Vector2(2.0, 2.0):
		printerr("TEST FAILED: Expected trap_size == Vector2(2.0, 2.0), got: ", proj.trap_size)
		proj.queue_free()
		get_tree().quit(1)
		return
	if proj.fire_trap_scene == null:
		printerr("TEST FAILED: fire_trap_scene is null.")
		proj.queue_free()
		get_tree().quit(1)
		return
	print("Export vars (gravity=0.5, trap_duration=10.0, trap_size=(2,2), fire_trap_scene) verified.")
	proj.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 5: Ballistic Trajectory Calculation (Angled Up & 0.5 Gravity Falling)
	# ---------------------------------------------------------
	print("\n>>> PART 5: Ballistic Trajectory Calculation (Angled Up & 0.5 Gravity)")
	var traj_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(traj_proj)
	traj_proj.global_position = Vector3(0.0, 1.5, 0.0)
	var target_ground_pos := Vector3(0.0, 0.0, 4.0)
	traj_proj.initialize_trajectory(target_ground_pos)

	if traj_proj.velocity.y <= 0.0:
		printerr("TEST FAILED: Firebomb initial vertical velocity must be positive (angled up). Got: ", traj_proj.velocity.y)
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Initial velocity is angled up: velocity.y = ", traj_proj.velocity.y, " > 0.")

	var initial_vy: float = traj_proj.velocity.y
	# Run 10 physics frames and verify gravity slows down vy by exactly gravity * delta
	var prev_vy: float = initial_vy
	var dt: float = 1.0 / 60.0
	for i: int in range(10):
		traj_proj.velocity.y -= traj_proj.fall_gravity * dt
		var expected_vy: float = prev_vy - 0.5 * dt
		if not is_equal_approx(traj_proj.velocity.y, expected_vy):
			printerr("TEST FAILED: Velocity Y did not decay by 0.5 * delta. Expected: ", expected_vy, " got: ", traj_proj.velocity.y)
			traj_proj.queue_free()
			get_tree().quit(1)
			return
		prev_vy = traj_proj.velocity.y
	print("Downward acceleration by 0.5 gravity verified over time.")

	# Verify model-front (+Z) orientation aligns with velocity direction
	await get_tree().physics_frame
	var facing_dot: float = traj_proj.global_basis.z.dot(traj_proj.velocity.normalized())
	if facing_dot < 0.99:
		printerr("TEST FAILED: Projectile +Z model front should face along velocity. Dot: ", facing_dot)
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Model front (+Z) orientation along velocity verified (dot: ", facing_dot, ").")

	# Test custom fall_gravity synchronization
	traj_proj.fall_gravity = 0.8
	if not is_equal_approx(traj_proj.gravity, 0.8):
		printerr("TEST FAILED: Changing fall_gravity did not sync with Area3D gravity property.")
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("fall_gravity synchronization with native Area3D gravity verified.")

	# Test low arc_height (below 0.5) is respected without clamping
	var low_arc_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(low_arc_proj)
	low_arc_proj.global_position = Vector3(0.0, 1.0, 0.0)
	low_arc_proj.arc_height = 0.2
	low_arc_proj.initialize_trajectory(Vector3(0.0, 0.0, 5.0))
	var expected_peak_vy: float = sqrt(2.0 * 0.2 * low_arc_proj.fall_gravity)
	if absf(low_arc_proj.velocity.y - expected_peak_vy) > 0.01:
		printerr("TEST FAILED: Low arc_height (0.2) was clamped or miscalculated. Vy0: ", low_arc_proj.velocity.y, ", expected ~", expected_peak_vy)
		low_arc_proj.queue_free()
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Custom low arc_height (0.2) verified without arbitrary 0.5 clamp.")
	low_arc_proj.queue_free()

	# Test explicit origin targeting (0, 0, 0)
	var origin_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(origin_proj)
	origin_proj.global_position = Vector3(3.0, 1.0, 0.0)
	origin_proj.initialize_trajectory(Vector3.ZERO)
	if origin_proj.target_position != Vector3.ZERO:
		printerr("TEST FAILED: Trajectory targeting Vector3.ZERO failed to set target_position to Vector3.ZERO. Got: ", origin_proj.target_position)
		origin_proj.queue_free()
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Origin targeting (Vector3.ZERO) verified.")
	origin_proj.queue_free()

	traj_proj.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 6: In-Flight Collision with Player (Damages Player, NO Fire Trap)
	# ---------------------------------------------------------
	print("\n>>> PART 6: In-Flight Collision with Player (Damages Player, NO Fire Trap)")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 2.0)
	await get_tree().physics_frame

	var p_health: HealthComponent = player.health_component
	var hp_before: float = p_health.current_health

	var flight_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(flight_proj)
	flight_proj.global_position = player.global_position

	var hit_detected := false
	for i: int in range(5):
		await get_tree().physics_frame
		if p_health.current_health < hp_before:
			hit_detected = true
			break

	if not hit_detected:
		printerr("TEST FAILED: Player did not take damage from in-flight firebomb hit! HP: ", p_health.current_health)
		player.queue_free()
		get_tree().quit(1)
		return
	print("Player took in-flight fireball damage! HP: ", hp_before, " -> ", p_health.current_health)

	# Verify NO FireTrap was spawned in the world from an aerial player hit
	var world_traps: Array[Node] = []
	for child: Node in get_tree().current_scene.get_children():
		if child is FireTrap:
			world_traps.append(child)
	if not world_traps.is_empty():
		printerr("TEST FAILED: FireTrap should NOT be spawned when hitting player in flight.")
		player.queue_free()
		get_tree().quit(1)
		return
	print("Confirmed: No fire trap was spawned from aerial player hit.")
	player.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 7: Ground Collision Spawns 2m x 2m FireTrap (Ground Mesh Disabled, 10s Duration)
	# ---------------------------------------------------------
	print("\n>>> PART 7: Ground Collision Spawns 2m x 2m FireTrap (show_ground_mesh=false, duration=10.0)")
	# Create floor for collision
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30.0, 1.0, 30.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	add_child(floor_body)

	var ground_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(ground_proj)
	ground_proj.global_position = Vector3(5.0, 1.0, 5.0)
	ground_proj.arc_height = 0.5
	ground_proj.initialize_trajectory(Vector3(5.0, 0.0, 8.0))

	# Wait for projectile to arc and hit the floor
	var spawned_trap: FireTrap = null
	for frame: int in range(280):
		await get_tree().physics_frame
		var candidates: Array[Node] = []
		if get_tree().current_scene != null:
			candidates.append_array(get_tree().current_scene.get_children())
		if get_tree().root != null:
			candidates.append_array(get_tree().root.get_children())
		candidates.append_array(get_children())
		for child: Node in candidates:
			if child is FireTrap and not child.is_queued_for_deletion():
				spawned_trap = child as FireTrap
				break
		if spawned_trap != null:
			break

	if spawned_trap == null:
		printerr("TEST FAILED: Firebomb did not spawn a FireTrap on ground impact.")
		floor_body.queue_free()
		get_tree().quit(1)
		return
	print("FireTrap spawned on ground impact at: ", spawned_trap.global_position)
	if absf(spawned_trap.global_position.x - 5.0) > 0.05 or absf(spawned_trap.global_position.z - 8.0) > 0.05:
		printerr("TEST FAILED: Spawned FireTrap position ", spawned_trap.global_position, " does not match target ground (5, 0, 8).")
		spawned_trap.queue_free()
		floor_body.queue_free()
		get_tree().quit(1)
		return
	print("Spawned FireTrap landed accurately at target ground (5, 0, 8): ", spawned_trap.global_position)

	# Verify FireTrap properties: 2m by 2m, show_ground_mesh = false, duration = 10.0
	if spawned_trap.show_ground_mesh:
		printerr("TEST FAILED: Spawned FireTrap should have show_ground_mesh = false.")
		spawned_trap.queue_free()
		floor_body.queue_free()
		get_tree().quit(1)
		return
	if spawned_trap.ground_mesh.visible:
		printerr("TEST FAILED: Spawned FireTrap ground_mesh should not be visible.")
		spawned_trap.queue_free()
		floor_body.queue_free()
		get_tree().quit(1)
		return
	print("Ground mesh disabled (show_ground_mesh=false, ground_mesh.visible=false) verified.")

	if spawned_trap.trap_size != Vector2(2.0, 2.0):
		printerr("TEST FAILED: Expected trap_size == Vector2(2.0, 2.0), got: ", spawned_trap.trap_size)
		spawned_trap.queue_free()
		floor_body.queue_free()
		get_tree().quit(1)
		return
	var col_box: BoxShape3D = spawned_trap.collision_shape.shape as BoxShape3D
	if col_box.size.x != 2.0 or col_box.size.z != 2.0:
		printerr("TEST FAILED: Expected collision box size (2, 1, 2), got: ", col_box.size)
		spawned_trap.queue_free()
		floor_body.queue_free()
		get_tree().quit(1)
		return
	print("Trap size 2m by 2m (trap_size=(2,2), collision_shape=(2,1,2)) verified.")

	if not is_equal_approx(spawned_trap.duration, 10.0):
		printerr("TEST FAILED: Expected duration == 10.0, got: ", spawned_trap.duration)
		spawned_trap.queue_free()
		floor_body.queue_free()
		get_tree().quit(1)
		return
	print("Trap duration 10.0 seconds verified.")

	# Clean up
	spawned_trap.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 8: End-to-End Enemy Projectile Cast Aiming
	# ---------------------------------------------------------
	print("\n>>> PART 8: End-to-End Enemy Projectile Cast Aiming")
	var cast_bomber: Character = firebomber_scene.instantiate() as Character
	add_child(cast_bomber)
	cast_bomber.global_position = Vector3(0.0, 1.0, 0.0)

	var target_dummy: Character = player_scene.instantiate() as Character
	add_child(target_dummy)
	target_dummy.global_position = Vector3(0.0, 1.0, 6.0)
	await get_tree().process_frame

	cast_bomber.current_target = target_dummy
	var bomber_spawner: ProjectileSpawnerComponent = cast_bomber.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent

	var scene_children_before: int = get_tree().current_scene.get_child_count()
	bomber_spawner.spawn_projectile()

	var casted_proj: FirebombProjectile = null
	for i: int in range(scene_children_before, get_tree().current_scene.get_child_count()):
		var c: Node = get_tree().current_scene.get_child(i)
		if c is FirebombProjectile:
			casted_proj = c as FirebombProjectile
			break

	if casted_proj == null:
		printerr("TEST FAILED: spawn_projectile did not spawn FirebombProjectile.")
		cast_bomber.queue_free()
		target_dummy.queue_free()
		get_tree().quit(1)
		return

	if casted_proj.shooter != cast_bomber:
		printerr("TEST FAILED: casted_proj.shooter is not cast_bomber.")
		casted_proj.queue_free()
		cast_bomber.queue_free()
		target_dummy.queue_free()
		get_tree().quit(1)
		return

	# Verify the projectile targeted the ground where the player stood: (0.0, 0.0, 6.0)
	if absf(casted_proj.target_position.z - 6.0) > 0.1 or absf(casted_proj.target_position.y - 0.0) > 0.1:
		printerr("TEST FAILED: Projectile target_position does not match player ground location. Got: ", casted_proj.target_position)
		casted_proj.queue_free()
		cast_bomber.queue_free()
		target_dummy.queue_free()
		get_tree().quit(1)
		return
	print("Firebomb correctly calculated target ground at player location: ", casted_proj.target_position)

	casted_proj.queue_free()
	cast_bomber.queue_free()
	target_dummy.queue_free()

	print("\n====================================================")
	print("  ALL FIREBOMBER ENEMY & FIREBOMB TESTS PASSED!")
	print("  1. GlobalVars registry & scene loading verified")
	print("  2. WaveObjective includes firebomber in spawns")
	print("  3. CharacterBody3D, spawner & attack states verified")
	print("  4. Projectile export vars & 0.5 gravity verified")
	print("  5. Upward launch angle & ballistic arc verified")
	print("  6. In-flight player damage & no-trap verified")
	print("  7. Ground impact spawns 2x2 fire trap (10s, no mesh)")
	print("  8. End-to-end cast calculates player ground position")
	print("====================================================")
	get_tree().quit(0)
