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

## Current dungeon level (starts at base_dungeon_level, +1 per cleared level).
var dungeon_level: int = 1

## Current floored difficulty rating budget used by WaveObjective.
var difficulty_level: int = 3


func _ready() -> void:
	reset_run()


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
	dungeon_level = base_dungeon_level
	difficulty_level = calculate_difficulty(dungeon_level)
