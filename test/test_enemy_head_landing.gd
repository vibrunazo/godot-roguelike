## Regression suite: enemy tops are never usable floors for the player.
##
## Mechanism: the player's states move via `Character.move_character()`, which
## retries any enemy-top floor contact in floating mode, so landing on a head
## can never report `is_on_floor()`, transition to PlayerRun, or launch the
## player (wall-like contact; momentum preserved, steering off the crown
## stripped, drift banked as distance). Uses the real Player and melee enemy
## scenes in the arena:
## - the player still lands normally on real floor,
## - a drop onto the slope of a head, onto the crown, or onto the crown while
##   steering back onto it every tick never counts as floor, never settles
##   into running on top, never launches the player faster than it walks, and
##   always ends on the ground,
## - the enemy body still blocks the player from the side,
## - enemies can still stand on other enemies.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned drop height above the enemy capsule top, in meters.
const DROP_HEIGHT: float = 1.0
## Horizontal offset from the enemy center for the slope drop, so contact
## starts on the dome slope instead of the apex point.
const DROP_OFFSET: float = 0.25
## Physics ticks to wait for a landing after a drop.
const LANDING_FRAMES: int = 240
## Consecutive ticks in PlayerRun above the crown that count as perching.
const PERCH_TICKS: int = 5
## Height above the floor that counts as "on top of the enemy" / "on the floor".
const ABOVE_FLOOR: float = 0.5
const ON_FLOOR: float = 0.2

var _arena: Node3D
var _player: Character
var _enemy: Character
var _floor_y: float = 0.0


func before_each() -> void:
	_arena = load_arena()
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	# Live input off: the test sets move_direction itself.
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_enemy = await _spawn_settled_enemy((_arena.get_node("EnemySpawn") as Node3D).global_position)
	await wait_until(func() -> bool: return _player.is_on_floor() and _state() == "PlayerRun", "the player should settle")
	_floor_y = _player.global_position.y


func test_the_player_still_lands_on_real_floor() -> void:
	_player.global_position += Vector3.UP
	_player.velocity = Vector3.ZERO
	await wait_until(func() -> bool: return _on_ground(), "a 1 m drop onto the floor should land back in running", LANDING_FRAMES)


func test_a_drop_onto_the_slope_of_a_head_slides_off_without_a_launch() -> void:
	await _drop_and_check(Vector3(DROP_OFFSET, 0.0, 0.0), false)


func test_a_drop_onto_the_crown_never_perches() -> void:
	await _drop_and_check(Vector3.ZERO, false)


func test_steering_onto_the_crown_every_tick_still_slides_off() -> void:
	await _drop_and_check(Vector3.ZERO, true)


func test_the_enemy_body_still_blocks_the_player_from_the_side() -> void:
	var start: Vector3 = _enemy.global_position + Vector3(2.0, 0.0, 0.0)
	start.y = _player.global_position.y
	_player.global_position = start
	_player.velocity = Vector3.ZERO
	var start_distance: float = _flat_distance()
	var closest: float = INF
	_player.move_direction = Vector3.LEFT
	for frame: int in range(ceili(Engine.physics_ticks_per_second)):
		await get_tree().physics_frame
		closest = minf(closest, _flat_distance())
	_player.move_direction = Vector3.ZERO
	check(closest < start_distance, "setup: the player should walk toward the enemy")
	check(closest > (_radius(_player) + _radius(_enemy)) * 0.8, "the player must not walk through the enemy body (got to %.2f m)" % closest)


func test_enemies_can_still_stand_on_enemies() -> void:
	var rider: Character = await _spawn_settled_enemy(Vector3(_enemy.global_position.x, _top(_enemy) + 0.5, _enemy.global_position.z))
	if check(rider != null, "an enemy dropped on another should settle on it"):
		check(rider.global_position.y > _enemy.global_position.y + ABOVE_FLOOR, "the rider should rest on the other enemy, not the floor")


## Drops the player from above the enemy (offset from its center) and checks
## the top never acts as a floor. With steer, the player steers toward the
## enemy's center every tick.
func _drop_and_check(offset: Vector3, steer: bool) -> void:
	_player.global_position = Vector3(_enemy.global_position.x, _top(_enemy) + DROP_HEIGHT, _enemy.global_position.z) + offset
	_player.velocity = Vector3.ZERO
	_player.move_direction = Vector3.ZERO
	var walk_speed: float = _player.attribute_component.get_current(AttributeComponent.STAT_SPEED)
	var head_floor: bool = false
	var perched: bool = false
	var fastest: float = 0.0
	var run_streak: int = 0
	var landed: bool = false
	for frame: int in range(LANDING_FRAMES):
		if steer:
			var to_enemy: Vector3 = _enemy.global_position - _player.global_position
			to_enemy.y = 0.0
			_player.move_direction = Vector3.ZERO if to_enemy.is_zero_approx() else to_enemy.normalized()
		await get_tree().physics_frame
		var on_head: bool = _flat_distance() < (_radius(_player) + _radius(_enemy)) * 1.25 and _player.global_position.y > _floor_y + ABOVE_FLOOR
		head_floor = head_floor or (on_head and _player.is_on_floor())
		run_streak = run_streak + 1 if on_head and _state() == "PlayerRun" else 0
		perched = perched or run_streak >= PERCH_TICKS
		fastest = maxf(fastest, Vector2(_player.velocity.x, _player.velocity.z).length())
		if _on_ground():
			landed = true
			break
	_player.move_direction = Vector3.ZERO
	check(not head_floor, "the enemy top must never count as floor")
	check(not perched, "the player must never settle into running on top of the enemy")
	check(fastest <= walk_speed, "the head contact must not launch the player (%.2f m/s, walking is %.2f)" % [fastest, walk_speed])
	check(landed, "the player should slide off and land on the floor")


## A still melee enemy that has landed, or null.
func _spawn_settled_enemy(at: Vector3) -> Character:
	var enemy: Character = spawn(MELEE_SCENE, _arena, at) as Character
	disable_ai(enemy)
	if not await wait_until(func() -> bool: return enemy.is_on_floor(), "setup: the enemy should land"):
		return null
	return enemy


func _on_ground() -> bool:
	return _player.is_on_floor() and _player.global_position.y <= _floor_y + ON_FLOOR and _state() == "PlayerRun"


## Height of the top of the character's capsule.
func _top(character: Character) -> float:
	var shape: CollisionShape3D = character.collision_shape_3d
	return shape.global_position.y + (shape.shape as CapsuleShape3D).height * 0.5


func _radius(character: Character) -> float:
	return (character.collision_shape_3d.shape as CapsuleShape3D).radius


func _flat_distance() -> float:
	return Vector2(_player.global_position.x - _enemy.global_position.x, _player.global_position.z - _enemy.global_position.z).length()


func _state() -> String:
	return str(_player.state_machine.state.name)
