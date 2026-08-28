class_name PlayerDash
extends PlayerState

var direction: Vector3

func enter(_previous_state_path: String, _data := {}) -> void:
	direction = _data.direction
	player.velocity = direction * 50.0
	
func physics_update(_delta: float) -> void:
	player.move_and_slide()
