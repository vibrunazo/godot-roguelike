## Regression suite: tall enemies (the brute and the Akira boss) pursue the
## player around Level 2's south-east pit corner without falling into the pit,
## both clockwise and counter-clockwise. The player is led around the corner
## by the test; positions are this level's corner.
## Caveat (2026-09-28): the suite no longer reproduces the bug it was written
## for. With the pre-fix navigation tuning (path_desired_distance 2.5, no path
## height offset) it still passes, so Level 2's corner no longer invites
## corner-cutting. It stays as a pursuit smoke test on a real level; see
## TODO.md for a reproducing scenario.
extends "res://test/lib/test_suite.gd"

const LEVEL_SCENE: PackedScene = preload("res://Levels/level_2.tscn")
const BRUTE_SCENE: PackedScene = preload("res://Enemy/enemy_brute.tscn")
const AKIRA_SCENE: PackedScene = preload("res://Enemy/akira_boss.tscn")
## Where the player waits before leading the enemy around the corner.
const PLAYER_START: Vector3 = Vector3(1.5, 1.0, -14.0)
## Test-owned speed (meters per tick) the player is led at.
const LEAD_STEP: float = 0.05
## Physics ticks the enemy gets to round the corner.
const ROUND_FRAMES: int = 200
## Test-owned player health, so no hit here can end the run.
const PLAYER_HEALTH: float = 100000.0
## Height below which the enemy has dropped off the floor into the pit.
const PIT_HEIGHT: float = 0.2

var _level: Node3D
var _player: Character


func before_each() -> void:
	ProgressionState.reset_run()
	_level = spawn(LEVEL_SCENE) as Node3D
	(_level.get_node("WaveObjective") as WaveObjective).stop_spawning()
	# No props: the enemy paths on floor and pit edges only.
	_level.find_child("Litter", true, false).queue_free()
	_player = _level.get_node("Player") as Character
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, PLAYER_HEALTH)
	_player.global_position = PLAYER_START
	await wait_physics_frames(2)


func after_each() -> void:
	UI.resume_game()


func test_the_brute_rounds_the_corner_clockwise() -> void:
	var brute: Character = await _spawn_pursuer(BRUTE_SCENE, Vector3(1.5, 1.5, -20.0))
	await _lead_around(brute, Vector3(-5.0, 1.0, -14.0), func() -> bool: return brute.global_position.x < -0.5 and brute.global_position.z > -16.0)


func test_the_akira_boss_rounds_the_corner_clockwise() -> void:
	var akira: Character = await _spawn_pursuer(AKIRA_SCENE, Vector3(1.5, 1.98, -20.0))
	# Pursuit only: no ranged or slam attacks interrupting the walk.
	for ability: String in ["AIFirebomb", "AISlam"]:
		var node: Node = akira.find_child(ability, true, false)
		if node != null:
			node.queue_free()
	await _lead_around(akira, Vector3(-5.0, 1.0, -14.0), func() -> bool: return akira.global_position.x < -0.5 and akira.global_position.z > -16.0)


func test_the_brute_rounds_the_corner_counter_clockwise() -> void:
	var brute: Character = await _spawn_pursuer(BRUTE_SCENE, Vector3(-4.0, 1.5, -14.0))
	await _lead_around(brute, Vector3(1.5, 1.0, -21.0), func() -> bool: return brute.global_position.x > 0.0 and brute.global_position.z < -17.0)


## Spawns the enemy and waits until it lands and starts moving.
func _spawn_pursuer(scene: PackedScene, at: Vector3) -> Character:
	var enemy: Character = spawn(scene, _level, at) as Character
	await wait_until(func() -> bool: return enemy.is_on_floor() and enemy.state_machine.state.name == "EnemyMove", "setup: %s should land and start pursuing" % enemy.name)
	return enemy


## Leads the player toward the destination and checks the enemy follows it
## around the corner (rounded) without ever falling into the pit.
func _lead_around(enemy: Character, destination: Vector3, rounded: Callable) -> void:
	var fell: bool = false
	for frame: int in range(ROUND_FRAMES):
		await get_tree().physics_frame
		_player.global_position = _player.global_position.move_toward(destination, LEAD_STEP)
		if enemy.state_machine.state.name == "EnemyFall" or not enemy.is_on_floor() or enemy.global_position.y < PIT_HEIGHT:
			fell = true
			break
		if rounded.call():
			break
	check(not fell, "%s must not fall into the pit (at %s, in %s)" % [enemy.name, enemy.global_position, enemy.state_machine.state.name])
	check(fell or rounded.call(), "%s should round the corner in time (at %s)" % [enemy.name, enemy.global_position])
