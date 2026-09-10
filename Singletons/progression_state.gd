## Run progression service, registered as the `ProgressionState` autoload (script) in `project.godot`.
## Access from anywhere via `ProgressionState`, e.g. `ProgressionState.advance_level()`.
##
## Unique responsibilities:
## - Current difficulty level (`difficulty_level`) and its lifecycle (`advance_level`, `reset_run`).
## - Difficulty scaling math (`get_enemy_count`), sampled from the
##   `GlobalVars.difficulty_curve` registry asset.
## It owns no scenes, no input, and no display code; scene/resource defaults live
## in the `GlobalVars` registry.
extends Node

## Current difficulty level. Drives enemy counts via the difficulty curve.
var difficulty_level: int = 1


## Advances the run to the next difficulty level.
func advance_level() -> void:
	difficulty_level += 1


## Resets run progression, e.g. on player defeat and game restart.
func reset_run() -> void:
	difficulty_level = 1


## Returns the enemy count for the current difficulty level.
func get_enemy_count() -> int:
	return int(floor(GlobalVars.difficulty_curve.sample(float(difficulty_level))))
