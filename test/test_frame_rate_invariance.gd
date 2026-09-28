## Gameplay must not depend on the render frame rate. Physics always ticks at
## the project's rate, but a slow device renders fewer frames, so anything
## timed on the render clock (idle AnimationTrees driving hit windows, idle
## Timers, SceneTreeTimers without process_in_physics) stretches, shrinks or
## skips gameplay windows. This suite runs at several render rates (see
## fps_matrix below) and checks the mechanics that broke that way:
## - an enemy melee attack lands on an adjacent target,
## - every player combo attack lands on an adjacent target,
## - the dash lasts its configured duration,
## - braking to a stop takes the same game time at any physics tick rate.
##
## fps_matrix: 12, 20, 30, 60
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Physics ticks the state machine may take to notice an expired dash timer
## and leave the dash state (timer timeout, then the state's next update).
const STATE_LATENCY_TICKS: int = 2
## Test-owned health large enough that no attack in this suite can kill.
const DUMMY_HEALTH: float = 100000.0
## Frame budget for one full attack animation.
const ATTACK_FRAMES: int = 600
## Test-owned braking setup: stop_time and how many times faster than the
## movement speed the character is moving when it starts braking.
const TEST_STOP_TIME: float = 0.2
const OVERSPEED: float = 3.0
## Physics tick rates the braking simulation is run at.
const TICK_RATES: Array[int] = [60, 30, 20]

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


func test_melee_enemy_attack_lands_on_adjacent_target() -> void:
	var enemy: Character = _spawn_dummy(MELEE_SCENE, Vector3(0.0, 1.0, 0.0))
	var player: Character = _spawn_dummy(PLAYER_SCENE, Vector3(0.0, 1.0, -_adjacent_distance(enemy, PLAYER_SCENE)))
	if not await _both_grounded(enemy, player):
		return
	var attack: CharacterAttack = enemy.state_machine.get_node("EnemyAttack") as CharacterAttack
	var hp_before: float = _health(player)
	enemy.state_machine.request_state("EnemyAttack", {"aim": Vector3(0.0, 0.0, -1.0)})
	await wait_signal(player.hurtbox.struck, "the melee enemy's attack should land on an adjacent player", ATTACK_FRAMES)
	check_approx(hp_before - _health(player), attack.damage * enemy.get_damage_modifier(), "the attack should deal its damage")


func test_player_combo_attacks_each_land_on_adjacent_target() -> void:
	var dummy: Character = _spawn_dummy(MELEE_SCENE, Vector3(0.0, 1.0, 0.0))
	var player: Character = _spawn_dummy(PLAYER_SCENE, Vector3(0.0, 1.0, _adjacent_distance(dummy, PLAYER_SCENE)))
	_stop_player_input(player)
	if not await _both_grounded(dummy, player):
		return
	for attack_name: String in ["PlayerAttack", "PlayerAttack2", "PlayerAttack3"]:
		var attack: CharacterAttack = player.state_machine.get_node(attack_name) as CharacterAttack
		player.aim_direction = Vector3(0.0, 0.0, -1.0)
		var hp_before: float = _health(dummy)
		player.state_machine.request_state(attack_name)
		var landed: bool = await wait_signal(dummy.hurtbox.struck, "%s should land on an adjacent target" % attack_name, ATTACK_FRAMES)
		await wait_until(func() -> bool: return player.state_machine.state.name != attack_name, "%s should finish" % attack_name, ATTACK_FRAMES)
		if landed:
			check(hp_before - _health(dummy) >= attack.damage * player.get_damage_modifier() - 0.001, "%s should deal at least one hit of its damage" % attack_name)


func test_dash_lasts_its_configured_duration() -> void:
	var player: Character = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_stop_player_input(player)
	if not await wait_until(func() -> bool: return player.is_on_floor() and player.state_machine.state.name == "PlayerRun", "player should settle into PlayerRun"):
		return
	var dash: PlayerDash = player.state_machine.get_node("PlayerDash") as PlayerDash
	var tick: float = 1.0 / Engine.physics_ticks_per_second
	var min_ticks: int = ceili(dash.dash_duration.wait_time / tick - 0.001)
	var start: Vector3 = player.global_position
	player.state_machine.request_state("PlayerDash", {"direction": Vector3(1.0, 0.0, 0.0)})
	var ticks: int = 0
	while player.state_machine.state == dash and ticks < ATTACK_FRAMES:
		await get_tree().physics_frame
		ticks += 1
	check(ticks >= min_ticks and ticks <= min_ticks + STATE_LATENCY_TICKS, "dash should last its duration (%d..%d physics ticks), lasted %d" % [min_ticks, min_ticks + STATE_LATENCY_TICKS, ticks])
	check(player.global_position.x - start.x > 0.0, "dash should move the player along its direction")


func test_braking_takes_the_same_time_at_any_tick_rate() -> void:
	var player: Character = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_stop_player_input(player)
	if not await wait_until(func() -> bool: return player.is_on_floor() and player.state_machine.state.name == "PlayerRun", "player should settle into PlayerRun"):
		return
	player.stop_time = TEST_STOP_TIME
	var run_state: CharacterState = player.state_machine.state as CharacterState
	var speed: float = player.attribute_component.get_current(AttributeComponent.STAT_SPEED)
	var expected: float = OVERSPEED * TEST_STOP_TIME
	for tick_rate: int in TICK_RATES:
		# Simulate ticks of this rate by calling the movement step with its delta.
		var tick: float = 1.0 / tick_rate
		player.velocity = Vector3(speed * OVERSPEED, 0.0, 0.0)
		var elapsed: float = 0.0
		while not is_zero_approx(player.velocity.x) and elapsed < expected * 10.0:
			run_state.core_movement(tick, speed)
			elapsed += tick
		check(elapsed >= expected - 0.001 and elapsed <= expected + tick + 0.001, "at %d ticks/s braking from %sx speed should take %.3f s, took %.3f s" % [tick_rate, OVERSPEED, expected, elapsed])


## Spawns a character with its AI stopped, test-owned huge health and no
## knockback, so it stays put through repeated hits.
func _spawn_dummy(scene: PackedScene, at: Vector3) -> Character:
	var character: Character = spawn(scene, _arena, at) as Character
	disable_ai(character)
	character.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, DUMMY_HEALTH)
	if character.knockback_component != null:
		character.knockback_component.max_knockback = 0.0
	return character


## Distance between two characters' origins that leaves a small gap between
## their capsules: any melee attack must reach this far.
func _adjacent_distance(first: Character, second_scene: PackedScene) -> float:
	var second: Character = second_scene.instantiate() as Character
	var second_radius: float = (second.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius")
	second.free()
	return _radius(first) + second_radius + 0.3


func _radius(character: Character) -> float:
	return float(character.collision_shape_3d.shape.get("radius"))


func _both_grounded(first: Character, second: Character) -> bool:
	return await wait_until(func() -> bool: return first.is_on_floor() and second.is_on_floor(), "both characters should land")


## Stops live input polling so the test alone sets the player's aim and moves.
func _stop_player_input(player: Character) -> void:
	var input_component: PlayerInputComponent = player.get_node("PlayerInputComponent") as PlayerInputComponent
	input_component.set_physics_process(false)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
