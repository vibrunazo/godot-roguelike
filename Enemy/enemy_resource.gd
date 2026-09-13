## Data resource representing an enemy archetype, its PackedScene, and difficulty level.
class_name EnemyResource
extends Resource

## The PackedScene of the enemy character.
@export var scene: PackedScene

## Difficulty level of this enemy archetype.
@export var difficulty_level: int = 1

## Alias for difficulty_level.
var difficulty: int:
	get:
		return difficulty_level
	set(value):
		difficulty_level = value
