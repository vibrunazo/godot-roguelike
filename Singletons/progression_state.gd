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

## The run's gear: every gear equip, in order (gear bought twice appears
## twice). Kept current by the bound player (see bind_player()); each level's
## fresh player gets it re-attached.
var player_gear: Array[GearItemResource] = []
## The run's player health, kept current by the bound player. INF until the
## run's first player is bound: a new run starts at full health.
var player_health: float = INF
## Items bought while no player exists (the shop between levels), applied in
## order to the next bound player.
var pending_items: Array[ItemResource] = []

## Item key -> times purchased this run (see get_purchase_count()).
var _purchase_counts: Dictionary[StringName, int] = {}


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
	player_gear.clear()
	player_health = INF
	pending_items.clear()
	_purchase_counts.clear()


## Makes player the run's player (each level binds its own fresh one): it gets
## the run's gear back (only the lasting part: instant effects ran when the
## gear was first equipped) and the run's health, then the pending items.
## From then on the run state follows the player: every gear it equips or
## unequips and every health change is recorded here, so nothing has to be
## copied when it leaves its scene.
func bind_player(player: Character) -> void:
	var equipment: EquipmentComponent = player.equipment_component
	var attributes: AttributeComponent = player.attribute_component
	for gear: GearItemResource in player_gear:
		equipment.restore_gear(gear)
	attributes.set_pool_current(AttributeComponent.POOL_HEALTH, player_health)
	player_health = attributes.get_current(AttributeComponent.POOL_HEALTH)
	equipment.gear_equipped.connect(_record_gear)
	equipment.gear_unequipped.connect(_forget_gear)
	attributes.attribute_changed.connect(_on_player_attribute_changed)
	for item: ItemResource in pending_items:
		equipment.apply_item(item)
	pending_items.clear()


## Times the item was purchased this run.
func get_purchase_count(item: ItemResource) -> int:
	return _purchase_counts.get(_item_key(item), 0) if item != null else 0


## Whether the item can be bought now: in stock (under max_purchases, when
## limited) and affordable.
func can_purchase(item: ItemResource) -> bool:
	if item == null:
		return false
	if item.max_purchases > 0 and get_purchase_count(item) >= item.max_purchases:
		return false
	return has_gold(item.cost)


## Counts one purchase of the item.
func record_purchase(item: ItemResource) -> void:
	if item != null:
		var key: StringName = _item_key(item)
		_purchase_counts[key] = _purchase_counts.get(key, 0) + 1


func _record_gear(gear: GearItemResource) -> void:
	player_gear.append(gear)


## Drops every equip of gear from the run's gear.
func _forget_gear(gear: GearItemResource) -> void:
	while player_gear.has(gear):
		player_gear.erase(gear)


func _on_player_attribute_changed(attribute_name: StringName, current_value: float) -> void:
	if attribute_name == AttributeComponent.POOL_HEALTH:
		player_health = current_value


## The identity purchases are counted under: the item id, else its resource
## path, else its title.
func _item_key(item: ItemResource) -> StringName:
	if not item.id.is_empty():
		return item.id
	if not item.resource_path.is_empty():
		return StringName(item.resource_path)
	return StringName(item.title)


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


## Generates the list of enemy archetype resources for a wave matching the
## difficulty budget (difficulty_level), from enemy_resources (GlobalVars.enemies
## when empty). Always picks 2 level-1 enemies first (fewer when the budget is
## smaller), then fills the remaining budget randomly with the tiers that fit.
func generate_wave_plan(enemy_resources: Array[EnemyResource] = []) -> Array[EnemyResource]:
	var available_resources: Array[EnemyResource] = enemy_resources if not enemy_resources.is_empty() else GlobalVars.enemies
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
## Boss arenas are never selected here (see boss_arena_for()).
func select_dungeon_for_encounter(enemy_count: int, available_dungeons: Array[DungeonResource] = []) -> DungeonResource:
	var dungeons_pool: Array[DungeonResource] = []
	for dungeon: DungeonResource in (available_dungeons if not available_dungeons.is_empty() else GlobalVars.dungeons):
		if dungeon != null and not dungeon.is_boss_arena():
			dungeons_pool.append(dungeon)
	if dungeons_pool.is_empty():
		push_error("ProgressionState: no regular dungeons are registered in GlobalVars.dungeons.")
		return null

	var matching_dungeons: Array[DungeonResource] = []
	for dungeon: DungeonResource in dungeons_pool:
		if dungeon.matches(difficulty_level, enemy_count):
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


## The boss arena registered for target_dungeon_level (its boss_at_level),
## or null when that level is a regular one.
func boss_arena_for(target_dungeon_level: int) -> DungeonResource:
	for dungeon: DungeonResource in GlobalVars.dungeons:
		if dungeon != null and dungeon.boss_at_level == target_dungeon_level:
			return dungeon
	return null


## Prepares the next encounter for the current dungeon level: its boss arena
## when one is registered (the arena brings its own bosses, so no enemies are
## planned), otherwise planned enemies from the difficulty budget and a
## matching regular dungeon.
func prepare_next_encounter() -> DungeonResource:
	var boss_arena: DungeonResource = boss_arena_for(dungeon_level)
	if boss_arena != null:
		current_planned_enemies.clear()
		current_dungeon = boss_arena
		return current_dungeon
	current_planned_enemies = generate_wave_plan()
	current_dungeon = select_dungeon_for_encounter(current_planned_enemies.size())
	return current_dungeon
