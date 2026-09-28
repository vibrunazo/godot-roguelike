## Firebomber, its firebomb, and its leaping dodge:
## - The firebomber is registered and lands in the wave's difficulty pool at
##   its own difficulty level.
## - A firebomb flies at its horizontal speed, faces along its velocity, and
##   lands on its target; on the ground it leaves a fire trap configured from
##   the bomb (size, duration, damage, no ground decal). Hitting the player in
##   flight damages them and leaves no fire trap.
## - A cast aims at the ground under the firebomber's current target.
## - AILeapingDodge keeps the values it is configured with, triggers only
##   within trigger_range and off cooldown, and never breaks a stun it is not
##   allowed to break.
## - The leap rises to peak_height, lands within max_range, keeps hyper-armor
##   when uninterruptable, clamps explicit targets, survives a zero direction,
##   and never targets a landing point through a wall.
## Every expected value comes from the live nodes or is set by the test, and
## every wait is on a condition, so the suite holds at any frame rate.
extends "res://test/lib/test_suite.gd"

const FIREBOMBER_SCENE: PackedScene = preload("res://Enemy/firebomber_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const FIREBOMB_SCENE: PackedScene = preload("res://Enemy/firebomb_projectile.tscn")
## Test-owned throw distance and a far point beyond any sensible leap range.
const THROW_DISTANCE: float = 6.0
const FAR_TARGET_DISTANCE: float = 1000.0
## Test-owned wall distance for the landing-through-walls check.
const WALL_DISTANCE: float = 2.0
## Frame budget for a whole bomb flight or leap.
const FLIGHT_FRAMES: int = 600

var _arena: Node3D
var _floor_top: float


func before_each() -> void:
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)


# --- Registration --------------------------------------------------------------

func test_firebomber_is_registered_as_a_spawnable_enemy() -> void:
	var resource: EnemyResource = GlobalVars.get_enemy_resource(FIREBOMBER_SCENE)
	if not check(resource != null, "GlobalVars.enemies should register the firebomber"):
		return
	var wave: WaveObjective = autofree(WaveObjective.new()) as WaveObjective
	var tier: Array = wave.build_difficulty_pool(GlobalVars.enemies).get(resource.difficulty_level, [])
	check(tier.has(resource), "the wave's difficulty pool should offer the firebomber at its own difficulty level")
	var instance: Character = autofree(resource.scene.instantiate()) as Character
	check(instance != null and instance.is_in_group("enemy"), "the registered scene should instantiate an enemy Character")


# --- Firebomb ------------------------------------------------------------------

func test_firebomb_flies_at_its_speed_and_lands_on_its_target() -> void:
	var bomb: FirebombProjectile = _spawn_bomb(Vector3(0.0, _floor_top + 1.5, 0.0))
	var target: Vector3 = Vector3(0.0, _floor_top, THROW_DISTANCE)
	bomb.initialize_trajectory(target)
	check_approx(Vector2(bomb.velocity.x, bomb.velocity.z).length(), bomb.speed, "the bomb's horizontal speed should equal its speed")
	await wait_physics_frames(1)
	check(bomb.global_basis.z.dot(bomb.velocity.normalized()) >= 0.99, "the bomb should face along its velocity")
	var trap: FireTrap = await _wait_for_fire_trap()
	if trap == null:
		return
	check(Vector2(trap.global_position.x - target.x, trap.global_position.z - target.z).length() < 0.1, "the bomb should land on its target (landed at %s)" % trap.global_position)
	check_approx(trap.global_position.y, _floor_top, "the fire trap should sit on the ground", 0.1)


func test_ground_impact_leaves_a_fire_trap_configured_from_the_bomb() -> void:
	var bomb: FirebombProjectile = _spawn_bomb(Vector3(0.0, _floor_top + 1.5, 0.0))
	var size: Vector2 = bomb.trap_size
	var duration: float = bomb.trap_duration
	var damage: float = bomb.trap_damage
	bomb.initialize_trajectory(Vector3(0.0, _floor_top, THROW_DISTANCE))
	var trap: FireTrap = await _wait_for_fire_trap()
	if trap == null:
		return
	check_eq(trap.trap_size, size, "the fire trap should take the bomb's trap_size")
	check_approx(trap.duration, duration, "the fire trap should take the bomb's trap_duration")
	check_approx(trap.damage, damage, "the fire trap should take the bomb's trap_damage")
	check(not trap.show_ground_mesh and not trap.ground_mesh.visible, "firebomb fire should not show a ground decal")


func test_fall_gravity_drives_the_area_gravity() -> void:
	var bomb: FirebombProjectile = _spawn_bomb(Vector3(0.0, _floor_top + 5.0, 0.0))
	bomb.fall_gravity = 0.8
	check_approx(bomb.gravity, 0.8 * FirebombProjectile.EARTH_GRAVITY, "the Area3D gravity should follow fall_gravity")


func test_hitting_the_player_in_flight_damages_them_without_a_fire_trap() -> void:
	var player: Character = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	await wait_until(func() -> bool: return player.is_on_floor(), "player should land")
	var health_before: float = _health(player)
	_spawn_bomb(player.global_position)
	if not await wait_signal(player.hurtbox.struck, "a bomb overlapping the player should hit them"):
		return
	check(_health(player) < health_before, "the hit should damage the player")
	await wait_physics_frames(2)
	check(_fire_traps().is_empty(), "a bomb that hits the player in flight must not leave a fire trap")


func test_cast_aims_at_the_ground_under_the_target() -> void:
	var bomber: Character = spawn(FIREBOMBER_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	disable_ai(bomber)
	var player: Character = spawn(PLAYER_SCENE, _arena, bomber.global_position + Vector3(0.0, 0.0, THROW_DISTANCE)) as Character
	if not await wait_until(func() -> bool: return player.is_on_floor() and bomber.is_on_floor(), "both should land"):
		return
	bomber.current_target = player
	(bomber.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent).spawn_projectile()
	var bomb: FirebombProjectile = null
	for child: Node in get_children():
		if child is FirebombProjectile:
			bomb = child as FirebombProjectile
	if not check(bomb != null, "the cast should throw a firebomb"):
		return
	check(bomb.shooter == bomber, "the bomb's shooter should be the firebomber")
	var aim: Vector3 = bomb.target_position
	check(Vector2(aim.x - player.global_position.x, aim.z - player.global_position.z).length() < 0.1, "the bomb should aim at the target's position")
	check_approx(aim.y, _floor_top, "the bomb should aim at the ground under the target", 0.1)


# --- Leaping dodge -------------------------------------------------------------

func test_leap_trigger_respects_range_and_cooldown() -> void:
	var bomber: Character = await _grounded_bomber()
	var ai_leap: AILeapingDodge = bomber.ai_state_machine.get_node("AILeapingDodge") as AILeapingDodge
	var player: Character = spawn(PLAYER_SCENE, _arena, bomber.global_position + Vector3(0.0, 0.0, ai_leap.trigger_range + 2.0)) as Character
	await wait_until(func() -> bool: return player.is_on_floor(), "player should land")
	ai_leap.cooldown_timer = 0.0
	check(not ai_leap.evaluate_trigger(0.0), "the leap must not trigger with the player outside trigger_range")
	player.global_position = bomber.global_position + Vector3(0.0, 0.0, ai_leap.trigger_range + 0.2)
	check(not ai_leap.evaluate_trigger(0.0), "the leap must not trigger just outside trigger_range")
	player.global_position = bomber.global_position + Vector3(0.0, 0.0, maxf(0.5, ai_leap.trigger_range - 1.0))
	if not check(ai_leap.evaluate_trigger(0.0), "the leap should trigger with the player inside trigger_range"):
		return
	check(bomber.ai_state_machine.state == ai_leap, "triggering should switch the mind to AILeapingDodge")
	check_approx(ai_leap.cooldown_timer, ai_leap.cooldown, "triggering should start the cooldown", 0.1)
	check(not ai_leap.evaluate_trigger(0.0), "the leap must not trigger again while on cooldown")
	var before: float = ai_leap.cooldown_timer
	var step: float = before * 0.25
	ai_leap.evaluate_trigger(step)
	check_approx(ai_leap.cooldown_timer, before - step, "the cooldown should count down by the elapsed time")


func test_leap_ai_keeps_the_values_it_is_configured_with() -> void:
	# The exact values an old _ready() silently overwrote (3.5 -> 5.0, stun
	# breaking forced off): configured values must survive entering the tree.
	var bomber: Character = FIREBOMBER_SCENE.instantiate() as Character
	var ai_leap: AILeapingDodge = bomber.get_node("AIStateMachine/AILeapingDodge") as AILeapingDodge
	ai_leap.trigger_range = 3.5
	ai_leap.can_break_stun = true
	autofree(bomber)
	_arena.add_child(bomber)
	check_approx(ai_leap.trigger_range, 3.5, "a configured trigger_range must not be rewritten")
	check(ai_leap.can_break_stun, "a configured can_break_stun must not be rewritten")


func test_leap_ai_does_not_break_a_stun_it_may_not_break() -> void:
	var bomber: Character = await _grounded_bomber()
	var ai_leap: AILeapingDodge = bomber.ai_state_machine.get_node("AILeapingDodge") as AILeapingDodge
	ai_leap.can_break_stun = false
	bomber.hurtbox.receive_hit(1.0, Vector3.ZERO)
	if not check(bomber.state_machine.state == bomber.stun_state, "setup: the hit should stun the firebomber"):
		return
	bomber.ai_state_machine.request_state("AILeapingDodge")
	await wait_physics_frames(1)
	check(bomber.state_machine.state.name != ai_leap.attack_state_name, "the leap must not break a stun when can_break_stun is off")


func test_leap_rises_to_its_peak_height_and_lands_within_max_range() -> void:
	var bomber: Character = await _grounded_bomber()
	var leap: EnemyLeapingDodge = bomber.state_machine.get_node("EnemyLeapingDodge") as EnemyLeapingDodge
	var start: Vector3 = bomber.global_position
	bomber.state_machine.request_state("EnemyLeapingDodge", {"direction": Vector3(1.0, 0.0, 0.0)})
	if not check(leap.is_leaping, "requesting the leap should start it"):
		return
	if leap.leap_audio != null:
		check(leap.leap_audio.playing, "the leap should play its sound")
	var apex: Array[float] = [start.y]
	var landed: bool = await wait_until(func() -> bool:
		apex[0] = maxf(apex[0], bomber.global_position.y)
		return bomber.state_machine.state != leap, "the leap should finish", FLIGHT_FRAMES)
	check_approx(apex[0] - start.y, leap.peak_height, "the leap should rise to peak_height", maxf(leap.peak_height * 0.1, 0.3))
	if landed:
		var travelled: Vector3 = bomber.global_position - start
		travelled.y = 0.0
		check(travelled.length() > 0.0 and travelled.length() <= leap.max_range + 0.1, "the leap should land within max_range (travelled %.2f m)" % travelled.length())


func test_uninterruptable_leap_ignores_hits() -> void:
	var bomber: Character = await _grounded_bomber()
	var leap: EnemyLeapingDodge = bomber.state_machine.get_node("EnemyLeapingDodge") as EnemyLeapingDodge
	leap.uninterruptable = true
	bomber.state_machine.request_state("EnemyLeapingDodge", {"direction": Vector3(1.0, 0.0, 0.0)})
	await wait_physics_frames(2)
	bomber.hurtbox.receive_hit(1.0, Vector3.ZERO)
	check(bomber.state_machine.state == leap, "a hit must not interrupt an uninterruptable leap")


func test_explicit_leap_target_is_clamped_to_max_range() -> void:
	var bomber: Character = await _grounded_bomber()
	var leap: EnemyLeapingDodge = bomber.state_machine.get_node("EnemyLeapingDodge") as EnemyLeapingDodge
	bomber.state_machine.request_state("EnemyLeapingDodge", {"target_position": bomber.global_position + Vector3(FAR_TARGET_DISTANCE, 0.0, 0.0)})
	check(leap.target_position.distance_to(leap.start_position) <= leap.max_range + 0.001, "an explicit target beyond max_range should be clamped")


func test_zero_leap_direction_falls_back_without_invalid_values() -> void:
	var bomber: Character = await _grounded_bomber()
	var leap: EnemyLeapingDodge = bomber.state_machine.get_node("EnemyLeapingDodge") as EnemyLeapingDodge
	bomber.state_machine.request_state("EnemyLeapingDodge", {"direction": Vector3.ZERO})
	check(leap.horizontal_velocity.is_finite() and leap.target_position.is_finite(), "a zero direction must fall back to a valid leap")


func test_leap_never_targets_through_a_wall() -> void:
	var bomber: Character = await _grounded_bomber()
	var leap: EnemyLeapingDodge = bomber.state_machine.get_node("EnemyLeapingDodge") as EnemyLeapingDodge
	var wall_face_z: float = bomber.global_position.z - WALL_DISTANCE
	_add_wall(wall_face_z)
	await wait_physics_frames(1)
	bomber.state_machine.request_state("EnemyLeapingDodge", {"direction": Vector3(0.0, 0.0, -1.0)})
	check(leap.target_position.z > wall_face_z, "the landing point must not lie beyond a wall (target %s, wall face z %.2f)" % [leap.target_position, wall_face_z])


# --- helpers -------------------------------------------------------------------

func _spawn_bomb(at: Vector3) -> FirebombProjectile:
	return spawn(FIREBOMB_SCENE, _arena, at) as FirebombProjectile


## A firebomber standing at the arena centre with its AI stopped.
func _grounded_bomber() -> Character:
	var bomber: Character = spawn(FIREBOMBER_SCENE, _arena, Vector3(0.0, _floor_top + 1.0, 0.0)) as Character
	disable_ai(bomber)
	await wait_until(func() -> bool: return bomber.is_on_floor() and bomber.state_machine.state == bomber.state_machine.initial_state, "the firebomber should land and settle")
	return bomber


## Fire traps in the world (game code parents them to the suite).
func _fire_traps() -> Array[FireTrap]:
	var found: Array[FireTrap] = []
	for child: Node in get_children():
		if child is FireTrap and not child.is_queued_for_deletion():
			found.append(child as FireTrap)
	return found


func _wait_for_fire_trap() -> FireTrap:
	if not await wait_until(func() -> bool: return not _fire_traps().is_empty(), "the bomb should land and leave a fire trap", FLIGHT_FRAMES):
		return null
	return _fire_traps()[0]


## A wide wall whose near face is the plane z = face_z, on the World layer.
func _add_wall(face_z: float) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 1
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(20.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, _floor_top + 2.0, face_z - box.size.z * 0.5)
	autofree(wall)
	_arena.add_child(wall)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
