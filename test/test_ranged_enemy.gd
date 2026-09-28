## The ranged enemy and its projectile (split from the old test_enemy_base):
## - its AI attacks a player within its attack range,
## - a shot leaves from the spawn point, facing the way the shooter faces,
##   into the world (not the shooter), and remembers its shooter,
## - a projectile flies forward and frees itself when its lifetime runs out,
## - a projectile hitting a player deals its damage, leaves an impact effect
##   where it hit and is gone,
## - a projectile flies through corpses and the exit trigger, and still hits
##   a living target beyond them.
## Ranges and damage are read from the enemy and the projectile.
extends "res://test/lib/test_suite.gd"

const RANGED_SCENE: PackedScene = preload("res://Enemy/ranged_enemy.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://Enemy/enemy_projectile.tscn")
const EXIT_SCENE: PackedScene = preload("res://Levels/exit_point.tscn")
## Test-owned health, so no hit here can kill.
const TOUGH: float = 100000.0
## Frame budget for an attack or a flight.
const ACTION_FRAMES: int = 600
## Ticks a projectile placed on something gets to react.
const CONTACT_FRAMES: int = 3
## Test-owned facing (radians) the shooter turns to before firing.
const TEST_FACING: float = 1.0

var _arena: Node3D
var _shooter: Character
var _impacts: Array[Node3D] = []


func before_each() -> void:
	_impacts.clear()
	get_tree().node_added.connect(_on_node_added)
	_arena = load_arena()
	_shooter = spawn(RANGED_SCENE, _arena, Vector3(0.0, 1.0, -8.0)) as Character
	disable_ai(_shooter)
	await wait_until(func() -> bool: return _shooter.is_on_floor(), "setup: the shooter should land")


func after_each() -> void:
	get_tree().node_added.disconnect(_on_node_added)


func test_the_ai_attacks_a_player_in_range() -> void:
	var meander: AIMeander = _shooter.ai_state_machine.get_node("AIMeander") as AIMeander
	var ai_attack: AIAttack = meander.attack_state as AIAttack
	await _spawn_player(_shooter.global_position + Vector3(meander.attack_range * 0.75, 0.0, 0.0))
	# Wake the AI only once the body can act: an attack attempted during the
	# spawn-landing stun is refused and currently costs its cooldown (TODO.md).
	if not await wait_until(func() -> bool: return _shooter.state_machine.state.name == "EnemyMove", "setup: the shooter should be ready to act"):
		return
	_shooter.ai_state_machine.process_mode = Node.PROCESS_MODE_INHERIT
	await wait_until(func() -> bool: return _shooter.state_machine.state.name == ai_attack.attack_state_name, "the AI should attack a player in range", ACTION_FRAMES)


func test_a_shot_leaves_the_spawn_point_facing_the_shooters_way() -> void:
	var spawner: ProjectileSpawnerComponent = _shooter.get_node("ProjectileSpawnerComponent") as ProjectileSpawnerComponent
	_shooter.mesh_mount.global_rotation.y = TEST_FACING
	var spawned: Array[EnemyProjectile] = []
	var watch: Callable = func(node: Node) -> void:
		if node is EnemyProjectile:
			spawned.append(node as EnemyProjectile)
	get_tree().node_added.connect(watch)
	spawner.spawn_projectile()
	get_tree().node_added.disconnect(watch)
	if not check_eq(spawned.size(), 1, "one shot should spawn one projectile"):
		return
	var shot: EnemyProjectile = spawned[0]
	check(not _shooter.is_ancestor_of(shot), "the projectile should live in the world, not on the shooter")
	check(shot.shooter == _shooter, "the projectile should remember its shooter")
	check(shot.global_position.is_equal_approx(spawner.spawn_point.global_position), "the projectile should leave from the spawn point")
	check_approx(shot.global_rotation.y, _shooter.mesh_mount.global_rotation.y, "the projectile should face the way the shooter faces")


func test_a_projectile_flies_forward_and_expires() -> void:
	var shot: EnemyProjectile = _fire(Vector3(10.0, 1.5, 10.0))
	var start: Vector3 = shot.global_position
	var forward: Vector3 = shot.global_basis.z
	await wait_physics_frames(2)
	check((shot.global_position - start).dot(forward) > 0.0, "the projectile should fly along its facing")
	(shot.get_node("Timer") as Timer).timeout.emit()
	check(shot.is_queued_for_deletion(), "the projectile should free itself when its lifetime runs out")


func test_a_projectile_hit_damages_leaves_an_impact_and_is_gone() -> void:
	var player: Character = await _spawn_player(Vector3(8.0, 1.0, 8.0))
	var before: float = _health(player)
	var shot: EnemyProjectile = _fire(player.global_position)
	var hit_at: Vector3 = shot.global_position
	var expected: float = shot.damage * player.attribute_component.get_damage_multiplier(&"physical")
	# The projectile may fly on for a tick or two before the hit registers.
	var drift: float = shot.speed / Engine.physics_ticks_per_second * CONTACT_FRAMES
	var shot_ref: WeakRef = weakref(shot)
	if not await wait_until(func() -> bool: return shot_ref.get_ref() == null or (shot_ref.get_ref() as Node).is_queued_for_deletion(), "the projectile should be gone after the hit", CONTACT_FRAMES):
		return
	check_approx(before - _health(player), expected, "the hit should deal the projectile's damage")
	if check_eq(_impacts.size(), 1, "one impact effect should appear"):
		check(_impacts[0].global_position.distance_to(hit_at) <= drift, "the impact should appear where it hit")


func test_a_projectile_flies_through_corpses_and_the_exit_but_hits_the_living() -> void:
	var corpse: Character = spawn(MELEE_SCENE, _arena, Vector3(-8.0, 1.0, 8.0)) as Character
	disable_ai(corpse)
	await wait_until(func() -> bool: return corpse.is_on_floor(), "setup: the enemy should land")
	corpse.attribute_component.damage_pool(AttributeComponent.POOL_HEALTH, _health(corpse))
	var exit_point: ExitPoint = spawn(EXIT_SCENE, _arena, Vector3(-8.0, 0.0, 14.0)) as ExitPoint
	var player: Character = await _spawn_player(Vector3(-8.0, 1.0, 2.0))
	await wait_physics_frames(1)
	var shot: EnemyProjectile = _fire(corpse.global_position)
	await wait_physics_frames(CONTACT_FRAMES)
	check(not shot.is_queued_for_deletion() and _impacts.is_empty(), "a projectile must fly through a corpse")
	shot.global_position = exit_point.global_position + Vector3.UP
	await wait_physics_frames(CONTACT_FRAMES)
	check(not shot.is_queued_for_deletion() and _impacts.is_empty(), "a projectile must fly through the exit trigger")
	var before: float = _health(player)
	shot.global_position = player.global_position
	await wait_until(func() -> bool: return _health(player) < before, "the projectile should still hit a living target", CONTACT_FRAMES)


## A projectile placed in the world, owned by the shooter.
func _fire(at: Vector3) -> EnemyProjectile:
	var shot: EnemyProjectile = PROJECTILE_SCENE.instantiate() as EnemyProjectile
	shot.shooter = _shooter
	autofree(shot)
	_arena.add_child(shot)
	shot.global_position = at
	return shot


func _spawn_player(at: Vector3) -> Character:
	var player: Character = spawn(PLAYER_SCENE, _arena, at) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, TOUGH)
	await wait_until(func() -> bool: return player.is_on_floor(), "setup: the player should land")
	return player


func _on_node_added(node: Node) -> void:
	if node is Node3D and GlobalVars.fireball_hit_scene != null and node.scene_file_path == GlobalVars.fireball_hit_scene.resource_path:
		_impacts.append(node as Node3D)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
