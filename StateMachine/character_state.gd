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


## Points the character's visual mesh toward the specified target in world space.
func look_at_target(target: Vector3) -> void:
	if character != null:
		character.look_at_target(target)


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
