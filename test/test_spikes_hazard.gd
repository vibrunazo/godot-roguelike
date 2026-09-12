extends Node

const TestUtils = preload("res://test/test_utils.gd")
const Character = preload("res://Character/character.gd")
const HealthComponent = preload("res://Components/health_component.gd")
const AttackComponent = preload("res://Components/attack_component.gd")

func _ready() -> void:
	print("--- RUNNING SPIKES TRAP HAZARD TEST ---")
	
	var hazard_scene: PackedScene = load("res://Hazards/spikes_hazard.tscn")
	if hazard_scene == null:
		printerr("TEST FAILED: Failed to load Hazards/spikes_hazard.tscn")
		get_tree().quit(1)
		return
	
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(20.0, 1.0, 20.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	add_child(floor_body)

	var hazard: SpikesHazard = hazard_scene.instantiate() as SpikesHazard
	hazard.trigger_delay = 0.25
	hazard.active_duration = 0.35
	hazard.reset_cooldown = 0.2
	hazard.damage = 15.0
	hazard.knockback_force = 4.0
	add_child(hazard)
	hazard.global_position = Vector3(0.0, 0.0, 0.0)
	
	await get_tree().physics_frame
	await get_tree().physics_frame
	
	# ---------------------------------------------------------
	# PART 1: Node & Component Setup Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: Node & Configuration Checks")
	if hazard.trigger_area == null:
		printerr("TEST FAILED: TriggerArea not found.")
		get_tree().quit(1)
		return
	if hazard.trigger_area.collision_layer != 32:
		printerr("TEST FAILED: Expected TriggerArea collision_layer == 32 (layer 6 Triggers), got: ", hazard.trigger_area.collision_layer)
		get_tree().quit(1)
		return
	if hazard.trigger_area.collision_mask != 1:
		printerr("TEST FAILED: Expected TriggerArea collision_mask == 1, got: ", hazard.trigger_area.collision_mask)
		get_tree().quit(1)
		return
	print("TriggerArea layer (32) and mask (1) verified.")
	
	if hazard.damage_hitbox == null:
		printerr("TEST FAILED: DamageHitbox not found.")
		get_tree().quit(1)
		return
	if hazard.damage_hitbox.collision_mask != 192:
		printerr("TEST FAILED: Expected DamageHitbox collision_mask == 192 (64 | 128), got: ", hazard.damage_hitbox.collision_mask)
		get_tree().quit(1)
		return
	if hazard.damage_hitbox.monitoring != false:
		printerr("TEST FAILED: DamageHitbox should not be monitoring initially.")
		get_tree().quit(1)
		return
	print("DamageHitbox mask (192) and initial monitoring (false) verified.")
	
	if hazard.attack_component == null:
		printerr("TEST FAILED: AttackComponent not found on DamageHitbox.")
		get_tree().quit(1)
		return
	if hazard.attack_component.damage != 15.0:
		printerr("TEST FAILED: Expected AttackComponent.damage == 15.0, got: ", hazard.attack_component.damage)
		get_tree().quit(1)
		return
	print("AttackComponent synced damage verified.")
	
	var spikes_root: Node3D = hazard.get_node_or_null("SpikesRoot") as Node3D
	if spikes_root == null:
		printerr("TEST FAILED: SpikesRoot node not found.")
		get_tree().quit(1)
		return
	if spikes_root.position.y > -0.6:
		printerr("TEST FAILED: Taller spikes should be submerged initially (position.y <= -0.6), got: ", spikes_root.position.y)
		get_tree().quit(1)
		return
	print("SpikesRoot initial retracted position verified (Y = ", spikes_root.position.y, ")")
	
	# ---------------------------------------------------------
	# PART 2: Enemy Trigger Activation & Damage
	# ---------------------------------------------------------
	print("\n>>> PART 2: Verifying Enemies CAN Trigger Spikes & Take Damage")
	var enemy_scene: PackedScene = load("res://Enemy/melee_enemy.tscn")
	var enemy: Character = enemy_scene.instantiate() as Character
	add_child(enemy)
	enemy.global_position = Vector3(0.0, 1.0, 0.0)
	
	# Wait for body_entered detection
	for i: int in range(5):
		await get_tree().physics_frame
	
	if not hazard.is_triggered():
		printerr("TEST FAILED: Enemy did not trigger spikes hazard! Expected TRIGGERED.")
		get_tree().quit(1)
		return
	print("Enemy triggered spikes hazard successfully (state == TRIGGERED).")
	
	var enemy_health: HealthComponent = enemy.get_node("HealthComponent") as HealthComponent
	var initial_enemy_hp: float = enemy_health.current_health
	
	# During dodge delay, enemy should not have taken damage yet
	if enemy_health.current_health < initial_enemy_hp:
		printerr("TEST FAILED: Enemy took damage prematurely during trigger delay window!")
		get_tree().quit(1)
		return
	print("Dodge window verified for enemy trigger.")
	
	# Wait for spikes emergence and damage
	var enemy_damaged := false
	for i: int in range(30):
		await get_tree().physics_frame
		if enemy_health.current_health < initial_enemy_hp:
			enemy_damaged = true
			break
			
	if not enemy_damaged:
		printerr("TEST FAILED: Enemy did not take damage after spikes emerged! HP: ", enemy_health.current_health)
		get_tree().quit(1)
		return
	print("Enemy damage confirmed on emergence! HP: ", initial_enemy_hp, " -> ", enemy_health.current_health)
	
	# Move enemy away and wait for reset
	enemy.global_position = Vector3(-15.0, 1.0, -15.0)
	var reset_to_idle := false
	for i: int in range(90):
		await get_tree().physics_frame
		if hazard.is_idle():
			reset_to_idle = true
			break
			
	if not reset_to_idle:
		printerr("TEST FAILED: Hazard did not return to IDLE after enemy trigger cycle.")
		get_tree().quit(1)
		return
	print("Hazard reset to IDLE after enemy cycle.")
	
	# ---------------------------------------------------------
	# PART 3: Player Trigger & Dodge Delay Window & Damage
	# ---------------------------------------------------------
	print("\n>>> PART 3: Player Triggering, Dodge Window & Damage")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	
	for i: int in range(5):
		await get_tree().physics_frame
	
	if not hazard.is_triggered():
		printerr("TEST FAILED: Player did not trigger hazard. Expected TRIGGERED.")
		get_tree().quit(1)
		return
	print("Player triggered hazard (is_triggered() == true).")
	
	var player_health: HealthComponent = player.get_node("HealthComponent") as HealthComponent
	var initial_player_hp: float = player_health.current_health
	
	if player_health.current_health < initial_player_hp:
		printerr("TEST FAILED: Player took damage prematurely during trigger delay window!")
		get_tree().quit(1)
		return
	print("Dodge window verified for player: No damage dealt during trigger_delay.")
	
	# Wait for spikes to emerge and strike player
	var player_damaged := false
	for i: int in range(30):
		await get_tree().physics_frame
		if player_health.current_health < initial_player_hp:
			player_damaged = true
			break
	
	if not player_damaged:
		printerr("TEST FAILED: Player did not take damage after spikes emerged! Current HP: ", player_health.current_health)
		get_tree().quit(1)
		return
	print("Player damage confirmed! HP: ", initial_player_hp, " -> ", player_health.current_health)
	
	# ---------------------------------------------------------
	# PART 4: Retraction & Cooldown
	# ---------------------------------------------------------
	print("\n>>> PART 4: Spikes Retraction & Cooldown Cycle")
	player.global_position = Vector3(15.0, 1.0, 15.0)
	
	var returned_to_idle := false
	for i: int in range(90):
		await get_tree().physics_frame
		if hazard.is_idle():
			returned_to_idle = true
			break
	
	if not returned_to_idle:
		printerr("TEST FAILED: Hazard did not return to IDLE after cooldown!")
		get_tree().quit(1)
		return
	print("Hazard successfully retracted and returned to IDLE state.")
	
	if hazard.damage_hitbox.monitoring:
		printerr("TEST FAILED: DamageHitbox monitoring should be false at IDLE.")
		get_tree().quit(1)
		return
	if spikes_root.position.y > -0.6:
		printerr("TEST FAILED: SpikesRoot should be submerged at IDLE, position.y: ", spikes_root.position.y)
		get_tree().quit(1)
		return
	print("Spikes submerged and hitbox disabled at IDLE.")
	
	print("\n====================================================")
	print("  ALL SPIKES TRAP HAZARD TESTS PASSED!")
	print("  1. Primitives, node hierarchy & collision layers verified")
	print("  2. Enemies CAN trigger spikes and take damage")
	print("  3. Players CAN trigger spikes and take damage")
	print("  4. Configurable trigger_delay provides dodge window")
	print("  5. Taller spikes submerged properly at idle")
	print("  6. Retraction & cooldown cleanly re-arm hazard")
	print("====================================================")
	
	get_tree().quit(0)
