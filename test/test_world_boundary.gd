## The level template's kill plane (WorldBoundary), which every level
## inherits:
## - a character falling off the level takes its full health as damage,
##   dies and is hidden,
## - the player falling off the level dies and the game-over screen follows.
## Bodies are dropped far outside any floor, so the level layout never matters.
extends "res://test/lib/test_suite.gd"

const LEVEL_TEMPLATE_SCENE: PackedScene = preload("res://Levels/level_template.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Far outside any floor of the template.
const OFF_THE_LEVEL: Vector3 = Vector3(500.0, 0.0, 500.0)
## Physics ticks allowed to fall to the kill plane.
const FALL_FRAMES: int = 300

var _level: Node3D


func before_each() -> void:
	_level = spawn(LEVEL_TEMPLATE_SCENE) as Node3D
	(_level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	await wait_physics_frames(1)


func after_each() -> void:
	UI.resume_game()


func test_a_character_falling_off_the_level_dies_and_is_hidden() -> void:
	var enemy: Character = spawn(MELEE_SCENE, _level, OFF_THE_LEVEL) as Character
	disable_ai(enemy)
	var defeated: Array[bool] = [false]
	enemy.attribute_component.defeat.connect(func() -> void: defeated[0] = true)
	await wait_until(func() -> bool: return defeated[0], "a character falling off the level should die", FALL_FRAMES)
	check_approx(enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH), 0.0, "the fall should take all of its health")
	check(not enemy.visible, "a fallen character should be hidden")


func test_the_player_falling_off_the_level_dies_and_gets_the_game_over_screen() -> void:
	var player: Character = _level.get_node("Player") as Character
	player.global_position = OFF_THE_LEVEL
	if not await wait_until(func() -> bool: return not player.is_alive(), "the player falling off the level should die", FALL_FRAMES):
		return
	var menu_delay: float = (player.get_node("PlayerDefeatHandler") as PlayerDefeatHandler).menu_delay
	var frames: int = ceili(menu_delay * Engine.physics_ticks_per_second) + 10
	await wait_until(func() -> bool: return UI.is_paused(), "the game-over screen should follow the player's death", frames)
