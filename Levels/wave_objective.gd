class_name WaveObjective
extends Node3D

## Enemy scenes to spawn, picked at random. Leave empty to use the GlobalVars registry.
@export var enemy_scenes: Array[PackedScene] = []

## Heavy enemy scene spawned deterministically. Leave null to use the GlobalVars registry.
@export var brute_scene: PackedScene = null

signal finished

var all_enemies: Array[Character] = []
var _scene_difficulty_cache: Dictionary = {}



## Returns the default list of enemy scenes from GlobalVars.
func _get_default_enemy_scenes() -> Array[PackedScene]:
	var scenes: Array[PackedScene] = []
	if GlobalVars != null:
		if GlobalVars.enemy_melee_scene != null:
			scenes.append(GlobalVars.enemy_melee_scene)
		if GlobalVars.enemy_ranged_scene != null:
			scenes.append(GlobalVars.enemy_ranged_scene)
		if GlobalVars.enemy_firebomber_scene != null:
			scenes.append(GlobalVars.enemy_firebomber_scene)
		if GlobalVars.enemy_brute_scene != null:
			scenes.append(GlobalVars.enemy_brute_scene)
		if GlobalVars.enemy_thunder_mage_scene != null:
			scenes.append(GlobalVars.enemy_thunder_mage_scene)
	return scenes


## Inspects and returns the difficulty rating for a given enemy scene.
func get_scene_difficulty(scene: PackedScene) -> int:
	if _scene_difficulty_cache.has(scene):
		return _scene_difficulty_cache[scene]
	var inst: Node = scene.instantiate()
	var rating: int = 1
	if "difficulty_rating" in inst:
		rating = inst.difficulty_rating
	inst.free()
	_scene_difficulty_cache[scene] = rating
	return rating


## Groups available enemy scenes into tiers by difficulty rating.
func build_difficulty_pool(scenes: Array[PackedScene]) -> Dictionary:
	var pool: Dictionary = {}
	for scene: PackedScene in scenes:
		if scene == null:
			continue
		var diff: int = get_scene_difficulty(scene)
		if not pool.has(diff):
			var arr: Array[PackedScene] = []
			pool[diff] = arr
		(pool[diff] as Array[PackedScene]).append(scene)
	return pool


## Generates the list of enemies for the current wave matching the progression difficulty budget.
## Always picks 2 level-1 enemies first, then fills the remaining budget randomly with available tiers.
func generate_wave_enemies() -> Array[Character]:
	if enemy_scenes.is_empty():
		enemy_scenes = _get_default_enemy_scenes()
	if brute_scene != null and not enemy_scenes.has(brute_scene):
		enemy_scenes.append(brute_scene)

	var pool: Dictionary = build_difficulty_pool(enemy_scenes)
	var target_budget: int = ProgressionState.difficulty_level if ProgressionState != null else 3
	var remaining_budget: int = max(0, target_budget)
	var generated_enemies: Array[Character] = []

	# Pick 2 level-1 enemies first (or remaining_budget if < 2)
	var level_1_count: int = 2 if remaining_budget >= 2 else remaining_budget
	if pool.has(1) and not (pool[1] as Array[PackedScene]).is_empty():
		var tier_1: Array[PackedScene] = pool[1] as Array[PackedScene]
		for _i: int in level_1_count:
			var scene: PackedScene = tier_1.pick_random()
			generated_enemies.append(scene.instantiate() as Character)
			remaining_budget -= 1

	# Fill the remaining difficulty budget
	while remaining_budget > 0:
		var valid_diffs: Array[int] = []
		for d: int in pool.keys():
			if d <= remaining_budget and not (pool[d] as Array[PackedScene]).is_empty():
				valid_diffs.append(d)
		if valid_diffs.is_empty():
			push_warning("WaveObjective: Cannot fulfill remaining difficulty budget %d with available scenes." % remaining_budget)
			break
		var chosen_diff: int = valid_diffs.pick_random()
		var candidate_scenes: Array[PackedScene] = pool[chosen_diff] as Array[PackedScene]
		var chosen_scene: PackedScene = candidate_scenes.pick_random()
		generated_enemies.append(chosen_scene.instantiate() as Character)
		remaining_budget -= chosen_diff

	return generated_enemies


func _ready() -> void:
	all_enemies = generate_wave_enemies()
	_print_wave_debug_info()

	var tween: Tween = create_tween()
	tween.tween_interval(2.5)
	for enemy: Character in all_enemies:
		tween.tween_interval(1.0)
		tween.tween_callback(spawn_enemy.bind(enemy))
		enemy.defeat.connect(update_enemies.bind(enemy))


## Returns a clean human-readable name for an enemy instance (e.g. "melee", "ranged", "firebomber", "brute", "thunder mage").
func _get_enemy_display_name(enemy: Character) -> String:
	var raw_name: String = enemy.name.to_snake_case()
	while raw_name.length() > 0 and raw_name[raw_name.length() - 1].is_valid_int():
		raw_name = raw_name.substr(0, raw_name.length() - 1)
	raw_name = raw_name.trim_prefix("enemy_").trim_suffix("_enemy")
	return raw_name.replace("_", " ")


## Debug prints the level, difficulty budget, and picked enemies with their difficulty ratings at wave start.
func _print_wave_debug_info() -> void:
	var current_dungeon_level: int = ProgressionState.dungeon_level if ProgressionState != null else 1
	var current_difficulty: int = ProgressionState.difficulty_level if ProgressionState != null else 3
	var enemy_parts: Array[String] = []
	for enemy: Character in all_enemies:
		var enemy_label: String = _get_enemy_display_name(enemy)
		enemy_parts.append("%s %d" % [enemy_label, enemy.difficulty_rating])
	var enemies_str: String = " + ".join(enemy_parts) if not enemy_parts.is_empty() else "none"
	print("Level %d, difficulty %d, %s" % [current_dungeon_level, current_difficulty, enemies_str])


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
