class_name WaveObjective
extends Node3D

## Enemy scenes to spawn, picked at random. Leave empty to use the GlobalVars registry.
@export var enemy_scenes: Array[PackedScene] = []

signal finished

var all_enemies: Array[Character] = []


func _ready() -> void:
	if enemy_scenes.is_empty():
		enemy_scenes = [GlobalVars.enemy_melee_scene, GlobalVars.enemy_ranged_scene]
	for _i: int in GlobalVars.get_enemy_count():
		var template: PackedScene = enemy_scenes.pick_random()
		var new_enemy: Character = template.instantiate() as Character
		all_enemies.append(new_enemy)

	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	for enemy: Character in all_enemies:
		tween.tween_interval(1.0)
		tween.tween_callback(spawn_enemy.bind(enemy))
		enemy.defeat.connect(update_enemies.bind(enemy))


## Adds enemy to scene tree and positions it randomly on the navigation mesh.
func spawn_enemy(enemy: Character) -> void:
	if not enemy.is_inside_tree():
		add_child(enemy)
	var random_point: Vector3 = NavigationServer3D.map_get_random_point(
		get_world_3d().navigation_map, 1, true
	)
	var half_height: float = 1.0
	if enemy.collision_shape_3d != null and enemy.collision_shape_3d.shape is CapsuleShape3D:
		half_height = (enemy.collision_shape_3d.shape as CapsuleShape3D).height * 0.5
	enemy.global_position = random_point + Vector3(0.0, half_height, 0.0)


func update_enemies(enemy: Character) -> void:
	all_enemies.erase(enemy)
	if all_enemies.is_empty():
		finished.emit()
