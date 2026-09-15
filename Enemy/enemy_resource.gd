## Data resource representing an enemy archetype, its PackedScene, and difficulty level.
class_name EnemyResource
extends Resource

## The PackedScene of the enemy character.
@export var scene: PackedScene

## Difficulty level of this enemy archetype.
@export var difficulty_level: int = 1

## Minimum run difficulty at which this enemy may appear in regular waves.
## 0 means always eligible. Bosses carry a high gate (e.g. 20) so they only
## join the regular rotation late, and spawn earlier solely via
## WaveObjective.boss_resources in their boss arena.
@export var minimum_spawn_difficulty: int = 0

## Alias for difficulty_level.
var difficulty: int:
	get:
		return difficulty_level
	set(value):
		difficulty_level = value
