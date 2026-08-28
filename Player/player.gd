class_name Player
extends CharacterBody3D

## Regular run speed in meters per second. Read by Run and Fall States
@export var movement_speed := 8.0
## Speed during dash in meters per second. Read by Dash State.
@export var dash_speed := 50.0

@onready var dash_cooldown: Timer = $DashCooldown

## Returns the current input direction towards camera. Normalized.
func get_movement_direction() -> Vector3:
	var input := Vector3.ZERO
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input = Vector3(input_vector.x, 0.0, input_vector.y)
	var camera := get_viewport().get_camera_3d()
	var camera_rotation := camera.global_rotation.y
	input = input.rotated(Vector3.UP, camera_rotation)
	return input.normalized()

func can_dash() -> bool:
	if get_movement_direction().is_zero_approx():
		return false
	return dash_cooldown.is_stopped()
