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

## Dungeon level at which the run detours to this dungeon as a boss arena
## instead of picking a regular dungeon. 0 = a regular dungeon. A boss arena
## is never picked by difficulty: its scene carries its bosses on its
## WaveObjective.boss_resources, and the eligibility limits above are ignored.
@export var boss_at_level: int = 0


## True for a boss arena (see boss_at_level).
func is_boss_arena() -> bool:
	return boss_at_level > 0


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
