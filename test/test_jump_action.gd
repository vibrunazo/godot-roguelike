extends Node

const PlayerJump = preload("res://StateMachine/PlayerStates/player_jump.gd")
const PlayerJumpKick = preload("res://StateMachine/PlayerStates/player_jump_kick.gd")

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
	check(is_equal_approx(player_jump.jump_height, 2.5), "Default jump_height is 2.5m")
	check(player_jump.control_ratio >= 0.0 and player_jump.control_ratio <= 1.0, "control_ratio is within valid [0.0, 1.0] range (current: %.2f)" % player_jump.control_ratio)
	check(player_jump.jump_audio != null, "PlayerJump.jump_audio is assigned")
	if player_jump.jump_audio != null:
		check(player_jump.jump_audio.stream != null and player_jump.jump_audio.stream.resource_path.ends_with("140867__juskiddink__boing.wav"), "JumpAudio uses boing.wav sound effect")

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
	# PART 8: Airborne Jump Kick Execution
	# =========================================================================
	print("\n>>> PART 8: Airborne Jump Kick Execution")
	player.global_position = spawn_pos
	player.velocity = Vector3.ZERO
	player.move_direction = Vector3.ZERO
	for i: int in range(15):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break

	sm._unhandled_input(jump_ev)
	check(sm.state == player_jump, "Jump started for JumpKick test")
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Mid-air attack order
	var attack_ev: InputEventAction = InputEventAction.new()
	attack_ev.action = "click"
	attack_ev.pressed = true
	sm._unhandled_input(attack_ev)

	check(sm.state == player_jump_kick, "Transitioned to PlayerJumpKick from mid-air jump")
	check(player_jump_kick.attack_animation_name == "JumpKick", "PlayerJumpKick uses JumpKick animation")

	# Let kick progress and land
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state == player_run:
			break
	check(sm.state == player_run, "Player safely landed and returned to PlayerRun after JumpKick")
	input_comp.set_physics_process(true)

	print("\n====================================================================")
	if failures == 0:
		print("  ALL JUMP ACTION & DASH REBIND TESTS PASSED!                       ")
	else:
		printerr("  JUMP ACTION TESTS FAILED WITH %d FAILURES                         " % failures)
	print("====================================================================")
	get_tree().quit(1 if failures > 0 else 0)

