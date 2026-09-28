## The level template every level inherits (split from the old
## test_enemy_base):
## - its wave plans enemies whose difficulties add up to the run's current
##   difficulty,
## - the exit starts hidden and locked, and the wave finishing unlocks and
##   shows it,
## - the scene transition's fade overlay never blocks the mouse.
## Difficulties are read from the run and the enemy registry.
extends "res://test/lib/test_suite.gd"

const LEVEL_TEMPLATE_SCENE: PackedScene = preload("res://Levels/level_template.tscn")

var _level: Node3D
var _wave: WaveObjective


func before_each() -> void:
	SceneTransition.player_cache = null
	_level = spawn(LEVEL_TEMPLATE_SCENE) as Node3D
	_wave = _level.get_node("WaveObjective") as WaveObjective


## Stopped after each test, not before: stopping frees the unspawned plan
## the first test reads.
func after_each() -> void:
	_wave.stop_spawning()


func test_the_wave_plans_enemies_worth_the_current_difficulty() -> void:
	var total: int = 0
	for enemy: Character in _wave.all_enemies:
		var resource: EnemyResource = GlobalVars.get_enemy_resource(load(enemy.scene_file_path) as PackedScene)
		if check(resource != null, "every planned enemy should be registered (%s)" % enemy.scene_file_path):
			total += resource.difficulty_level
	check(not _wave.all_enemies.is_empty(), "the wave should plan enemies")
	check_eq(total, ProgressionState.difficulty_level, "the planned difficulties should add up to the run's difficulty")


func test_the_exit_starts_locked_and_the_finished_wave_unlocks_it() -> void:
	var exit_point: ExitPoint = _level.get_node("ExitPoint") as ExitPoint
	check(not exit_point.visible and exit_point.locked, "the exit should start hidden and locked")
	_wave.finished.emit()
	check(exit_point.visible and not exit_point.locked, "finishing the wave should show and unlock the exit")


func test_the_fade_overlay_never_blocks_the_mouse() -> void:
	for control: Node in SceneTransition.find_children("*", "Control", true, false):
		check_eq((control as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "the transition overlay must not block the mouse (%s)" % control.name)
