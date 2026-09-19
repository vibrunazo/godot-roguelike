extends Node

const PlayerJump = preload("res://StateMachine/PlayerStates/player_jump.gd")
const PlayerJumpKick = preload("res://StateMachine/PlayerStates/player_jump_kick.gd")
const MeleeEnemyScene := preload("res://Enemy/melee_enemy.tscn")
const TestUtils = preload("res://test/test_utils.gd")

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

	# Space is the shared jump/dash button: out of combat it always dashes, so
	# the jump-only parts below pin a deterministic combat lock instead. All
	# wave-spawned roamers are removed and a single frozen foe is staged in the
	# +Z direction these parts treat as "forward", so neutral or +Z movement
	# resolves to jump no matter where the camera or enemies happen to be.
	for roamers: Node in get_tree().get_nodes_in_group("enemy"):
		roamers.queue_free()
	var wave_gate: Node = level.get_node_or_null("WaveObjective")
	if wave_gate != null:
		wave_gate.process_mode = Node.PROCESS_MODE_DISABLED
	var jump_lock_foe: Character = MeleeEnemyScene.instantiate() as Character
	level.add_child(jump_lock_foe)
	jump_lock_foe.global_position = spawn_pos + Vector3(0.0, 0.0, 3.0)
	if jump_lock_foe.ai_state_machine != null:
		jump_lock_foe.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	for i: int in range(5):
		await get_tree().physics_frame
		if player.current_target == jump_lock_foe:
			break
	check(player.current_target == jump_lock_foe, "Jump-only setup: auto-aim locks the staged foe")

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

	# Restore defaults and position
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	if sm.state != player_run:
		sm.request_state(player_run.name)
	await get_tree().physics_frame

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

	# Press jump while attacking (neutral input + locked target = jump).
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

	# Press jump while attacking Attack 3 (neutral + locked = jump, but
	# PlayerAttack3 forbids cancels, so it must be ignored).
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

	# 8A: Jump neutrally (input must be neutral: a held direction with a combat
	# lock snaps the leap onto the locked foe) and jump kick mid-air. The jump
	# must be ordered straight out of PlayerRun, before any attack-cancel
	# residue can stall the attack chain window. The staged lock foe stays
	# alive: out of combat Space dashes by design, so this part jumps in
	# combat, with the foe's bearing as the kick's aim.
	var reset_8a := func() -> void:
		player.global_position = spawn_pos
		player.velocity = Vector3.ZERO
		player.move_direction = Vector3.ZERO
		if sm.state != player_run:
			sm.request_state(player_run.name)
	reset_8a.call()
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break
	reset_8a.call()
	check(sm.state == player_run, "Back in PlayerRun before the JumpKick test (state: %s)" % sm.state.name)
	player.current_target = jump_lock_foe
	player.aim_direction = Vector3(0.0, 0.0, 1.0)
	player.move_direction = Vector3.ZERO
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started for JumpKick test")


	var expected_speed: float = player.attribute_component.get_current(AttributeComponent.STAT_SPEED) if player.attribute_component != null else 6.0



	# Mid-air attack order
	var attack_ev: InputEventAction = InputEventAction.new()
	attack_ev.action = "click"
	attack_ev.pressed = true
	sm._unhandled_input(attack_ev)

	check(sm.state == player_jump_kick, "Transitioned to PlayerJumpKick from mid-air jump")
	check(player_jump_kick.attack_animation_name == "JumpKick", "PlayerJumpKick uses JumpKick animation")

	# Wait for the lunge to activate and verify dash_speed adds horizontal kick
	# velocity on top of the (here neutral) jump carry (speeds up, never stalls).
	var saw_speedup: bool = false
	var max_kick_speed_h: float = 0.0
	for i: int in range(40):
		await get_tree().physics_frame
		var h_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		if h_speed > max_kick_speed_h:
			max_kick_speed_h = h_speed
		if player_jump_kick.lunging and h_speed > 0.1:
			saw_speedup = true
		if player.is_on_floor():
			break

	check(saw_speedup, "Jump kick dash speed adds to velocity (max horizontal: %.2f, speeds up from neutral)" % max_kick_speed_h)

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
	player.jump_requested = false
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
	player.move_direction = Vector3.ZERO
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
	player.attack_requested = false
	player.dash_requested = false
	player.jump_requested = false
	foe.queue_free()
	player.current_target = jump_lock_foe
	# Await the free so the auto-aim tick observes the freed foe exactly once
	# (it clears the kick lock it held) and re-pins the staged jump foe from
	# the manual acquisition above.
	for i: int in range(5):
		await get_tree().physics_frame
		if player.current_target == jump_lock_foe or not is_instance_valid(foe):
			break
	# The freed foe invalidates the manual lock above the same tick the tick
	# clears it: re-pin deterministically and confirm the lock survived.
	player.current_target = jump_lock_foe
	for i: int in range(5):
		await get_tree().physics_frame
		if player.current_target == jump_lock_foe:
			break
	check(player.current_target == jump_lock_foe, "Kick cleanup re-pins the staged jump foe")
	# Cache the live ratio count before Part 10's legacy mutations: Part 10
	# deliberately re-tunes the state's ratio, and its alias-setter write
	# restores the default afterwards, so nothing here may drift.
	var cached_default_ratio: float = player_jump.movement_speed_ratio

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
	check(is_equal_approx(player_jump.movement_speed_ratio, cached_default_ratio), "movement_speed_ratio defaults to %.1f" % cached_default_ratio)
	check(is_equal_approx(player_jump.movement_speed, cached_default_ratio), "movement_speed alias defaults to %.1f" % cached_default_ratio)
	check(is_equal_approx(player_jump.movement_ratio, cached_default_ratio), "movement_ratio alias defaults to %.1f" % cached_default_ratio)
	check(is_equal_approx(player_jump.movement_speed_ration, cached_default_ratio), "movement_speed_ration alias defaults to %.1f" % cached_default_ratio)

	input_comp.set_physics_process(false)
	var walk_speed: float = player.attribute_component.get_current(AttributeComponent.STAT_SPEED) if player.attribute_component != null else 6.0

	# Test movement_speed_ratio = 0.5 (half speed during jump). The legacy lock
	# must be idle here: with a lock and aligned input, the input controller
	# would apply its own dynamic landing ratio and override the state's tuned
	# default. Clearing the lock alone is not enough though - out of combat
	# Space always dashes - so the jump is raised directly on the character
	# instead of going through the shared Space routing.
	player.current_target = null
	player.auto_aim_range = 0.0
	player.move_direction = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.attack_requested = false
	player.dash_requested = false
	player.jump_requested = false
	for i: int in range(5):
		await get_tree().physics_frame
	player_jump.movement_speed_ratio = 0.5
	player_jump.control_ratio = 1.0
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	player.velocity = Vector3.ZERO

	player.jump_requested = true
	var jumped: bool = player_run.check_jump()
	player.jump_requested = false
	check(jumped and sm.state == player_jump, "Jump started with movement_speed_ratio = 0.5")
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

	# Part 10 is done with locks: free the staged foe so only Part 11's own
	# lock setup drives dispatch from here on. Also clear any buffered intent
	# the foe's death may have left pending, so the legacy parts below start
	# from a clean intent state.
	jump_lock_foe.queue_free()
	player.current_target = null
	player.attack_requested = false
	player.dash_requested = false
	player.jump_requested = false

	# Test alias setter
	player_jump.movement_speed_ration = 1.0


	check(is_equal_approx(player_jump.movement_speed_ratio, 1.0), "Setting movement_speed_ration alias updates movement_speed_ratio to 1.0")
	player.auto_aim_range = input_comp.auto_aim_range
	input_comp.set_physics_process(true)


	# =========================================================================
	# PART 11: Situational Jump/Dash Dispatch (single Space button)
	# =========================================================================
	print("\n>>> PART 11: Situational Jump/Dash Dispatch (shared Space button)")
	var dash_state_node: CharacterState = sm.get_node_or_null("PlayerDash") as CharacterState
	check(dash_state_node != null, "PlayerDash state exists under StateMachine")
	var camera: Camera3D = player.get_viewport().get_camera_3d()
	var cam_yaw: float = camera.global_rotation.y if camera != null else 0.0

	## Rotates a camera-relative WASD input vector (x = right, y = back) into a
	## world-space direction, mirroring PlayerInputComponent.update_movement_intent.
	var to_world := func(input_vec: Vector2) -> Vector3:
		return Vector3(input_vec.x, 0.0, input_vec.y).rotated(Vector3.UP, cam_yaw).normalized()

	## Puts the player back on the spawn floor in PlayerRun with clean motion and
	## a fresh dash cooldown, holding a facing snapshot while physics ticks.
	var reset_run := func(stop_cooldown: bool) -> void:
		player.global_position = spawn_pos
		player.velocity = Vector3.ZERO
		if stop_cooldown:
			var dash_cd: Timer = player.get_node_or_null("DashCooldown") as Timer
			if dash_cd != null:
				dash_cd.stop()
		if sm.state != player_run:
			sm.request_state(player_run.name)
		TestUtils.clear_lock_and_hold_facing(player)

	## Waits until the player lands back in PlayerRun.
	var await_run := func() -> bool:
		for i: int in range(120):
			await get_tree().physics_frame
			if player.is_on_floor() and sm.state == player_run:
				return true
		return false

	input_comp.set_physics_process(false)

	# 11A: Out of combat (no locked target), Space always dashes - even standing
	# still or moving in any direction. Auto-aim acquisition is disabled so a
	# roaming level enemy can never roll a surprise lock mid-press.
	player.auto_aim_range = 0.0
	for dir_vec: Vector2 in [Vector2.ZERO, Vector2(0.0, -1.0), Vector2(1.0, 0.0)]:
		reset_run.call(true)
		await await_run.call()
		reset_run.call(true)
		player.current_target = null
		player.move_direction = (to_world.call(dir_vec) as Vector3) if dir_vec != Vector2.ZERO else Vector3.ZERO
		sm._unhandled_input(jump_ev)
		check(sm.state == dash_state_node, "Out of combat: Space dashes with held input %s (state: %s)" % [str(dir_vec), sm.state.name])
		for i: int in range(90):
			await get_tree().physics_frame
			if sm.state == player_run:
				break
		check(sm.state == player_run, "Out-of-combat dash returned to PlayerRun")

	# 11B: In combat with a locked target to the north (+Z at the spawn point),
	# the button follows the example matrix: neutral/towards jumps, sideways/
	# backwards dashes. A frozen melee enemy acts as the locked target and the
	# aim bubble is tightened so only it qualifies. Input vectors are expressed
	# as raw world directions (input polling is disabled, so the camera is
	# irrelevant here): (0,0,-1) means holding -Z, i.e. "backwards".
	player.auto_aim_range = 2.5
	var lock_foe: Character = MeleeEnemyScene.instantiate() as Character
	level.add_child(lock_foe)
	if lock_foe.ai_state_machine != null:
		lock_foe.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	## Lock-on offset placing the foe dead ahead of the held "forward" axis (+Z).
	var north: Vector3 = Vector3(0.0, 0.0, 2.0)

	## Teleports the foe to the given world offset from the player and waits one
	## physics tick so the auto-aim lock lands on it.
	var lock_target := func(offset: Vector3) -> void:
		lock_foe.velocity = Vector3.ZERO
		lock_foe.global_position = player.global_position + offset
		player.force_retarget()
		await get_tree().physics_frame

	## Holds the given world-space input direction, presses Space, and returns
	## the resulting state name. Resets the player into a clean PlayerRun first.
	var press_space := func(input_dir: Vector3) -> String:
		reset_run.call(true)
		await await_run.call()
		reset_run.call(true)
		await lock_target.call(north)
		print("DIAG press_space: lock=", player.current_target, " lock_foe=", lock_foe, " dist=", player.global_position.distance_to(lock_foe.global_position), " range=", player.auto_aim_range, " state=", sm.state.name, " input=", input_dir)
		if player.current_target != lock_foe:
			printerr("TEST FAILED: lost the staged foe lock before pressing Space (input %s)." % str(input_dir))
			return "<no-lock>"
		player.move_direction = input_dir
		sm._unhandled_input(jump_ev)
		return sm.state.name

	reset_run.call(false)
	await await_run.call()
	reset_run.call(false)
	await lock_target.call(north)
	check(player.current_target == lock_foe, "In-combat setup: auto-aim locks onto the staged foe")

	var neutral_state: String = await press_space.call(Vector3.ZERO)
	check(neutral_state == player_jump.name, "In combat: neutral Space jumps (state: %s)" % neutral_state)
	if neutral_state == player_jump.name:
		var neutral_h: Vector2 = Vector2(player.velocity.x, player.velocity.z)
		check(neutral_h.length() < 0.1, "Neutral jump stays neutral (horizontal speed: %.2f)" % neutral_h.length())

	var forward_state: String = await press_space.call(Vector3(0.0, 0.0, 1.0))
	check(forward_state == player_jump.name, "In combat: towards-target + Space jumps (state: %s)" % forward_state)
	if forward_state == player_jump.name:
		check(player.velocity.y > 0.0, "In-combat forward jump gains upward velocity (vy: %.2f)" % player.velocity.y)

	# 11D: The input controller sizes the forward leap so it lands
	# jump_landing_gap meters short of the locked target, clamped to
	# [0.2, 1.0]. Predict the same ballistic range here and compare.
	var predict_ratio := func(offset: Vector3, gap: float) -> float:
		var height: float = player_jump.jump_height
		var speed: float = player.attribute_component.get_current(AttributeComponent.STAT_SPEED) if player.attribute_component != null else 8.0
		var grav: float = player.get_gravity().length()
		if is_zero_approx(grav):
			grav = 9.8
		var flight: float = 2.0 * sqrt(2.0 * height / grav)
		return clampf((offset.length() - gap) / maxf(speed * flight, 0.001), 0.2, 1.0)

	reset_run.call(true)
	await await_run.call()
	reset_run.call(true)
	await lock_target.call(north)
	check(player.current_target == lock_foe, "Sizing setup: auto-aim locks the staged foe")
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	var expected_ratio: float = predict_ratio.call(north, input_comp.jump_landing_gap)
	var actual_ratio: float = input_comp.get_forward_jump_ratio()
	check(is_equal_approx(actual_ratio, expected_ratio), "Dynamic forward ratio matches ballistic prediction (%.3f)" % actual_ratio)
	check(actual_ratio >= 0.2 and actual_ratio <= 1.0, "Dynamic forward ratio stays inside [0.2, 1.0] (%.3f)" % actual_ratio)
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	var ratio_before: float = player_jump.movement_speed_ratio
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Sized forward jump starts (state: %s)" % sm.state.name)
	if sm.state == player_jump:
		check(is_equal_approx(player_jump.movement_speed_ratio, expected_ratio), "Sized leap applies the dynamic ratio (%.3f)" % player_jump.movement_speed_ratio)
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break
	check(is_equal_approx(player_jump.movement_speed_ratio, ratio_before), "Sized leap restores the default ratio on landing (%.3f)" % player_jump.movement_speed_ratio)

	# A close target clamps the ratio at the 0.2 floor instead of undershooting.
	var close_offset: Vector3 = north.normalized() * (input_comp.jump_landing_gap + 0.2)
	reset_run.call(true)
	await await_run.call()
	reset_run.call(true)
	await lock_target.call(close_offset)
	check(player.current_target == lock_foe, "Clamp setup: auto-aim locks the close foe")
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	var close_ratio: float = input_comp.get_forward_jump_ratio()
	check(is_equal_approx(close_ratio, 0.2), "Close target clamps the forward ratio at 0.2 (%.3f)" % close_ratio)
	# Landing state is irrelevant after the clamp read; parking there is fine.
	for i: int in range(30):
		await get_tree().physics_frame

	# A target past full ballistic range clamps the ratio at the 1.0 ceiling.
	# Full range at the default speed/height is ~10 m, so the ceiling case needs
	# a ~12 m target: widen the aim bubble for it and stage the foe on the long
	# -Z stretch of the template floor (the +Z side ends ~8 m out).
	player.auto_aim_range = 15.0
	var far_offset: Vector3 = Vector3(0.0, 0.0, -12.0)
	reset_run.call(true)
	await await_run.call()
	reset_run.call(true)
	await lock_target.call(far_offset)
	check(player.current_target == lock_foe, "Ceiling setup: auto-aim locks the far foe")
	player.move_direction = Vector3(0.0, 0.0, -1.0)
	var far_ratio: float = input_comp.get_forward_jump_ratio()
	check(is_equal_approx(far_ratio, 1.0), "Far target clamps the forward ratio at 1.0 (%.3f)" % far_ratio)
	for i: int in range(30):
		await get_tree().physics_frame

	for side_dir: Vector3 in [Vector3(-1.0, 0.0, 0.0), Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, -1.0)]:
		var dash_result: String = await press_space.call(side_dir)
		check(dash_result == dash_state_node.name, "In combat: sideways/backwards %s + Space dashes (state: %s)" % [str(side_dir), dash_result])
		if dash_result == dash_state_node.name:
			var actual_dash: Vector3 = dash_state_node.get("direction") as Vector3
			check(actual_dash.dot(side_dir) > 0.99, "Dodge dash follows the held direction (dot: %.3f)" % actual_dash.dot(side_dir))
		for i: int in range(90):
			await get_tree().physics_frame
			if sm.state == player_run:
				break

	# 11C: A towards-target press snaps the leap onto the exact direction of the
	# locked foe. With the foe parked 30 degrees off the forward axis, W + Space
	# launches along the foe's bearing (so the follow-up kick cannot miss), not
	# along the raw input axis.
	var angled_offset: Vector3 = Vector3(0.0, 0.0, 2.0).rotated(Vector3.UP, deg_to_rad(30.0))
	var expected_snap: Vector3 = angled_offset.normalized()
	reset_run.call(true)
	await await_run.call()
	reset_run.call(true)
	await lock_target.call(angled_offset)
	check(player.current_target == lock_foe, "Snap setup: auto-aim locks the angled foe")
	player.move_direction = Vector3(0.0, 0.0, 1.0)
	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Snap setup: angled W + Space jumps (state: %s)" % sm.state.name)
	if sm.state == player_jump:
		var launch_h: Vector3 = Vector3(player.velocity.x, 0.0, player.velocity.z)
		check(not launch_h.is_zero_approx(), "Angled forward jump launches horizontally towards the foe")
		var launch_dir: Vector3 = launch_h.normalized() if not launch_h.is_zero_approx() else Vector3.ZERO
		check(launch_dir.dot(expected_snap) > 0.99, "Forward jump snaps to the locked target (dot: %.3f vs 30deg off-axis)" % launch_dir.dot(expected_snap))
	# Let the snap jump land before wrapping up.
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	# Cleanup: restore input polling and auto-aim, hold the facing, drop the foe.
	input_comp.set_physics_process(true)
	player.auto_aim_range = input_comp.auto_aim_range
	reset_run.call(false)
	await await_run.call()
	reset_run.call(false)
	lock_foe.queue_free()

	print("\n====================================================================")
	if failures == 0:
		print("  ALL JUMP ACTION & DASH REBIND TESTS PASSED!                       ")
	else:
		printerr("  JUMP ACTION TESTS FAILED WITH %d FAILURES                         " % failures)
	print("====================================================================")
	get_tree().quit(1 if failures > 0 else 0)

