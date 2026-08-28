class_name PlayerRun
extends PlayerState

@export var fall_state: PlayerState

func physics_update(_delta: float) -> void:
	core_movement(_delta, 8.0)
	if player.is_on_floor() == false:
		finished.emit(fall_state.name)
	player.move_and_slide()

func handle_input(_event: InputEvent) -> void:
	check_dash(_event)
