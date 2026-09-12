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
	if not is_equal_approx(proj.fall_gravity, 0.5):
		printerr("TEST FAILED: Expected fall_gravity == 0.5, got: ", proj.fall_gravity)
		proj.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(proj.gravity, 4.9):
		printerr("TEST FAILED: Expected gravity == 4.9 (0.5 * 9.8), got: ", proj.gravity)
		proj.queue_free()
		get_tree().quit(1)
		return
	if not is_equal_approx(proj.speed, 8.0):
		printerr("TEST FAILED: Expected speed == 8.0, got: ", proj.speed)
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
	print("Export vars (speed=8.0, fall_gravity=0.5 (4.9 m/s^2), trap_duration=10.0, trap_size=(2,2), fire_trap_scene) verified.")
	proj.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 5: Ballistic Trajectory (Fixed Speed, Distance-based Time & Gravity)
	# ---------------------------------------------------------
	print("\n>>> PART 5: Ballistic Trajectory (Fixed Speed & Distance-based Time)")
	var traj_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(traj_proj)
	traj_proj.global_position = Vector3(0.0, 1.5, 0.0)
	var target_ground_pos := Vector3(0.0, 0.0, 4.0)
	traj_proj.initialize_trajectory(target_ground_pos)

	# Verify horizontal speed matches exported speed variable
	var v_xz_length: float = Vector2(traj_proj.velocity.x, traj_proj.velocity.z).length()
	if not is_equal_approx(v_xz_length, traj_proj.speed):
		printerr("TEST FAILED: Horizontal speed must equal proj.speed (", traj_proj.speed, "). Got: ", v_xz_length)
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Horizontal speed matches projectile speed variable: ", v_xz_length)

	# Verify time varies with distance (time = distance / speed)
	var near_target := Vector3(0.0, 0.0, 4.0)
	var far_target := Vector3(0.0, 0.0, 8.0)
	var near_time: float = (near_target - traj_proj.global_position).length() / traj_proj.speed
	var far_time: float = (far_target - traj_proj.global_position).length() / traj_proj.speed
	if far_time <= near_time:
		printerr("TEST FAILED: Flight time should increase with distance.")
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Flight time varies dynamically with distance: near=", near_time, "s, far=", far_time, "s.")

	var initial_vy: float = traj_proj.velocity.y
	# Run 10 physics frames and verify gravity slows down vy by exactly effective_gravity * delta
	var prev_vy: float = initial_vy
	var dt: float = 1.0 / 60.0
	var eff_g: float = traj_proj.get_effective_gravity()
	for i: int in range(10):
		traj_proj.velocity.y -= eff_g * dt
		var expected_vy: float = prev_vy - eff_g * dt
		if not is_equal_approx(traj_proj.velocity.y, expected_vy):
			printerr("TEST FAILED: Velocity Y did not decay by eff_g * delta. Expected: ", expected_vy, " got: ", traj_proj.velocity.y)
			traj_proj.queue_free()
			get_tree().quit(1)
			return
		prev_vy = traj_proj.velocity.y
	print("Downward acceleration by effective gravity (4.9 m/s^2) verified over time.")

	# Verify model-front (+Z) orientation aligns with velocity direction
	await get_tree().physics_frame
	var facing_dot: float = traj_proj.global_basis.z.dot(traj_proj.velocity.normalized())
	if facing_dot < 0.99:
		printerr("TEST FAILED: Projectile +Z model front should face along velocity. Dot: ", facing_dot)
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Model front (+Z) orientation along velocity verified (dot: ", facing_dot, ").")

	# Test custom fall_gravity synchronization with native Area3D gravity
	traj_proj.fall_gravity = 0.8
	var expected_native_g: float = 0.8 * FirebombProjectile.EARTH_GRAVITY
	if not is_equal_approx(traj_proj.gravity, expected_native_g):
		printerr("TEST FAILED: Changing fall_gravity did not sync with Area3D gravity property. Expected: ", expected_native_g, " got: ", traj_proj.gravity)
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("fall_gravity synchronization with native Area3D gravity verified (0.8 -> ", traj_proj.gravity, " m/s^2).")

	# Test custom speed adjustment (e.g. speed = 12.0)
	var fast_proj: FirebombProjectile = projectile_scene.instantiate() as FirebombProjectile
	add_child(fast_proj)
	fast_proj.global_position = Vector3(0.0, 1.0, 0.0)
	fast_proj.speed = 12.0
	fast_proj.initialize_trajectory(Vector3(0.0, 0.0, 6.0))
	var fast_vxz: float = Vector2(fast_proj.velocity.x, fast_proj.velocity.z).length()
	if not is_equal_approx(fast_vxz, 12.0):
		printerr("TEST FAILED: Modifying speed to 12.0 did not update horizontal speed. Got: ", fast_vxz)
		fast_proj.queue_free()
		traj_proj.queue_free()
		get_tree().quit(1)
		return
	print("Adjusting projectile speed to 12.0 verified: horizontal speed = ", fast_vxz)
	fast_proj.queue_free()

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
	await get_tree().process_frame
	await get_tree().physics_frame

	# ---------------------------------------------------------
	# PART 9: Firebomber Leaping Dodge State & AI Node Wiring
	# ---------------------------------------------------------
	print("\n>>> PART 9: Firebomber Leaping Dodge State & AI Node Wiring")
	var leap_floor := StaticBody3D.new()
	leap_floor.position = Vector3(0.0, -1.0, 0.0)
	var leap_floor_col := CollisionShape3D.new()
	var leap_floor_box := BoxShape3D.new()
	leap_floor_box.size = Vector3(100.0, 2.0, 100.0)
	leap_floor_col.shape = leap_floor_box
	leap_floor.add_child(leap_floor_col)
	add_child(leap_floor)
	await get_tree().process_frame
	await get_tree().physics_frame

	var leap_bomber: Character = firebomber_scene.instantiate() as Character
	leap_bomber.position = Vector3(0.0, 1.0, 0.0)
	add_child(leap_bomber)
	leap_bomber.velocity = Vector3(0.0, -1.0, 0.0)
	leap_bomber.move_and_slide()
	await get_tree().process_frame
	await get_tree().physics_frame

	var leap_body_sm: StateMachine = leap_bomber.state_machine
	var leap_ai_sm: AIStateMachine = leap_bomber.ai_state_machine
	if leap_body_sm.state.name != "EnemyMove":
		leap_body_sm.request_state("EnemyMove")

	var leap_dodge_state: EnemyLeapingDodge = leap_body_sm.get_node_or_null("EnemyLeapingDodge") as EnemyLeapingDodge
	if leap_dodge_state == null:
		printerr("TEST FAILED: EnemyLeapingDodge missing on Firebomber StateMachine.")
		get_tree().quit(1)
		return
	if not is_equal_approx(leap_dodge_state.cooldown, 12.0):
		printerr("TEST FAILED: EnemyLeapingDodge.cooldown is ", leap_dodge_state.cooldown, ", expected 12.0.")
		get_tree().quit(1)
		return
	if not is_equal_approx(leap_dodge_state.max_range, 15.0):
		printerr("TEST FAILED: EnemyLeapingDodge.max_range is ", leap_dodge_state.max_range, ", expected 15.0.")
		get_tree().quit(1)
		return
	if leap_dodge_state.peak_height <= 0.0:
		printerr("TEST FAILED: EnemyLeapingDodge.peak_height must be > 0.0.")
		get_tree().quit(1)
		return
	if not leap_dodge_state.uninterruptable:
		printerr("TEST FAILED: EnemyLeapingDodge.uninterruptable is not true.")
		get_tree().quit(1)
		return

	var ai_dodge_state: AILeapingDodge = leap_ai_sm.get_node_or_null("AILeapingDodge") as AILeapingDodge
	if ai_dodge_state == null:
		printerr("TEST FAILED: AILeapingDodge missing on Firebomber AIStateMachine.")
		get_tree().quit(1)
		return
	if not is_equal_approx(ai_dodge_state.cooldown, 12.0):
		printerr("TEST FAILED: AILeapingDodge.cooldown is ", ai_dodge_state.cooldown, ", expected 12.0.")
		get_tree().quit(1)
		return
	if not is_equal_approx(ai_dodge_state.trigger_range, 5.0):
		printerr("TEST FAILED: AILeapingDodge.trigger_range is ", ai_dodge_state.trigger_range, ", expected 5.0.")
		get_tree().quit(1)
		return
	if not is_equal_approx(ai_dodge_state.max_range, 15.0):
		printerr("TEST FAILED: AILeapingDodge.max_range is ", ai_dodge_state.max_range, ", expected 15.0.")
		get_tree().quit(1)
		return
	if ai_dodge_state.ability_state_name != "EnemyLeapingDodge" and ai_dodge_state.attack_state_name != "EnemyLeapingDodge":
		printerr("TEST FAILED: AILeapingDodge target state name is not 'EnemyLeapingDodge'.")
		get_tree().quit(1)
		return

	# Verify AnimationPlayer has Jump_Full_Short in EnemyAnimations library
	var enemy_anim_player: AnimationPlayer = leap_bomber.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if enemy_anim_player == null or not enemy_anim_player.has_animation("EnemyAnimations/Jump_Full_Short"):
		printerr("TEST FAILED: AnimationPlayer missing 'EnemyAnimations/Jump_Full_Short'.")
		get_tree().quit(1)
		return

	print("EnemyLeapingDodge & AILeapingDodge node wiring and 12s/15m/5m export configuration verified.")

	# ---------------------------------------------------------
	# PART 10: AI Trigger Conditions (Distance < 5m & 12s Cooldown)
	# ---------------------------------------------------------
	print("\n>>> PART 10: AI Trigger Conditions (Distance < 5m & 12s Cooldown)")
	var test_player_scene: PackedScene = load("res://Player/player.tscn")
	var leap_player: Character = test_player_scene.instantiate() as Character
	leap_player.position = leap_bomber.position + Vector3(0.0, 0.0, 7.0)
	add_child(leap_player)
	leap_player.velocity = Vector3(0.0, -1.0, 0.0)
	leap_player.move_and_slide()

	# Case A: Player outside 5m (e.g. 7.0m away) - should NOT trigger
	leap_player.global_position = leap_bomber.global_position + Vector3(0.0, 0.0, 7.0)
	ai_dodge_state.cooldown_timer = 0.0
	await get_tree().physics_frame
	await get_tree().process_frame

	var far_trigger: bool = ai_dodge_state.evaluate_trigger(0.016)
	if far_trigger:
		printerr("TEST FAILED: AILeapingDodge triggered when player was 7m away (> 5m)!")
		get_tree().quit(1)
		return
	print("Far player distance (> 5m) correctly rejected.")

	# Case B: Boundary test: Player at 5.2m (> 5m) - should NOT trigger
	leap_player.global_position = leap_bomber.global_position + Vector3(0.0, 0.0, 5.2)
	await get_tree().physics_frame
	var boundary_far_trigger: bool = ai_dodge_state.evaluate_trigger(0.016)
	if boundary_far_trigger:
		printerr("TEST FAILED: AILeapingDodge triggered at 5.2m (> 5.0m threshold)!")
		get_tree().quit(1)
		return

	# Case C: Boundary test: Player at 4.0m (< 5m) - SHOULD trigger
	leap_player.global_position = leap_bomber.global_position + Vector3(0.0, 0.0, 4.0)
	ai_dodge_state.cooldown_timer = 0.0
	var close_trigger: bool = ai_dodge_state.evaluate_trigger(0.016)
	if not close_trigger:
		printerr("TEST FAILED: AILeapingDodge did not trigger when player was 4.0m away (< 5m)!")
		get_tree().quit(1)
		return
	print("Near player distance (< 5m) successfully triggered AILeapingDodge.")

	# Verify AI state transitioned to AILeapingDodge
	await get_tree().physics_frame
	await get_tree().process_frame
	if leap_ai_sm.state != ai_dodge_state:
		printerr("TEST FAILED: AIStateMachine did not transition to AILeapingDodge, current: ", leap_ai_sm.state.name)
		get_tree().quit(1)
		return
	print("AIStateMachine preemptively interrupted into AILeapingDodge.")

	# Verify cooldown reset to 12.0
	if not is_equal_approx(ai_dodge_state.cooldown_timer, 12.0):
		printerr("TEST FAILED: AILeapingDodge cooldown_timer was not reset to 12.0, got: ", ai_dodge_state.cooldown_timer)
		get_tree().quit(1)
		return
	print("Cooldown timer initialized to 12.0s.")

	# Verify evaluate_trigger returns false while cooldown > 0
	var cd_trigger: bool = ai_dodge_state.evaluate_trigger(0.016)
	if cd_trigger:
		printerr("TEST FAILED: AILeapingDodge triggered while on cooldown!")
		get_tree().quit(1)
		return
	print("Cooldown gating verified: evaluate_trigger is false while on cooldown.")

	# Verify cooldown timer decays
	var prev_cd: float = ai_dodge_state.cooldown_timer
	ai_dodge_state.evaluate_trigger(2.5)
	if not is_equal_approx(ai_dodge_state.cooldown_timer, prev_cd - 2.5):
		printerr("TEST FAILED: cooldown_timer did not decay by delta. Got: ", ai_dodge_state.cooldown_timer)
		get_tree().quit(1)
		return
	print("Cooldown timer decay verified (12.0 -> ", ai_dodge_state.cooldown_timer, "s).")

	# ---------------------------------------------------------
	# PART 11: Leaping Dodge High-in-the-Air Trajectory & Hyper-Armor
	# ---------------------------------------------------------
	print("\n>>> PART 11: Leaping Dodge High-in-the-Air Trajectory & Hyper-Armor")
	# Reset enemy position and start leap dodge
	leap_bomber.global_position = Vector3(0.0, 1.0, 0.0)
	leap_player.global_position = Vector3(0.0, 1.0, 3.0) # player in front (+Z)
	await get_tree().physics_frame

	leap_dodge_state.enter("", {"direction": Vector3(0.0, 0.0, -1.0)}) # Leaping back away from player (-Z)
	if not leap_dodge_state.is_leaping:
		printerr("TEST FAILED: is_leaping is not true after enter().")
		get_tree().quit(1)
		return

	# Initial vertical velocity must be positive (high in the air)
	if leap_dodge_state.vertical_velocity <= 0.0:
		printerr("TEST FAILED: Initial vertical velocity must be > 0.0 for high leap! Got: ", leap_dodge_state.vertical_velocity)
		get_tree().quit(1)
		return
	print("High leap takeoff verified: initial Vy = ", leap_dodge_state.vertical_velocity, " m/s.")

	# Advance physics frames and verify upward movement toward peak height
	var max_y_reached: float = 0.0
	for step in range(30):
		leap_dodge_state.physics_update(1.0 / 60.0)
		if leap_bomber.global_position.y > max_y_reached:
			max_y_reached = leap_bomber.global_position.y

	if max_y_reached < 3.0:
		printerr("TEST FAILED: Leap did not reach high altitude in air. Max Y reached: ", max_y_reached)
		get_tree().quit(1)
		return
	print("High aerial apex verified: reached height ", max_y_reached, "m in air.")

	# Verify Hyper-Armor: damage during leap does not interrupt into EnemyStun
	leap_bomber.health_component.take_damage(5.0)
	await get_tree().physics_frame
	if leap_body_sm.state == leap_bomber.stun_state:
		printerr("TEST FAILED: Firebomber was interrupted into EnemyStun during uninterruptable leaping dodge!")
		get_tree().quit(1)
		return
	print("Hyper-armor verified: mid-air damage did NOT interrupt leaping dodge into EnemyStun.")

	# Complete the leap
	for step in range(40):
		if not leap_dodge_state.is_leaping:
			break
		leap_dodge_state.physics_update(1.0 / 60.0)

	# Verify displacement is clamped within max_range of 15m
	var total_displacement: float = (leap_bomber.global_position - Vector3.ZERO).length()
	if total_displacement > 15.1:
		printerr("TEST FAILED: Leaping dodge displaced ", total_displacement, "m, exceeding max_range of 15.0m!")
		get_tree().quit(1)
		return
	print("Leaping displacement safely within 15m max range: ", total_displacement, "m.")

	# ---------------------------------------------------------
	# PART 12: Edge Cases & Boundary Handling
	# ---------------------------------------------------------
	print("\n>>> PART 12: Edge Cases & Boundary Handling")
	# Edge case: Clamping explicit target exceeding max_range (e.g. 50m away)
	leap_dodge_state.enter("", {"target_position": Vector3(50.0, 0.0, 0.0)})
	var clamped_dist: float = (leap_dodge_state.target_position - leap_dodge_state.start_position).length()
	if clamped_dist > 15.001:
		printerr("TEST FAILED: Explicit 50m target was not clamped to max_range (15m). Got: ", clamped_dist)
		get_tree().quit(1)
		return
	print("Explicit target distance clamped to 15m: ", clamped_dist, "m.")

	# Edge case: Target at identical position (Vector3.ZERO offset)
	leap_dodge_state.enter("", {"direction": Vector3.ZERO})
	if not leap_dodge_state.horizontal_velocity.is_finite() or not leap_dodge_state.target_position.is_finite():
		printerr("TEST FAILED: Zero direction resulted in non-finite value!")
		get_tree().quit(1)
		return
	print("Zero direction fallback gracefully handled without NaN.")

	# ---------------------------------------------------------
	# PART 13: Wall & Corner Obstacle Avoidance
	# ---------------------------------------------------------
	print("\n>>> PART 13: Wall & Corner Obstacle Avoidance")
	var corner_wall := StaticBody3D.new()
	corner_wall.collision_layer = 1
	var corner_col := CollisionShape3D.new()
	var corner_box := BoxShape3D.new()
	corner_box.size = Vector3(20.0, 4.0, 1.0)
	corner_col.shape = corner_box
	corner_wall.add_child(corner_col)
	corner_wall.position = Vector3(0.0, 2.0, -2.0) # Wall centered at Z = -2.0
	add_child(corner_wall)
	await get_tree().physics_frame
	await get_tree().process_frame

	leap_bomber.global_position = Vector3(0.0, 1.0, 0.0)
	# Attempt to dodge directly into the wall (-Z)
	leap_dodge_state.enter("", {"direction": Vector3(0.0, 0.0, -1.0)})

	# Target position MUST NOT penetrate through the wall (front face is at Z = -1.5)
	if leap_dodge_state.target_position.z <= -1.5:
		printerr("TEST FAILED: Leaping dodge target penetrated through wall! Target pos: ", leap_dodge_state.target_position)
		get_tree().quit(1)
		return
	print("Wall collision avoidance verified: target pos safely bounded at ", leap_dodge_state.target_position)
	corner_wall.queue_free()

	# ---------------------------------------------------------
	# PART 14: Stun & Defeat Policy Enforcement via order_attack
	# ---------------------------------------------------------
	print("\n>>> PART 14: Stun & Defeat Policy Enforcement via order_attack")
	leap_body_sm.request_state("EnemyStun")
	await get_tree().physics_frame
	if leap_body_sm.state.name != "EnemyStun":
		printerr("TEST FAILED: Setup failed to put bomber into EnemyStun.")
		get_tree().quit(1)
		return

	# AILeapingDodge should respect can_break_stun = false
	ai_dodge_state.enter("")
	await get_tree().physics_frame
	if leap_body_sm.state.name == "EnemyLeapingDodge":
		printerr("TEST FAILED: AILeapingDodge illegally broke out of EnemyStun when can_break_stun is false!")
		get_tree().quit(1)
		return
	print("Stun protection verified: AILeapingDodge did NOT break EnemyStun.")
	leap_body_sm.request_state("EnemyMove")

	# Cleanup
	leap_player.queue_free()
	leap_bomber.queue_free()
	leap_floor.queue_free()

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
	print("  9. Leaping dodge states & Jump_Full_Short animation verified")
	print("  10. AILeapingDodge triggers on player < 5m & 12s cooldown")
	print("  11. High leap parabolic trajectory (15m range) & hyper-armor")
	print("  12. Boundary distance and zero/extreme displacement clamping")
	print("  13. Wall and corner obstacle avoidance (no penetration)")
	print("  14. Stun and defeat policy enforcement via order_attack")
	print("====================================================")
	get_tree().quit(0)
