## The brute enemy:
## - its body is set up for fair hits and pathing: in the enemy group, full
##   health, a hurtbox at least as wide as its body, and a navigation agent
##   as wide as its body,
## - the wave pool offers it at its own difficulty,
## - the slam hurts only after its windup, only what stands in its impact
##   zone (not far in front, not behind), and switches off in recovery; the
##   slam has hyper-armor: hits hurt the brute but do not stun it,
## - the punch hurts only after its windup, and can be interrupted into a stun,
## - the slam AI breaks out of a stun into the slam and then waits out its
##   cooldown; the pursue AI's cooldown runs down with time,
## - on defeat it enters the defeat state and its body and hurtbox switch off.
## Ranges, damage and timings are read from the brute; the slam's impact zone
## is measured from one slam before the targets are placed.
extends "res://test/lib/test_suite.gd"

const BRUTE_SCENE: PackedScene = preload("res://Enemy/enemy_brute.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned values.
const TEST_HIT: float = 10.0
const TEST_COOLDOWN: float = 2.0
const TEST_TICK: float = 0.5
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600
## Minimum facing alignment (cosine) before the punch is thrown.
const FACING: float = 0.999

var _arena: Node3D
var _brute: Character
var _slam: CharacterAttack
var _mind_slam: AIConditionalAttack
var _pursue: AIPursue


func before_each() -> void:
	_arena = load_arena()
	_brute = await _spawn_brute(Vector3(0.0, 1.0, -8.0))
	_slam = _brute.state_machine.get_node(NodePath(_mind_slam_state())) as CharacterAttack


func test_the_body_is_set_up_for_fair_hits_and_pathing() -> void:
	check(_brute.is_in_group("enemy"), "the brute should be an enemy")
	var attributes: AttributeComponent = _brute.attribute_component
	check_approx(attributes.get_current(AttributeComponent.POOL_HEALTH), attributes.get_current(AttributeComponent.STAT_MAX_HEALTH), "the brute should spawn at full health")
	var body_radius: float = _radius(_brute.collision_shape_3d)
	check(_radius(_brute.hurtbox.get_node("CollisionShape3D") as CollisionShape3D) >= body_radius, "the hurtbox should be at least as wide as the body, so hits on it always register")
	check_approx(_brute.navigation_agent_3d.radius, body_radius, "the navigation agent should be as wide as the body")


func test_the_wave_pool_offers_it_at_its_difficulty() -> void:
	var resource: EnemyResource = GlobalVars.get_enemy_resource(BRUTE_SCENE)
	if not check(resource != null, "the brute should be registered"):
		return
	var pool: Dictionary = ProgressionState.build_difficulty_pool([resource])
	check(pool.has(resource.difficulty_level) and (pool[resource.difficulty_level] as Array).has(resource), "the pool should offer the brute at its difficulty")


func test_the_slam_hurts_only_its_impact_zone_after_its_windup() -> void:
	var zone: Array = await _measure_slam_zone()
	if zone.is_empty():
		return
	var center: Vector3 = zone[0]
	var radius: float = zone[1]
	var forward: Vector3 = _flat(center - _brute.global_position).normalized()
	# A second brute, facing the same way, slams at targets placed from the
	# measured zone.
	var slammer: Character = await _spawn_brute(Vector3(8.0, 1.0, -8.0))
	var offset: Vector3 = center - _brute.global_position
	var inside: Character = await _spawn_target(slammer.global_position + Vector3(offset.x, 0.0, offset.z))
	var far: Character = await _spawn_target(slammer.global_position + Vector3(offset.x, 0.0, offset.z) + forward * (radius * 2.0 + 3.0))
	var behind: Character = await _spawn_target(slammer.global_position - forward * (_flat(offset).length() + 1.0))
	var health: Dictionary[Character, float] = {inside: _health(inside), far: _health(far), behind: _health(behind)}
	var slam: CharacterAttack = slammer.state_machine.get_node(NodePath(_slam.name)) as CharacterAttack
	var hitbox: Area3D = slam.get_weapon_slot().hitbox
	slammer.state_machine.request_state(slam.name)
	var early: Array[bool] = [false]
	if not await wait_until(func() -> bool:
		early[0] = early[0] or (not hitbox.monitoring and _health(inside) < health[inside])
		return hitbox.monitoring, "the slam should open its hitbox", ATTACK_FRAMES):
		return
	check(not early[0], "nothing should be hurt during the windup")
	await wait_until(func() -> bool: return not hitbox.monitoring, "the slam should close its hitbox", ATTACK_FRAMES)
	check_approx(health[inside] - _health(inside), _expected_damage(slam, slammer, inside), "a target in the impact zone should take the slam's damage")
	check_approx(_health(far), health[far], "a target far in front should not be hurt")
	check_approx(_health(behind), health[behind], "a target behind should not be hurt")
	await wait_until(func() -> bool: return slammer.state_machine.state.name != slam.name, "the slam should end", ATTACK_FRAMES)
	check(not hitbox.monitoring, "the hitbox should stay off in recovery")


func test_the_slam_has_hyper_armor() -> void:
	_brute.state_machine.request_state(_slam.name)
	await wait_physics_frames(1)
	var before: float = _health(_brute)
	check(_brute.hurtbox.receive_hit(TEST_HIT, Vector3.ZERO), "a hit during the slam should land")
	await wait_physics_frames(1)
	check_approx(before - _health(_brute), TEST_HIT, "the hit should hurt the brute")
	check_eq(str(_brute.state_machine.state.name), _slam.name, "the hit must not interrupt the slam")


func test_the_punch_hurts_after_its_windup_and_can_be_interrupted() -> void:
	var punch: CharacterAttack = _brute.state_machine.get_node(NodePath(_pursue.attack_state_name)) as CharacterAttack
	var hitbox: Area3D = punch.get_weapon_slot().hitbox
	# Inside the range the pursue AI orders the punch from.
	var target: Character = await _spawn_target(_brute.global_position + Vector3(0.0, 0.0, _pursue.attack_range * 0.9))
	# The brute turns at its rotation speed: face the target before punching.
	if not await wait_until(func() -> bool:
		_brute.look_at_target(target.global_position, 1.0 / Engine.physics_ticks_per_second)
		return _flat(_brute.mesh_mount.global_basis.z).normalized().dot(_flat(target.global_position - _brute.global_position).normalized()) >= FACING, "setup: the brute should face the target"):
		return
	var before: float = _health(target)
	_brute.state_machine.request_state(punch.name)
	var early: Array[bool] = [false]
	if not await wait_until(func() -> bool:
		early[0] = early[0] or (not hitbox.monitoring and _health(target) < before)
		return hitbox.monitoring, "the punch should open its hitbox", ATTACK_FRAMES):
		return
	check(not early[0], "nothing should be hurt during the windup")
	await wait_until(func() -> bool: return _brute.state_machine.state.name != punch.name, "the punch should end", ATTACK_FRAMES)
	check_approx(before - _health(target), _expected_damage(punch, _brute, target), "the punch should deal its damage")
	_brute.state_machine.request_state(punch.name)
	await wait_physics_frames(1)
	_brute.hurtbox.receive_hit(TEST_HIT, Vector3.ZERO)
	await wait_until(func() -> bool: return _brute.state_machine.state.name == "EnemyStun", "a hit should interrupt the punch into a stun", 5)


func test_the_slam_ai_breaks_a_stun_then_waits_out_its_cooldown() -> void:
	await _spawn_target(_brute.global_position + Vector3(0.0, 0.0, _mind_slam.trigger_range * 0.5))
	_brute.hurtbox.receive_hit(TEST_HIT, Vector3.ZERO)
	if not await wait_until(func() -> bool: return _brute.state_machine.state.name == "EnemyStun", "setup: a hit should stun the brute", 5):
		return
	# The mind orders the slam from its own tick: let it run.
	_mind_slam.cooldown_timer = 0.0
	_brute.ai_state_machine.process_mode = Node.PROCESS_MODE_INHERIT
	if not await wait_until(func() -> bool: return _brute.state_machine.state.name == _slam.name, "a ready slam AI with the player in range should break the stun into the slam", 10):
		return
	check(_mind_slam.is_on_cooldown(), "the slam should start its cooldown")
	check(not _mind_slam.evaluate_trigger(TEST_TICK), "the slam must not trigger again on cooldown")


func test_the_pursue_cooldown_runs_down_with_time() -> void:
	_pursue.cooldown_timer = TEST_COOLDOWN
	_pursue.evaluate_trigger(TEST_TICK)
	check_approx(_pursue.cooldown_timer, TEST_COOLDOWN - TEST_TICK, "the pursue cooldown should run down by the elapsed time")


func test_defeat_enters_the_defeat_state_and_switches_the_body_off() -> void:
	var defeated: Array[bool] = [false]
	_brute.defeat.connect(func() -> void: defeated[0] = true)
	_brute.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, _health(_brute))
	check(defeated[0], "losing all health should report the defeat")
	await wait_until(func() -> bool: return _brute.state_machine.state.name == "EnemyDefeat", "the brute should enter its defeat state", 5)
	await wait_physics_frames(1)
	check(_brute.collision_shape_3d.disabled, "a corpse must not block movement")
	check(not _brute.hurtbox.monitoring and not _brute.hurtbox.monitorable, "a corpse must not take hits")


## Runs one slam with nothing around and returns [impact center, radius] of
## its hitbox when it opens, or [] on failure.
func _measure_slam_zone() -> Array:
	var hitbox: Area3D = _slam.get_weapon_slot().hitbox
	_brute.state_machine.request_state(_slam.name)
	if not await wait_until(func() -> bool: return hitbox.monitoring, "setup: the slam should open its hitbox", ATTACK_FRAMES):
		return []
	var shape: CollisionShape3D = hitbox.get_node("CollisionShape3D") as CollisionShape3D
	return [shape.global_position, _radius(shape)]


## A still brute; also caches its mind states on first use.
func _spawn_brute(at: Vector3) -> Character:
	var brute: Character = spawn(BRUTE_SCENE, _arena, at) as Character
	disable_ai(brute)
	if _brute == null:
		_mind_slam = brute.ai_state_machine.get_node("AISlam") as AIConditionalAttack
		_pursue = brute.ai_state_machine.get_node("AIPursue") as AIPursue
	await wait_until(func() -> bool: return brute.is_on_floor(), "setup: the brute should land")
	return brute


## A still player to hit, standing on the arena floor.
func _spawn_target(at: Vector3) -> Character:
	var target: Character = spawn(PLAYER_SCENE, _arena, Vector3(at.x, 1.0, at.z)) as Character
	(target.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	await wait_until(func() -> bool: return target.is_on_floor(), "setup: the target should land")
	return target


func _mind_slam_state() -> String:
	return _mind_slam.attack_state_name


func _expected_damage(attack: CharacterAttack, attacker: Character, victim: Character) -> float:
	return attack.damage * attacker.get_damage_modifier() * victim.attribute_component.get_damage_multiplier(&"physical")


func _radius(shape: CollisionShape3D) -> float:
	return float(shape.shape.get("radius"))


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)
