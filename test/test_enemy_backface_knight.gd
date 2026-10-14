## The Backface Knight, a shield bearer, and its Move and Slide charge:
## - the knight casts the very AbilityResource its drop book teaches, from its
##   own ability slot, and its mind charges from that slot,
## - its shield blocks a hit from the front (no damage, no stun, a block
##   report) and lets the same hit through from behind,
## - its mind keeps its distance: it backs away from a close target and walks
##   up to a far one,
## - a target up close takes the shield bash,
## - with a clear line at charge range it charges: a target in its path is
##   hurt and thrown; with a wall in between it never charges,
## - the player casting the same ability (from the book) lunges forward and
##   hits an enemy in the path.
## Positions and health are test-owned; ranges and the facing are read from
## the live nodes.
extends "res://test/lib/project_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const KNIGHT_SCENE: PackedScene = preload("res://Enemy/enemy_backface_knight.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const AOE_SCENE: PackedScene = preload("res://Hazards/ground_damage_aoe.tscn")
## Frame budget for an AI decision plus a cast.
const DECISION_FRAMES: int = 600
## Test-owned health high enough that nothing here dies.
const HUGE_HEALTH: float = 1.0e9
## Test-owned damage of the blasts aimed at the shield.
const TEST_DAMAGE: float = 10.0
## Distance in front of or behind the knight at which a test blast goes off.
const BLAST_OFFSET: float = 1.0
## Physics ticks allowed for an area to register a fresh overlap.
const DETECT_FRAMES: int = 20
## How far a kept distance must change to count as a retreat or an approach.
const RANGE_CHANGE: float = 1.0
## Distance the player must cover for a cast to count as a charge.
const CHARGE_TRAVEL: float = 2.0

var _arena: Node3D
var _floor_top: float
var _knight: Character
var _ability: AbilityResource


func before_each() -> void:
	ProgressionState.reset_run()
	_arena = load_arena()
	_floor_top = arena_floor_top(_arena)
	await wait_for_navigation(_arena)
	_knight = _spawn(KNIGHT_SCENE, Vector3(0.0, 1.0, 0.0))
	_ability = _knight.ability_system_component.get_ability(0)
	# Landing ends in the landing recovery state: wait for the knight to settle.
	await wait_until(func() -> bool: return _knight.is_on_floor() and _knight.state_machine.state == _knight.state_machine.initial_state, "setup: the knight should land and settle")


func after_each() -> void:
	ProgressionState.reset_run()
	UI.resume_game()


func test_the_knight_charges_with_the_ability_its_book_teaches() -> void:
	var archetype: EnemyResource = GlobalVars.get_enemy_resource(KNIGHT_SCENE)
	if not check(archetype != null and not archetype.item_drops.is_empty(), "the Backface Knight should be registered with a drop"):
		return
	var book: BookItemResource = archetype.item_drops[0].item as BookItemResource
	check(book != null and book.granted_abilities.has(_ability), "the Backface Knight's slot should hold the very ability its book teaches")
	var charge: AIConditionalAttack = _knight.ai_state_machine.get_node("AICharge") as AIConditionalAttack
	check(charge != null and charge.body_state == _knight.ability_system_component.slots[0], "the Backface Knight's mind should charge from that slot")


func test_the_shield_blocks_hits_from_the_front_and_not_from_behind() -> void:
	disable_ai(_knight)
	var shield: ShieldComponent = _knight.hurtbox.shield
	if not check(shield != null, "the knight's hurtbox should carry a shield"):
		return
	var blocks: Array[int] = [0]
	shield.blocked.connect(func(_damage: float, _origin: Vector3) -> void: blocks[0] += 1)
	var stunned: Array[bool] = [false]
	var before: float = _health(_knight)
	_blast(_knight.global_position + _facing(_knight) * BLAST_OFFSET)
	await wait_until(func() -> bool:
		stunned[0] = stunned[0] or _knight.state_machine.state == _knight.stun_state
		return blocks[0] >= 1, "a blast in front of the knight should be blocked", DETECT_FRAMES)
	await wait_physics_frames(DETECT_FRAMES)
	check_approx(_health(_knight), before, "a blocked hit should deal no damage")
	check(not stunned[0], "a blocked hit should not stun the knight")
	_blast(_knight.global_position - _facing(_knight) * BLAST_OFFSET)
	await wait_until(func() -> bool: return _health(_knight) < before, "a blast behind the knight should hurt it", DETECT_FRAMES)
	check_eq(blocks[0], 1, "a hit from behind should not be blocked")


func test_the_knight_backs_away_from_a_close_target() -> void:
	var keep: AIKeepDistance = _knight.ai_state_machine.get_node("AIKeepDistance") as AIKeepDistance
	var bash: AIConditionalAttack = _knight.ai_state_machine.get_node("AIShieldBash") as AIConditionalAttack
	# Inside the kept range but out of the bash's reach: nothing to do but back off.
	var start: float = (keep.preferred_range - keep.range_tolerance + bash.trigger_range) * 0.5
	var player: Character = _spawn_player(Vector3(0.0, 1.0, start))
	await wait_until(func() -> bool: return _distance(player) > start + RANGE_CHANGE, "the knight should back away from a target inside its kept range", DECISION_FRAMES)


func test_the_knight_walks_up_to_a_far_target() -> void:
	var keep: AIKeepDistance = _knight.ai_state_machine.get_node("AIKeepDistance") as AIKeepDistance
	var charge: AIConditionalAttack = _knight.ai_state_machine.get_node("AICharge") as AIConditionalAttack
	# Beyond both the kept range and the charge: it has to walk.
	var start: float = maxf(keep.preferred_range + keep.range_tolerance, charge.trigger_range) + RANGE_CHANGE * 2.0
	var player: Character = _spawn_player(Vector3(0.0, 1.0, start))
	await wait_until(func() -> bool: return _distance(player) < start - RANGE_CHANGE, "the knight should walk up to a far target", DECISION_FRAMES)


func test_a_close_target_takes_the_shield_bash() -> void:
	var bash: AIConditionalAttack = _knight.ai_state_machine.get_node("AIShieldBash") as AIConditionalAttack
	_spawn_player(_knight.global_position + _facing(_knight) * bash.trigger_range * 0.6)
	await wait_until(func() -> bool: return _knight.state_machine.state == bash.body_state, "a close target should take the shield bash", DECISION_FRAMES)


func test_the_charge_hurts_and_throws_a_target_in_its_path() -> void:
	var charge: AIConditionalAttack = _knight.ai_state_machine.get_node("AICharge") as AIConditionalAttack
	var player: Character = _spawn_player(_knight.global_position + _facing(_knight) * (charge.min_range + charge.trigger_range) * 0.5)
	player.knockback_component.max_knockback = 50.0
	if not await wait_until(func() -> bool: return _knight.state_machine.state == charge.body_state, "with a clear line the knight should charge", DECISION_FRAMES):
		return
	var before: float = _health(player)
	var thrown: Array[bool] = [false]
	await wait_until(func() -> bool:
		thrown[0] = thrown[0] or player.knockback_component.magnitude.dot(_facing(_knight)) > 0.0
		return _health(player) < before and thrown[0], "the charge should hurt the target and throw it along the charge", DECISION_FRAMES)


func test_a_wall_in_the_way_stops_the_charge() -> void:
	var keep: AIKeepDistance = _knight.ai_state_machine.get_node("AIKeepDistance") as AIKeepDistance
	var charge: AIConditionalAttack = _knight.ai_state_machine.get_node("AICharge") as AIConditionalAttack
	var facing: Vector3 = _facing(_knight)
	# Inside the kept range (so the knight stands) and the charge range, behind a wide wall.
	_spawn_player(_knight.global_position + facing * keep.preferred_range)
	_spawn_wall(_knight.global_position + facing * keep.preferred_range * 0.5)
	# A must-not-happen check: watch every frame of the window.
	var charged: bool = false
	for _frame: int in DECISION_FRAMES / 2:
		await wait_physics_frames(1)
		charged = charged or _knight.state_machine.state == charge.body_state
	check(not charged, "the knight should not charge a target behind a wall")


func test_the_player_casting_it_charges_through_an_enemy() -> void:
	_knight.queue_free()
	var player: Character = _spawn_player(Vector3(0.0, 1.0, 0.0))
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(true)
	var enemy: Character = _quiet_enemy(MELEE_SCENE, Vector3(0.0, 1.0, CHARGE_TRAVEL * 2.0))
	enemy.knockback_component.max_knockback = 50.0
	await wait_until(func() -> bool: return player.is_on_floor() and enemy.is_on_floor(), "setup: everyone should land")
	if not check(player.ability_system_component.grant_ability(_ability) == 0, "setup: the player should learn the ability in slot 1"):
		return
	# The ability may come with a starting cooldown.
	await wait_until(func() -> bool: return player.ability_system_component.is_ready(0), "setup: the ability should come off its starting cooldown", DECISION_FRAMES)
	var start: Vector3 = player.global_position
	var before: float = _health(enemy)
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _health(enemy) < before, "the player's charge should hit the enemy in its path", DECISION_FRAMES):
		return
	await wait_until(func() -> bool: return player.global_position.distance_to(start) > CHARGE_TRAVEL, "the charge should carry the player forward", DECISION_FRAMES)
	check(enemy.knockback_component.magnitude.z > 0.0, "the enemy should be thrown along the charge")


# --- Helpers -----------------------------------------------------------------

func _spawn(scene: PackedScene, at: Vector3) -> Character:
	return spawn(scene, _arena, at) as Character


## An enemy with its mind off and test-owned huge health.
func _quiet_enemy(scene: PackedScene, at: Vector3) -> Character:
	var enemy: Character = _spawn(scene, at)
	disable_ai(enemy)
	enemy.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, HUGE_HEALTH)
	enemy.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, HUGE_HEALTH)
	return enemy


## A player that only the test and physics move, with test-owned huge health
## and no knockback (tests that need it switch it back on).
func _spawn_player(at: Vector3) -> Character:
	var player: Character = _spawn(PLAYER_SCENE, at)
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, HUGE_HEALTH)
	player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, HUGE_HEALTH)
	player.knockback_component.max_knockback = 0.0
	return player


## A blast that hits everyone, centered at the floor point under at.
func _blast(at: Vector3) -> void:
	var blast: GroundDamageArea = AOE_SCENE.instantiate() as GroundDamageArea
	autofree(blast)
	blast.hits_all = true
	blast.damage = TEST_DAMAGE
	blast.position = Vector3(at.x, _floor_top, at.z)
	_arena.add_child(blast)


## A wide, tall wall on the World layer, centered at the floor point under at
## and facing the knight's charge line.
func _spawn_wall(at: Vector3) -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(12.0, 4.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	autofree(wall)
	_arena.add_child(wall)
	wall.global_position = Vector3(at.x, _floor_top + 2.0, at.z)


## The knight's horizontal facing.
func _facing(character: Character) -> Vector3:
	var front: Vector3 = character.mesh_mount.global_basis.z
	front.y = 0.0
	return front.normalized()


func _distance(character: Character) -> float:
	var to_other: Vector3 = character.global_position - _knight.global_position
	to_other.y = 0.0
	return to_other.length()


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
