## A mover reaches its target after distance / speed of game time at any
## frame rate and emits arrived exactly once; the GameClock autoload counts
## physics ticks.
##
## fps_matrix: 12, 30, 60
extends "res://test/lib/project_suite.gd"

const MOVER_SCENE: PackedScene = preload("res://game/mover.tscn")
## Test-owned movement: TEST_DISTANCE meters at TEST_SPEED meters per second.
const TEST_SPEED: float = 6.0
const TEST_DISTANCE: float = 3.0
## Physics ticks of slack for where in a tick the arrival lands.
const TICK_SLACK: int = 2
## Physics frames the GameClock test waits.
const CLOCK_FRAMES: int = 10


func test_mover_arrives_after_distance_over_speed() -> void:
	var mover: Mover = MOVER_SCENE.instantiate() as Mover
	mover.speed = TEST_SPEED
	mover.target_position = Vector3(TEST_DISTANCE, 0.0, 0.0)
	add_child(autofree(mover))
	var arrivals: Array[int] = [0]
	mover.arrived.connect(func() -> void: arrivals[0] += 1)
	var expected_ticks: int = ceili(TEST_DISTANCE / TEST_SPEED * Engine.physics_ticks_per_second)
	var ticks: int = 0
	while arrivals[0] == 0 and ticks < expected_ticks * 4:
		await get_tree().physics_frame
		ticks += 1
	check(absi(ticks - expected_ticks) <= TICK_SLACK, "the mover should arrive after %d physics ticks, took %d" % [expected_ticks, ticks])
	await wait_physics_frames(CLOCK_FRAMES)
	check_eq(arrivals[0], 1, "arrived should be emitted exactly once")


func test_game_clock_counts_physics_ticks() -> void:
	var before: int = GameClock.ticks
	await wait_physics_frames(CLOCK_FRAMES)
	check(absi(GameClock.ticks - before - CLOCK_FRAMES) <= 1, "GameClock should count every physics tick")


func test_suites_get_the_configured_user_args() -> void:
	check(OS.get_cmdline_user_args().has("--save-path=user://selftest_save.dat"), "test.user_args from godot_kit.toml should reach every suite")
