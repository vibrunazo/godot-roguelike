## WaveObjective spawn lifecycle:
## - stop_spawning() frees every planned enemy that has not entered the level,
##   and nothing spawns afterwards,
## - enemies already in the level still complete the wave when defeated,
## - stopping never completes the wave by itself,
## - deleting the wave mid-way frees its unspawned enemies (no leak).
##
## Waves are built from a test-owned EnemyResource list (boss_resources, which
## spawns exactly the listed enemies) with test-owned spawn delays, so the
## suite depends on neither the difficulty budget nor any tuning.
extends "res://test/lib/test_suite.gd"

const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned wave shape and pacing.
const WAVE_SIZE: int = 3
const FIRST_SPAWN_DELAY: float = 0.1
const SPAWN_INTERVAL: float = 0.2
## Lethal test damage for defeating spawned enemies.
const LETHAL_DAMAGE: float = 100000.0

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


func test_stop_spawning_frees_unspawned_enemies_and_spawns_no_more() -> void:
	var wave: WaveObjective = _spawn_wave()
	if not await wait_until(func() -> bool: return _spawned(wave).size() == 1, "the first enemy should spawn", _frames_for(FIRST_SPAWN_DELAY + SPAWN_INTERVAL)):
		return
	var unspawned: Array[WeakRef] = []
	for enemy: Character in wave.all_enemies:
		if not enemy.is_inside_tree():
			unspawned.append(weakref(enemy))
	wave.stop_spawning()
	for ref: WeakRef in unspawned:
		check(ref.get_ref() == null, "an unspawned enemy should be freed by stop_spawning()")
	check_eq(wave.all_enemies.size(), 1, "all_enemies should keep only the enemy already in the level")
	await wait_physics_frames(_frames_for(SPAWN_INTERVAL * WAVE_SIZE))
	check_eq(_spawned(wave).size(), 1, "no enemy should spawn after stop_spawning()")


func test_enemies_already_spawned_still_complete_the_wave() -> void:
	var wave: WaveObjective = _spawn_wave()
	if not await wait_until(func() -> bool: return _spawned(wave).size() == 1, "the first enemy should spawn", _frames_for(FIRST_SPAWN_DELAY + SPAWN_INTERVAL)):
		return
	wave.stop_spawning()
	var finished: Array[bool] = [false]
	wave.finished.connect(func() -> void: finished[0] = true)
	_spawned(wave)[0].hurtbox.receive_hit(LETHAL_DAMAGE, Vector3.ZERO)
	check(finished[0], "defeating the last enemy in the level should finish a stopped wave")


func test_stopping_before_any_spawn_never_finishes_the_wave() -> void:
	var wave: WaveObjective = _spawn_wave()
	var finished: Array[bool] = [false]
	wave.finished.connect(func() -> void: finished[0] = true)
	wave.stop_spawning()
	check(wave.all_enemies.is_empty(), "stopping before the first spawn should free every planned enemy")
	await wait_physics_frames(_frames_for(FIRST_SPAWN_DELAY + SPAWN_INTERVAL * WAVE_SIZE))
	check(_spawned(wave).is_empty(), "no enemy should spawn after stop_spawning()")
	check(not finished[0], "stop_spawning() must not report the wave as finished")


func test_deleting_the_wave_mid_way_frees_unspawned_enemies() -> void:
	var wave: WaveObjective = _spawn_wave()
	var unspawned: Array[WeakRef] = []
	for enemy: Character in wave.all_enemies:
		unspawned.append(weakref(enemy))
	wave.queue_free()
	await wait_physics_frames(2)
	for ref: WeakRef in unspawned:
		check(ref.get_ref() == null, "an enemy that never spawned should be freed with its wave")


## A wave of WAVE_SIZE melee enemies with test-owned pacing, in the arena.
func _spawn_wave() -> WaveObjective:
	var resource: EnemyResource = EnemyResource.new()
	resource.scene = MELEE_SCENE
	var wave: WaveObjective = WaveObjective.new()
	for i: int in range(WAVE_SIZE):
		wave.boss_resources.append(resource)
	wave.first_spawn_delay = FIRST_SPAWN_DELAY
	wave.spawn_interval = SPAWN_INTERVAL
	autofree(wave)
	_arena.add_child(wave)
	return wave


func _spawned(wave: WaveObjective) -> Array[Character]:
	var result: Array[Character] = []
	for enemy: Character in wave.all_enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree():
			result.append(enemy)
	return result


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 10
