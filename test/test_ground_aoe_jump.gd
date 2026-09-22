## Automated verification suite for GroundDamageArea, Brute Slam ground impact,
## and player jump evasion.
## Tests that:
## 1. GroundDamageArea uses a low-height CylinderShape3D resting on the floor.
## 2. Standing players inside the radius receive relative damage matching the attack.
## 3. Jumping players in mid-air clear the low cylinder height and take ZERO damage.
## 4. Downward raycast correctly snaps the AOE to the floor even if the caster is elevated.
extends Node3D

var passed_checks: int = 0


func _ready() -> void:
	print("\n====================================================")
	print("  STARTING GROUND AOE & JUMP EVASION TEST SUITE")
	print("====================================================")

	# Build physical floor on layer 1 (World)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0) # top of floor is at y = 0.0
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	await get_tree().physics_frame
	await get_tree().process_frame

	_run_tests()


func _run_tests() -> void:
	# -------------------------------------------------------------
	# PART 1: GroundDamageArea Dimensions & Cylinder Positioning
	# -------------------------------------------------------------
	print("\n>>> PART 1: GroundDamageArea Cylinder Shape & Floor Alignment")
	var aoe_scene: PackedScene = load("res://Hazards/ground_damage_aoe.tscn")
	if aoe_scene == null:
		_fail("Could not load Hazards/ground_damage_aoe.tscn.")
		return

	var aoe: GroundDamageArea = aoe_scene.instantiate() as GroundDamageArea
	add_child(aoe)
	await get_tree().physics_frame

	var col: CollisionShape3D = aoe.get_node_or_null("DamageHitbox/CollisionShape3D") as CollisionShape3D
	if col == null or col.shape == null or not (col.shape is CylinderShape3D):
		_fail("GroundDamageArea missing CylinderShape3D on DamageHitbox.")
		return

	var cyl: CylinderShape3D = col.shape as CylinderShape3D
	if not is_equal_approx(cyl.radius, aoe.radius):
		_fail("CylinderShape3D radius does not match aoe.radius.")
		return
	if not is_equal_approx(cyl.height, aoe.height):
		_fail("CylinderShape3D height does not match aoe.height.")
		return
	# Base of cylinder must align with y=0, meaning center position.y must be height / 2.0
	if not is_equal_approx(col.position.y, aoe.height * 0.5):
		_fail("CollisionShape3D center is not offset to height / 2.0. Base is not at y=0.")
		return

	# Verify visual components exist
	var shockwave: MeshInstance3D = aoe.get_node_or_null("ShockwaveRing") as MeshInstance3D
	var indicator: MeshInstance3D = aoe.get_node_or_null("GroundIndicator") as MeshInstance3D
	var particles: GPUParticles3D = aoe.get_node_or_null("GPUParticles3D") as GPUParticles3D
	if shockwave == null or indicator == null or particles == null:
		_fail("GroundDamageArea missing visual nodes (ShockwaveRing, GroundIndicator, GPUParticles3D).")
		return

	aoe.queue_free()
	print("GroundDamageArea cylindrical hitbox, floor alignment, and visuals verified.")
	passed_checks += 1

	# -------------------------------------------------------------
	# PART 2: Standing Player takes Damage vs Jumping Player takes 0
	# -------------------------------------------------------------
	print("\n>>> PART 2: Jump Evasion (Standing takes damage, Jumping takes 0)")
	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn")
	var brute: Character = brute_scene.instantiate() as Character
	brute.position = Vector3.ZERO
	add_child(brute)

	var enemy_attack: CharacterAttack = brute.state_machine.get_node_or_null("EnemyAttack") as CharacterAttack
	if enemy_attack == null:
		_fail("Brute EnemyAttack node missing.")
		return

	var forward: Vector3 = brute.mesh_mount.global_basis.z.normalized() if brute.mesh_mount != null else Vector3.FORWARD
	var offset: float = enemy_attack.get("aoe_forward_offset") if "aoe_forward_offset" in enemy_attack else 2.8
	var test_impact_xz: Vector3 = brute.global_position + forward * offset

	var player_scene: PackedScene = load("res://Player/player.tscn")

	# Phase 2A: Standing player inside impact zone
	var standing_player: Character = player_scene.instantiate() as Character
	standing_player.position = test_impact_xz
	add_child(standing_player)

	# Let standing player settle on the floor
	for _i: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

	var standing_hp_before: float = standing_player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	brute.state_machine.request_state("EnemyAttack")

	# Advance physics frames until slam apex strikes and completes
	for _i: int in range(60):
		await get_tree().physics_frame
	await get_tree().process_frame

	var standing_hp_after: float = standing_player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var standing_damage_taken: float = standing_hp_before - standing_hp_after
	print("Standing player damage taken: ", standing_damage_taken, " (expected: ", enemy_attack.damage, ")")

	if not is_equal_approx(standing_damage_taken, enemy_attack.damage):
		_fail("Standing player did not take relative damage equal to enemy_attack.damage! Got: %f" % standing_damage_taken)
		return

	standing_player.queue_free()
	await get_tree().physics_frame

	# Phase 2B: Jumping player inside impact zone
	var jumping_player: Character = player_scene.instantiate() as Character
	jumping_player.position = test_impact_xz
	add_child(jumping_player)

	for _i: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

	var jumping_hp_before: float = jumping_player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)

	# Reset brute slam cooldown and trigger slam
	enemy_attack.cooldown_timer = 0.0
	brute.state_machine.request_state("EnemyAttack")

	# Wait until slam windup is underway (~25 frames), then jump
	for _i: int in range(25):
		await get_tree().physics_frame

	jumping_player.state_machine.request_state("PlayerJump")

	# Advance through apex impact (~35 more frames)
	for _i: int in range(40):
		await get_tree().physics_frame
	await get_tree().process_frame

	var jumping_hp_after: float = jumping_player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var jumping_damage_taken: float = jumping_hp_before - jumping_hp_after
	print("Jumping player damage taken: ", jumping_damage_taken, " (expected: 0.0)")

	if not is_equal_approx(jumping_damage_taken, 0.0):
		_fail("Jumping player took %f damage! Jumping over the slam should take 0 damage." % jumping_damage_taken)
		return

	jumping_player.queue_free()
	brute.queue_free()
	print("Jump evasion confirmed: standing player took damage, jumping player took 0.")
	passed_checks += 1

	# -------------------------------------------------------------
	# PART 3: Downward Raycast Floor Detection for Elevated Caster
	# -------------------------------------------------------------
	print("\n>>> PART 3: Downward Raycast Floor Detection for Elevated Caster")
	var elevated_brute: Character = brute_scene.instantiate() as Character
	elevated_brute.position = Vector3(0.0, 3.5, 0.0) # High in mid-air
	add_child(elevated_brute)

	await get_tree().physics_frame
	await get_tree().process_frame

	var elevated_attack: GroundSlamAttack = elevated_brute.state_machine.get_node_or_null("EnemyAttack") as GroundSlamAttack
	if elevated_attack == null:
		_fail("EnemyAttack is not GroundSlamAttack.")
		return

	# Trigger slam from elevated position
	elevated_attack._spawn_ground_aoe()
	await get_tree().physics_frame
	await get_tree().process_frame

	# Find spawned AOE in scene
	var spawned_aoe: GroundDamageArea = null
	for child: Node in get_tree().current_scene.get_children():
		if child is GroundDamageArea and not child.is_queued_for_deletion():
			spawned_aoe = child as GroundDamageArea
			break

	if spawned_aoe == null:
		_fail("GroundDamageArea was not spawned into the scene tree.")
		return

	print("Elevated brute position Y: ", elevated_brute.global_position.y)
	print("Spawned AOE position Y: ", spawned_aoe.global_position.y, " (floor top is at 0.0)")

	# The raycast must place the AOE at y = 0.0 (the floor), not at y = 3.5!
	if not is_equal_approx(spawned_aoe.global_position.y, 0.0):
		_fail("Spawned AOE did not snap to floor y=0.0! Spawned at y=%f" % spawned_aoe.global_position.y)
		return

	spawned_aoe.queue_free()
	elevated_brute.queue_free()
	print("Downward raycast accurately snapped ground AOE to floor surface.")
	passed_checks += 1

	# -------------------------------------------------------------
	# PART 4: Friendly Fire Verification
	# -------------------------------------------------------------
	print("\n>>> PART 4: Friendly Fire (Allied enemy takes damage, caster takes 0)")
	var ff_brute: Character = brute_scene.instantiate() as Character
	ff_brute.position = Vector3.ZERO
	add_child(ff_brute)
	await get_tree().physics_frame
	await get_tree().process_frame

	var ff_attack: GroundSlamAttack = ff_brute.state_machine.get_node_or_null("EnemyAttack") as GroundSlamAttack
	if ff_attack == null or not ff_attack.friendly_fire:
		_fail("Brute EnemyAttack does not have friendly_fire enabled.")
		return

	var ally_scene: PackedScene = load("res://Enemy/melee_enemy.tscn")
	var ally_enemy: Character = ally_scene.instantiate() as Character
	var ally_offset: float = ff_attack.aoe_forward_offset
	var ally_forward: Vector3 = ff_brute.mesh_mount.global_basis.z.normalized() if ff_brute.mesh_mount != null else Vector3.FORWARD
	ally_enemy.position = ff_brute.global_position + ally_forward * ally_offset
	add_child(ally_enemy)
	await get_tree().physics_frame
	await get_tree().process_frame

	var ally_attrs: AttributeComponent = ally_enemy.attribute_component
	var brute_attrs: AttributeComponent = ff_brute.attribute_component
	var ally_hp_before: float = ally_attrs.get_current(AttributeComponent.POOL_HEALTH)
	var brute_hp_before: float = brute_attrs.get_current(AttributeComponent.POOL_HEALTH)

	# Trigger slam with friendly_fire enabled
	ff_attack._spawn_ground_aoe()
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var ally_hp_after: float = ally_attrs.get_current(AttributeComponent.POOL_HEALTH)
	var brute_hp_after: float = brute_attrs.get_current(AttributeComponent.POOL_HEALTH)
	var ally_damage_taken: float = ally_hp_before - ally_hp_after
	var brute_damage_taken: float = brute_hp_before - brute_hp_after

	var expected_slam_damage: float = ff_attack.damage * (ff_brute.get_damage_modifier() if ff_brute.has_method("get_damage_modifier") else 1.0)
	print("Ally enemy damage taken: ", ally_damage_taken, " (expected: ", expected_slam_damage, ")")
	print("Casting brute damage taken: ", brute_damage_taken, " (expected: 0.0)")

	if not is_equal_approx(ally_damage_taken, expected_slam_damage):
		_fail("Allied enemy did not take friendly fire damage! Expected %f, got %f" % [expected_slam_damage, ally_damage_taken])
		return

	if not is_equal_approx(brute_damage_taken, 0.0):
		_fail("Casting brute damaged itself! Self-damage must be 0, got %f" % brute_damage_taken)
		return

	# Clean up friendly fire entities and spawned AOEs
	ally_enemy.queue_free()
	ff_brute.queue_free()
	for child: Node in get_tree().current_scene.get_children():
		if child is GroundDamageArea:
			child.queue_free()
	await get_tree().physics_frame
	await get_tree().process_frame

	# Verify Akira Boss friendly fire toggle
	var boss_scene: PackedScene = load("res://Enemy/akira_boss.tscn")
	var boss: Character = boss_scene.instantiate() as Character
	add_child(boss)
	await get_tree().physics_frame
	var boss_attack: GroundSlamAttack = boss.state_machine.get_node_or_null("EnemyAttack") as GroundSlamAttack
	if boss_attack == null or not boss_attack.friendly_fire:
		_fail("Akira Boss EnemyAttack does not have friendly_fire enabled.")
		return
	boss.queue_free()
	await get_tree().physics_frame

	print("Friendly fire verified: allied enemies take damage, caster takes 0 self-damage, boss configured.")
	passed_checks += 1

	# -------------------------------------------------------------
	# Summary
	# -------------------------------------------------------------
	print("\n====================================================")
	print("  ALL GROUND AOE & JUMP EVASION CHECKS PASSED (%d/4)" % passed_checks)
	print("  1. Low cylinder height & floor alignment verified")
	print("  2. Standing player hit & jumping player evasion verified")
	print("  3. Downward raycast floor height detection verified")
	print("  4. Friendly fire on allies and self-damage immunity verified")
	print("====================================================\n")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("TEST FAILED: ", reason)
	get_tree().quit(1)
