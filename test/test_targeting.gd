## Player auto-aim targeting:
## - acquires the nearest enemy within its TargetingComponent's auto_aim_range;
##   enemies (no TargetingComponent) do not auto-aim,
## - a single player-only reticle follows the target and hides without one,
## - the retarget cooldown holds the current target until it expires or
##   force_retarget() is called,
## - a target leaving the range clears at once, whatever the cooldown,
## - with no target held, an enemy entering the range is acquired on the next
##   tick, whatever the cooldown,
## - an attack turns toward the target instead of the aim direction,
## - the target is frozen during an attack; a target killed mid-attack clears
##   at once and nothing replaces it until the attack ends,
## - killing the target clears it synchronously and switches to the nearest
##   living enemy without waiting out the cooldown; the corpse is never
##   targeted again,
## - a target freed from the tree (not killed) is dropped without errors and
##   the nearest living enemy is targeted instead,
## - an enemy near the aimed floor point (the cursor) is targeted, and shown by
##   the reticle, ahead of the nearest one and at once, whatever the cooldown
##   or its distance from the player; with the cursor away from every enemy,
##   targeting falls back to the nearest.
## Distances are fractions of the player's own auto_aim_range.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned retarget cooldown, far longer than any watch window below, so a
## switch inside a window can only come from something other than the cooldown.
const LONG_COOLDOWN: float = 10.0
## Test-owned watch window (seconds) for "must not change" checks.
const HOLD_WINDOW: float = 0.5
## Ticks auto-aim may take to react (the change lands on the next tick).
const REACT_FRAMES: int = 3
## Test-owned enemy health, so the player's attacks never kill by accident.
const ENEMY_HEALTH: float = 100000.0
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600
## Minimum facing alignment (cosine) that counts as "turned toward".
const TURNED: float = 0.85

var _arena: Node3D
var _player: Character
var _home: Vector3


func before_each() -> void:
	_arena = load_arena()
	_home = (_arena.get_node("PlayerSpawn") as Node3D).global_position
	_player = spawn(PLAYER_SCENE, _arena, _home) as Character
	# Live mouse aim off: the test sets the aim direction itself.
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	await wait_until(func() -> bool: return _player.is_on_floor() and _state() == "PlayerRun", "the player should settle")
	check(_aim().auto_aim_range > 0.0, "setup: the player should have auto-aim enabled")


func test_acquires_the_nearest_enemy_in_range_and_enemies_do_not_auto_aim() -> void:
	var near: Character = await _spawn_enemy(_at(0.3, Vector3.RIGHT))
	var far: Character = await _spawn_enemy(_at(0.5, Vector3.LEFT))
	await wait_until(func() -> bool: return _player.current_target == near, "the player should target the nearest enemy")
	check(far.current_target == null and near.current_target == null, "enemies should not auto-aim")


func test_the_reticle_follows_the_target_and_hides_without_one() -> void:
	var enemy: Character = await _spawn_enemy(_at(0.3, Vector3.RIGHT))
	if not await wait_until(func() -> bool: return _player.current_target == enemy, "setup: the player should target the enemy"):
		return
	await wait_until(func() -> bool: return _reticle() != null and _reticle().target == enemy and _reticle().visible, "the reticle should show on the player's target")
	check_eq(get_tree().root.find_children("*", "TargetReticle", true, false).size(), 1, "there should be exactly one (player-only) reticle")
	enemy.global_position = _at(1.5, Vector3.RIGHT)
	await wait_until(func() -> bool: return _reticle() != null and _reticle().target == null and not _reticle().visible, "the reticle should hide when the target is lost")


func test_the_retarget_cooldown_holds_the_target_until_forced() -> void:
	_aim().target_retarget_cooldown = LONG_COOLDOWN
	var first: Character = await _spawn_enemy(_at(0.4, Vector3.RIGHT))
	var second: Character = await _spawn_enemy(_at(0.6, Vector3.LEFT))
	if not await wait_until(func() -> bool: return _player.current_target == first, "setup: the player should target the nearer enemy"):
		return
	second.global_position = _at(0.2, Vector3.LEFT)
	await _check_target_held(first, "the target should not switch while the retarget cooldown runs")
	_aim().force_retarget()
	await wait_until(func() -> bool: return _player.current_target == second, "force_retarget() should switch to the nearer enemy", REACT_FRAMES)


func test_a_target_leaving_the_range_clears_at_once() -> void:
	_aim().target_retarget_cooldown = LONG_COOLDOWN
	var enemy: Character = await _spawn_enemy(_at(0.3, Vector3.RIGHT))
	if not await wait_until(func() -> bool: return _player.current_target == enemy, "setup: the player should target the enemy"):
		return
	enemy.global_position = _at(1.5, Vector3.RIGHT)
	await wait_until(func() -> bool: return _player.current_target == null, "an out-of-range target should clear without waiting out the cooldown", REACT_FRAMES)


func test_with_no_target_held_an_enemy_entering_range_is_acquired_at_once() -> void:
	_aim().target_retarget_cooldown = LONG_COOLDOWN
	var enemy: Character = await _spawn_enemy(_at(1.5, Vector3.RIGHT))
	await _check_target_held(null, "nothing should be targeted while every enemy is out of range")
	enemy.global_position = _at(0.3, Vector3.RIGHT)
	await wait_until(func() -> bool: return _player.current_target == enemy, "an enemy entering range should be acquired on the next tick, whatever the cooldown", REACT_FRAMES)


func test_an_attack_turns_toward_the_target_instead_of_the_aim() -> void:
	var enemy: Character = await _spawn_enemy(_at(0.3, Vector3.RIGHT))
	if not await wait_until(func() -> bool: return _player.current_target == enemy, "setup: the player should target the enemy"):
		return
	_player.aim_direction = Vector3.LEFT
	press_action(&"click")
	if not await wait_until(func() -> bool: return _player.is_attacking, "pressing attack should start an attack", 10):
		return
	var budget: int = ceili(180.0 / _player.get_rotation_speed() * Engine.physics_ticks_per_second) + 5
	await wait_until(func() -> bool: return _facing().dot(_flat(enemy.global_position - _player.global_position)) >= TURNED, "the attack should turn toward the target, not the aim direction", budget)


func test_the_target_is_frozen_during_an_attack_and_a_kill_is_not_replaced_until_it_ends() -> void:
	var target: Character = await _spawn_enemy(_at(0.3, Vector3.RIGHT))
	if not await wait_until(func() -> bool: return _player.current_target == target, "setup: the player should target the enemy"):
		return
	_player.aim_direction = Vector3.RIGHT
	press_action(&"click")
	if not await wait_until(func() -> bool: return _player.is_attacking, "pressing attack should start an attack", 10):
		return
	# A nearer living enemy appears and the target moves away (still in range).
	var alternative: Character = await _spawn_enemy(_at(0.2, Vector3.BACK))
	target.global_position = _at(0.6, Vector3.LEFT)
	_aim().force_retarget()
	await wait_physics_frames(REACT_FRAMES)
	if not check(_player.is_attacking, "setup: the attack should outlast the retarget reaction time"):
		return
	check(_player.current_target == target, "the target should not change during an attack")
	target.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, target.attribute_component.get_current(AttributeComponent.POOL_HEALTH))
	check(_player.current_target == null, "a target killed mid-attack should clear at once")
	var replaced: Array[bool] = [false]
	await wait_until(func() -> bool:
		replaced[0] = replaced[0] or (_player.is_attacking and _player.current_target != null)
		return not _player.is_attacking, "the attack should end", ATTACK_FRAMES)
	check(not replaced[0], "no new target should be acquired until the attack ends")
	await wait_until(func() -> bool: return _player.current_target == alternative, "after the attack the living enemy should be targeted")


func test_killing_the_target_switches_to_the_nearest_living_enemy_at_once() -> void:
	_aim().target_retarget_cooldown = LONG_COOLDOWN
	var nearest: Character = await _spawn_enemy(_at(0.2, Vector3.RIGHT))
	var next: Character = await _spawn_enemy(_at(0.4, Vector3.LEFT))
	await _spawn_enemy(_at(0.6, Vector3.BACK))
	if not await wait_until(func() -> bool: return _player.current_target == nearest, "setup: the player should target the nearest enemy"):
		return
	nearest.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, nearest.attribute_component.get_current(AttributeComponent.POOL_HEALTH))
	check(_player.current_target == null, "a killed target should clear in the same frame")
	if not await wait_until(func() -> bool: return _player.current_target == next, "the nearest living enemy should be targeted without waiting out the cooldown", REACT_FRAMES):
		return
	_aim().force_retarget()
	await _check_target_held(next, "the corpse must never be targeted again")


func test_a_freed_target_is_dropped_and_replaced() -> void:
	var nearest: Character = await _spawn_enemy(_at(0.2, Vector3.RIGHT))
	var next: Character = await _spawn_enemy(_at(0.4, Vector3.LEFT))
	if not await wait_until(func() -> bool: return _player.current_target == nearest, "setup: the player should target the nearest enemy"):
		return
	nearest.free()
	await wait_until(func() -> bool: return is_same(_player.current_target, next), "a freed target should be replaced by the nearest living enemy", REACT_FRAMES)


func test_an_enemy_near_the_cursor_is_targeted_before_the_nearest() -> void:
	_aim().target_retarget_cooldown = LONG_COOLDOWN
	var nearest: Character = await _spawn_enemy(_at(0.2, Vector3.RIGHT))
	var far: Character = await _spawn_enemy(_at(1.5, Vector3.LEFT))
	if not await wait_until(func() -> bool: return _player.current_target == nearest, "setup: the player should target the nearest enemy"):
		return
	_player.aim_target = AimTarget.at(far.get_feet_position() + Vector3.BACK * _aim().cursor_assist_radius * 0.5)
	if not await wait_until(func() -> bool: return _player.current_target == far, "an enemy near the cursor should be targeted at once, even out of auto-aim range", REACT_FRAMES):
		return
	await wait_until(func() -> bool: return _reticle() != null and _reticle().target == far, "the reticle should show the enemy near the cursor")
	_player.aim_target = AimTarget.at(_at(0.5, Vector3.FORWARD))
	_aim().force_retarget()
	await wait_until(func() -> bool: return _player.current_target == nearest, "with the cursor away from every enemy, the nearest should be targeted again", REACT_FRAMES)


## Fails if the player's target is ever anything but expected during
## HOLD_WINDOW (checked every tick, not just at the end).
func _check_target_held(expected: Character, message: String) -> void:
	var changed: Array[bool] = [false]
	var ticks: int = ceili(HOLD_WINDOW * Engine.physics_ticks_per_second)
	for tick: int in range(ticks):
		await get_tree().physics_frame
		changed[0] = changed[0] or _player.current_target != expected
	check(not changed[0], message)


## Spawns a still, hard-to-kill melee enemy and lets it tick once, so the next
## spawn never shares its first physics frame (same-frame spawns displace the
## second body).
func _spawn_enemy(at: Vector3) -> Character:
	var enemy: Character = spawn(MELEE_SCENE, _arena, at) as Character
	disable_ai(enemy)
	enemy.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, ENEMY_HEALTH)
	if enemy.knockback_component != null:
		enemy.knockback_component.max_knockback = 0.0
	await wait_physics_frames(2)
	return enemy


## Point at the given fraction of the player's auto-aim range from the player
## spawn, along a horizontal direction.
func _at(range_fraction: float, direction: Vector3) -> Vector3:
	return _home + direction * _aim().auto_aim_range * range_fraction


func _reticle() -> TargetReticle:
	return VfxManager.target_reticle if is_instance_valid(VfxManager.target_reticle) else null


func _facing() -> Vector3:
	return _flat(_player.mesh_mount.global_basis.z)


func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z).normalized()


func _state() -> String:
	return str(_player.state_machine.state.name)


## The player's auto-aim (TargetingComponent).
func _aim() -> TargetingComponent:
	return _player.get_node("TargetingComponent") as TargetingComponent
