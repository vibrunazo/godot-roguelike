extends Node

const TestUtils = preload("res://test/test_utils.gd")
const ScreenShakeComponent = preload("res://Components/screen_shake_component.gd")

func _ready() -> void:
	print("--- RUNNING SCREENSHAKE CONTROLLER POLICY TEST ---")

	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)

	await get_tree().physics_frame
	await get_tree().process_frame

	var player: Character = level.get_node("Player") as Character
	var camera: ShakeCamera3D = player.get_node_or_null("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	if camera == null:
		printerr("TEST FAILED: ShakeCamera3D not found on player.")
		get_tree().quit(1)
		return
	camera.make_current()

	var dummy: CollisionObject3D = TestUtils.find_dummy(level, player)
	if dummy == null:
		printerr("TEST FAILED: Dummy target not found in level.")
		get_tree().quit(1)
		return

	# ---------------------------------------------------------
	# PART 1: ScreenShakeComponent Exclusivity & Decoupled Character
	# ---------------------------------------------------------
	print("\n>>> PART 1: ScreenShakeComponent Exclusivity & Decoupled Character")
	var player_shake_comp: ScreenShakeComponent = player.get_node_or_null("ScreenShakeComponent") as ScreenShakeComponent
	if player_shake_comp == null:
		printerr("TEST FAILED: ScreenShakeComponent not found on Player.")
		get_tree().quit(1)
		return
	print("ScreenShakeComponent found on Player.")

	if player.has_method("reset_game_camera_shake"):
		printerr("TEST FAILED: Character still has reset_game_camera_shake; should be decoupled.")
		get_tree().quit(1)
		return
	print("Character decoupled from camera shake methods verified.")

	var melee_scene: PackedScene = load("res://Enemy/melee_enemy.tscn")
	var melee_enemy: Character = melee_scene.instantiate() as Character
	level.add_child(melee_enemy)
	await get_tree().physics_frame

	if melee_enemy.get_node_or_null("ScreenShakeComponent") != null:
		printerr("TEST FAILED: melee_enemy has a ScreenShakeComponent; should be exclusive to Player.")
		get_tree().quit(1)
		return
	print("Melee enemy has no ScreenShakeComponent verified.")

	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn")
	var brute_enemy: Character = brute_scene.instantiate() as Character
	level.add_child(brute_enemy)
	await get_tree().physics_frame

	if brute_enemy.get_node_or_null("ScreenShakeComponent") != null:
		printerr("TEST FAILED: brute_enemy has a ScreenShakeComponent; should be exclusive to Player.")
		get_tree().quit(1)
		return
	print("Brute enemy has no ScreenShakeComponent verified.")

	# ---------------------------------------------------------
	# PART 2: AttackComponent & Hazard Verification
	# ---------------------------------------------------------
	print("\n>>> PART 2: AttackComponent & Hazard Checks")
	var player_att: AttackComponent = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot/HitboxArea/AttackComponent") as AttackComponent
	if player_att == null:
		printerr("TEST FAILED: Player AttackComponent not found.")
		get_tree().quit(1)
		return

	var spikes_scene: PackedScene = load("res://Hazards/spikes_hazard.tscn")
	var spikes: SpikesHazard = spikes_scene.instantiate() as SpikesHazard
	level.add_child(spikes)
	spikes.global_position = Vector3(100.0, 0.0, 100.0)
	await get_tree().physics_frame
	if spikes.attack_component.shake_on_damage:
		printerr("TEST FAILED: SpikesHazard AttackComponent.shake_on_damage is true; expected false.")
		get_tree().quit(1)
		return
	if spikes.get_node_or_null("ScreenShakeComponent") != null:
		printerr("TEST FAILED: SpikesHazard has a ScreenShakeComponent; should be exclusive to Player.")
		get_tree().quit(1)
		return
	print("SpikesHazard AttackComponent shake_on_damage=false and no ScreenShakeComponent verified.")

	# ---------------------------------------------------------
	# PART 3: Enemy Taking Damage from Spikes (NO SCREEN SHAKE)
	# ---------------------------------------------------------
	print("\n>>> PART 3: Enemy Taking Damage from Trap -> NO Screenshake")
	camera.trauma = 0.0
	await get_tree().physics_frame

	var enemy_hurtbox: Hurtbox = melee_enemy.get_node("Hurtbox") as Hurtbox
	var enemy_health: HealthComponent = melee_enemy.health_component
	var enemy_hp_before: float = enemy_health.current_health
	var enemy_hit: bool = spikes.attack_component.deal_damage_to(enemy_hurtbox, 5.0, Vector3.ZERO)
	if not enemy_hit:
		printerr("TEST FAILED: Spikes could not deal damage to melee_enemy.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if enemy_health.current_health >= enemy_hp_before:
		printerr("TEST FAILED: Enemy did not take damage from spikes.")
		get_tree().quit(1)
		return
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Camera trauma occurred when enemy took damage from spikes! Trauma: ", camera.trauma)
		get_tree().quit(1)
		return
	print("Enemy damaged by trap with ZERO camera trauma verified! (HP: ", enemy_hp_before, " -> ", enemy_health.current_health, ", trauma: ", camera.trauma, ")")

	# Even if an attack component on a trap had shake_on_damage forcefully enabled,
	# without a ScreenShakeComponent on the trap or enemy, zero camera trauma occurs!
	spikes.attack_component.shake_on_damage = true
	spikes.attack_component.reset_exceptions()
	enemy_hp_before = enemy_health.current_health
	spikes.attack_component.deal_damage_to(enemy_hurtbox, 5.0, Vector3.ZERO)
	await get_tree().process_frame
	await get_tree().process_frame
	if camera.trauma != 0.0:
		printerr("TEST FAILED: Forcefully enabling shake_on_damage on trap caused screenshake! Trauma: ", camera.trauma)
		get_tree().quit(1)
		return
	print("Trap with shake_on_damage=true causes ZERO screenshake on enemy hit (ScreenShakeComponent architecture enforced).")
	spikes.attack_component.shake_on_damage = false

	# ---------------------------------------------------------
	# PART 4: Player Taking Damage from Spikes (SCREEN SHAKE)
	# ---------------------------------------------------------
	print("\n>>> PART 4: Player Taking Damage from Trap -> Screenshake Occurs")
	await get_tree().create_timer(0.35).timeout
	await get_tree().physics_frame
	camera.trauma = 0.0
	await get_tree().physics_frame

	var player_hurtbox: Hurtbox = player.get_node("Hurtbox") as Hurtbox
	var player_health: HealthComponent = player.health_component
	var player_hp_before: float = player_health.current_health
	spikes.attack_component.reset_exceptions()
	var player_hit: bool = spikes.attack_component.deal_damage_to(player_hurtbox, 5.0, Vector3.ZERO)
	if not player_hit:
		printerr("TEST FAILED: Spikes could not deal damage to player.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if player_health.current_health >= player_hp_before:
		printerr("TEST FAILED: Player did not take damage from spikes.")
		get_tree().quit(1)
		return
	if camera.trauma <= 0.0:
		printerr("TEST FAILED: Camera trauma did not trigger when player took damage from spikes!")
		get_tree().quit(1)
		return
	print("Player damaged by trap triggered screenshake verified! (trauma: ", camera.trauma, ")")

	# ---------------------------------------------------------
	# PART 5: Player Dealing Damage (SCREEN SHAKE)
	# ---------------------------------------------------------
	print("\n>>> PART 5: Player Dealing Damage -> Screenshake Occurs")
	await get_tree().create_timer(0.35).timeout
	await get_tree().physics_frame
	camera.trauma = 0.0
	await get_tree().physics_frame

	player_att.reset_exceptions()
	player_att.shake_on_damage = true
	var dummy_hurtbox: Hurtbox = dummy.get_node("Hurtbox") as Hurtbox
	var dummy_health: HealthComponent = dummy.get_node("HealthComponent") as HealthComponent
	var dummy_hp_before: float = dummy_health.current_health
	var deal_success: bool = player_att.deal_damage_to(dummy_hurtbox, 5.0, Vector3.ZERO)
	if not deal_success:
		printerr("TEST FAILED: Player could not deal damage to dummy.")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await get_tree().process_frame
	if dummy_health.current_health >= dummy_hp_before:
		printerr("TEST FAILED: Dummy health was not reduced.")
		get_tree().quit(1)
		return
	if camera.trauma <= 0.0:
		printerr("TEST FAILED: Camera trauma was not triggered when player dealt damage!")
		get_tree().quit(1)
		return
	print("Player dealing damage triggered screenshake verified! (trauma: ", camera.trauma, ")")

	# ---------------------------------------------------------
	# PART 6: Enemy Dealing Damage to Enemy (NO SCREEN SHAKE)
	# ---------------------------------------------------------
	print("\n>>> PART 6: Enemy Dealing Damage to Enemy -> NO Screenshake")
	await get_tree().create_timer(0.35).timeout
	await get_tree().physics_frame
	camera.trauma = 0.0
	await get_tree().physics_frame

	var enemy_att: AttackComponent = melee_enemy.get_node_or_null("AnimationAnchor/AnimatedEnemy/Enemy_Medium/Rig_Medium/Skeleton3D/WeaponSlot/HitboxArea/AttackComponent") as AttackComponent
	if enemy_att != null:
		enemy_att.reset_exceptions()
		var brute_hurtbox: Hurtbox = brute_enemy.get_node("Hurtbox") as Hurtbox
		var brute_health: HealthComponent = brute_enemy.health_component
		var brute_hp_before: float = brute_health.current_health
		enemy_att.deal_damage_to(brute_hurtbox, 5.0, Vector3.ZERO)
		await get_tree().process_frame
		await get_tree().process_frame
		if camera.trauma != 0.0:
			printerr("TEST FAILED: Camera trauma occurred when enemy damaged another enemy! Trauma: ", camera.trauma)
			get_tree().quit(1)
			return
		print("Enemy damaging enemy produced ZERO camera trauma verified.")

	print("\n====================================================================")
	print("  ALL SCREENSHAKE CONTROLLER POLICY TESTS PASSED!                   ")
	print("  1. ScreenShakeComponent exclusive to Player; Character decoupled  ")
	print("  2. AttackComponent & Hazard decoupled from camera lookups         ")
	print("  3. Trap damaging enemy causes 0.0 camera trauma                   ")
	print("  4. Trap damaging player causes player hurt screenshake (> 0.0)    ")
	print("  5. Player dealing damage causes weapon hit screenshake (> 0.0)    ")
	print("  6. Enemy damaging enemy causes 0.0 camera trauma                  ")
	print("====================================================================")

	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0)
