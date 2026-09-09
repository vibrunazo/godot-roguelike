## Physical state handling player running, movement blending, and action inputs.
class_name PlayerRun
extends PlayerState


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	core_movement(delta, character.movement_speed, character.move_direction)
	if character.animation_tree != null:
		if not character.move_direction.is_zero_approx():
			character.animation_tree.blend_target = 1.0
		else:
			character.animation_tree.blend_target = -1.0
	if not character.is_on_floor() and fall_state != null:
		finished.emit(fall_state.name)
	character.move_and_slide()


func handle_input(event: InputEvent) -> void:
	check_dash(event)
	check_attack(event)
