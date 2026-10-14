## Autoload: counts physics ticks since the game started.
extends Node

## Physics ticks since start.
var ticks: int = 0


func _physics_process(_delta: float) -> void:
	ticks += 1
