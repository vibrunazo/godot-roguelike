class_name Player
extends CharacterBody3D

func get_movement_direction() -> Vector3:
	var input := Vector3.ZERO
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input = Vector3(input_vector.x, 0.0, input_vector.y)
	return input.normalized()
