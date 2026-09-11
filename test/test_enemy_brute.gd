## Automated verification suite for Enemy Brute.
## Verifies Enemy Large skeletal mesh, 2H slam AOE attack, timing, collision radius,
## difficulty-based wave spawning, and captures debug collision screenshots into movies/.
extends Node3D

var passed_steps: int = 0
var total_steps: int = 6


func _ready() -> void:
	print("====================================================")
	print("  STARTING ENEMY BRUTE VERIFICATION SUITE")
	print("====================================================")

	# Enable debug collision shapes rendering for visual verification
	get_tree().debug_collisions_hint = true

	# Set up 3D environment for camera capture
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 4.0, 8.0)
	cam.look_at(Vector3(0.0, 1.0, 2.0))

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(light)

	# Static floor to keep physics characters grounded
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(50.0, 2.0, 50.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)
	add_child(floor_body)

	# -------------------------------------------------------------
	# PART 1: Scene Loading & GlobalVars Registration
	# -------------------------------------------------------------
	print("\n>>> PART 1: GlobalVars Registration & Scene Verification")
	if GlobalVars.enemy_brute_scene == null:
		printerr("TEST FAILED: GlobalVars.enemy_brute_scene is null.")
		get_tree().quit(1)
		return
	var brute_scene: PackedScene = GlobalVars.enemy_brute_scene
	var brute: Character = brute_scene.instantiate() as Character
	if brute == null:
		printerr("TEST FAILED: Could not instantiate enemy_brute.tscn as Character.")
		get_tree().quit(1)
		return
	add_child(brute)
	await get_tree().physics_frame
	await get_tree().process_frame

	if not brute.is_in_group("enemy"):
		printerr("TEST FAILED: Brute is not in 'enemy' group.")
		get_tree().quit(1)
		return
	if brute.collision_layer != 3:
		printerr("TEST FAILED: Brute collision_layer is ", brute.collision_layer, ", expected 3.")
		get_tree().quit(1)
		return
	if brute.health_component == null or not is_equal_approx(brute.health_component.max_health, 100.0):
		printerr("TEST FAILED: Brute max_health is ", brute.health_component.max_health if brute.health_component else 0.0, ", expected 100.0.")
		get_tree().quit(1)
		return
	if not is_equal_approx(brute.movement_speed, 2.2):
		printerr("TEST FAILED: Brute movement_speed is ", brute.movement_speed, ", expected 2.2.")
		get_tree().quit(1)
		return

	# Verify collision shape size for large enemy (radius 0.5 matching navmesh agent, height ~3.0)
	var cap_shape: CapsuleShape3D = brute.collision_shape_3d.shape as CapsuleShape3D
	if cap_shape == null or cap_shape.height < 2.5 or not is_equal_approx(cap_shape.radius, 0.5):
		printerr("TEST FAILED: Brute CollisionShape3D not configured with radius 0.5.")
		get_tree().quit(1)
		return

	# Verify hurtbox (larger capsule shape for hit detection matching visual mesh)
	if brute.hurtbox == null or brute.hurtbox.collision_layer != 128:
		printerr("TEST FAILED: Brute Hurtbox not on layer 128.")
		get_tree().quit(1)
		return
	var hurtbox_shape: CollisionShape3D = brute.hurtbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var hurtbox_cap: CapsuleShape3D = hurtbox_shape.shape as CapsuleShape3D if hurtbox_shape else null
	if hurtbox_cap == null or hurtbox_cap.radius < 0.75:
		printerr("TEST FAILED: Brute hurtbox shape radius is smaller than 0.75.")
		get_tree().quit(1)
		return

	# Verify NavigationAgent3D settings
	var nav_agent: NavigationAgent3D = brute.navigation_agent_3d
	if nav_agent == null or nav_agent.path_desired_distance < 1.4:
		printerr("TEST FAILED: Brute NavigationAgent3D path_desired_distance is too small for tall agent.")
		get_tree().quit(1)
		return

	# Verify weapon hitbox
	if brute.weapon_hitbox == null or brute.weapon_hitbox.collision_mask != 64:
		printerr("TEST FAILED: Brute weapon_hitbox not masking layer 64 (player hurtbox).")
		get_tree().quit(1)
		return

	print("Enemy Brute hierarchy, components, and exported properties verified.")
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 2: AnimationTree & State Configuration
	# -------------------------------------------------------------
	print("\n>>> PART 2: AnimationTree & State Machine Wiring")
	var anim_tree: AnimationTree = brute.animation_tree
	if anim_tree == null:
		printerr("TEST FAILED: Brute animation_tree is null.")
		get_tree().quit(1)
		return
	var sm_root: AnimationNodeStateMachine = anim_tree.tree_root as AnimationNodeStateMachine
	if sm_root == null:
		printerr("TEST FAILED: Brute AnimationTree tree_root is not AnimationNodeStateMachine.")
		get_tree().quit(1)
		return
	for state_name: String in ["WalkSpace", "MeleeAttack", "Stun", "Defeat"]:
		if not sm_root.has_node(StringName(state_name)):
			printerr("TEST FAILED: AnimationNodeStateMachine missing state: ", state_name)
			get_tree().quit(1)
			return

	# Verify StateMachine nodes
	var body_sm: StateMachine = brute.state_machine
	var enemy_attack: CharacterAttack = body_sm.get_node_or_null("EnemyAttack") as CharacterAttack
	if enemy_attack == null:
		printerr("TEST FAILED: EnemyAttack node missing on StateMachine.")
		get_tree().quit(1)
		return
	if not is_equal_approx(enemy_attack.damage, 25.0):
		printerr("TEST FAILED: EnemyAttack damage is ", enemy_attack.damage, ", expected 25.0.")
		get_tree().quit(1)
		return
	if not is_equal_approx(enemy_attack.knockback, 35.0):
		printerr("TEST FAILED: EnemyAttack knockback is ", enemy_attack.knockback, ", expected 35.0.")
		get_tree().quit(1)
		return
	if enemy_attack.attack_animation_name != "MeleeAttack":
		printerr("TEST FAILED: EnemyAttack attack_animation_name is ", enemy_attack.attack_animation_name, ", expected 'MeleeAttack'.")
		get_tree().quit(1)
		return

	# Verify AIStateMachine nodes
	var ai_sm: AIStateMachine = brute.ai_state_machine
	var ai_pursue: AIPursue = ai_sm.get_node_or_null("AIPursue") as AIPursue
	if ai_pursue == null or not is_equal_approx(ai_pursue.attack_range, 3.5):
		printerr("TEST FAILED: AIPursue missing or attack_range != 3.5.")
		get_tree().quit(1)
		return

	print("AnimationTree and StateMachine wiring verified.")
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 3: WaveObjective Spawning Difficulty Formula
	# -------------------------------------------------------------
	print("\n>>> PART 3: WaveObjective Difficulty Progression Spawning")
	var wave_obj := WaveObjective.new()
	add_child(wave_obj)

	# Test get_brute_count() for different progression levels:
	# Level 1-2: 1 brute; Level 3-4: 2 brutes; Level 5-6: 3 brutes
	ProgressionState.difficulty_level = 1
	if wave_obj.get_brute_count() != 1:
		printerr("TEST FAILED: get_brute_count() at diff 1 returned ", wave_obj.get_brute_count(), ", expected 1.")
		get_tree().quit(1)
		return
	ProgressionState.difficulty_level = 2
	if wave_obj.get_brute_count() != 1:
		printerr("TEST FAILED: get_brute_count() at diff 2 returned ", wave_obj.get_brute_count(), ", expected 1.")
		get_tree().quit(1)
		return
	ProgressionState.difficulty_level = 3
	if wave_obj.get_brute_count() != 2:
		printerr("TEST FAILED: get_brute_count() at diff 3 returned ", wave_obj.get_brute_count(), ", expected 2.")
		get_tree().quit(1)
		return
	ProgressionState.difficulty_level = 4
	if wave_obj.get_brute_count() != 2:
		printerr("TEST FAILED: get_brute_count() at diff 4 returned ", wave_obj.get_brute_count(), ", expected 2.")
		get_tree().quit(1)
		return
	ProgressionState.difficulty_level = 5
	if wave_obj.get_brute_count() != 3:
		printerr("TEST FAILED: get_brute_count() at diff 5 returned ", wave_obj.get_brute_count(), ", expected 3.")
		get_tree().quit(1)
		return

	# Reset progression
	ProgressionState.difficulty_level = 1
	wave_obj.queue_free()
	print("WaveObjective brute spawning progression formula verified.")
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 4: 2H Slam AOE Hitbox Timing & Damage Zone
	# -------------------------------------------------------------
	print("\n>>> PART 4: 2H Slam AOE Attack Timing, Radius & Damage Detection")
	# Spawn player inside AOE zone: Brute faces forward (+Z), slam impacts at ~ +3.0m Z
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player_target: Character = player_scene.instantiate() as Character
	player_target.position = Vector3(0.0, 0.0, 2.5) # Directly inside ground slam impact zone
	add_child(player_target)

	# Spawn player dummy outside AOE zone (7.0m away)
	var player_outside: Character = player_scene.instantiate() as Character
	player_outside.position = Vector3(0.0, 0.0, 7.5) # Far out of slam range
	add_child(player_outside)

	# Spawn player dummy behind brute (-3.0m)
	var player_behind: Character = player_scene.instantiate() as Character
	player_behind.position = Vector3(0.0, 0.0, -3.0) # Behind brute
	add_child(player_behind)

	await get_tree().physics_frame
	await get_tree().process_frame

	var target_hp_before: float = player_target.health_component.current_health
	var outside_hp_before: float = player_outside.health_component.current_health
	var behind_hp_before: float = player_behind.health_component.current_health

	# Trigger brute slam attack
	print("Triggering EnemyAttack on Brute...")
	print("Initial state: ", body_sm.state.name if body_sm.state else "null")
	body_sm.request_state("EnemyAttack")
	await get_tree().physics_frame
	await get_tree().process_frame
	print("State after request: ", body_sm.state.name if body_sm.state else "null")
	print("EnemyAttack attack_component: ", enemy_attack.attack_component)
	print("weapon_hitbox monitoring: ", brute.weapon_hitbox.monitoring)
	print("WeaponSlot node: ", brute.find_child("WeaponSlot", true, false))

	# Phase 4A: Windup (~0.45s in)
	# Advance 20 physics frames (~0.33s)
	for _f: int in range(20):
		await get_tree().physics_frame
	await get_tree().process_frame

	# Save windup screenshot
	_save_debug_screenshot("movies/brute_slam_windup.png")
	if brute.weapon_hitbox.monitoring:
		printerr("TEST FAILED: weapon_hitbox is monitoring during windup!")
		get_tree().quit(1)
		return
	if not is_equal_approx(player_target.health_component.current_health, target_hp_before):
		printerr("TEST FAILED: Player damaged during windup phase!")
		get_tree().quit(1)
		return
	print("Slam windup phase verified: hitbox inactive, no damage dealt.")

	# Phase 4B: Ground Impact Apex (~0.95s - 1.05s)
	# Advance frame by frame and log monitoring & overlap
	var saw_monitoring: bool = false
	for _f: int in range(50):
		await get_tree().physics_frame
		if brute.weapon_hitbox.monitoring:
			saw_monitoring = true
			print("Frame ", _f, " monitoring=true! Hitbox pos: ", brute.weapon_hitbox.global_position, " Player pos: ", player_target.global_position)
			print("Overlapping areas: ", brute.weapon_hitbox.get_overlapping_areas())
	await get_tree().process_frame

	print("Saw monitoring during apex? ", saw_monitoring)
	print("Player target Hurtbox: ", player_target.hurtbox, " layer: ", player_target.hurtbox.collision_layer if player_target.hurtbox else "null")
	print("Brute weapon_hitbox mask: ", brute.weapon_hitbox.collision_mask)

	# Save impact screenshot (hitbox shape visibly active in cyan debug)
	_save_debug_screenshot("movies/brute_slam_impact.png")

	# Target inside AOE should take 25.0 damage
	var target_damage_dealt: float = target_hp_before - player_target.health_component.current_health
	if not is_equal_approx(target_damage_dealt, 25.0):
		printerr("TEST FAILED: Target inside AOE took ", target_damage_dealt, " damage, expected 25.0!")
		get_tree().quit(1)
		return
	print("AOE impact hit verified: target inside shockwave received ", target_damage_dealt, " damage.")

	# Target outside AOE should take 0 damage
	if not is_equal_approx(player_outside.health_component.current_health, outside_hp_before):
		printerr("TEST FAILED: Target outside AOE range took damage!")
		get_tree().quit(1)
		return
	print("AOE radius boundary verified: target at 7.5m took 0 damage.")

	# Target behind brute should take 0 damage
	if not is_equal_approx(player_behind.health_component.current_health, behind_hp_before):
		printerr("TEST FAILED: Target behind brute took damage from forward slam!")
		get_tree().quit(1)
		return
	print("Directional slam boundary verified: target behind brute took 0 damage.")

	# Phase 4C: Recovery phase
	for _f: int in range(30):
		await get_tree().physics_frame
	await get_tree().process_frame

	_save_debug_screenshot("movies/brute_slam_recovery.png")
	if brute.weapon_hitbox.monitoring:
		printerr("TEST FAILED: weapon_hitbox remained monitoring during recovery phase!")
		get_tree().quit(1)
		return
	print("Slam recovery phase verified: hitbox deactivated.")

	# Cleanup targets
	player_target.queue_free()
	player_outside.queue_free()
	player_behind.queue_free()
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 5: Stun State Verification & Screenshot
	# -------------------------------------------------------------
	print("\n>>> PART 5: Stun State Verification")
	brute.health_component.take_damage(20.0)
	await get_tree().physics_frame
	await get_tree().process_frame

	if body_sm.state.name != "EnemyStun":
		printerr("TEST FAILED: Taking damage did not transition Brute to EnemyStun, current: ", body_sm.state.name)
		get_tree().quit(1)
		return
	_save_debug_screenshot("movies/brute_stun.png")
	print("EnemyStun transition verified.")
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 6: Defeat State Verification & Screenshot
	# -------------------------------------------------------------
	print("\n>>> PART 6: Defeat State Verification")
	var defeat_emitted: Array[bool] = []
	brute.defeat.connect(func() -> void: 
		defeat_emitted.append(true)
	)
	brute.health_component.take_damage(100.0)
	await get_tree().physics_frame
	await get_tree().process_frame

	if defeat_emitted.is_empty():
		printerr("TEST FAILED: Brute defeat signal was not emitted upon reaching 0 health!")
		get_tree().quit(1)
		return
	if body_sm.state.name != "EnemyDefeat":
		printerr("TEST FAILED: Defeat did not transition Brute to EnemyDefeat, current: ", body_sm.state.name)
		get_tree().quit(1)
		return

	# Deferred collision disabled verification
	await get_tree().physics_frame
	if not brute.collision_shape_3d.disabled:
		printerr("TEST FAILED: CollisionShape3D was not disabled on defeat!")
		get_tree().quit(1)
		return
	_save_debug_screenshot("movies/brute_defeat.png")
	print("EnemyDefeat transition and collision deactivation verified.")
	passed_steps += 1

	brute.queue_free()
	await get_tree().physics_frame

	# -------------------------------------------------------------
	# SUMMARY
	# -------------------------------------------------------------
	print("\n====================================================")
	print("  ALL ENEMY BRUTE TESTS PASSED! (", passed_steps, "/", total_steps, " parts)")
	print("====================================================")
	get_tree().quit(0)


## Captures the current viewport texture with visible debug shapes to movies/
func _save_debug_screenshot(file_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var tex: ViewportTexture = viewport.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img != null:
		var dir_err: Error = DirAccess.make_dir_recursive_absolute("movies")
		if dir_err == OK or dir_err == ERR_ALREADY_EXISTS:
			img.save_png(file_path)
			print("Saved screenshot: ", file_path, " (", img.get_width(), "x", img.get_height(), ")")
