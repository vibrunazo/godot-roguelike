class_name PlayerState
extends State

@export var player: Player

func core_movement(delta: float, speed: float) -> void:
	var direction := player.get_movement_direction()
	player.velocity = direction * speed
