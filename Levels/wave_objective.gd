class_name WaveObjective
extends Node3D

const RANGED_ENEMY: PackedScene = preload("res://Enemy/ranged_enemy.tscn")
const MELEE_ENEMY: PackedScene = preload("res://Enemy/melee_enemy.tscn")

signal finished

var all_enemies: Array[Enemy] = []


func _ready() -> void:
	for _i: int in GlobalVars.get_enemy_count():
		var new_enemy: Enemy = MELEE_ENEMY.instantiate() as Enemy
		all_enemies.append(new_enemy)

	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	for enemy: Enemy in all_enemies:
		tween.tween_interval(1.0)
		tween.tween_callback(add_child.bind(enemy))
		enemy.defeat.connect(update_enemies.bind(enemy))


func update_enemies(enemy: Enemy) -> void:
	all_enemies.erase(enemy)
	if all_enemies.is_empty():
		finished.emit()

