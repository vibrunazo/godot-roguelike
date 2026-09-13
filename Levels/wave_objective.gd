class_name WaveObjective
extends Node3D

## Enemy scenes to spawn, picked at random. Leave empty to use the GlobalVars registry.
@export var enemy_scenes: Array[PackedScene] = []

## Heavy enemy scene spawned deterministically. Leave null to use the GlobalVars registry.
@export var brute_scene: PackedScene = null

signal finished

var all_enemies: Array[Character] = []


## Returns the number of brutes that must spawn for the current difficulty level:
## 1 brute at difficulty 1-2, increasing by 1 every 2 difficulty levels (e.g. 2 at diff 3-4, 3 at diff 5-6).
func get_brute_count() -> int:
	var diff: int = ProgressionState.difficulty_level if ProgressionState != null else 1
	return 0 + int((diff - 1.0) / 2.0)


func _ready() -> void:
	if enemy_scenes.is_empty():
		enemy_scenes = [GlobalVars.enemy_melee_scene, GlobalVars.enemy_ranged_scene]
		if GlobalVars.enemy_firebomber_scene != null:
			enemy_scenes.append(GlobalVars.enemy_firebomber_scene)
		if GlobalVars.enemy_thunder_mage_scene != null:
			enemy_scenes.append(GlobalVars.enemy_thunder_mage_scene)
	var brute_template: PackedScene = brute_scene if brute_scene != null else GlobalVars.enemy_brute_scene
	var total_count: int = ProgressionState.get_enemy_count() if ProgressionState != null else 3
	var brute_count: int = get_brute_count()

	# Fill standard enemies first
	var remaining_count: int = max(0, total_count - brute_count)
	for _i: int in remaining_count:
		var template: PackedScene = enemy_scenes.pick_random()
		var new_enemy: Character = template.instantiate() as Character
		all_enemies.append(new_enemy)

	# Spawn guaranteed brutes according to difficulty progression
	if brute_template != null:
		for _b: int in brute_count:
			var brute_enemy: Character = brute_template.instantiate() as Character
			all_enemies.append(brute_enemy)

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
