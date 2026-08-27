class_name PlayerFall
extends PlayerState

@export var run_state: PlayerState

func physics_update(_delta: float) -> void:
	core_movement(_delta, 8.0)
	if player.is_on_floor() == true:
		finished.emit(run_state.name)
	player.velocity += player.get_gravity()
	player.move_and_slide()
