## Automated verification suite for Enemy Brute.
## Verifies Enemy Large skeletal mesh, 2H slam AOE attack, timing, collision radius,
## difficulty-based wave spawning, and captures debug collision screenshots into movies/.
extends Node3D

var passed_steps: int = 0
var total_steps: int = 7


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
	if brute.health_component == null or brute.health_component.max_health <= 0.0:
		printerr("TEST FAILED: Brute max_health is invalid: ", brute.health_component.max_health if brute.health_component else 0.0)
		get_tree().quit(1)
		return
	if not is_equal_approx(brute.health_component.current_health, brute.health_component.max_health):
		printerr("TEST FAILED: Brute current_health does not match max_health initially.")
		get_tree().quit(1)
		return
	if brute.movement_speed <= 0.0:
		printerr("TEST FAILED: Brute movement_speed must be > 0.0, got: ", brute.movement_speed)
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
	for state_name: String in ["WalkSpace", "MeleeAttack", "PunchAttack", "Stun", "Defeat"]:
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
	if enemy_attack.damage <= 0.0:
		printerr("TEST FAILED: EnemyAttack damage must be > 0.0.")
		get_tree().quit(1)
		return
	if enemy_attack.knockback <= 0.0:
		printerr("TEST FAILED: EnemyAttack knockback must be > 0.0.")
		get_tree().quit(1)
		return
	if enemy_attack.attack_animation_name != "MeleeAttack":
		printerr("TEST FAILED: EnemyAttack attack_animation_name is ", enemy_attack.attack_animation_name, ", expected 'MeleeAttack'.")
		get_tree().quit(1)
		return
	if not enemy_attack.uninterruptable:
		printerr("TEST FAILED: EnemyAttack is not marked uninterruptable.")
		get_tree().quit(1)
		return
	if enemy_attack.cooldown <= 0.0:
		printerr("TEST FAILED: EnemyAttack cooldown must be > 0.0, got: ", enemy_attack.cooldown)
		get_tree().quit(1)
		return
	if enemy_attack.starting_cooldown < 0.0:
		printerr("TEST FAILED: EnemyAttack starting_cooldown cannot be negative, got: ", enemy_attack.starting_cooldown)
		get_tree().quit(1)
		return
	if enemy_attack.starting_cooldown > 0.0:
		if enemy_attack.cooldown_timer > enemy_attack.starting_cooldown or enemy_attack.cooldown_timer <= 0.0 or not enemy_attack.is_on_cooldown():
			printerr("TEST FAILED: EnemyAttack should be on starting cooldown upon spawn. Got: ", enemy_attack.cooldown_timer)
			get_tree().quit(1)
			return

	# Verify EnemyPunch node
	var enemy_punch: CharacterAttack = body_sm.get_node_or_null("EnemyPunch") as CharacterAttack
	if enemy_punch == null:
		printerr("TEST FAILED: EnemyPunch node missing on StateMachine.")
		get_tree().quit(1)
		return
	if enemy_punch.damage <= 0.0:
		printerr("TEST FAILED: EnemyPunch damage must be > 0.0.")
		get_tree().quit(1)
		return
	if enemy_punch.uninterruptable:
		printerr("TEST FAILED: EnemyPunch should not be uninterruptable.")
		get_tree().quit(1)
		return

	# Verify AIStateMachine nodes
	var ai_sm: AIStateMachine = brute.ai_state_machine
	var ai_slam: AIConditionalAttack = ai_sm.get_node_or_null("AISlam") as AIConditionalAttack
	if ai_slam == null:
		printerr("TEST FAILED: AISlam missing on AIStateMachine.")
		get_tree().quit(1)
		return
	if ai_slam.cooldown <= 0.0:
		printerr("TEST FAILED: AISlam cooldown must be > 0.0.")
		get_tree().quit(1)
		return
	if not ai_slam.is_on_cooldown():
		printerr("TEST FAILED: AISlam should report is_on_cooldown() true while EnemyAttack is on starting cooldown.")
		get_tree().quit(1)
		return
	if not ai_slam.can_break_stun:
		printerr("TEST FAILED: AISlam can_break_stun is not true.")
		get_tree().quit(1)
		return

	var ai_pursue: AIPursue = ai_sm.get_node_or_null("AIPursue") as AIPursue
	if ai_pursue == null or ai_pursue.attack_range <= 0.0:
		printerr("TEST FAILED: AIPursue missing or attack_range <= 0.")
		get_tree().quit(1)
		return
	if ai_pursue.attack_state_name != "EnemyPunch":
		printerr("TEST FAILED: AIPursue attack_state_name is ", ai_pursue.attack_state_name, ", expected 'EnemyPunch'.")
		get_tree().quit(1)
		return
	if ai_pursue.attack_cooldown <= 0.0:
		printerr("TEST FAILED: AIPursue attack_cooldown must be > 0.")
		get_tree().quit(1)
		return

	# Verify AIPursue cooldown decay
	ai_pursue.cooldown_timer = 2.0
	ai_pursue.evaluate_trigger(0.5)
	if not is_equal_approx(ai_pursue.cooldown_timer, 1.5):
		printerr("TEST FAILED: AIPursue evaluate_trigger did not decay cooldown_timer, got: ", ai_pursue.cooldown_timer)
		get_tree().quit(1)
		return
	ai_pursue.cooldown_timer = 0.0

	print("AnimationTree, dual attack states, AIStateMachine wiring, and punch cooldown verified.")
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 3: WaveObjective Spawning Difficulty Formula
	# -------------------------------------------------------------
	print("\n>>> PART 3: WaveObjective Difficulty Progression Spawning")
	var wave_obj := WaveObjective.new()
	add_child(wave_obj)

	# Test get_brute_count() for different progression levels:
	# Verifies non-negative count and non-decreasing monotonic scaling with difficulty.
	ProgressionState.difficulty_level = 1
	var c1: int = wave_obj.get_brute_count()
	if c1 < 0:
		printerr("TEST FAILED: get_brute_count() at diff 1 returned negative count: ", c1)
		get_tree().quit(1)
		return

	ProgressionState.difficulty_level = 2
	var c2: int = wave_obj.get_brute_count()
	if c2 < c1:
		printerr("TEST FAILED: get_brute_count() at diff 2 returned ", c2, " which is less than diff 1 (", c1, ").")
		get_tree().quit(1)
		return

	ProgressionState.difficulty_level = 3
	var c3: int = wave_obj.get_brute_count()
	if c3 < c2:
		printerr("TEST FAILED: get_brute_count() at diff 3 returned ", c3, " which is less than diff 2 (", c2, ").")
		get_tree().quit(1)
		return

	ProgressionState.difficulty_level = 4
	var c4: int = wave_obj.get_brute_count()
	if c4 < c3:
		printerr("TEST FAILED: get_brute_count() at diff 4 returned ", c4, " which is less than diff 3 (", c3, ").")
		get_tree().quit(1)
		return

	ProgressionState.difficulty_level = 5
	var c5: int = wave_obj.get_brute_count()
	if c5 < c4 or c5 <= c1:
		printerr("TEST FAILED: get_brute_count() at diff 5 returned ", c5, " which did not scale above diff 1 (", c1, ").")
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

	# Target inside AOE should take enemy_attack.damage
	var target_damage_dealt: float = target_hp_before - player_target.health_component.current_health
	if not is_equal_approx(target_damage_dealt, enemy_attack.damage):
		printerr("TEST FAILED: Target inside AOE took ", target_damage_dealt, " damage, expected ", enemy_attack.damage, "!")
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

	# Phase 4C: Hyper-Armor & Recovery phase
	# Brute is still in uninterruptable EnemyAttack. Dealing damage must NOT interrupt into EnemyStun!
	var hp_before_armor_hit: float = brute.health_component.current_health
	brute.health_component.take_damage(10.0)
	await get_tree().physics_frame
	await get_tree().process_frame
	if body_sm.state.name != "EnemyAttack":
		printerr("TEST FAILED: Brute was interrupted during uninterruptable EnemyAttack! State: ", body_sm.state.name)
		get_tree().quit(1)
		return
	if not is_equal_approx(brute.health_component.current_health, hp_before_armor_hit - 10.0):
		printerr("TEST FAILED: Brute did not take damage during hyper-armor!")
		get_tree().quit(1)
		return
	print("Hyper-armor verified: damage during 2H slam reduced health but did NOT interrupt into EnemyStun.")

	# Advance frames until EnemyAttack completes and transitions back to move/idle
	var wait_frames: int = 0
	while body_sm.state.name == "EnemyAttack" and wait_frames < 90:
		await get_tree().physics_frame
		wait_frames += 1
	await get_tree().process_frame

	_save_debug_screenshot("movies/brute_slam_recovery.png")
	if brute.weapon_hitbox.monitoring:
		printerr("TEST FAILED: weapon_hitbox remained monitoring during recovery phase!")
		get_tree().quit(1)
		return
	print("Slam recovery phase verified: hitbox deactivated, state: ", body_sm.state.name)

	# Cleanup slam targets
	player_target.queue_free()
	player_outside.queue_free()
	player_behind.queue_free()
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 5: Punch Attack Timing, Damage & Stunlockability
	# -------------------------------------------------------------
	print("\n>>> PART 5: Punch Attack Timing, Damage & Stunlockability")
	brute.global_position = Vector3.ZERO
	brute.velocity = Vector3.ZERO
	var punch_player: Character = player_scene.instantiate() as Character
	punch_player.position = Vector3(-0.3, 0.0, 2.4)
	add_child(punch_player)
	await get_tree().physics_frame
	await get_tree().process_frame
	brute.look_at_target(punch_player.global_position)

	var punch_slot: BoneAttachment3D = brute.find_child("PunchSlot", true, false) as BoneAttachment3D
	if punch_slot == null or punch_slot.hitbox == null:
		printerr("TEST FAILED: PunchSlot or PunchSlot hitbox missing on Brute.")
		get_tree().quit(1)
		return

	var punch_target_hp_before: float = punch_player.health_component.current_health

	# Trigger Punch
	print("Triggering EnemyPunch on Brute...")
	body_sm.request_state("EnemyPunch")
	await get_tree().physics_frame
	await get_tree().process_frame
	if body_sm.state.name != "EnemyPunch":
		printerr("TEST FAILED: request_state('EnemyPunch') failed, current state: ", body_sm.state.name)
		get_tree().quit(1)
		return

	# Windup check (~10 frames)
	for _f: int in range(10):
		await get_tree().physics_frame
	if punch_slot.hitbox.monitoring:
		printerr("TEST FAILED: Punch hitbox is monitoring during windup!")
		get_tree().quit(1)
		return
	if not is_equal_approx(punch_player.health_component.current_health, punch_target_hp_before):
		printerr("TEST FAILED: Punch target took damage during windup!")
		get_tree().quit(1)
		return
	print("Punch windup verified: hitbox inactive, no damage dealt.")

	# Apex check: advance frames to find active punch hitbox
	var saw_punch_monitoring: bool = false
	for _f: int in range(35):
		await get_tree().physics_frame
		if punch_slot.hitbox.monitoring:
			saw_punch_monitoring = true
	await get_tree().process_frame

	_save_debug_screenshot("movies/brute_punch_apex.png")

	if not saw_punch_monitoring:
		printerr("TEST FAILED: Punch hitbox was never activated during punch animation!")
		get_tree().quit(1)
		return

	var punch_damage: float = punch_target_hp_before - punch_player.health_component.current_health
	if not is_equal_approx(punch_damage, enemy_punch.damage):
		printerr("TEST FAILED: Punch dealt ", punch_damage, " damage, expected ", enemy_punch.damage, "!")
		get_tree().quit(1)
		return
	print("Punch hit verified: dealt damage to target in range.")

	# Wait until Punch finishes
	var p_wait: int = 0
	while body_sm.state.name == "EnemyPunch" and p_wait < 60:
		await get_tree().physics_frame
		p_wait += 1

	# Test stunlockability during punch (punch is interruptable)
	body_sm.request_state("EnemyPunch")
	await get_tree().physics_frame
	if body_sm.state.name != "EnemyPunch":
		printerr("TEST FAILED: Could not restart EnemyPunch for stunlock test.")
		get_tree().quit(1)
		return

	brute.health_component.take_damage(10.0)
	await get_tree().physics_frame
	await get_tree().process_frame
	if body_sm.state.name != "EnemyStun":
		printerr("TEST FAILED: Punch was NOT interrupted by damage! Current state: ", body_sm.state.name)
		get_tree().quit(1)
		return
	print("Stunlockability verified: Punch attack was interrupted into EnemyStun upon taking damage.")
	_save_debug_screenshot("movies/brute_stun.png")

	punch_player.queue_free()
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 6: AISlam Cooldown & Stun Break Verification
	# -------------------------------------------------------------
	print("\n>>> PART 6: AISlam Cooldown & Stun Break Verification")
	# Brute is currently in EnemyStun from Part 5!
	var slam_player: Character = player_scene.instantiate() as Character
	slam_player.position = Vector3(0.0, 0.0, 2.5) # within 3.5m
	add_child(slam_player)
	await get_tree().physics_frame
	await get_tree().process_frame

	# Ensure AISlam cooldown is 0 so it is ready
	ai_slam.cooldown_timer = 0.0
	if body_sm.state.name != "EnemyStun":
		printerr("TEST FAILED: Brute is not in EnemyStun before stun break test. State: ", body_sm.state.name)
		get_tree().quit(1)
		return

	# Evaluate trigger
	var trigger_result: bool = ai_slam.evaluate_trigger(0.016)
	if not trigger_result:
		printerr("TEST FAILED: ai_slam.evaluate_trigger() returned false while ready and in range!")
		get_tree().quit(1)
		return

	await get_tree().physics_frame
	await get_tree().process_frame
	if body_sm.state.name != "EnemyAttack":
		printerr("TEST FAILED: AISlam did not break out of EnemyStun into EnemyAttack! Current: ", body_sm.state.name)
		get_tree().quit(1)
		return
	print("Stun break verified: AISlam successfully broke free of EnemyStun into EnemyAttack.")

	if ai_slam.cooldown_timer < (ai_slam.cooldown - 0.1) or ai_slam.cooldown_timer > ai_slam.cooldown:
		printerr("TEST FAILED: AISlam cooldown_timer was not reset to cooldown (", ai_slam.cooldown, "), current: ", ai_slam.cooldown_timer)
		get_tree().quit(1)
		return
	print("Cooldown reset verified: AISlam cooldown set to ", ai_slam.cooldown, "s.")

	# Verify evaluate_trigger returns false while on cooldown
	var trigger_on_cooldown: bool = ai_slam.evaluate_trigger(0.016)
	if trigger_on_cooldown:
		printerr("TEST FAILED: AISlam triggered while on cooldown!")
		get_tree().quit(1)
		return
	print("Cooldown gating verified: AISlam cannot trigger while cooldown > 0.")

	# Wait for slam to complete
	var s_wait: int = 0
	while body_sm.state.name == "EnemyAttack" and s_wait < 90:
		await get_tree().physics_frame
		s_wait += 1

	slam_player.queue_free()
	passed_steps += 1

	# -------------------------------------------------------------
	# PART 7: Defeat State Verification & Screenshot
	# -------------------------------------------------------------
	print("\n>>> PART 7: Defeat State Verification")
	var defeat_emitted: Array[bool] = []
	brute.defeat.connect(func() -> void: 
		defeat_emitted.append(true)
	)
	brute.health_component.take_damage(brute.health_component.max_health)
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
