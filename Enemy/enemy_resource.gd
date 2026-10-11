## Data resource representing an enemy archetype, its PackedScene, and difficulty level.
class_name EnemyResource
extends Resource

## The PackedScene of the enemy character.
@export var scene: PackedScene

## Difficulty level of this enemy archetype.
@export var difficulty_level: int = 1

## Minimum run difficulty at which this enemy may appear in regular waves.
## 0 means always eligible. Bosses carry a high gate (e.g. 20) so they only
## join the regular rotation late, and spawn earlier solely as the boss of
## their boss level (boss_at_level).
@export var minimum_spawn_difficulty: int = 0

## Dungeon level at which this enemy is fought as a boss, alone in a boss
## arena. Every registered enemy with the same boss_at_level forms that
## level's boss pool, and each run fights one of them, picked at random
## (ProgressionState.boss_pool()). 0 = not a boss.
@export var boss_at_level: int = 0

## Gold currency awarded to the player when an enemy of this archetype is defeated.
@export var gold_drop: int = 5

## Items an enemy of this archetype may drop when defeated, each rolled on its
## own (see LootDrop and LootComponent). Each enemy drops a book teaching an
## ability it uses itself.
@export var item_drops: Array[LootDrop] = []
