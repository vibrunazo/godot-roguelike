## The player's basic attack flow, driven by the `click` action:
## - pressing attack starts the first combo attack, which hits an adjacent
##   target exactly once for its damage and then returns to running,
## - attacking again after recovering hits again (hit exceptions reset),
## - pressing again inside the attack's queue window chains into combo_next,
##   which lands its own hit,
## - a press after the queue window has passed is dropped (no chain).
## Replaces test_attack_dummy, test_attack_cycle and test_queued_attack.
## Damage, combo links and queue windows are read from the live attack states.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned dummy health, high enough that no attack here can kill it.
const DUMMY_HEALTH: float = 100000.0
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600

var _player: Character
var _dummy: Character
var _first_attack: CharacterAttack


func before_each() -> void:
	var arena: Node3D = load_arena()
	_dummy = spawn(MELEE_SCENE, arena, Vector3(0.0, 1.0, 0.0)) as Character
	disable_ai(_dummy)
	_dummy.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, DUMMY_HEALTH)
	_dummy.knockback_component.max_knockback = 0.0
	_player = spawn(PLAYER_SCENE, arena, Vector3(0.0, 1.0, _adjacent_distance())) as Character
	# Live mouse aim off: attacks aim at the test-set direction (the dummy).
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_player.aim_direction = Vector3(0.0, 0.0, -1.0)
	_first_attack = _player.state_machine.get_node("PlayerAttack") as CharacterAttack
	await wait_until(func() -> bool: return _player.is_on_floor() and _dummy.is_on_floor() and _state() == "PlayerRun", "player and dummy should settle")


func test_attack_hits_an_adjacent_target_once_then_returns_to_running() -> void:
	var health_before: float = _health()
	var strikes: Array[int] = [0]
	_dummy.hurtbox.struck.connect(func(_damage: float) -> void: strikes[0] += 1)
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _first_attack.name, "pressing attack should start the first combo attack", 10):
		return
	await wait_until(func() -> bool: return _state() == "PlayerRun", "the attack should finish and return to running", ATTACK_FRAMES)
	check_eq(strikes[0], 1, "one attack should hit the target exactly once")
	check_approx(health_before - _health(), _hit(_first_attack), "the hit should deal the attack's damage")


func test_attacking_again_after_recovery_hits_again() -> void:
	for attempt: int in range(2):
		var health_before: float = _health()
		press_action(&"click")
		if not await wait_until(func() -> bool: return _state() == _first_attack.name, "attack %d should start" % (attempt + 1), 10):
			return
		await wait_until(func() -> bool: return _state() == "PlayerRun", "attack %d should finish" % (attempt + 1), ATTACK_FRAMES)
		check_approx(health_before - _health(), _hit(_first_attack), "attack %d should land its hit (hit exceptions reset between attacks)" % (attempt + 1))


func test_pressing_inside_the_queue_window_chains_the_combo() -> void:
	var next_attack: CharacterAttack = _first_attack.combo_next as CharacterAttack
	if not check(next_attack != null, "setup: the first attack should chain into a combo_next"):
		return
	var health_before: float = _health()
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _first_attack.name, "the first attack should start", 10):
		return
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == next_attack.name, "a press inside the queue window should chain into %s" % next_attack.name, ATTACK_FRAMES):
		return
	await wait_until(func() -> bool: return _state() == "PlayerRun", "the combo should finish and return to running", ATTACK_FRAMES)
	check_approx(health_before - _health(), _hit(_first_attack) + _hit(next_attack), "both combo attacks should land their hits")


func test_a_press_after_the_queue_window_is_dropped() -> void:
	var next_attack: State = _first_attack.combo_next
	press_action(&"click")
	if not await wait_until(func() -> bool: return _state() == _first_attack.name, "the first attack should start", 10):
		return
	await wait_physics_frames(ceili(_first_attack.queued_attack_time * Engine.physics_ticks_per_second) + 2)
	if not check(_state() == _first_attack.name, "setup: the first attack should outlast its queue window"):
		return
	press_action(&"click")
	var chained: Array[bool] = [false]
	await wait_until(func() -> bool:
		chained[0] = chained[0] or (next_attack != null and _state() == next_attack.name)
		return _state() == "PlayerRun", "the first attack should finish", ATTACK_FRAMES)
	check(not chained[0], "a press after the queue window must not chain the combo")


func _state() -> String:
	return str(_player.state_machine.state.name)


func _health() -> float:
	return _dummy.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## Damage one hit of the attack deals.
func _hit(attack: CharacterAttack) -> float:
	return attack.damage * _player.get_damage_modifier()


## Distance between origins that leaves a small gap between the capsules.
func _adjacent_distance() -> float:
	var player: Character = PLAYER_SCENE.instantiate() as Character
	var player_radius: float = float((player.get_node("CollisionShape3D") as CollisionShape3D).shape.get("radius"))
	player.free()
	return float(_dummy.collision_shape_3d.shape.get("radius")) + player_radius + 0.3
