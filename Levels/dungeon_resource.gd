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
