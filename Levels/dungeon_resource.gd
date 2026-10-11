## Data resource representing a dungeon level, its PackedScene, and eligibility constraints.
class_name DungeonResource
extends Resource

## The display or identifier name of the dungeon level.
@export var name: String = ""

## The PackedScene of the dungeon level.
@export var scene: PackedScene

## Minimum run difficulty rating required for this dungeon to be selected. 0 = unlimited.
@export var min_difficulty: int = 0

## Maximum run difficulty rating allowed for this dungeon to be selected. 0 = unlimited.
@export var max_difficulty: int = 0

## Minimum enemy count required for this dungeon to be selected. 0 = unlimited.
@export var min_enemies: int = 0

## Maximum enemy count allowed for this dungeon to be selected. 0 = unlimited.
@export var max_enemies: int = 0

## Whether this dungeon is a boss arena: a layout for boss fights, never
## picked as a regular dungeon. On a boss level (one some boss's
## EnemyResource.boss_at_level names) the run detours to a random boss arena
## and plans that level's boss as its whole wave
## (ProgressionState.prepare_next_encounter()); the eligibility limits above
## are ignored.
@export var boss_arena: bool = false


## Returns true if this dungeon is eligible for the given difficulty rating and planned enemy count.
func matches(difficulty: int, enemy_count: int) -> bool:
	if min_difficulty > 0 and difficulty < min_difficulty:
		return false
	if max_difficulty > 0 and difficulty > max_difficulty:
		return false
	if min_enemies > 0 and enemy_count < min_enemies:
		return false
	if max_enemies > 0 and enemy_count > max_enemies:
		return false
	return true
