## Base state for physical character states.
## Provides unified core physics, movement, orientation, and knockback handling.
class_name CharacterState
extends State

## Reference to the Character controlled by this state.
@export var character: Character
## State to transition to when falling off floor/ledges.
@export var fall_state: CharacterState


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
