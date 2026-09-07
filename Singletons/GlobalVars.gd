# TODO: Autoloads should be separated into different global systems with different names and responsibilities, instead of a generic GlobalVars autoload with multiple responsibilities.
extends Node

const DIFFICULTY_CURVE: Curve = preload("res://Singletons/difficulty_curve.tres")

var level: int = 1


func finish_level() -> void:
	level += 1


func get_enemy_count() -> int:
	return int(floor(DIFFICULTY_CURVE.sample(float(level))))
