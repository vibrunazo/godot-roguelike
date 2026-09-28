class_name WaveObjective
extends Node3D

## Enemy resources available to spawn. Leave empty to use GlobalVars.enemies.
@export var enemy_resources: Array[EnemyResource] = []

## Boss resources for a boss arena. When non-empty, the wave is exactly these
## bosses (each spawned once, bypassing the difficulty budget and the
## minimum-spawn gate); the regular budget fill is skipped. Leave empty for a
## normal level. Reusable: later bosses only need their own arena scene with
## this set.
@export var boss_resources: Array[EnemyResource] = []
## Seconds after the level starts before the first spawn step.
@export var first_spawn_delay: float = 2.5
## Seconds between consecutive enemy spawns (also before the first one).
@export var spawn_interval: float = 1.0

signal finished

## Every enemy planned for this wave. Instanced up front in _ready() but only
## added to the tree one by one by spawn_enemy(), so entries may be orphans
## (not yet in the tree) until their spawn tween step fires.
var all_enemies: Array[Character] = []
var _enemy_difficulties: Dictionary = {}
## Paces the spawns scheduled in _ready(); killed by stop_spawning().
var _spawn_tween: Tween = null


## Frees planned enemies that never spawned when the wave is deleted. They
## were instanced by this node but never entered the tree, so nothing else
## owns them: leaving the level mid-wave (restart, quit to menu, scene change)
## would otherwise leak each one with its physics, navigation and rendering
## server resources.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_unspawned_enemies()
		all_enemies.clear()


## Stops the wave from spawning any more enemies. The pending spawn schedule
## is cancelled, and every planned enemy that has not entered the level yet is
## freed and removed from all_enemies. Enemies already in the level are left
## alone and still count toward the wave: finished is emitted once they are
## all defeated. Stopping never emits finished by itself, since a stopped wave
## is not a completed one. Safe to call at any time, repeatedly.
func stop_spawning() -> void:
	if _spawn_tween != null and _spawn_tween.is_valid():
		_spawn_tween.kill()
	_spawn_tween = null
	_free_unspawned_enemies()


## Frees and forgets every planned enemy that is not in the tree yet.
func _free_unspawned_enemies() -> void:
	var spawned: Array[Character] = []
	for enemy: Character in all_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.is_inside_tree():
			spawned.append(enemy)
		else:
			_enemy_difficulties.erase(enemy)
			enemy.free()
	all_enemies = spawned


## Returns the default list of enemy resources from GlobalVars.
func _get_default_enemy_resources() -> Array[EnemyResource]:
	if GlobalVars != null and not GlobalVars.enemies.is_empty():
		return GlobalVars.enemies
	return []


## Groups available enemy resources into tiers by difficulty level.
## Resources gated by minimum_spawn_difficulty above current_difficulty are
## excluded. Pass -1 (default) to skip gating, e.g. for inspection.
func build_difficulty_pool(resources: Array[EnemyResource], current_difficulty: int = -1) -> Dictionary:
	var pool: Dictionary = {}
	for res: EnemyResource in resources:
		if res == null or res.scene == null:
			continue
		if current_difficulty >= 0 and res.minimum_spawn_difficulty > current_difficulty:
			continue
		var diff: int = res.difficulty_level
		if not pool.has(diff):
			var arr: Array[EnemyResource] = []
			pool[diff] = arr
		(pool[diff] as Array[EnemyResource]).append(res)
	return pool


## Generates the list of enemies for the current wave matching the progression difficulty budget.
## Always picks 2 level-1 enemies first, then fills the remaining budget randomly with available tiers.
## When boss_resources is set (boss arena), the wave is exactly those bosses and the budget fill is skipped.
func generate_wave_enemies() -> Array[Character]:
	_enemy_difficulties.clear()
	if not boss_resources.is_empty():
		return _instantiate_all(boss_resources)
	# If ProgressionState pre-planned enemies for this encounter, consume them
	if not ProgressionState.current_planned_enemies.is_empty():
		return _instantiate_all(ProgressionState.current_planned_enemies)
	if enemy_resources.is_empty():
		enemy_resources = _get_default_enemy_resources()
	return _fill_difficulty_budget(ProgressionState.difficulty_level)


## One enemy per usable resource, in order.
func _instantiate_all(resources: Array[EnemyResource]) -> Array[Character]:
	var enemies: Array[Character] = []
	for resource: EnemyResource in resources:
		if resource != null and resource.scene != null:
			enemies.append(_instantiate_enemy(resource))
	return enemies


## Instances the resource's enemy and records its difficulty for the wave.
func _instantiate_enemy(resource: EnemyResource) -> Character:
	var enemy: Character = resource.scene.instantiate() as Character
	_enemy_difficulties[enemy] = resource.difficulty_level
	return enemy


## Random enemies worth budget difficulty in total: 2 level-1 enemies first
## (fewer when the budget is smaller), then random tiers that still fit.
func _fill_difficulty_budget(budget: int) -> Array[Character]:
	var enemies: Array[Character] = []
	var pool: Dictionary = build_difficulty_pool(enemy_resources, budget)
	var remaining_budget: int = maxi(0, budget)
	if pool.has(1) and not (pool[1] as Array[EnemyResource]).is_empty():
		var tier_1: Array[EnemyResource] = pool[1] as Array[EnemyResource]
		for _i: int in mini(2, remaining_budget):
			enemies.append(_instantiate_enemy(tier_1.pick_random()))
			remaining_budget -= 1
	while remaining_budget > 0:
		var fitting: Array[int] = []
		for tier: int in pool.keys():
			if tier <= remaining_budget and not (pool[tier] as Array[EnemyResource]).is_empty():
				fitting.append(tier)
		if fitting.is_empty():
			push_warning("WaveObjective: Cannot fulfill remaining difficulty budget %d with available enemy resources." % remaining_budget)
			break
		var chosen_tier: int = fitting.pick_random()
		enemies.append(_instantiate_enemy((pool[chosen_tier] as Array[EnemyResource]).pick_random()))
		remaining_budget -= chosen_tier
	return enemies

func _ready() -> void:
	all_enemies = generate_wave_enemies()
	_print_wave_debug_info()

	# Spawn pacing is gameplay: step it on the physics clock.
	_spawn_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_spawn_tween.tween_interval(first_spawn_delay)
	for enemy: Character in all_enemies:
		_spawn_tween.tween_interval(spawn_interval)
		_spawn_tween.tween_callback(spawn_enemy.bind(enemy))
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
		var diff: int = _enemy_difficulties.get(enemy, 1)
		enemy_parts.append("%s %d" % [enemy_label, diff])
	var enemies_str: String = " + ".join(enemy_parts) if not enemy_parts.is_empty() else "none"
	print("Level %d, difficulty %d, %s" % [current_dungeon_level, current_difficulty, enemies_str])


## Finds all RoomSpawnArea nodes in the current level.
func get_room_spawn_areas() -> Array[RoomSpawnArea]:
	var areas: Array[RoomSpawnArea] = []
	var root: Node = get_parent() if get_parent() != null else self
	for child: Node in root.find_children("*", "RoomSpawnArea", true, false):
		if child is RoomSpawnArea:
			areas.append(child as RoomSpawnArea)
	return areas


## Adds enemy to scene tree and positions it in a room spawn area or randomly on the navigation mesh.
func spawn_enemy(enemy: Character) -> void:
	if not enemy.is_inside_tree():
		add_child(enemy)

	var spawn_areas: Array[RoomSpawnArea] = get_room_spawn_areas()
	var spawn_pos: Vector3 = Vector3.ZERO
	if not spawn_areas.is_empty():
		spawn_areas.sort_custom(func(a: RoomSpawnArea, b: RoomSpawnArea) -> bool:
			return a.assigned_enemies.size() < b.assigned_enemies.size()
		)
		var chosen_area: RoomSpawnArea = spawn_areas.front()
		chosen_area.assign_enemy(enemy)
		spawn_pos = chosen_area.get_random_spawn_point()
	else:
		var nmap: RID = get_world_3d().navigation_map
		spawn_pos = NavigationServer3D.map_get_random_point(nmap, 1, true)
		if spawn_pos.is_zero_approx():
			var jitter: Vector3 = Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(nmap, jitter)
			spawn_pos = closest if not closest.is_zero_approx() else jitter

	var half_height: float = 1.0
	if enemy.collision_shape_3d != null and enemy.collision_shape_3d.shape is CapsuleShape3D:
		half_height = (enemy.collision_shape_3d.shape as CapsuleShape3D).height * 0.5
	enemy.global_position = spawn_pos + Vector3(0.0, half_height, 0.0)
	enemy.home_position = enemy.global_position


func update_enemies(enemy: Character) -> void:
	_enemy_difficulties.erase(enemy)
	all_enemies.erase(enemy)
	if all_enemies.is_empty():
		finished.emit()
