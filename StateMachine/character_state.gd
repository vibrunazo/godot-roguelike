## Base state for physical character states.
## Provides unified core physics, movement, orientation, and knockback handling.
class_name CharacterState
extends State

## Reference to the Character controlled by this state.
@export var character: Character
## State to transition to when falling off floor/ledges.
@export var fall_state: CharacterState
## State to transition to when a dash intent is consumed.
@export var dash_state: CharacterState
## State to transition to when an attack intent is consumed.
@export var attack_state: CharacterState
## Ability identity tags this state broadcasts lifecycle events with (e.g.
## &"ability.dash"). Empty (the default) means the state broadcasts nothing and
## granted passives never see its lifecycle.
@export var ability_tags: Array[StringName] = []
## State to transition to when a jump intent is consumed.
@export var jump_state: CharacterState


## Consumes a pending dash intent and transitions to dash_state if available.
## Returns true when the intent was consumed and acted upon. Intents are consumed
## on read even when gated off, so a press never leaks into a later state.
func check_dash() -> bool:
	if character == null or character.state_machine == null:
		return false
	if not character.consume_dash_request():
		return false
	if dash_state == null or not character.can_dash():
		return false
	var direction: Vector3 = character.move_direction
	if direction.is_zero_approx() and character.mesh_mount != null:
		direction = character.mesh_mount.global_basis.z.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	return character.state_machine.request_state(dash_state.name, {"direction": direction})


## Consumes a pending jump intent and transitions to jump_state if available and on floor.
## Returns true when the intent was consumed and acted upon. The optional
## launch_ratio overrides the jump state's default movement_speed_ratio for the
## leap (values < 0.0 keep the default); the state restores its own default on
## exit so the override never leaks into later jumps.
func check_jump(launch_ratio: float = -1.0) -> bool:
	if character == null or character.state_machine == null:
		return false
	if not character.consume_jump_request():
		return false
	if jump_state == null or not character.is_on_floor():
		return false
	var data: Dictionary = {"direction": get_jump_launch_direction()}
	if launch_ratio >= 0.0:
		data["movement_speed_ratio"] = launch_ratio
	return character.state_machine.request_state(jump_state.name, data)


## Resolves the horizontal launch direction for a jump. While a target is
## locked, any held movement input snaps the leap to the exact ground direction
## towards that target (forward or strafing presses alike), so jump attacks
## cannot miss the locked enemy laterally. Neutral input stays neutral: the
## jump preserves whatever momentum the character already has.
func get_jump_launch_direction() -> Vector3:
	if character == null or character.move_direction.is_zero_approx():
		return Vector3.ZERO
	var target: Node3D = character.current_target
	if target == null or not is_instance_valid(target):
		return character.move_direction
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return character.move_direction
	return to_target.normalized()


## Consumes a pending attack intent and transitions to attack_state if available.
## Returns true when the intent was consumed and acted upon.
func check_attack() -> bool:
	if character == null or character.state_machine == null:
		return false
	if not character.consume_attack_request():
		return false
	if attack_state == null:
		return false
	return character.state_machine.request_state(attack_state.name, {"direction": character.move_direction})


## Requests the character's visual mesh toward the target in world space. The
## character turns at its rotation speed limit (see Character.look_at_target).
func look_at_target(target: Vector3, delta: float) -> void:
	if character != null:
		character.look_at_target(target, delta)


## Handles unified velocity calculation, knockback application, and orientation smoothing.
func core_movement(delta: float, speed: float, direction: Vector3 = Vector3.ZERO) -> void:
	if character == null:
		return
	if not character.is_on_floor() and fall_state != null:
		finished.emit(fall_state.name)
		return

	if character.knockback_component != null and character.knockback_component.is_active():
		character.velocity = character.knockback_component.magnitude
	elif not direction.is_zero_approx():
		character.velocity.x = direction.x * speed
		character.velocity.z = direction.z * speed
		character.look_toward_direction(direction, delta)
	else:
		character.velocity.x = move_toward(character.velocity.x, 0.0, speed)
		character.velocity.z = move_toward(character.velocity.z, 0.0, speed)


## Broadcasts one lifecycle point of this state to the character's
## PassiveAbilityComponent as an AbilityEvent (position = the character's world
## position, direction = event_direction or the character's movement/forward).
## No-op when the state is untagged or no component exists. extra_data's
## standard key is "completed" (bool) for states that can be interrupted
## mid-ability; events without it count as completed.
func broadcast_ability_event(phase: int, extra_data: Dictionary = {}, event_direction: Vector3 = Vector3.ZERO) -> void:
	if ability_tags.is_empty() or character == null or not is_instance_valid(character):
		return
	var event: AbilityEvent = AbilityEvent.new()
	var event_tags: Array[StringName] = []
	event_tags.assign(ability_tags)
	event.tags = event_tags
	event.phase = phase
	event.instigator = character
	event.source = self
	event.position = character.global_position
	event.direction = event_direction
	if event.direction.is_zero_approx():
		event.direction = character.move_direction
	if event.direction.is_zero_approx() and character.mesh_mount != null:
		event.direction = character.mesh_mount.global_basis.z.normalized()
	event.data = extra_data
	character.broadcast_ability_event(event)
