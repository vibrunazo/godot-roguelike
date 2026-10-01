## Active abilities: slots on the AbilitySystemComponent, cast from the
## ability_N actions.
## - granting fills the first free slot (or the one asked for) and refuses a
##   duplicate, a taken slot and full slots; revoking empties the slot,
## - pressing a slot's action casts it: the payload leaves at release time
##   from the cast origin, flies at the aim and hits a foe, never the caster,
## - a slot on cooldown, an empty slot, or a cost the pool cannot pay casts
##   nothing; a paid cast takes its cost from the pool,
## - casting is refused while dashing and allowed in mid-air while jumping; a
##   melee attack is cancelled into a cast only when it is cancelable,
## - a cast is committed until release (another ability cannot cut in), but a
##   cancelable one can still be dashed out of,
## - a cast reports STARTED, ACTIVE (at release) and ENDED (once, with
##   completed) to passives, tagged with the ability's tags,
## - the shipped Fireball ability casts a projectile,
## - an enemy with a slot, a starting ability and an AIConditionalAttack on
##   that slot casts it at the player (no ability-specific AI state).
## Every ability here is built by the test; its numbers are test-owned.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const PAYLOAD_SCENE: PackedScene = preload("res://Enemy/fireball_projectile.tscn")
const FIREBALL: AbilityResource = preload("res://Abilities/AbilityResources/ability_fireball.tres")
## Test-owned ability numbers.
const TEST_COOLDOWN: float = 5.0
const TEST_RELEASE_TIME: float = 0.2
const TEST_DAMAGE: float = 7.0
const TEST_COST: float = 4.0
const TEST_TAG: StringName = &"ability.test_spell"
## Test-owned foe health and distance ahead of the caster.
const FOE_HEALTH: float = 100000.0
const FOE_DISTANCE: float = 4.0
## Test-owned direction of the foe, off the default +Z heading so a payload
## that ignored the aim would miss.
const FOE_DIRECTION: Vector3 = Vector3.RIGHT
## AnimationTree state of the enemy rig the enemy's test cast plays.
const ENEMY_CAST_ANIMATION: String = "RangedAttack"
## Frame budget for a cast or a flight.
const ACTION_FRAMES: int = 600


## Records every ability event it receives.
class EventRecorder extends PassiveAbility:
	var events: Array[AbilityEvent] = []

	func handle_ability_event(event: AbilityEvent) -> void:
		events.append(event)


var _arena: Node3D
var _player: Character
var _asc: AbilitySystemComponent
var _run: CharacterState
var _spawned: Array[Projectile] = []


func before_each() -> void:
	_spawned.clear()
	get_tree().node_added.connect(_on_node_added)
	_arena = load_arena()
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	# Live input polling off: the test sets the aim itself.
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_player.aim_direction = FOE_DIRECTION
	_asc = _player.ability_system_component
	_run = _player.state_machine.get_node("PlayerRun") as CharacterState
	await _wait_running("the player should settle")


func after_each() -> void:
	get_tree().node_added.disconnect(_on_node_added)


# --- Slots -------------------------------------------------------------------

func test_granting_fills_free_slots_and_refuses_duplicates_and_full_slots() -> void:
	var count: int = _asc.get_slot_count()
	if not check(count >= 2, "setup: the player should have several ability slots"):
		return
	var abilities: Array[AbilityResource] = []
	for index: int in count:
		abilities.append(_ability())
	check_eq(_asc.grant_ability(abilities[0], null, 1), 1, "granting into a free slot should use that slot")
	check_eq(_asc.grant_ability(abilities[1]), 0, "granting without a slot should use the first free one")
	check_eq(_asc.grant_ability(abilities[0]), -1, "an ability already held should be refused")
	check_eq(_asc.grant_ability(abilities[2], null, 1), -1, "a taken slot should be refused")
	for index: int in range(2, count):
		_asc.grant_ability(abilities[index])
	check(not _asc.has_free_slot(), "every slot should be filled")
	check_eq(_asc.grant_ability(_ability()), -1, "an ability should be refused when every slot is full")
	check(_asc.revoke_ability(1) == abilities[0], "revoking should return the slot's ability")
	check(_asc.get_ability(1) == null and _asc.has_free_slot(), "revoking should empty the slot")


# --- Casting -----------------------------------------------------------------

func test_the_ability_key_casts_its_slot_and_the_payload_hits_a_foe_not_the_caster() -> void:
	var foe: Character = _spawn_foe()
	var ability: AbilityResource = _ability()
	_asc.grant_ability(ability, null, 0)
	var caster_health: float = _health(_player)
	var foe_health: float = _health(foe)
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "pressing ability_1 should cast slot 1", 10):
		return
	if not await wait_until(func() -> bool: return not _spawned.is_empty(), "the cast should release its payload", ACTION_FRAMES):
		return
	var shot: Projectile = _spawned[0]
	check(shot.shooter == _player, "the payload should belong to the caster")
	var origin: Node3D = _asc.slots[0].cast_origin
	check(_flat(shot.global_position - origin.global_position).length() < 0.5, "the payload should leave from the cast origin")
	check(_flat(shot.global_basis.z).normalized().dot(_flat(foe.global_position - _player.global_position).normalized()) > 0.99, "the payload should fly at the foe")
	if not await wait_until(func() -> bool: return _health(foe) < foe_health, "the payload should hit the foe", ACTION_FRAMES):
		return
	check_approx(foe_health - _health(foe), TEST_DAMAGE * _player.get_damage_modifier(), "the hit should deal the payload's damage scaled by the caster's attack")
	check_approx(_health(_player), caster_health, "the payload should never hit its caster")
	await _wait_running("the cast should end in running")


func test_a_slot_on_cooldown_or_empty_casts_nothing() -> void:
	_asc.grant_ability(_ability(), null, 0)
	press_action(&"ability_2")
	await wait_physics_frames(2)
	check_eq(_state(), _run.name, "an empty slot should cast nothing")
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "the first cast should start", 10):
		return
	await _wait_running("the first cast should end")
	check(_asc.get_cooldown_fraction(0) > 0.0, "the slot should be on cooldown after a cast")
	press_action(&"ability_1")
	await wait_physics_frames(2)
	check_eq(_state(), _run.name, "a slot on cooldown should cast nothing")


func test_a_cast_pays_its_cost_and_is_refused_when_the_pool_is_short() -> void:
	var ability: AbilityResource = _ability()
	ability.cost_pool = AttributeComponent.POOL_MANA
	ability.cost_amount = TEST_COST
	ability.cooldown = 0.0
	_asc.grant_ability(ability, null, 0)
	var attributes: AttributeComponent = _player.attribute_component
	attributes.set_base(AttributeComponent.STAT_MAX_MANA, TEST_COST * 1.5)
	attributes.set_pool_current(AttributeComponent.POOL_MANA, TEST_COST * 1.5)
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "a cast the pool can pay should start", 10):
		return
	check_approx(attributes.get_current(AttributeComponent.POOL_MANA), TEST_COST * 0.5, "the cast should take its cost from the pool")
	await _wait_running("the cast should end")
	press_action(&"ability_1")
	await wait_physics_frames(2)
	check_eq(_state(), _run.name, "a cast the pool cannot pay should be refused")


# --- When casting is allowed ---------------------------------------------------

func test_casting_is_refused_while_dashing() -> void:
	_asc.grant_ability(_ability(), null, 0)
	_player.state_machine.request_state(_run.dash_state.name, {"direction": Vector3.BACK})
	press_action(&"ability_1")
	var cast: Array[bool] = [false]
	await wait_until(func() -> bool:
		cast[0] = cast[0] or _state() == _asc.slots[0].name
		return _state() == _run.name, "the dash should end in running", ACTION_FRAMES)
	check(not cast[0], "a press during the dash should not cast")
	check(_asc.get_cooldown_fraction(0) == 0.0, "a refused press should not start the cooldown")


func test_a_press_while_jumping_casts_in_mid_air() -> void:
	_asc.grant_ability(_ability(), null, 0)
	_player.state_machine.request_state(_run.jump_state.name)
	if not await wait_until(func() -> bool: return not _player.is_on_floor(), "the jump should leave the floor", ACTION_FRAMES):
		return
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "a press during the jump should cast", 10):
		return
	check(not _player.is_on_floor(), "the cast should start in mid-air")
	await wait_until(func() -> bool: return not _spawned.is_empty(), "the mid-air cast should release its payload", ACTION_FRAMES)
	await _wait_running("the player should land and run after the cast")


func test_a_melee_attack_is_cancelled_into_a_cast_only_when_cancelable() -> void:
	_asc.grant_ability(_ability(), null, 0)
	var attack: CharacterAction = _run.attack_state as CharacterAction
	for cancelable: bool in [false, true]:
		await _wait_running("the player should be running before attacking")
		attack.cancelable = cancelable
		_player.state_machine.request_state(attack.name)
		press_action(&"ability_1")
		await wait_physics_frames(2)
		if cancelable:
			check_eq(_state(), _asc.slots[0].name, "a cancelable attack should be cancelled into the cast")
		else:
			check_eq(_state(), attack.name, "an attack that is not cancelable should keep running")
		await _wait_running("the %s should end" % _state())


func test_a_cast_is_committed_until_release_but_a_dash_cancels_it() -> void:
	var first: AbilityResource = _ability()
	first.release_time = 10.0
	_asc.grant_ability(first, null, 0)
	_asc.grant_ability(_ability(), null, 1)
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "the first cast should start", 10):
		return
	press_action(&"ability_2")
	await wait_physics_frames(2)
	check_eq(_state(), _asc.slots[0].name, "another ability should not cut into a cast before release")
	check(not _player.can_accept_order(_asc.slots[1]), "the body should refuse orders before release")
	_player.dash_requested = true
	await wait_physics_frames(2)
	check_eq(_state(), _run.dash_state.name, "a dash should cancel a cancelable cast")
	check(_spawned.is_empty(), "a cast cancelled before release should release nothing")


func test_a_cast_reports_started_active_and_ended_to_passives() -> void:
	var recorder: EventRecorder = EventRecorder.new()
	recorder.id = &"event_recorder"
	_asc.add_passive_instance(recorder)
	_asc.grant_ability(_ability(), null, 0)
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "the cast should start", 10):
		return
	await _wait_running("the cast should end")
	var phases: Array[int] = []
	for event: AbilityEvent in recorder.events:
		if event.matches_tag(TEST_TAG):
			phases.append(event.phase)
	var expected: Array[int] = [AbilityEvent.Phase.STARTED, AbilityEvent.Phase.ACTIVE, AbilityEvent.Phase.ENDED]
	check_eq(phases, expected, "the cast should report STARTED, ACTIVE and ENDED once each, in order")
	var ended: AbilityEvent = recorder.events.back() as AbilityEvent
	check(bool(ended.data.get("completed", false)), "a cast that released should end completed")


func test_the_fireball_ability_casts_a_projectile() -> void:
	_asc.grant_ability(FIREBALL, null, 0)
	press_action(&"ability_1")
	if not await wait_until(func() -> bool: return _state() == _asc.slots[0].name, "the fireball cast should start", 10):
		return
	await wait_until(func() -> bool: return not _spawned.is_empty(), "the fireball should release a projectile", ACTION_FRAMES)
	check_no_engine_errors("casting the fireball should raise no engine errors")


func test_an_enemy_casts_its_starting_ability_at_the_player() -> void:
	var ability: AbilityResource = _ability()
	# The enemy rig has no CastSpell state; its ranged attack animation serves.
	ability.cast_animation = ENEMY_CAST_ANIMATION
	var caster: Character = MELEE_SCENE.instantiate() as Character
	var asc: AbilitySystemComponent = AbilitySystemComponent.new()
	var slot: AbilityCastState = AbilityCastState.new()
	slot.name = "AbilitySlot1"
	slot.character = caster
	slot.cast_origin = caster.mesh_mount
	slot.next_states = [caster.state_machine.initial_state]
	_add_owned(caster, caster.state_machine, slot)
	asc.slots = [slot]
	asc.starting_abilities = [ability]
	_add_owned(caster, caster, asc)
	caster.ability_system_component = asc
	var mind: AIConditionalAttack = AIConditionalAttack.new()
	mind.ai_state_machine = caster.ai_state_machine
	mind.body_state = slot
	mind.trigger_range = FOE_DISTANCE * 3.0
	mind.desired_angle = 360.0
	mind.priority = 100
	mind.next_state = caster.ai_state_machine.initial_state as AIState
	_add_owned(caster, caster.ai_state_machine, mind)
	autofree(caster)
	_arena.add_child(caster)
	caster.global_position = _player.global_position + FOE_DIRECTION * FOE_DISTANCE
	var cast: Callable = func() -> bool:
		for shot: Projectile in _spawned:
			if is_instance_valid(shot) and shot.shooter == caster:
				return true
		return false
	await wait_until(cast, "the enemy's AI should cast its ability at the player", ACTION_FRAMES)
	check_no_engine_errors("an enemy casting should raise no engine errors")


# --- Helpers -----------------------------------------------------------------

## Adds node under parent inside a scene not yet in the tree, owned by root
## like an authored node (state machines only wire states the scene owns).
func _add_owned(root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = root


## A test-owned ability releasing the fireball projectile with test damage.
func _ability() -> AbilityResource:
	var ability: AbilityResource = AbilityResource.new()
	ability.id = StringName("test_ability_%d" % randi())
	ability.display_name = "Test Spell"
	ability.ability_tags = [TEST_TAG]
	ability.cooldown = TEST_COOLDOWN
	ability.release_time = TEST_RELEASE_TIME
	ability.cast_animation = FIREBALL.cast_animation
	ability.payload_scene = PAYLOAD_SCENE
	var damage: PayloadPropertyOverride = PayloadPropertyOverride.new()
	damage.property = &"damage"
	damage.float_value = TEST_DAMAGE
	ability.payload_overrides = [damage]
	return ability


func _spawn_foe() -> Character:
	var foe: Character = spawn(MELEE_SCENE, _arena, _player.global_position + FOE_DIRECTION * FOE_DISTANCE) as Character
	disable_ai(foe)
	foe.attribute_component.set_base(AttributeComponent.STAT_MAX_HEALTH, FOE_HEALTH)
	foe.attribute_component.set_pool_current(AttributeComponent.POOL_HEALTH, FOE_HEALTH)
	foe.knockback_component.max_knockback = 0.0
	return foe


func _wait_running(message: String) -> bool:
	return await wait_until(func() -> bool: return _player.is_on_floor() and _state() == _run.name, message, ACTION_FRAMES)


func _state() -> String:
	return str(_player.state_machine.state.name)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _on_node_added(node: Node) -> void:
	if node is Projectile:
		_spawned.append(node as Projectile)
