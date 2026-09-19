## Run progression service, registered as the `ProgressionState` autoload (script) in `project.godot`.
## Access from anywhere via `ProgressionState`, e.g. `ProgressionState.advance_level()`.
##
## Unique responsibilities:
## - Current dungeon level (`dungeon_level`) and difficulty level (`difficulty_level`).
## - Progression lifecycle (`advance_level`, `reset_run`).
## - Cleanly exposed tuning parameters for difficulty balance.
## It owns no scenes, no input, and no display code; scene/resource defaults live
## in the `GlobalVars` registry.
extends Node

# -----------------------------------------------------------------------------
# Tuning Parameters (Easily adjustable for game balance)
# -----------------------------------------------------------------------------

## Starting dungeon level when a new run begins.
@export var base_dungeon_level: int = 1

## Starting difficulty rating at base_dungeon_level.
@export var base_difficulty: float = 3.0

## Amount added to the difficulty rating for each completed level.
@export var difficulty_increase_per_level: float = 1.35

# -----------------------------------------------------------------------------
# Active Run State
# -----------------------------------------------------------------------------

## Emitted when run gold currency changes.
signal currency_gold_changed(new_amount: int)

## Current gold currency collected during this run.
var currency_gold: int = 0

## Current dungeon level (starts at base_dungeon_level, +1 per cleared level).
var dungeon_level: int = 1

## Current floored difficulty rating budget used by WaveObjective.
var difficulty_level: int = 3

## Currently planned enemy archetype resources for the active encounter.
var current_planned_enemies: Array[EnemyResource] = []

## Currently selected dungeon resource for the active encounter.
var current_dungeon: DungeonResource = null

## History of recently visited dungeon resources to avoid back-to-back repetitions.
var recently_visited_dungeons: Array[DungeonResource] = []


func _ready() -> void:
	reset_run()


## Adds gold to the current run and notifies listeners.
func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	currency_gold += amount
	currency_gold_changed.emit(currency_gold)


## Attempts to spend gold from the run balance. Returns true if successful.
func spend_gold(amount: int) -> bool:
	if amount < 0 or currency_gold < amount:
		return false
	currency_gold -= amount
	currency_gold_changed.emit(currency_gold)
	return true


## Checks if the player has at least the specified amount of gold.
func has_gold(amount: int) -> bool:
	return currency_gold >= amount


## Computes the floored integer difficulty rating for any given dungeon level.
func calculate_difficulty(target_dungeon_level: int) -> int:
	var raw_difficulty: float = base_difficulty + float(target_dungeon_level - base_dungeon_level) * difficulty_increase_per_level
	return int(floor(raw_difficulty))


## Advances the run to the next dungeon level and recalculates difficulty_level.
func advance_level() -> void:
	dungeon_level += 1
	difficulty_level = calculate_difficulty(dungeon_level)


## Resets run progression back to starting parameters (e.g. on game restart).
func reset_run() -> void:
	currency_gold = 0
	currency_gold_changed.emit(currency_gold)
	dungeon_level = base_dungeon_level
	difficulty_level = calculate_difficulty(dungeon_level)
	current_planned_enemies.clear()
	current_dungeon = null
	recently_visited_dungeons.clear()


## Groups available enemy resources into tiers by difficulty level.
## Resources gated by minimum_spawn_difficulty above current_difficulty are excluded.
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


## Generates the list of enemy archetype resources for a wave matching the difficulty budget.
## Always picks 2 level-1 enemies first, then fills the remaining budget randomly with available tiers.
func generate_wave_plan(enemy_resources: Array[EnemyResource] = []) -> Array[EnemyResource]:
	var available_resources: Array[EnemyResource] = enemy_resources
	if available_resources.is_empty() and GlobalVars != null:
		available_resources = GlobalVars.enemies
	var planned: Array[EnemyResource] = []
	var target_budget: int = difficulty_level
	var pool: Dictionary = build_difficulty_pool(available_resources, target_budget)
	var remaining_budget: int = max(0, target_budget)

	# Pick 2 level-1 enemies first (or remaining_budget if < 2)
	var level_1_count: int = 2 if remaining_budget >= 2 else remaining_budget
	if pool.has(1) and not (pool[1] as Array[EnemyResource]).is_empty():
		var tier_1: Array[EnemyResource] = pool[1] as Array[EnemyResource]
		for _i: int in level_1_count:
			var chosen_res: EnemyResource = tier_1.pick_random()
			planned.append(chosen_res)
			remaining_budget -= 1

	# Fill the remaining difficulty budget
	while remaining_budget > 0:
		var valid_diffs: Array[int] = []
		for d: int in pool.keys():
			if d <= remaining_budget and not (pool[d] as Array[EnemyResource]).is_empty():
				valid_diffs.append(d)
		if valid_diffs.is_empty():
			push_warning("ProgressionState: Cannot fulfill remaining difficulty budget %d with available enemy resources." % remaining_budget)
			break
		var chosen_diff: int = valid_diffs.pick_random()
		var candidate_resources: Array[EnemyResource] = pool[chosen_diff] as Array[EnemyResource]
		var chosen_resource: EnemyResource = candidate_resources.pick_random()
		planned.append(chosen_resource)
		remaining_budget -= chosen_diff

	return planned


## Selects an eligible DungeonResource based on difficulty rating and enemy count.
## Avoids recently visited dungeons where possible and provides graceful fallback.
func select_dungeon_for_encounter(enemy_count: int, available_dungeons: Array[DungeonResource] = []) -> DungeonResource:
	var dungeons_pool: Array[DungeonResource] = available_dungeons
	if dungeons_pool.is_empty() and GlobalVars != null:
		dungeons_pool = GlobalVars.dungeons
	if dungeons_pool.is_empty():
		push_warning("ProgressionState: No dungeons available in GlobalVars!")
		return null

	var matching_dungeons: Array[DungeonResource] = []
	for dungeon: DungeonResource in dungeons_pool:
		if dungeon != null and dungeon.matches(difficulty_level, enemy_count):
			matching_dungeons.append(dungeon)

	# If strict matching finds no dungeon, relax criteria to all dungeons as fallback
	if matching_dungeons.is_empty():
		push_warning("ProgressionState: No dungeon strictly matched difficulty %d with %d enemies. Using fallback." % [difficulty_level, enemy_count])
		matching_dungeons = dungeons_pool.duplicate()

	# Filter out recently visited if there are other candidates
	var non_recent: Array[DungeonResource] = []
	for d: DungeonResource in matching_dungeons:
		if not recently_visited_dungeons.has(d):
			non_recent.append(d)

	var candidates: Array[DungeonResource] = non_recent if not non_recent.is_empty() else matching_dungeons
	var chosen: DungeonResource = candidates.pick_random()

	# Update recent history (keep last 3)
	if chosen != null:
		recently_visited_dungeons.append(chosen)
		if recently_visited_dungeons.size() > 3:
			recently_visited_dungeons.pop_front()

	return chosen


## Prepares the next encounter: plans enemies based on difficulty, then selects matching dungeon.
func prepare_next_encounter() -> DungeonResource:
	current_planned_enemies = generate_wave_plan()
	current_dungeon = select_dungeon_for_encounter(current_planned_enemies.size())
	return current_dungeon
