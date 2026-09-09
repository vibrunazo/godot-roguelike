class_name WaveObjective
extends Node3D

const RANGED_ENEMY: PackedScene = preload("res://Enemy/ranged_enemy.tscn")
const MELEE_ENEMY: PackedScene = preload("res://Enemy/melee_enemy.tscn")

signal finished

var all_enemies: Array[Character] = []


func _ready() -> void:
	for _i: int in GlobalVars.get_enemy_count():
		var template: PackedScene = [MELEE_ENEMY, RANGED_ENEMY].pick_random()
		var new_enemy: Character = template.instantiate() as Character
		new_enemy.position = Vector3(0.0, 1.0, 0.0)
		all_enemies.append(new_enemy)

	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	for enemy: Character in all_enemies:
		tween.tween_interval(1.0)
		tween.tween_callback(add_child.bind(enemy))
		enemy.defeat.connect(update_enemies.bind(enemy))


func update_enemies(enemy: Character) -> void:
	all_enemies.erase(enemy)
	if all_enemies.is_empty():
		finished.emit()

