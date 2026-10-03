## The Producer, a support enemy, and its Crunch Time ability:
## - the Producer casts the very AbilityResource its drop book teaches, from
##   its own ability slot,
## - in combat, with an ally close by, it casts Crunch Time, which buffs the
##   allies within the burst (itself included) and never far allies or foes,
## - without allies it never casts, and a player who gets close takes its
##   emergency melee strike,
## - the player casting the same ability (from the book) buffs themself and
##   no enemy,
## - an attack buff raises a ranged enemy's projectile damage (attack scales
##   every attack, ranged ones included).
## Positions, health and the attack stat are test-owned; ranges and the
## effect are read from the live nodes and resources.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const PRODUCER_SCENE: PackedScene = preload("res://Enemy/enemy_producer.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const RANGED_SCENE: PackedScene = preload("res://Enemy/ranged_enemy.tscn")
## Frame budget for an AI decision plus a cast.
const DECISION_FRAMES: int = 600
## Test-owned health high enough that nothing here dies.
const HUGE_HEALTH: float = 1.0e9
## Test-owned attack stat for the projectile scaling test (base is 100).
const DOUBLE_ATTACK: float = 200.0

var _arena: Node3D
var _producer: Character
var _ability: AbilityResource
var _burst: EffectBurst
var _effect_id: StringName


func before_each() -> void:
	ProgressionState.reset_run()
	_arena = load_arena()
	await wait_for_navigation(_arena)
	_producer = _spawn(PRODUCER_SCENE, Vector3(0.0, 1.0, 0.0))
	_ability = _producer.ability_system_component.get_ability(0)
	_burst = autofree(_ability.payload_scene.instantiate()) as EffectBurst
	_effect_id = StringName(_burst.effects[0].effect_name)


func after_each() -> void:
	ProgressionState.reset_run()
	UI.resume_game()


func test_the_producer_casts_the_ability_its_book_teaches() -> void:
	var archetype: EnemyResource = GlobalVars.get_enemy_resource(PRODUCER_SCENE)
	if not check(archetype != null and not archetype.item_drops.is_empty(), "the Producer should be registered with a drop"):
		return
	var book: BookItemResource = archetype.item_drops[0].item as BookItemResource
	check(book != null and book.granted_abilities.has(_ability), "the Producer's slot should hold the very ability its book teaches")
	var support: AISupportAllies = _producer.ai_state_machine.get_node("AICrunchTime") as AISupportAllies
	check(support != null and support.body_state == _producer.ability_system_component.slots[0], "the Producer's mind should cast from that slot")


func test_crunch_time_buffs_nearby_allies_only() -> void:
	var near: Character = _quiet_enemy(MELEE_SCENE, Vector3(_burst.radius * 0.5, 1.0, 0.0))
	var far: Character = _quiet_enemy(MELEE_SCENE, Vector3(-_burst.radius * 2.0, 1.0, 0.0))
	var player: Character = _spawn_player(Vector3(0.0, 1.0, _burst.radius * 0.8))
	if not await wait_until(func() -> bool: return near.attribute_component.has_effect_instance(_effect_id), "the Producer should buff a nearby ally in combat", DECISION_FRAMES):
		return
	check(_producer.attribute_component.has_effect_instance(_effect_id), "the burst should buff the Producer itself")
	check(not far.attribute_component.has_effect_instance(_effect_id), "an ally outside the burst should not be buffed")
	check(not player.attribute_component.has_effect_instance(_effect_id), "the burst should never buff a foe")


func test_without_allies_it_never_casts() -> void:
	var strike: AIConditionalAttack = _producer.ai_state_machine.get_node("AIEmergencyStrike") as AIConditionalAttack
	var cast: Array[bool] = [false]
	_producer.ability_system_component.ability_cast.connect(func(_slot: int, _cast_ability: AbilityResource) -> void: cast[0] = true)
	# In combat, out of strike range, nobody else around.
	_spawn_player(_producer.global_position + Vector3(0.0, 0.0, strike.trigger_range + _burst.radius * 0.5))
	await wait_physics_frames(DECISION_FRAMES / 2)
	check(not cast[0], "with no ally around the Producer should never cast its support ability")


func test_a_close_player_takes_the_emergency_strike() -> void:
	var strike: AIConditionalAttack = _producer.ai_state_machine.get_node("AIEmergencyStrike") as AIConditionalAttack
	_spawn_player(_producer.global_position + Vector3(0.0, 0.0, strike.trigger_range * 0.6))
	await wait_until(func() -> bool: return _producer.state_machine.state == strike.body_state, "a close player should take the emergency strike", DECISION_FRAMES)


func test_the_player_casting_it_buffs_only_themself() -> void:
	_producer.queue_free()
	var player: Character = _spawn_player(Vector3(0.0, 1.0, 4.0))
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(true)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_MANA, _ability.cost_amount * 2.0)
	player.attribute_component.set_pool_current(AttributeComponent.POOL_MANA, _ability.cost_amount * 2.0)
	var enemy: Character = _quiet_enemy(MELEE_SCENE, player.global_position + Vector3(_burst.radius * 0.5, 0.0, 0.0))
	await wait_until(func() -> bool: return player.is_on_floor(), "setup: the player should land")
	if not check(player.ability_system_component.grant_ability(_ability) == 0, "setup: the player should learn the ability in slot 1"):
		return
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return player.attribute_component.has_effect_instance(_effect_id), "casting Crunch Time should buff the player", DECISION_FRAMES):
		return
	check(not enemy.attribute_component.has_effect_instance(_effect_id), "the player's Crunch Time should never buff an enemy")


func test_attack_buffs_scale_enemy_projectiles() -> void:
	_producer.queue_free()
	var player: Character = _spawn_player(Vector3(0.0, 1.0, 8.0))
	var base_damage: float = await _shot_damage(_quiet_enemy(RANGED_SCENE, Vector3(-3.0, 1.0, 0.0)), player)
	var buffed: Character = _quiet_enemy(RANGED_SCENE, Vector3(3.0, 1.0, 0.0))
	buffed.attribute_component.set_base(AttributeComponent.STAT_ATTACK, DOUBLE_ATTACK)
	var buffed_damage: float = await _shot_damage(buffed, player)
	check_approx(buffed_damage, base_damage * DOUBLE_ATTACK / 100.0, "a projectile's damage should scale with the shooter's attack")


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


## A player that only the test and physics move, with test-owned huge health.
func _spawn_player(at: Vector3) -> Character:
	var player: Character = _spawn(PLAYER_SCENE, at)
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	player.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, HUGE_HEALTH)
	player.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, HUGE_HEALTH)
	player.knockback_component.max_knockback = 0.0
	return player


## Orders shooter's ranged attack at target and returns the damage of the
## projectile it fires (the projectile is freed again).
func _shot_damage(shooter: Character, target: Character) -> float:
	await wait_until(func() -> bool: return shooter.is_on_floor() and shooter.state_machine.state == shooter.state_machine.initial_state, "setup: the shooter should land and settle")
	var attack: CharacterState = (shooter.ai_state_machine.get_node("AIAttack") as AIAttack).body_state
	var fired: Array[Projectile] = []
	var watch: Callable = func(node: Node) -> void:
		if node is Projectile and (node as Projectile).shooter == shooter:
			fired.append(node as Projectile)
	get_tree().node_added.connect(watch)
	shooter.ai_state_machine.order_attack(attack, false, {"aim_target": AimTarget.at_node(target)})
	await wait_until(func() -> bool: return not fired.is_empty(), "the ranged attack should fire a projectile", DECISION_FRAMES)
	get_tree().node_added.disconnect(watch)
	if fired.is_empty():
		return 0.0
	var damage: float = fired[0].damage
	fired[0].queue_free()
	return damage
