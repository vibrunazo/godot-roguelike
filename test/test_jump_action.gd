## The player's jump, jump kick and the shared jump/dash button:
## - a neutral jump rises to jump_height (launch speed sqrt(2 g h)) and lands
##   where it took off,
## - air control: control_ratio 0 keeps the launch momentum, 1 steers freely,
##   releasing the steering never re-accelerates, and movement_speed_ratio
##   scales both the launch and the air speed,
## - the jump button dashes out of combat whatever the held direction; in
##   combat it jumps when standing or moving toward the locked target (within
##   jump_dash_alignment) and dashes along the held direction otherwise,
## - a combat leap snaps onto the target's bearing, lands jump_landing_gap
##   short of it, and its sizing ratio is clamped to the input component's
##   limits and restored on landing,
## - attacks with dash_cancel can be jump-cancelled, others cannot,
## - attacking mid-air performs the jump kick: it lunges, strikes with its own
##   weapon slot (never the sword), and landing cancels it into running, or
##   into the ground attack when an attack was pressed during the kick.
## Balance values are read from the live nodes or set by the test.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned jump height for the air-control tests, so the character stays
## airborne for the whole steering window whatever the tuned height.
const TEST_JUMP_HEIGHT: float = 2.0
## Test-owned air-control settings.
const HALF_CONTROL: float = 0.5
const HALF_SPEED_RATIO: float = 0.5
## Physics ticks of mid-air steering in the air-control tests.
const STEER_FRAMES: int = 10
## Test-owned landing gap for the leap-sizing tests, wide enough that the
## landing capsule never touches the target's.
const LANDING_GAP: float = 2.0
## Test-owned tolerances: apex sampling at the physics rate, landing position
## (the air time is quantized to ticks) and "landed in place".
const APEX_TOLERANCE: float = 0.15
const LANDING_TOLERANCE: float = 0.3
const IN_PLACE_TOLERANCE: float = 0.05
## Degrees on either side of the jump/dash alignment threshold the dispatch
## test holds its input at.
const ALIGNMENT_MARGIN_DEGREES: float = 10.0
## Test-owned foe health, so no hit here can kill it.
const FOE_HEALTH: float = 100000.0
## Frame budget for one jump or attack.
const ACTION_FRAMES: int = 600

var _arena: Node3D
var _player: Character
var _input: PlayerInputComponent
var _run: CharacterState
var _jump: PlayerJump
var _kick: CharacterAttack
var _home: Vector3


func before_each() -> void:
	_arena = load_arena()
	_home = (_arena.get_node("PlayerSpawn") as Node3D).global_position
	_player = spawn(PLAYER_SCENE, _arena, _home) as Character
	_input = _player.get_node("PlayerInputComponent") as PlayerInputComponent
	# Live input polling off: the test sets move_direction and aim itself.
	_input.set_physics_process(false)
	_run = _player.state_machine.get_node("PlayerRun") as CharacterState
	_jump = _run.jump_state as PlayerJump
	_kick = _jump.attack_state as CharacterAttack if _jump != null else null
	await _wait_running("the player should settle")
	check(_jump != null and _kick != null, "setup: running should lead to a jump state, and the jump to a kick")


# --- Jump -------------------------------------------------------------------

func test_a_neutral_jump_rises_to_its_jump_height_and_lands_in_place() -> void:
	await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.5)
	for height: float in [_jump.jump_height, _jump.jump_height * 1.5]:
		_jump.jump_height = height
		await _reset_at_home()
		var start: Vector3 = _player.global_position
		press_action(&"jump")
		if not await wait_until(func() -> bool: return _state() == _jump.name, "a neutral press in combat should jump", 10):
			return
		check_approx(_player.velocity.y, sqrt(2.0 * _player.get_gravity().length() * height), "the launch speed should be sqrt(2 g h) for jump_height %.2f" % height, 0.001)
		check(_horizontal(_player.velocity).is_zero_approx(), "a neutral jump should have no horizontal velocity")
		var apex: Array[float] = [start.y]
		await wait_until(func() -> bool:
			apex[0] = maxf(apex[0], _player.global_position.y)
			return _player.velocity.y <= 0.0, "the jump should reach its apex", ACTION_FRAMES)
		check_approx(apex[0] - start.y, height, "the jump should peak at jump_height %.2f" % height, APEX_TOLERANCE)
		await _wait_running("the jump should land back in running")
		check(_horizontal(_player.global_position - start).length() < IN_PLACE_TOLERANCE, "a neutral jump should land where it took off")


func test_zero_air_control_keeps_the_launch_momentum() -> void:
	_jump.jump_height = TEST_JUMP_HEIGHT
	_jump.control_ratio = 0.0
	var launch: Vector3 = Vector3.BACK * _speed() * _jump.movement_speed_ratio
	_player.state_machine.request_state(_jump.name, {"direction": Vector3.BACK})
	check_approx(_player.velocity.z, launch.z, "the launch should carry the jump speed along its direction")
	_player.move_direction = Vector3.RIGHT
	await wait_physics_frames(STEER_FRAMES)
	if not check(_state() == _jump.name, "setup: the player should still be airborne"):
		return
	check(is_zero_approx(_player.velocity.x), "with control_ratio 0 steering should not change the velocity")
	check_approx(_player.velocity.z, launch.z, "with control_ratio 0 the launch momentum should be kept")


func test_full_air_control_steers_mid_air() -> void:
	_jump.jump_height = TEST_JUMP_HEIGHT
	_jump.control_ratio = 1.0
	_player.state_machine.request_state(_jump.name, {"direction": Vector3.ZERO})
	_player.move_direction = Vector3.RIGHT
	await wait_physics_frames(2)
	check(_player.velocity.x > 0.0, "with control_ratio 1 steering should accelerate the player mid-air")


func test_releasing_the_steering_mid_air_never_reaccelerates() -> void:
	_jump.jump_height = TEST_JUMP_HEIGHT
	_jump.control_ratio = HALF_CONTROL
	_player.state_machine.request_state(_jump.name, {"direction": Vector3.BACK})
	var launch_speed: float = _player.velocity.z
	_player.move_direction = Vector3.FORWARD
	await wait_physics_frames(STEER_FRAMES)
	var slowed: float = _player.velocity.z
	check(slowed < launch_speed, "steering against the launch should slow the jump")
	_player.move_direction = Vector3.ZERO
	var fastest: float = slowed
	for frame: int in range(STEER_FRAMES):
		await get_tree().physics_frame
		fastest = maxf(fastest, _player.velocity.z)
	check(_state() == _jump.name, "setup: the player should still be airborne")
	check(fastest <= slowed + 0.01, "releasing the steering should coast, never re-accelerate (peaked at %.2f after slowing to %.2f)" % [fastest, slowed])


func test_movement_speed_ratio_scales_the_launch_and_the_air_speed() -> void:
	_jump.jump_height = TEST_JUMP_HEIGHT
	_jump.control_ratio = 1.0
	_jump.movement_speed_ratio = HALF_SPEED_RATIO
	var capped: float = _speed() * HALF_SPEED_RATIO
	_player.state_machine.request_state(_jump.name, {"direction": Vector3.BACK})
	check_approx(_player.velocity.z, capped, "the launch should be movement_speed_ratio times the walk speed")
	_player.move_direction = Vector3.RIGHT
	await wait_physics_frames(STEER_FRAMES * 2)
	check(_state() == _jump.name, "setup: the player should still be airborne")
	check(_horizontal(_player.velocity).length() <= capped + 0.05, "steering mid-air should stay capped at movement_speed_ratio times the walk speed")


# --- Shared jump/dash button -------------------------------------------------

func test_out_of_combat_the_jump_button_always_dashes() -> void:
	check(_player.current_target == null, "setup: no target in an empty arena")
	for held: Vector3 in [Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT]:
		await _reset_at_home()
		_player.move_direction = held
		press_action(&"jump")
		if not await wait_until(func() -> bool: return _state() == _run.dash_state.name, "out of combat the jump button should dash (holding %s)" % held, 10):
			return
		_player.move_direction = Vector3.ZERO


func test_in_combat_the_jump_button_jumps_toward_the_target_and_dashes_otherwise() -> void:
	var foe: Character = await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.5)
	var threshold: float = rad_to_deg(acos(clampf(_input.jump_dash_alignment, -1.0, 1.0)))
	var inside: float = maxf(threshold - ALIGNMENT_MARGIN_DEGREES, 0.0)
	var outside: float = minf(threshold + ALIGNMENT_MARGIN_DEGREES, 180.0)
	var cases: Array[Dictionary] = [
		{"held": Vector3.ZERO, "jumps": true, "what": "standing"},
		{"held": Vector3.BACK, "jumps": true, "what": "toward the target"},
		{"held": Vector3.BACK.rotated(Vector3.UP, deg_to_rad(inside)), "jumps": true, "what": "%.0f degrees off the target (inside the alignment)" % inside},
		{"held": Vector3.BACK.rotated(Vector3.UP, deg_to_rad(outside)), "jumps": false, "what": "%.0f degrees off the target (outside the alignment)" % outside},
		{"held": Vector3.FORWARD, "jumps": false, "what": "away from the target"},
	]
	for case: Dictionary in cases:
		await _reset_at_home()
		if not await wait_until(func() -> bool: return _player.current_target == foe, "setup: the foe should stay locked"):
			return
		var held: Vector3 = case["held"]
		_player.move_direction = held
		press_action(&"jump")
		var expected: String = _jump.name if case["jumps"] else _run.dash_state.name
		var entered: bool = await wait_until(func() -> bool: return _state() == expected, "in combat, holding %s should %s" % [case["what"], "jump" if case["jumps"] else "dash"], 10)
		if entered and not case["jumps"]:
			check((_run.dash_state.get("direction") as Vector3).dot(held) > 0.99, "the dodge should dash along the held direction (%s)" % case["what"])
		_player.move_direction = Vector3.ZERO


func test_a_combat_leap_snaps_onto_the_target_bearing() -> void:
	var threshold: float = rad_to_deg(acos(clampf(_input.jump_dash_alignment, -1.0, 1.0)))
	var off_axis: Vector3 = Vector3.BACK.rotated(Vector3.UP, deg_to_rad(threshold * 0.5))
	var foe: Character = await _lock_foe(off_axis * _aim().auto_aim_range * 0.5)
	_player.move_direction = Vector3.BACK
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _jump.name, "holding roughly toward the target should jump", 10):
		return
	var launch: Vector3 = _horizontal(_player.velocity)
	if not check(not launch.is_zero_approx(), "the leap should launch horizontally"):
		return
	var bearing: Vector3 = _horizontal(foe.global_position - _player.global_position).normalized()
	check(launch.normalized().dot(bearing) > 0.99, "the leap should follow the target's bearing, not the held direction")


func test_a_combat_leap_lands_its_landing_gap_short_of_the_target_and_restores_its_ratio() -> void:
	_input.jump_landing_gap = LANDING_GAP
	# Midway between the landing gap and the edge of the aim range, so the leap
	# is sized well inside its clamp limits.
	var foe: Character = await _lock_foe(Vector3.BACK * (LANDING_GAP + _aim().auto_aim_range * 0.9) * 0.5)
	_player.move_direction = Vector3.BACK
	var ratio: float = _input.get_forward_jump_ratio()
	if not check(ratio > _input.min_forward_jump_ratio and ratio < _input.max_forward_jump_ratio, "setup: the leap ratio should be unclamped at this distance (%.3f)" % ratio):
		return
	var default_ratio: float = _jump.movement_speed_ratio
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _jump.name, "holding toward the target should jump", 10):
		return
	check(not is_equal_approx(_jump.movement_speed_ratio, default_ratio), "the leap should apply its sized ratio")
	# No input mid-air: the leap coasts on its launch velocity.
	_player.move_direction = Vector3.ZERO
	if not await wait_until(func() -> bool: return _state() != _jump.name, "the leap should land", ACTION_FRAMES):
		return
	check_approx(_horizontal(foe.global_position - _player.global_position).length(), LANDING_GAP, "the leap should land jump_landing_gap short of the target", LANDING_TOLERANCE)
	check_approx(_jump.movement_speed_ratio, default_ratio, "landing should restore the jump's default ratio")


func test_the_leap_ratio_is_clamped_to_its_limits() -> void:
	_input.jump_landing_gap = LANDING_GAP
	await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.9)
	_player.move_direction = Vector3.BACK
	_input.min_forward_jump_ratio = 0.0
	_input.max_forward_jump_ratio = INF
	var unclamped: float = _input.get_forward_jump_ratio()
	if not check(unclamped > 0.0, "setup: the target should be past the landing gap"):
		return
	_input.max_forward_jump_ratio = unclamped * 0.5
	check_approx(_input.get_forward_jump_ratio(), unclamped * 0.5, "the ratio should be clamped to max_forward_jump_ratio")
	_input.min_forward_jump_ratio = unclamped * 2.0
	_input.max_forward_jump_ratio = unclamped * 4.0
	check_approx(_input.get_forward_jump_ratio(), unclamped * 2.0, "the ratio should be clamped to min_forward_jump_ratio")


# --- Attacks and the jump kick -----------------------------------------------

func test_a_dash_cancellable_attack_can_be_jump_cancelled() -> void:
	await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.5)
	var attack: CharacterAttack = _run.attack_state as CharacterAttack
	attack.dash_cancel = true
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == attack.name, "setup: the attack should start", 10):
		return
	press_action(&"jump")
	await wait_until(func() -> bool: return _state() == _jump.name, "a dash-cancellable attack should cancel into the jump", 10)


func test_an_attack_without_dash_cancel_ignores_the_jump_button() -> void:
	await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.5)
	var attack: CharacterAttack = _run.attack_state as CharacterAttack
	attack.dash_cancel = false
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == attack.name, "setup: the attack should start", 10):
		return
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() != attack.name, "the attack should finish", ACTION_FRAMES):
		return
	check_eq(_state(), _run.name, "the attack should finish into running, ignoring the jump press")


func test_attacking_mid_air_performs_a_lunging_jump_kick_that_landing_cancels_into_running() -> void:
	await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.5)
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _jump.name, "setup: a neutral press in combat should jump", 10):
		return
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _kick.name, "attacking mid-air should perform the jump kick", 10):
		return
	var lunged: Array[bool] = [false]
	await wait_until(func() -> bool:
		lunged[0] = lunged[0] or (_kick.lunging and _horizontal(_player.velocity).length() > 0.1)
		return _player.is_on_floor(), "the kick should come down", ACTION_FRAMES)
	check(lunged[0], "the kick's lunge should add horizontal speed to a neutral jump")
	await wait_until(func() -> bool: return _state() == _run.name, "landing should cancel the kick into running at once", 2)


func test_an_attack_pressed_during_the_kick_lands_straight_into_the_ground_attack() -> void:
	await _lock_foe(Vector3.BACK * _aim().auto_aim_range * 0.5)
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _jump.name, "setup: a neutral press in combat should jump", 10):
		return
	await wait_until(func() -> bool: return _player.velocity.y < 0.0, "setup: the jump should start descending", ACTION_FRAMES)
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _kick.name, "attacking mid-air should perform the jump kick", 10):
		return
	press_action(&"click")
	await wait_until(func() -> bool: return _state() != _kick.name, "the kick should land", ACTION_FRAMES)
	check_eq(_state(), _kick.attack_state.name, "landing with an attack pressed during the kick should go straight into the ground attack")


func test_the_jump_kick_strikes_with_its_own_weapon_slot_never_the_sword() -> void:
	var sword_slot: WeaponSlot = (_run.attack_state as CharacterAttack).get_weapon_slot()
	var feet_slot: WeaponSlot = _kick.get_weapon_slot()
	if not check(sword_slot != null and feet_slot != null and feet_slot != sword_slot, "setup: the kick should strike with a different weapon slot than the ground attack"):
		return
	var foe: Character = await _lock_foe(Vector3.BACK * _adjacent_distance())
	var health_before: float = foe.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state() == _jump.name, "setup: a neutral press in combat should jump", 10):
		return
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _kick.name, "attacking mid-air should perform the jump kick", 10):
		return
	var feet_opened: Array[bool] = [false]
	var sword_opened: Array[bool] = [false]
	await wait_until(func() -> bool:
		if feet_slot.hitbox.monitoring:
			feet_opened[0] = true
			# Keep the foe on the kick's strike point so the window can land.
			foe.global_position = feet_slot.hitbox.global_position
		sword_opened[0] = sword_opened[0] or sword_slot.hitbox.monitoring
		return _state() != _kick.name, "the kick should land", ACTION_FRAMES)
	check(feet_opened[0], "the kick's weapon slot should open its hitbox during the strike")
	check(not sword_opened[0], "the sword hitbox must never open during the kick")
	var expected: float = _kick.damage * _player.get_damage_modifier() * foe.attribute_component.get_damage_multiplier(&"physical")
	check_approx(health_before - foe.attribute_component.get_current(AttributeComponent.POOL_HEALTH), expected, "the kick should deal its damage through its own hitbox")
	check(not feet_slot.hitbox.monitoring and not sword_slot.hitbox.monitoring, "landing should leave both hitboxes off")


# --- Helpers ------------------------------------------------------------------

## Spawns a still, unkillable melee foe at the given offset from the player's
## home and waits until auto-aim locks onto it.
func _lock_foe(offset: Vector3) -> Character:
	var foe: Character = spawn(MELEE_SCENE, _arena, _home + offset) as Character
	disable_ai(foe)
	foe.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, FOE_HEALTH)
	if foe.knockback_component != null:
		foe.knockback_component.max_knockback = 0.0
	await wait_until(func() -> bool: return foe.is_on_floor() and _player.current_target == foe, "setup: auto-aim should lock onto the foe")
	return foe


## Puts the player back at its home spawn, at rest in running, with the dash
## off cooldown.
func _reset_at_home() -> void:
	await _wait_running("the player should be back in running")
	_player.move_direction = Vector3.ZERO
	_player.global_position = _home
	_player.velocity = Vector3.ZERO
	if _player.dash_cooldown != null:
		_player.dash_cooldown.stop()
	await wait_physics_frames(1)
	await _wait_running("the player should settle at home")


func _wait_running(message: String) -> bool:
	return await wait_until(func() -> bool: return _player.is_on_floor() and _state() == _run.name, message, ACTION_FRAMES)


## Distance between origins that leaves a small gap between the player's and a
## melee foe's capsules.
func _adjacent_distance() -> float:
	var foe: Character = MELEE_SCENE.instantiate() as Character
	var foe_radius: float = float((foe.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius"))
	foe.free()
	return float(_player.collision_shape_3d.shape.get("radius")) + foe_radius + 0.3


func _speed() -> float:
	return _player.attribute_component.get_current(AttributeComponent.STAT_SPEED)


func _horizontal(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _state() -> String:
	return str(_player.state_machine.state.name)


## The player's auto-aim (TargetingComponent).
func _aim() -> TargetingComponent:
	return _player.get_node("TargetingComponent") as TargetingComponent
