extends Node

var level: int = 1


func finish_level() -> void:
	level += 1


func get_enemy_count() -> int:
	return level
