## GroundDamageArea and the ground slam (GroundSlamAttack):
## - The damage hitbox is a low cylinder (the area's radius and height) whose
##   base rests on the area's origin, i.e. on the floor it was spawned on.
## - A standing character inside the area takes its damage exactly once.
## - An airborne character whose feet are above the cylinder takes none (jump
##   evasion).
## - The brute's slam spawns an area that hits a standing player for the
##   attack's damage, hits allies too when friendly_fire is on (never the
##   caster), and snaps to the ground below when slamming from a ledge.
##
## Every expected value is read from the live nodes (radius, height, damage,
## aoe_forward_offset) or set by the test, and every wait is on a condition, so
## the suite holds at any frame rate and survives retuning.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const BRUTE_SCENE: PackedScene = preload("res://Enemy/enemy_brute.tscn")
const AOE_SCENE: PackedScene = preload("res://Hazards/ground_damage_aoe.tscn")
## Test-owned damage for areas spawned directly by the suite.
const TEST_AOE_DAMAGE: float = 10.0
## Test-owned ledge height for the ledge slam scenario.
const LEDGE_HEIGHT: float = 3.0
## Generous frame budget for a full slam (windup, impact, recovery).
const SLAM_FRAMES: int = 600

var _arena: Node3D
var _floor_top: float


func before_each() -> void:
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)


func test_hitbox_is_a_low_cylinder_resting_on_the_floor() -> void:
	var aoe: GroundDamageArea = _spawn_aoe(Vector3(0.0, _floor_top, 0.0))
	await wait_physics_frames(1)
	var col: CollisionShape3D = aoe.get_node("DamageHitbox/CollisionShape3D") as CollisionShape3D
	if not check(col.shape is CylinderShape3D, "damage hitbox should be a CylinderShape3D"):
		return
	var cylinder: CylinderShape3D = col.shape as CylinderShape3D
	check_approx(cylinder.radius, aoe.radius, "cylinder radius should follow the area's radius")
	check_approx(cylinder.height, aoe.height, "cylinder height should follow the area's height")
	check_approx(col.global_position.y - cylinder.height * 0.5, aoe.global_position.y, "cylinder base should rest on the area's origin (the floor)")


func test_standing_player_inside_takes_its_damage_once() -> void:
	var player: Character = await _spawn_grounded_player()
	var hp_before: float = _health(player)
	var aoe: GroundDamageArea = _spawn_aoe(Vector3(player.global_position.x, _floor_top, player.global_position.z))
	await wait_signal(player.hurtbox.struck, "a standing player inside the area should be struck")
	await _wait_until_inactive(aoe)
	check_approx(hp_before - _health(player), aoe.damage, "standing player should take the area's damage exactly once")


func test_airborne_player_above_the_cylinder_takes_nothing() -> void:
	var player: Character = await _spawn_grounded_player()
	var hp_before: float = _health(player)
	var aoe: GroundDamageArea = AOE_SCENE.instantiate() as GroundDamageArea
	var clearance: float = _floor_top + aoe.height
	player.state_machine.request_state("PlayerJump", {"direction": Vector3.ZERO})
	var cleared: bool = await wait_until(func() -> bool: return _feet_y(player) > clearance, "jumping player's feet should rise above the area's height")
	if not cleared:
		aoe.free()
		return
	_add_aoe(aoe, Vector3(player.global_position.x, _floor_top, player.global_position.z))
	await _wait_until_inactive(aoe)
	check(not player.is_on_floor(), "setup: the player should still be airborne when the damage window closes")
	check_approx(_health(player), hp_before, "an airborne player above the cylinder should take no damage")


func test_brute_slam_hits_standing_player_for_attack_damage() -> void:
	var brute: Character = await _spawn_grounded_brute()
	var slam: GroundSlamAttack = brute.state_machine.get_node("EnemyAttack") as GroundSlamAttack
	var player: Character = await _spawn_grounded_player(_impact_point(brute, slam))
	var hp_before: float = _health(player)
	brute.state_machine.request_state("EnemyAttack")
	await wait_signal(player.hurtbox.struck, "the slam should strike a player standing at its impact point", SLAM_FRAMES)
	await _wait_until_no_live_aoes()
	check_approx(hp_before - _health(player), slam.damage * brute.get_damage_modifier(), "the slam should deal the attack's damage once")


func test_brute_slam_friendly_fire_hits_ally_but_never_caster() -> void:
	var brute: Character = await _spawn_grounded_brute()
	var slam: GroundSlamAttack = brute.state_machine.get_node("EnemyAttack") as GroundSlamAttack
	slam.friendly_fire = true
	var ally: Character = _spawn_character(MELEE_SCENE, _impact_point(brute, slam))
	await wait_until(func() -> bool: return ally.is_on_floor(), "ally should land")
	var ally_before: float = _health(ally)
	var brute_before: float = _health(brute)
	brute.state_machine.request_state("EnemyAttack")
	await wait_signal(ally.hurtbox.struck, "with friendly_fire on, the slam should strike an ally at its impact point", SLAM_FRAMES)
	await _wait_until_no_live_aoes()
	check_approx(ally_before - _health(ally), slam.damage * brute.get_damage_modifier(), "the ally should take the slam's damage once")
	check_approx(_health(brute), brute_before, "the caster must never damage itself")


func test_slam_from_a_ledge_lands_on_the_ground_below() -> void:
	var spawn_xz: Vector3 = (_arena.get_node("EnemySpawn") as Node3D).global_position
	var brute: Character = _spawn_character(BRUTE_SCENE, Vector3(spawn_xz.x, _floor_top + LEDGE_HEIGHT + 1.0, spawn_xz.z))
	# A pillar barely wider than the brute, so the slam's impact point lies
	# beyond its edge and the area has to find the ground below.
	var half_extent: float = (brute.collision_shape_3d.shape as CapsuleShape3D).radius + 0.05
	var pillar: StaticBody3D = _add_pillar(Vector3(spawn_xz.x, _floor_top, spawn_xz.z), half_extent, LEDGE_HEIGHT)
	await wait_until(func() -> bool: return brute.is_on_floor(), "brute should land on the ledge")
	brute.state_machine.request_state("EnemyAttack")
	if not await wait_until(func() -> bool: return not _live_aoes().is_empty(), "the slam should spawn a ground area", SLAM_FRAMES):
		return
	var aoe: GroundDamageArea = _live_aoes()[0]
	var offset: Vector3 = aoe.global_position - pillar.global_position
	if not check(absf(offset.x) > half_extent or absf(offset.z) > half_extent, "setup: the impact point should lie beyond the ledge (offset %s, half extent %.2f)" % [offset, half_extent]):
		return
	check_approx(aoe.global_position.y, _floor_top, "an area slammed from a ledge should snap to the ground below, not the caster's height", 0.05)


# --- helpers -----------------------------------------------------------------

func _spawn_character(scene: PackedScene, at: Vector3) -> Character:
	var character: Character = spawn(scene, _arena, at) as Character
	disable_ai(character)
	return character


func _spawn_grounded_player(at: Vector3 = Vector3.INF) -> Character:
	var position: Vector3 = (_arena.get_node("PlayerSpawn") as Node3D).global_position if at == Vector3.INF else at
	var player: Character = _spawn_character(PLAYER_SCENE, position)
	await wait_until(func() -> bool: return player.is_on_floor(), "player should land on the arena floor")
	return player


func _spawn_grounded_brute() -> Character:
	var brute: Character = _spawn_character(BRUTE_SCENE, (_arena.get_node("EnemySpawn") as Node3D).global_position)
	await wait_until(func() -> bool: return brute.is_on_floor(), "brute should land on the arena floor")
	return brute


## Point on the arena floor the slam targets: in front of the brute by the
## attack's aoe_forward_offset (well inside the area's radius either way).
func _impact_point(brute: Character, slam: GroundSlamAttack) -> Vector3:
	var forward: Vector3 = brute.mesh_mount.global_basis.z
	forward.y = 0.0
	var point: Vector3 = brute.global_position + forward.normalized() * slam.aoe_forward_offset
	return Vector3(point.x, brute.global_position.y, point.z)


## Instances a test-owned area (TEST_AOE_DAMAGE, hits the player) at a floor
## position. The position must be set before it enters the tree, because the
## area strikes everything it overlaps as soon as it is ready.
func _spawn_aoe(at: Vector3) -> GroundDamageArea:
	return _add_aoe(AOE_SCENE.instantiate() as GroundDamageArea, at)


func _add_aoe(aoe: GroundDamageArea, at: Vector3) -> GroundDamageArea:
	aoe.damage = TEST_AOE_DAMAGE
	aoe.can_hit_player = true
	aoe.position = at
	autofree(aoe)
	_arena.add_child(aoe)
	return aoe


## Waits for the area's damage window to open and close again (or for the
## area to be freed).
func _wait_until_inactive(aoe: GroundDamageArea) -> void:
	var hitbox: Area3D = aoe.get_node("DamageHitbox") as Area3D
	await wait_until(func() -> bool: return not is_instance_valid(aoe) or hitbox.monitoring, "the area's damage window should open")
	await wait_until(func() -> bool: return not is_instance_valid(aoe) or not hitbox.monitoring, "the area's damage window should close")


## Ground areas spawned by game code (parented to the current scene, which is
## this suite) that have not expired yet.
func _live_aoes() -> Array[GroundDamageArea]:
	var found: Array[GroundDamageArea] = []
	for child: Node in get_children():
		if child is GroundDamageArea and not child.is_queued_for_deletion() and not (child as GroundDamageArea).is_expired():
			found.append(child as GroundDamageArea)
	return found


func _wait_until_no_live_aoes() -> void:
	await wait_until(func() -> bool: return not _live_aoes().is_empty(), "the slam should spawn a ground area", SLAM_FRAMES)
	await wait_until(func() -> bool: return _live_aoes().is_empty(), "the slam's ground area should expire", SLAM_FRAMES)


func _add_pillar(base_center: Vector3, half_extent: float, height: float) -> StaticBody3D:
	var pillar: StaticBody3D = StaticBody3D.new()
	pillar.collision_layer = 1
	pillar.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(half_extent * 2.0, height, half_extent * 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	pillar.add_child(shape)
	pillar.position = base_center
	autofree(pillar)
	_arena.add_child(pillar)
	return pillar


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


## World height of the character's feet (bottom of its capsule).
func _feet_y(character: Character) -> float:
	var shape: CollisionShape3D = character.collision_shape_3d
	return shape.global_position.y - (shape.shape as CapsuleShape3D).height * 0.5
