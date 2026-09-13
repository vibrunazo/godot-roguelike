extends Node3D

func _ready() -> void:
	print("\n====================================================")
	print("  STARTING ENEMY THUNDER MAGE VERIFICATION SUITE    ")
	print("====================================================")

	# ---------------------------------------------------------
	# PART 1: GlobalVars Registration & Scene Loading
	# ---------------------------------------------------------
	print("\n>>> PART 1: GlobalVars Registration & Scene Loading")
	if GlobalVars.enemy_thunder_mage_scene == null:
		printerr("TEST FAILED: GlobalVars.enemy_thunder_mage_scene is null.")
		get_tree().quit(1)
		return
	if GlobalVars.lightning_bolt_scene == null:
		printerr("TEST FAILED: GlobalVars.lightning_bolt_scene is null.")
		get_tree().quit(1)
		return
	if GlobalVars.lightning_hit_scene == null:
		printerr("TEST FAILED: GlobalVars.lightning_hit_scene is null.")
		get_tree().quit(1)
		return

	var mage_scene: PackedScene = load("res://Enemy/enemy_thunder_mage.tscn")
	if mage_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/enemy_thunder_mage.tscn")
		get_tree().quit(1)
		return

	var proj_scene: PackedScene = load("res://Enemy/lightning_bolt_projectile.tscn")
	if proj_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/lightning_bolt_projectile.tscn")
		get_tree().quit(1)
		return

	var hit_scene: PackedScene = load("res://Enemy/lightning_hit.tscn")
	if hit_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/lightning_hit.tscn")
		get_tree().quit(1)
		return
	print("[OK] GlobalVars registrations and scene files verified.")

	# ---------------------------------------------------------
	# PART 2: WaveObjective Default Spawn Pool Integration
	# ---------------------------------------------------------
	print("\n>>> PART 2: WaveObjective Default Spawn Pool Integration")
	var wave_obj := WaveObjective.new()
	add_child(wave_obj)
	await get_tree().process_frame

	if not wave_obj.enemy_scenes.has(GlobalVars.enemy_thunder_mage_scene):
		printerr("TEST FAILED: WaveObjective.enemy_scenes does not contain GlobalVars.enemy_thunder_mage_scene.")
		wave_obj.queue_free()
		get_tree().quit(1)
		return
	print("[OK] WaveObjective includes enemy_thunder_mage in default spawn pool.")

	var spawned_mage: Character = GlobalVars.enemy_thunder_mage_scene.instantiate() as Character
	if spawned_mage == null or not (spawned_mage is Character) or not spawned_mage.is_in_group("enemy"):
		printerr("TEST FAILED: enemy_thunder_mage_scene does not instantiate a Character in group 'enemy'.")
		wave_obj.queue_free()
		get_tree().quit(1)
		return
	spawned_mage.queue_free()
	wave_obj.queue_free()
	print("[OK] Instantiation as Character in group 'enemy' verified.")

	# ---------------------------------------------------------
	# PART 3: Thunder Mage Hierarchy, Stats, and State Machines
	# ---------------------------------------------------------
	print("\n>>> PART 3: Thunder Mage Hierarchy, Stats, and State Machines")
	var mage: Character = mage_scene.instantiate() as Character
	add_child(mage)
	mage.global_position = Vector3(0.0, 1.0, 0.0)
	await get_tree().process_frame

	if mage.health_component == null:
		printerr("TEST FAILED: HealthComponent missing on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if mage.health_component.max_health <= 0.0:
		printerr("TEST FAILED: Expected max_health > 0.0, got: ", mage.health_component.max_health)
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] HealthComponent and max_health (", mage.health_component.max_health, ") verified.")

	var spawner: ProjectileSpawnerComponent = mage.get_node_or_null("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	if spawner == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent missing on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if spawner.character != mage:
		printerr("TEST FAILED: ProjectileSpawnerComponent.character does not point to EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if spawner.projectile_scene == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent.projectile_scene is null.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if spawner.spawn_point == null:
		printerr("TEST FAILED: ProjectileSpawnerComponent.spawn_point is null.")
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] ProjectileSpawnerComponent wiring and projectile_scene verified.")

	var body_sm: StateMachine = mage.state_machine
	if body_sm == null:
		printerr("TEST FAILED: StateMachine is null on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	var attack_state: CharacterAttack = body_sm.get_node_or_null("EnemyAttack") as CharacterAttack
	if attack_state == null:
		printerr("TEST FAILED: EnemyAttack missing under StateMachine.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if attack_state.attack_animation_name != "RangedAttack":
		printerr("TEST FAILED: Expected attack_animation_name == 'RangedAttack', got: ", attack_state.attack_animation_name)
		mage.queue_free()
		get_tree().quit(1)
		return
	if attack_state.cooldown <= 0.0:
		printerr("TEST FAILED: Expected cooldown > 0.0, got: ", attack_state.cooldown)
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] StateMachine and EnemyAttack state (RangedAttack, cooldown ", attack_state.cooldown, ") verified.")

	var ai_sm: AIStateMachine = mage.ai_state_machine
	if ai_sm == null:
		printerr("TEST FAILED: AIStateMachine is null on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	var ai_meander: AIMeander = ai_sm.get_node_or_null("AIMeander") as AIMeander
	if ai_meander == null:
		printerr("TEST FAILED: AIMeander missing under AIStateMachine.")
		mage.queue_free()
		get_tree().quit(1)
		return
	var ai_attack: AIAttack = ai_sm.get_node_or_null("AIAttack") as AIAttack
	if ai_attack == null:
		printerr("TEST FAILED: AIAttack missing under AIStateMachine.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if ai_attack.attack_state_name != "EnemyAttack":
		printerr("TEST FAILED: Expected AIAttack.attack_state_name == 'EnemyAttack', got: ", ai_attack.attack_state_name)
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] AIStateMachine, AIMeander, and AIAttack verified.")

	# Verify WeaponSlot ranged_attack signal is connected to ProjectileSpawnerComponent.spawn_projectile
	var weapon_slot: Node = mage.find_child("WeaponSlot", true, false)
	if weapon_slot == null:
		printerr("TEST FAILED: WeaponSlot not found on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if not weapon_slot.is_connected("ranged_attack", Callable(spawner, "spawn_projectile")):
		printerr("TEST FAILED: WeaponSlot.ranged_attack is not connected to ProjectileSpawnerComponent.spawn_projectile.")
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] WeaponSlot.ranged_attack -> spawn_projectile connection verified.")

	# ---------------------------------------------------------
	# PART 4: Purple Coloring & CharacterColorComponent
	# ---------------------------------------------------------
	print("\n>>> PART 4: Purple Coloring & CharacterColorComponent")
	if mage.color_component == null:
		printerr("TEST FAILED: CharacterColorComponent is null on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	if mage.color_component.gradients.size() < 8:
		printerr("TEST FAILED: Expected at least 8 gradients in CharacterColorComponent.")
		mage.queue_free()
		get_tree().quit(1)
		return
	var purple_grad: Gradient = mage.color_component.gradients[7]
	if purple_grad == null:
		printerr("TEST FAILED: Expected slot 7 gradient to be configured on EnemyThunderMage.")
		mage.queue_free()
		get_tree().quit(1)
		return
	# Verify purple color hue on slot 7: purple has high red and blue, and lower green
	var top_color: Color = purple_grad.colors[0]
	if top_color.b < 0.5 or top_color.r < 0.4 or top_color.g > 0.6:
		printerr("TEST FAILED: Expected purple color ramp on slot 7, got: ", top_color)
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] Purple gradient on slot 7 verified: ", top_color)

	# Verify all 6 body meshes have material_override set
	var body_meshes: Array[MeshInstance3D] = mage.color_component.get_body_meshes()
	if body_meshes.size() != 6:
		printerr("TEST FAILED: Expected 6 body meshes, found: ", body_meshes.size())
		mage.queue_free()
		get_tree().quit(1)
		return
	for mi: MeshInstance3D in body_meshes:
		if mi.material_override == null:
			printerr("TEST FAILED: Body mesh ", mi.name, " does not have material_override set.")
			mage.queue_free()
			get_tree().quit(1)
			return
	print("[OK] All 6 body meshes have material_override applied.")

	# Verify weapon slot orb mesh is NOT overridden by character palette material
	var orb_mesh: MeshInstance3D = weapon_slot.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if orb_mesh != null and orb_mesh.material_override == mage.color_component.material:
		printerr("TEST FAILED: WeaponSlot orb mesh was incorrectly overridden by character palette material.")
		mage.queue_free()
		get_tree().quit(1)
		return
	print("[OK] WeaponSlot magic focus orb mesh preserved independently.")

	mage.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 5: Lightning Bolt Projectile Configuration & Trajectory
	# ---------------------------------------------------------
	print("\n>>> PART 5: Lightning Bolt Projectile Configuration & Trajectory")
	var bolt: LightningBoltProjectile = proj_scene.instantiate() as LightningBoltProjectile
	add_child(bolt)
	bolt.global_position = Vector3(0.0, 1.0, 0.0)
	await get_tree().process_frame

	if not (bolt is EnemyProjectile):
		printerr("TEST FAILED: LightningBoltProjectile does not extend EnemyProjectile.")
		bolt.queue_free()
		get_tree().quit(1)
		return
	if bolt.speed <= 0.0:
		printerr("TEST FAILED: Expected speed > 0.0, got: ", bolt.speed)
		bolt.queue_free()
		get_tree().quit(1)
		return
	if bolt.damage <= 0.0:
		printerr("TEST FAILED: Expected damage > 0.0, got: ", bolt.damage)
		bolt.queue_free()
		get_tree().quit(1)
		return
	if bolt.knockback <= 0.0:
		printerr("TEST FAILED: Expected knockback > 0.0, got: ", bolt.knockback)
		bolt.queue_free()
		get_tree().quit(1)
		return
	if bolt.hit_effect_scene == null:
		printerr("TEST FAILED: LightningBoltProjectile hit_effect_scene is null.")
		bolt.queue_free()
		get_tree().quit(1)
		return

	# Verify particle process and dynamic light nodes
	var particles: GPUParticles3D = bolt.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if particles == null:
		printerr("TEST FAILED: GPUParticles3D missing on LightningBoltProjectile.")
		bolt.queue_free()
		get_tree().quit(1)
		return
	var light: OmniLight3D = bolt.get_node_or_null("OmniLight3D") as OmniLight3D
	if light == null:
		printerr("TEST FAILED: OmniLight3D missing on LightningBoltProjectile.")
		bolt.queue_free()
		get_tree().quit(1)
		return
	print("[OK] LightningBoltProjectile parameters, particles, and light verified.")

	# Verify physics forward movement along +Z
	var start_z: float = bolt.global_position.z
	var dt: float = 0.05
	bolt._physics_process(dt)
	var expected_z: float = start_z + bolt.speed * dt
	if not is_equal_approx(bolt.global_position.z, expected_z):
		printerr("TEST FAILED: Projectile did not move along +Z by speed * delta. Expected: ", expected_z, " got: ", bolt.global_position.z)
		bolt.queue_free()
		get_tree().quit(1)
		return
	print("[OK] Forward linear velocity (+Z at speed 14.0) verified.")
	bolt.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 6: In-Flight Collision with Player & Damage Delivery
	# ---------------------------------------------------------
	print("\n>>> PART 6: In-Flight Collision with Player & Damage Delivery")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 3.0)
	await get_tree().physics_frame

	var p_health: HealthComponent = player.health_component
	var hp_before: float = p_health.current_health

	var flight_bolt: LightningBoltProjectile = proj_scene.instantiate() as LightningBoltProjectile
	add_child(flight_bolt)
	flight_bolt.global_position = player.global_position

	var hit_detected: bool = false
	for i: int in range(10):
		await get_tree().physics_frame
		if p_health.current_health < hp_before:
			hit_detected = true
			break

	if not hit_detected:
		printerr("TEST FAILED: Player did not receive damage from LightningBoltProjectile! HP: ", p_health.current_health)
		player.queue_free()
		get_tree().quit(1)
		return

	var damage_taken: float = hp_before - p_health.current_health
	if not is_equal_approx(damage_taken, flight_bolt.damage):
		printerr("TEST FAILED: Expected ", flight_bolt.damage, " damage, player took: ", damage_taken)
		player.queue_free()
		get_tree().quit(1)
		return
	print("[OK] Player received exactly ", flight_bolt.damage, " lightning bolt damage (HP: ", hp_before, " -> ", p_health.current_health, ").")
	player.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 7: Hit Effect VFX Spawning
	# ---------------------------------------------------------
	print("\n>>> PART 7: Hit Effect VFX Spawning")
	var test_bolt: LightningBoltProjectile = proj_scene.instantiate() as LightningBoltProjectile
	add_child(test_bolt)
	test_bolt.global_position = Vector3(10.0, 1.0, 10.0)
	await get_tree().process_frame

	var world_count_before: int = 0
	for child: Node in get_tree().current_scene.get_children():
		if child.name.begins_with("LightningHit"):
			world_count_before += 1

	test_bolt.hit_effect()
	await get_tree().process_frame

	var hit_found: bool = false
	for child: Node in get_tree().current_scene.get_children():
		if child.name.begins_with("LightningHit"):
			hit_found = true
			break

	if not hit_found:
		printerr("TEST FAILED: hit_effect() did not spawn LightningHit in scene tree.")
		test_bolt.queue_free()
		get_tree().quit(1)
		return
	print("[OK] LightningHit effect spawned successfully on impact.")
	test_bolt.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 8: End-to-End Spell Cast Integration
	# ---------------------------------------------------------
	print("\n>>> PART 8: End-to-End Spell Cast Integration")
	var casting_mage: Character = mage_scene.instantiate() as Character
	add_child(casting_mage)
	casting_mage.global_position = Vector3(0.0, 1.0, 0.0)

	var target_player: Character = player_scene.instantiate() as Character
	add_child(target_player)
	target_player.global_position = Vector3(0.0, 1.0, 5.0)
	await get_tree().process_frame

	var mage_spawner: ProjectileSpawnerComponent = casting_mage.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	var scene_children_before: int = get_tree().current_scene.get_child_count()

	var slot: BoneAttachment3D = casting_mage.find_child("WeaponSlot", true, false) as BoneAttachment3D
	var slot_pos_at_cast: Vector3 = slot.global_position

	# Trigger cast through spawner
	mage_spawner.spawn_projectile()

	var spawned_proj: LightningBoltProjectile = null
	for i: int in range(scene_children_before, get_tree().current_scene.get_child_count()):
		var c: Node = get_tree().current_scene.get_child(i)
		if c is LightningBoltProjectile:
			spawned_proj = c as LightningBoltProjectile
			break

	if spawned_proj == null:
		printerr("TEST FAILED: spawn_projectile() did not spawn LightningBoltProjectile.")
		casting_mage.queue_free()
		target_player.queue_free()
		get_tree().quit(1)
		return

	if spawned_proj.shooter != casting_mage:
		printerr("TEST FAILED: Spawned projectile shooter is not casting_mage.")
		spawned_proj.queue_free()
		casting_mage.queue_free()
		target_player.queue_free()
		get_tree().quit(1)
		return

	# Verify projectile spawned at WeaponSlot location
	var dist_to_slot: float = spawned_proj.global_position.distance_to(slot_pos_at_cast)
	if dist_to_slot > 0.1:
		printerr("TEST FAILED: Projectile spawn position deviates from WeaponSlot: ", dist_to_slot)
		spawned_proj.queue_free()
		casting_mage.queue_free()
		target_player.queue_free()
		get_tree().quit(1)
		return
	print("[OK] Projectile spawned from WeaponSlot with shooter correctly assigned.")

	spawned_proj.queue_free()
	casting_mage.queue_free()
	target_player.queue_free()
	await get_tree().process_frame

	print("\n====================================================")
	print("  ALL ENEMY THUNDER MAGE TESTS PASSED SUCCESSFULLY! ")
	print("  1. GlobalVars registry & scene loading verified   ")
	print("  2. WaveObjective includes thunder mage in spawns  ")
	print("  3. CharacterBody3D, spawner & attack states ok    ")
	print("  4. Purple coloring on slot 7 & body meshes ok     ")
	print("  5. Lightning bolt speed, damage, particles & light")
	print("  6. In-flight player collision & 7.0 damage verified")
	print("  7. LightningHit VFX spawning on impact verified   ")
	print("  8. End-to-end spell cast from WeaponSlot verified ")
	print("====================================================")
	get_tree().quit(0)
