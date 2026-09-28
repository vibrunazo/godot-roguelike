## Fire trap (a floor fire that is always burning):
## - a character touching it is hurt at once, then not again until
##   damage_interval has passed (no stunlock), then again while it lingers,
## - it hurts the player too,
## - resizing it grows the area that hurts, its hitbox and ground plate, and
##   scales its particle count with the area,
## - the ground plate can be hidden,
## - a fire with a duration goes out when it ends: it stops hurting and stops
##   emitting.
## Damage intervals and durations are read from the trap or set by the test.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const TRAP_SCENE: PackedScene = preload("res://Hazards/fire_trap.tscn")
## Where the trap sits, away from the arena's spawn markers.
const TRAP_SPOT: Vector3 = Vector3(8.0, 0.0, -8.0)
## Physics ticks allowed for a first touch to register.
const TOUCH_FRAMES: int = 10
## Test-owned sizes and duration.
const LARGE_SIZE: Vector2 = Vector2(3.0, 2.0)
const TEST_DURATION: float = 0.2
## Offset from the trap center that is outside a 1 x 1 fire but inside a
## LARGE_SIZE one, even counting the character's capsule radius.
const EDGE_OFFSET: float = 1.2

var _arena: Node3D
var _trap: FireTrap


func before_each() -> void:
	_arena = load_arena()
	_trap = spawn(TRAP_SCENE, _arena, _trap_center()) as FireTrap
	await wait_physics_frames(1)


func test_touching_the_fire_hurts_at_once_and_then_only_every_damage_interval() -> void:
	var enemy: Character = _spawn_enemy(_standing(Vector3.ZERO))
	var strikes: Array[int] = [0]
	enemy.hurtbox.struck.connect(func(_damage: float) -> void: strikes[0] += 1)
	if not await wait_until(func() -> bool: return strikes[0] == 1, "touching the fire should hurt at once", TOUCH_FRAMES):
		return
	var interval_ticks: int = floori(_trap.damage_interval * Engine.physics_ticks_per_second)
	var early: bool = false
	for tick: int in range(interval_ticks - 2):
		await get_tree().physics_frame
		early = early or strikes[0] > 1
	check(not early, "the fire must not hit again before damage_interval (no stunlock)")
	await wait_until(func() -> bool: return strikes[0] > 1, "a character lingering in the fire should be hurt again after damage_interval", TOUCH_FRAMES + 5)


func test_the_fire_hurts_the_player_too() -> void:
	var player: Character = spawn(PLAYER_SCENE, _arena, _standing(Vector3.ZERO)) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	var health_before: float = player.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	await wait_until(func() -> bool: return player.attribute_component.get_current(AttributeComponent.POOL_HEALTH) < health_before, "the fire should hurt the player", TOUCH_FRAMES)


func test_resizing_grows_the_area_that_hurts() -> void:
	var enemy: Character = _spawn_enemy(_standing(Vector3(EDGE_OFFSET, 0.0, 0.0)))
	var strikes: Array[int] = [0]
	enemy.hurtbox.struck.connect(func(_damage: float) -> void: strikes[0] += 1)
	await wait_physics_frames(TOUCH_FRAMES)
	if not check(strikes[0] == 0, "setup: a character beside a 1 x 1 fire should not be hurt"):
		return
	_trap.set_trap_size(LARGE_SIZE)
	await wait_until(func() -> bool: return strikes[0] > 0, "after growing the fire, the same character should be hurt", TOUCH_FRAMES)
	var hitbox: Vector3 = (_trap.collision_shape.shape as BoxShape3D).size
	check(is_equal_approx(hitbox.x, LARGE_SIZE.x) and is_equal_approx(hitbox.z, LARGE_SIZE.y), "the hitbox should match the new size (got %s)" % hitbox)
	var plate: Vector3 = (_trap.ground_mesh.mesh as BoxMesh).size
	check(is_equal_approx(plate.x, LARGE_SIZE.x) and is_equal_approx(plate.z, LARGE_SIZE.y), "the ground plate should match the new size (got %s)" % plate)
	check_eq(_trap.particles.amount, roundi(_trap.base_particle_amount * LARGE_SIZE.x * LARGE_SIZE.y), "the particle count should scale with the area")
	_trap.set_trap_size(Vector2.ONE)
	check_eq(_trap.particles.amount, _trap.base_particle_amount, "back to 1 x 1, the particle count should return to its base amount")


func test_the_ground_plate_can_be_hidden() -> void:
	_trap.show_ground_mesh = false
	check(not _trap.ground_mesh.visible, "hiding the ground plate should hide it")
	_trap.show_ground_mesh = true
	check(_trap.ground_mesh.visible, "showing the ground plate should show it")


func test_a_fire_with_a_duration_goes_out_when_it_ends() -> void:
	var timed: FireTrap = autofree(TRAP_SCENE.instantiate()) as FireTrap
	timed.duration = TEST_DURATION
	_arena.add_child(timed)
	timed.global_position = _trap_center() + Vector3(-16.0, 0.0, 0.0)
	var frames: int = ceili(TEST_DURATION * Engine.physics_ticks_per_second) + 5
	if not await wait_until(func() -> bool: return timed.is_extinguished(), "the fire should go out when its duration ends", frames):
		return
	await wait_physics_frames(1)
	check(not timed.damage_hitbox.monitoring, "a fire that went out should stop hurting")
	check(not timed.particles.emitting, "a fire that went out should stop emitting")


func _spawn_enemy(at: Vector3) -> Character:
	var enemy: Character = spawn(MELEE_SCENE, _arena, at) as Character
	disable_ai(enemy)
	return enemy


func _trap_center() -> Vector3:
	return Vector3(TRAP_SPOT.x, arena_floor_top(_arena), TRAP_SPOT.z)


## A standing spot at the given offset from the trap center.
func _standing(offset: Vector3) -> Vector3:
	return _trap_center() + offset + Vector3.UP
