class_name PlayerRun
extends PlayerState

func physics_update(_delta: float) -> void:
	core_movement(_delta, 8.0)
	player.move_and_slide()
