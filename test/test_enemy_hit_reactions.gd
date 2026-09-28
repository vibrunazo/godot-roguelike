## How every enemy reacts to hits, using the base enemy scene in the arena
## (split from the old test_enemy_base):
## - a hit plays the hit sound, deals its damage and stuns; the stun ends
##   back in moving,
## - while stunned the body follows knockback and otherwise stands still,
## - moving applies the speed stat along the direction and stops without one,
## - an enemy that loses its footing falls and lands into its landing state,
## - defeat reports once, enters the defeat state and stays there after the
##   defeat animation; the corpse stops blocking and stops taking hits,
## - a dead target rejects hits, from its hurtbox and from attacks.
## Damage and knockback are test-owned; speeds are read from the enemy.
extends "res://test/lib/test_suite.gd"

const ENEMY_SCENE: PackedScene = preload("res://Enemy/enemy_base.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const TEST_DAMAGE: float = 10.0
const TEST_KNOCKBACK: Vector3 = Vector3(15.0, 0.0, 0.0)
const TEST_TICK: float = 0.1
## Test-owned drop height for the fall test.
const DROP_HEIGHT: float = 4.0
## Frame budget for a stun, a fall or a defeat animation.
const REACTION_FRAMES: int = 600

var _arena: Node3D
var _enemy: Character


func before_each() -> void:
	_arena = load_arena()
	_enemy = await _spawn_enemy((_arena.get_node("EnemySpawn") as Node3D).global_position)


func test_a_hit_sounds_hurts_and_stuns_until_the_stun_ends() -> void:
	var before: float = _health(_enemy)
	check(_enemy.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO), "the hit should land")
	check_approx(before - _health(_enemy), TEST_DAMAGE, "the hit should deal its damage")
	await wait_until(func() -> bool: return _enemy.hurtbox.hit_audio.playing, "the hit should play the hit sound", 5)
	check_eq(_state(_enemy), _enemy.stun_state.name, "the hit should stun")
	await wait_until(func() -> bool: return _state(_enemy) == "EnemyMove", "the stun should end back in moving", REACTION_FRAMES)


func test_a_stunned_body_follows_knockback_and_otherwise_stands_still() -> void:
	var stun: CharacterState = _enemy.stun_state
	_enemy.state_machine.request_state(stun.name)
	_enemy.knockback_component.magnitude = TEST_KNOCKBACK
	stun.physics_update(TEST_TICK)
	check(_enemy.velocity.is_equal_approx(TEST_KNOCKBACK), "a stunned body should move with its knockback")
	_enemy.knockback_component.magnitude = Vector3.ZERO
	_enemy.velocity = Vector3(5.0, 0.0, 5.0)
	stun.physics_update(TEST_TICK)
	check(_enemy.velocity.is_zero_approx(), "a stunned body without knockback should stand still")


func test_moving_uses_the_speed_stat_and_stops_without_a_direction() -> void:
	var move: CharacterState = _enemy.state_machine.get_node("EnemyMove") as CharacterState
	var speed: float = _enemy.attribute_component.get_current(AttributeComponent.STAT_SPEED)
	move.core_movement(TEST_TICK, speed, Vector3.RIGHT)
	check(is_equal_approx(_enemy.velocity.x, speed) and is_zero_approx(_enemy.velocity.z), "moving should go at the speed stat along the direction")
	move.core_movement(TEST_TICK, speed, Vector3.ZERO)
	check(is_zero_approx(_enemy.velocity.x), "moving without a direction should stop")


func test_an_enemy_that_loses_its_footing_falls_and_lands() -> void:
	var fall: EnemyFall = _enemy.state_machine.get_node("EnemyFall") as EnemyFall
	_enemy.global_position += Vector3.UP * DROP_HEIGHT
	if not await wait_until(func() -> bool: return _state(_enemy) == fall.name, "an enemy off the floor should fall", REACTION_FRAMES):
		return
	await wait_until(func() -> bool: return _enemy.is_on_floor() and _state(_enemy) == fall.land_state.name, "the fall should land into its landing state", REACTION_FRAMES)


func test_defeat_reports_once_stays_down_and_the_corpse_stops_blocking_and_taking_hits() -> void:
	var reports: Array[int] = [0]
	_enemy.defeat.connect(func() -> void: reports[0] += 1)
	_enemy.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, _health(_enemy))
	_enemy.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, TEST_DAMAGE)
	check_eq(reports[0], 1, "defeat should be reported exactly once")
	if not await wait_until(func() -> bool: return _state(_enemy) == _enemy.defeat_state.name, "the enemy should enter its defeat state", 5):
		return
	_enemy.animation_tree.animation_finished.emit(&"Defeat")
	await wait_physics_frames(2)
	check_eq(_state(_enemy), _enemy.defeat_state.name, "the enemy should stay defeated after the defeat animation")
	check(_enemy.collision_shape_3d.disabled, "a corpse must not block movement")
	var hurtbox_shape: CollisionShape3D = _enemy.hurtbox.get_node("CollisionShape3D") as CollisionShape3D
	check(not _enemy.hurtbox.monitoring and not _enemy.hurtbox.monitorable and hurtbox_shape.disabled and not _enemy.hurtbox.is_alive(), "a corpse's hurtbox should be switched off")


func test_a_dead_target_rejects_hits() -> void:
	var attacker: Character = await _spawn_enemy((_arena.get_node("EnemySpawn") as Node3D).global_position + Vector3(4.0, 0.0, 0.0), MELEE_SCENE)
	var weapon: AttackComponent = (attacker.state_machine.get_node("EnemyAttack") as CharacterAttack).get_attack_component()
	_enemy.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, _health(_enemy))
	await wait_physics_frames(1)
	var after_death: float = _health(_enemy)
	check(not _enemy.hurtbox.receive_hit(TEST_DAMAGE, Vector3.ZERO), "a dead target's hurtbox should reject hits")
	weapon.reset_exceptions()
	check(not weapon.deal_damage_to(_enemy.hurtbox, TEST_DAMAGE, Vector3.ZERO), "attacks should not land on a dead target")
	check_approx(_health(_enemy), after_death, "a dead target's health must not change")


## A still enemy standing on the arena floor.
func _spawn_enemy(at: Vector3, scene: PackedScene = ENEMY_SCENE) -> Character:
	var enemy: Character = spawn(scene, _arena, at) as Character
	disable_ai(enemy)
	await wait_until(func() -> bool: return enemy.is_on_floor() and _state(enemy) == "EnemyMove", "setup: the enemy should land")
	return enemy


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


func _state(character: Character) -> String:
	return str(character.state_machine.state.name)
