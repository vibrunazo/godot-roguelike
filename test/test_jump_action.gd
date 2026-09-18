extends Node

const PlayerJump = preload("res://StateMachine/PlayerStates/player_jump.gd")
const PlayerJumpKick = preload("res://StateMachine/PlayerStates/player_jump_kick.gd")
const MeleeEnemyScene := preload("res://Enemy/melee_enemy.tscn")

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if condition:
		print("  ok: ", message)
	else:
		failures += 1
		printerr("TEST FAILED: ", message)


func _ready() -> void:
	print("--- RUNNING JUMP ACTION & DASH REBIND TEST ---")

	# =========================================================================
	# PART 1: InputMap Bindings
	# =========================================================================
	print("\n>>> PART 1: InputMap Action Bindings")
	check(InputMap.has_action("dash"), "InputMap has 'dash' action")
	check(InputMap.has_action("jump"), "InputMap has 'jump' action")

	var dash_events: Array[InputEvent] = InputMap.action_get_events("dash")
	var has_left_shift: bool = false
	for ev: InputEvent in dash_events:
		if ev is InputEventKey:
			var iek: InputEventKey = ev as InputEventKey
			if iek.physical_keycode == KEY_SHIFT and iek.location == KeyLocation.KEY_LOCATION_LEFT:
				has_left_shift = true
				break
	check(has_left_shift, "dash action bound to Left Shift (physical_keycode KEY_SHIFT, location LEFT)")

	var jump_events: Array[InputEvent] = InputMap.action_get_events("jump")
	var has_space: bool = false
	for ev: InputEvent in jump_events:
		if ev is InputEventKey:
			var iek: InputEventKey = ev as InputEventKey
			if iek.physical_keycode == KEY_SPACE:
				has_space = true
				break
	check(has_space, "jump action bound to Spacebar (physical_keycode KEY_SPACE)")

	if failures > 0:
		get_tree().quit(1)
		return

	# =========================================================================
	# PART 2: Scene & Node Configuration
	# =========================================================================
	print("\n>>> PART 2: Node & State Configuration")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)

	var player: Character = level.get_node("Player") as Character
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	var player_run: PlayerRun = sm.get_node("PlayerRun") as PlayerRun
	var player_jump: PlayerJump = sm.get_node_or_null("PlayerJump") as PlayerJump

	check(player_jump != null, "PlayerJump state exists under StateMachine")
	check(player_run.jump_state == player_jump, "PlayerRun.jump_state wired to PlayerJump")
	check(player_jump.jump_height > 0.0, "jump_height is positive (current: %.2fm)" % player_jump.jump_height)
	check(player_jump.control_ratio >= 0.0 and player_jump.control_ratio <= 1.0, "control_ratio is within valid [0.0, 1.0] range (current: %.2f)" % player_jump.control_ratio)
	check(player_jump.jump_audio != null, "PlayerJump.jump_audio is assigned")
	if player_jump.jump_audio != null:
		check(player_jump.jump_audio.stream != null, "JumpAudio has an audio stream assigned")


	var player_jump_kick: PlayerJumpKick = sm.get_node_or_null("PlayerJumpKick") as PlayerJumpKick
	check(player_jump_kick != null, "PlayerJumpKick state exists under StateMachine")
	check(player_jump.attack_state == player_jump_kick, "PlayerJump.attack_state wired to PlayerJumpKick")
	var p_attack: CharacterAttack = sm.get_node_or_null("PlayerAttack") as CharacterAttack
	var p_attack2: CharacterAttack = sm.get_node_or_null("PlayerAttack2") as CharacterAttack
	var p_attack3: CharacterAttack = sm.get_node_or_null("PlayerAttack3") as CharacterAttack
	check(p_attack != null and p_attack.jump_state == player_jump, "PlayerAttack.jump_state wired to PlayerJump")
	check(p_attack2 != null and p_attack2.jump_state == player_jump, "PlayerAttack2.jump_state wired to PlayerJump")
	check(p_attack3 != null and p_attack3.jump_state == player_jump, "PlayerAttack3.jump_state wired to PlayerJump")

	if failures > 0:
		get_tree().quit(1)
		return

	# =========================================================================
	# PART 3: Live Jump Mechanics & Peak Height
	# =========================================================================
	print("\n>>> PART 3: Live Jump Execution & Peak Height")
	# Wait for player to settle on floor
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	check(player.is_on_floor() and sm.state == player_run, "Player settled on floor in PlayerRun")
	var start_y: float = player.global_position.y
	var spawn_pos: Vector3 = player.global_position

	# Dispatch jump action
	var jump_ev: InputEventAction = InputEventAction.new()
	jump_ev.action = "jump"
	jump_ev.pressed = true
	sm._unhandled_input(jump_ev)

	check(sm.state == player_jump, "Player transitioned to PlayerJump on jump action")
	check(is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.z), "Neutral jump has zero horizontal velocity (vx == 0, vz == 0)")
	var gravity_mag: float = player.get_gravity().length()
	var expected_v0: float = sqrt(2.0 * gravity_mag * player_jump.jump_height)
	check(is_equal_approx(player.velocity.y, expected_v0), "Initial upward velocity is sqrt(2*g*h) = %.2f m/s" % expected_v0)

	# Track jump apex
	var max_y: float = start_y
	var reached_apex: bool = false
	for i: int in range(90):
		await get_tree().physics_frame
		if player.global_position.y > max_y:
			max_y = player.global_position.y
		if player.velocity.y <= 0.0:
			reached_apex = true
			break

	check(reached_apex, "Player reached jump apex")
	var measured_height: float = max_y - start_y
	print("  Measured jump height: %.3f m (expected: %.3f m)" % [measured_height, player_jump.jump_height])
	check(absf(measured_height - player_jump.jump_height) < 0.15, "Measured apex matches jump_height within tolerance (2.5m)")

	# Wait for player to land back on floor
	var landed: bool = false
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			landed = true
			break

	check(landed, "Player landed back on floor and transitioned to PlayerRun")
	var horizontal_drift: float = Vector2(player.global_position.x - spawn_pos.x, player.global_position.z - spawn_pos.z).length()
	check(horizontal_drift < 0.05, "Neutral jump does not jump forward (horizontal drift: %.4fm < 0.05m)" % horizontal_drift)

	# =========================================================================
	# PART 4: Horizontal Control Ratio (0.0 vs 1.0)
	# =========================================================================
	print("\n>>> PART 4: Horizontal Air Control Ratio (0.0 vs 1.0)")
	var input_comp: PlayerInputComponent = player.get_node("PlayerInputComponent") as PlayerInputComponent
	input_comp.set_physics_process(false)

	# Test control_ratio = 0.0: strictly maintains launch momentum, ignores in-air steering
	player_jump.control_ratio = 0.0
	var launch_speed: float = 1.0
	player.velocity = Vector3(0.0, 0.0, launch_speed)
	player.move_direction = Vector3.ZERO

	# Trigger jump
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started for control_ratio = 0.0 test")

	# In mid-air, apply sideways input (move_direction.x = 1.0)
	player.move_direction = Vector3(1.0, 0.0, 0.0)
	for i: int in range(10):
		await get_tree().physics_frame

	check(is_zero_approx(player.velocity.x), "control_ratio = 0.0 prevents steering along X axis (velocity.x == 0.0)")
	check(is_equal_approx(player.velocity.z, launch_speed), "control_ratio = 0.0 preserves launch velocity along Z axis (velocity.z == %.1f)" % launch_speed)

	# Stop horizontal motion so player lands safely on the platform
	player.move_direction = Vector3.ZERO
	player.velocity.x = 0.0
	player.velocity.z = 0.0

	# Wait for landing
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Test control_ratio = 1.0: allows full air steering
	player_jump.control_ratio = 1.0
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO

	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started for control_ratio = 1.0 test")

	# In mid-air, steer sideways
	player.move_direction = Vector3(1.0, 0.0, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	check(player.velocity.x > 0.0, "control_ratio = 1.0 allows full steering (velocity.x > 0.0: %.2f)" % player.velocity.x)

	# Stop horizontal motion so player lands safely on the platform
	player.move_direction = Vector3.ZERO
	player.velocity.x = 0.0
	player.velocity.z = 0.0

	# Wait for landing
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	input_comp.set_physics_process(true)

	# =========================================================================
	# PART 5: Configurable Jump Height
	# =========================================================================
	print("\n>>> PART 5: Configurable Jump Height")
	player_jump.jump_height = 4.0
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO

	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started with jump_height = 4.0")
	var expected_v0_4: float = sqrt(2.0 * gravity_mag * 4.0)
	check(is_equal_approx(player.velocity.y, expected_v0_4), "Higher jump calculates proportional upward velocity (%.2f m/s)" % expected_v0_4)

	# Wait for landing
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Restore defaults
	player_jump.jump_height = 2.5
	player_jump.control_ratio = 1.0

	# =========================================================================
	# PART 6: Cumulative Air Control & Coasting
	# =========================================================================
	print("\n>>> PART 6: Cumulative Air Control & Coasting")
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	input_comp.set_physics_process(false)
	player_jump.control_ratio = 0.5
	var init_fwd: float = 2.0
	player.velocity = Vector3(0.0, 0.0, init_fwd)
	player.move_direction = Vector3.ZERO

	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started with forward velocity for coasting test")

	# Steer backward mid-air to slow down
	player.move_direction = Vector3(0.0, 0.0, -1.0)
	for i: int in range(10):
		await get_tree().physics_frame
	var slowed_v: float = player.velocity.z
	check(slowed_v < init_fwd, "Steering backwards reduced forward velocity (%.2f < %.2f)" % [slowed_v, init_fwd])

	# Release input mid-air (neutral input)
	player.move_direction = Vector3.ZERO
	for i: int in range(10):
		await get_tree().physics_frame

	# When keys released, character MUST NOT accelerate forward again!
	check(player.velocity.z <= slowed_v + 0.01, "Releasing keys mid-air does NOT accelerate forward again (vz: %.2f <= %.2f)" % [player.velocity.z, slowed_v])

	# Wait for landing
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# =========================================================================
	# PART 7: Attack-to-Jump Canceling
	# =========================================================================
	print("\n>>> PART 7: Attack-to-Jump Canceling")
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Test Attack 1 (dash_cancel = true) can cancel into jump
	check(p_attack.dash_cancel == true, "PlayerAttack has dash_cancel = true")
	sm.request_state("PlayerAttack")
	check(sm.state == p_attack, "Entered PlayerAttack")
	await get_tree().physics_frame

	# Press jump while attacking
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "PlayerAttack successfully cancelled into PlayerJump")

	# Land
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Test Attack 3 (dash_cancel = false) CANNOT cancel into jump
	check(p_attack3.dash_cancel == false, "PlayerAttack3 has dash_cancel = false")
	sm.request_state("PlayerAttack3")
	check(sm.state == p_attack3, "Entered PlayerAttack3")
	await get_tree().physics_frame

	# Press jump while attacking
	sm._unhandled_input(jump_ev)
	check(sm.state == p_attack3, "PlayerAttack3 cannot be cancelled by jump (remains in PlayerAttack3)")

	# Wait or return to PlayerRun
	for i: int in range(90):
		await get_tree().physics_frame
		if sm.state == player_run:
			break
	if sm.state != player_run:
		sm.request_state("PlayerRun")

	# =========================================================================
	# PART 8: Airborne Jump Kick Execution, Lunge Speedup & Landing Cancel
	# =========================================================================
	print("\n>>> PART 8: Airborne Jump Kick Execution, Lunge Speedup & Landing Cancel")
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# 8A: Jump forward with full speed (8 m/s) and jump kick
	player.auto_aim_range = 0.0
	player.current_target = null
	player.aim_direction = Vector3(0.0, 0.0, 1.0)
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started for JumpKick test")


	var expected_speed: float = player.attribute_component.get_current(AttributeComponent.STAT_SPEED) if player.attribute_component != null else 6.0
	var initial_jump_speed_z: float = player.velocity.z
	check(initial_jump_speed_z >= expected_speed - 0.5, "Forward jump has full speed (vz: %.2f >= %.2f)" % [initial_jump_speed_z, expected_speed - 0.5])



	# Mid-air attack order
	var attack_ev: InputEventAction = InputEventAction.new()
	attack_ev.action = "click"
	attack_ev.pressed = true
	sm._unhandled_input(attack_ev)

	check(sm.state == player_jump_kick, "Transitioned to PlayerJumpKick from mid-air jump")
	check(player_jump_kick.attack_animation_name == "JumpKick", "PlayerJumpKick uses JumpKick animation")

	# Wait for lunge to activate and verify dash_speed adds to jump velocity (speeds up, not slows down)
	var saw_speedup: bool = false
	var max_kick_speed_z: float = initial_jump_speed_z
	for i: int in range(40):
		await get_tree().physics_frame
		if player.velocity.z > max_kick_speed_z:
			max_kick_speed_z = player.velocity.z
		if player_jump_kick.lunging and player.velocity.z > initial_jump_speed_z:
			saw_speedup = true
		if player.is_on_floor():
			break

	check(saw_speedup, "Jump kick dash speed adds to velocity (max vz: %.2f > %.2f, speeds up)" % [max_kick_speed_z, initial_jump_speed_z])

	# Wait for landing: landing cancels jump kick instantly into PlayerRun
	for i: int in range(120):
		if player.is_on_floor() and sm.state == player_run:
			break
		await get_tree().physics_frame
	check(sm.state == player_run, "Landing cancels JumpKick immediately into PlayerRun without waiting for animation")

	# 8B: Landing cancel directly into ground attack
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Jump and wait until descending
	sm._unhandled_input(jump_ev)
	for i: int in range(60):
		await get_tree().physics_frame
		if player.velocity.y < 0.0:
			break

	# Execute JumpKick during descent
	sm._unhandled_input(attack_ev)
	check(sm.state == player_jump_kick, "JumpKick started during descent for landing cancel test")

	# Buffer ground attack intent while still mid-air in JumpKick
	await get_tree().physics_frame
	sm._unhandled_input(attack_ev)

	# On landing, it should cancel JumpKick in mid-animation and immediately transition to PlayerAttack
	var transitioned_to_ground_attack: bool = false
	for i: int in range(60):
		await get_tree().physics_frame
		if sm.state == p_attack:
			transitioned_to_ground_attack = true
			break
		if player.is_on_floor() and sm.state == player_run:
			break

	check(transitioned_to_ground_attack, "Landing cancels JumpKick and instantly transitions to ground PlayerAttack")
	input_comp.set_physics_process(true)

	# =========================================================================
	# PART 9: JumpKick Strikes With the Feet Slot, Never the Sword
	# =========================================================================
	print("\n>>> PART 9: JumpKick FeetSlot Hitbox")
	var sword_slot: WeaponSlot = player.get_node("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot") as WeaponSlot
	var feet_slot: WeaponSlot = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/FeetSlot") as WeaponSlot
	check(feet_slot != null, "FeetSlot exists on the player rig")
	var sword_comp: AttackComponent = null
	if sword_slot != null:
		sword_comp = sword_slot.hitbox.get_node_or_null("AttackComponent") as AttackComponent
	check(player_jump_kick.weapon_slot == feet_slot, "PlayerJumpKick strikes with FeetSlot")
	var kick_comp: AttackComponent = player_jump_kick.get_attack_component()
	check(kick_comp != null and kick_comp != sword_comp, "Kick resolves a non-sword AttackComponent")
	check(p_attack.get_attack_component() == sword_comp, "Sword attacks still resolve the sword component (legacy path)")

	# Live kick against a frozen enemy: only the feet window may open and hit.
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break
	var foe: Character = MeleeEnemyScene.instantiate() as Character
	level.add_child(foe)
	foe.global_position = player.global_position + Vector3(0.0, 0.0, 1.2)
	foe.velocity = Vector3.ZERO
	if foe.ai_state_machine != null:
		foe.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	input_comp.set_physics_process(false)
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started for feet-hitbox test")
	sm._unhandled_input(attack_ev)
	check(sm.state == player_jump_kick, "JumpKick started for feet-hitbox test")
	var sword_area: Area3D = sword_slot.hitbox
	var feet_area: Area3D = feet_slot.hitbox
	var foe_hp_before: float = foe.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var saw_feet_window: bool = false
	var sword_ever_on: bool = false
	for i: int in range(60):
		# Read after the step: test-driven transitions happen mid-physics-step,
		# so pre-step reads can still see the canceled attack's hitbox before
		# its deferred disable flushes. Post-step reads observe settled state.
		await get_tree().physics_frame
		if sm.state != player_jump_kick:
			break
		if feet_area.monitoring:
			saw_feet_window = true
			foe.global_position = feet_area.global_position
		if sword_area.monitoring:
			sword_ever_on = true
	check(saw_feet_window, "Feet hitbox opens during the kick strike window")
	check(not sword_ever_on, "Sword hitbox never opens during the kick")
	var foe_hp_after: float = foe.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var expected_kick: float = player_jump_kick.damage * player.get_damage_modifier() * foe.attribute_component.get_damage_multiplier(&"physical")
	check(is_equal_approx(foe_hp_before - foe_hp_after, expected_kick), "Kick damages the enemy through the feet hitbox (dealt %.1f)" % expected_kick)

	# Landing cancel must leave no hitbox stuck on.
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break
	check(not feet_area.monitoring and not sword_area.monitoring, "Landing cancel leaves both hitboxes off")
	player.move_direction = Vector3.ZERO
	input_comp.set_physics_process(true)
	foe.queue_free()

	# =========================================================================
	# PART 10: Horizontal Movement Speed Ratio (movement_speed_ratio)
	# =========================================================================
	print("\n>>> PART 10: Horizontal Movement Speed Ratio (movement_speed_ratio)")
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Check default ratio and aliases
	check(is_equal_approx(player_jump.movement_speed_ratio, 1.0), "movement_speed_ratio defaults to 1.0")
	check(is_equal_approx(player_jump.movement_speed, 1.0), "movement_speed alias defaults to 1.0")
	check(is_equal_approx(player_jump.movement_ratio, 1.0), "movement_ratio alias defaults to 1.0")
	check(is_equal_approx(player_jump.movement_speed_ration, 1.0), "movement_speed_ration alias defaults to 1.0")

	input_comp.set_physics_process(false)
	var walk_speed: float = player.attribute_component.get_current(AttributeComponent.STAT_SPEED) if player.attribute_component != null else 6.0

	# Test movement_speed_ratio = 0.5 (half speed during jump)
	player_jump.movement_speed_ratio = 0.5
	player_jump.control_ratio = 1.0
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	player.velocity = Vector3.ZERO

	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started with movement_speed_ratio = 0.5")
	var expected_half_speed: float = walk_speed * 0.5
	check(is_equal_approx(player.velocity.z, expected_half_speed), "Forward jump launch speed reduced to half walk speed (vz: %.2f == %.2f)" % [player.velocity.z, expected_half_speed])

	# Mid-air steering with ratio 0.5 should cap horizontal speed at half walk speed
	player.move_direction = Vector3(1.0, 0.0, 0.0)
	for i: int in range(20):
		await get_tree().physics_frame
		if player.is_on_floor():
			break

	var mid_air_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	check(mid_air_speed <= expected_half_speed + 0.05, "Mid-air steering speed is capped at half walk speed (%.2f <= %.2f)" % [mid_air_speed, expected_half_speed + 0.05])

	# Land and reset
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(90):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Test alias setter
	player_jump.movement_speed_ration = 1.0
	check(is_equal_approx(player_jump.movement_speed_ratio, 1.0), "Setting movement_speed_ration alias updates movement_speed_ratio to 1.0")
	input_comp.set_physics_process(true)

	print("\n====================================================================")
	if failures == 0:
		print("  ALL JUMP ACTION & DASH REBIND TESTS PASSED!                       ")
	else:
		printerr("  JUMP ACTION TESTS FAILED WITH %d FAILURES                         " % failures)
	print("====================================================================")
	get_tree().quit(1 if failures > 0 else 0)

