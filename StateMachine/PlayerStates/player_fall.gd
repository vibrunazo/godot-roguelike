## Physical state handling airborne gravity and falling for player characters.
class_name PlayerFall
extends PlayerState

## State to transition to after landing on the floor.
@export var run_state: PlayerState


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	core_movement(delta, character.movement_speed, character.move_direction)
	if character.is_on_floor() and run_state != null:
		finished.emit(run_state.name)
	character.velocity += character.get_gravity()
	character.move_and_slide()
