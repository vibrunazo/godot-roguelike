## Behavioral contract suite for the passive ability system: item granting and
## revoking, ability lifecycle event matching (tags, phases, prefix triggers,
## character tag gates), cooldown and completion gates, payload spawning with
## property overrides, end-to-end dash detonation through the real state
## machine, payloads spawned from inside a physics callback, and the landing
## blast. No balance values are asserted; damage checks compare against the
## payload's own configuration.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const DASH_EXPLOSION_SCENE: PackedScene = preload("res://Passives/passive_dash_explosion.tscn")
const LANDING_BLAST_SCENE: PackedScene = preload("res://Passives/passive_landing_blast.tscn")
const EXPLOSION_SCENE: PackedScene = preload("res://Hazards/explosion.tscn")
const DASH_TAG: StringName = &"ability.dash"
## Test-owned override value for the payload radius.
const TEST_RADIUS: float = 4.25
## Frame budget for a dash or a jump.
const ACTION_FRAMES: int = 600
## Physics ticks allowed for a spawned payload to arm and land its hit.
const PAYLOAD_FRAMES: int = 10

## Minimal counting passive used to probe trigger matching without payloads.
class TriggerCounter extends AbilityLifecyclePassive:
	var activations: int = 0

	func _activate(_event: AbilityEvent) -> void:
		activations += 1


var _arena: Node3D
var _player: Character
var _floor_y: float = 0.0
## Payloads spawned during the current test. Counting spawns (not live nodes)
## keeps checks immune to payloads freeing themselves after their visual.
var _payload_spawns: int = 0
var _newest_payload: WeakRef = weakref(null)
## Context for the physics-callback probe (see
## test_a_payload_spawned_during_a_physics_callback_still_lands_its_hit).
var _flush_origin: Vector3 = Vector3.ZERO
var _flush_armed: bool = false


func before_each() -> void:
	_payload_spawns = 0
	_newest_payload = weakref(null)
	get_tree().node_added.connect(_on_node_added)
	_arena = load_arena()
	_floor_y = arena_floor_top(_arena)
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	# Live input polling off: the test alone drives the player.
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	await wait_until(func() -> bool: return _player.is_on_floor() and _state() == "PlayerRun", "the player should settle")


func after_each() -> void:
	get_tree().node_added.disconnect(_on_node_added)
	_flush_armed = false


# --- Granting ----------------------------------------------------------------

func test_equipping_gear_grants_its_passive_and_unequipping_revokes_it() -> void:
	var passive: PassiveAbility = DASH_EXPLOSION_SCENE.instantiate() as PassiveAbility
	var passive_id: StringName = passive.id
	var display_name: String = passive.display_name
	passive.free()
	var gear: GearItemResource = GearItemResource.new()
	gear.id = &"test_passive_gear"
	gear.granted_passives.append(DASH_EXPLOSION_SCENE)
	if not check(_player.equipment_component.equip_gear(gear), "equipping passive-granting gear should succeed"):
		return
	check(_player.ability_system_component.has_passive(passive_id), "equipping the gear should grant its passive")
	check(gear.get_stat_summary(null).contains(display_name), "the gear summary should list the granted passive")
	check(_player.equipment_component.unequip_gear(gear), "unequipping the gear should succeed")
	check(not _player.ability_system_component.has_passive(passive_id), "unequipping the gear should revoke its passive")


# --- Trigger matching ---------------------------------------------------------

func test_a_passive_fires_only_on_its_tag_and_phase() -> void:
	var counter: TriggerCounter = _add_counter([DASH_TAG])
	_broadcast([&"ability.jump"], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 0, "a different tag should not trigger the passive")
	_broadcast([DASH_TAG], AbilityEvent.Phase.STARTED)
	check_eq(counter.activations, 0, "a different phase should not trigger the passive")
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 1, "the passive's own tag and phase should trigger it once")


func test_a_prefix_trigger_tag_matches_its_child_tags() -> void:
	var counter: TriggerCounter = _add_counter([&"ability"])
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 1, "a parent trigger tag should match a child event tag")


func test_character_tags_can_block_or_require_a_trigger() -> void:
	var counter: TriggerCounter = _add_counter([DASH_TAG])
	var blocked: Array[StringName] = [&"test.blocked"]
	counter.blocked_tags = blocked
	_player.add_tag(&"test.blocked")
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 0, "a blocked character tag should suppress the trigger")
	_player.remove_tag(&"test.blocked")
	var required: Array[StringName] = [&"test.ready"]
	counter.required_tags = required
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 0, "a missing required character tag should suppress the trigger")
	_player.add_tag(&"test.ready")
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 1, "a present required character tag should allow the trigger")
	_player.remove_tag(&"test.ready")


func test_the_cooldown_suppresses_retriggers_until_it_elapses() -> void:
	var counter: TriggerCounter = _add_counter([DASH_TAG])
	counter.cooldown = 0.25
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 1, "the cooldown should suppress an immediate retrigger")
	counter.tick_cooldown(counter.cooldown)
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check_eq(counter.activations, 2, "the passive should trigger again once its cooldown elapsed")


func test_the_completion_filter_skips_interrupted_events() -> void:
	var strict: TriggerCounter = _add_counter([DASH_TAG])
	strict.require_completion = true
	var lenient: TriggerCounter = _add_counter([DASH_TAG])
	lenient.require_completion = false
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED, {"completed": false})
	check(strict.activations == 0 and lenient.activations == 1, "an interrupted event should reach only passives that do not require completion (strict %d, lenient %d)" % [strict.activations, lenient.activations])
	_broadcast([DASH_TAG], AbilityEvent.Phase.ENDED)
	check(strict.activations == 1 and lenient.activations == 2, "an event without a completion report should count as completed (strict %d, lenient %d)" % [strict.activations, lenient.activations])


# --- Payloads -----------------------------------------------------------------

func test_a_payload_spawns_at_the_event_for_its_owner_and_deals_its_damage() -> void:
	_player.ability_system_component.add_passive(DASH_EXPLOSION_SCENE)
	var origin: Vector3 = Vector3(6.0, _floor_y, -6.0)
	var victim: Character = await _spawn_victim(origin)
	var health_before: float = _health(victim)
	_broadcast([DASH_TAG], AbilityEvent.Phase.STARTED, {}, origin)
	var explosion: GroundDamageArea = _newest()
	if not check(explosion != null, "the dash STARTED event should spawn the explosion"):
		return
	check(explosion.global_position.is_equal_approx(origin), "the payload should spawn at the event position")
	check(explosion.wielder == _player, "the payload should belong to the passive's owner")
	var expected: float = explosion.damage * victim.attribute_component.get_damage_multiplier(&"physical")
	await wait_until(func() -> bool: return health_before - _health(victim) > 0.0, "the payload should hit the victim", PAYLOAD_FRAMES)
	check_approx(health_before - _health(victim), expected, "the payload should deal its own damage")


func test_payload_overrides_patch_the_payload_and_unknown_ones_are_ignored() -> void:
	var radius_override: PayloadPropertyOverride = _float_override(&"radius", TEST_RADIUS)
	var probe: PayloadPassiveAbility = PayloadPassiveAbility.new()
	probe.id = &"override_probe"
	var probe_tags: Array[StringName] = [&"ability.probe"]
	probe.trigger_tags = probe_tags
	probe.payload_scene = EXPLOSION_SCENE
	probe.scale_with_attack = false
	probe.payload_overrides.append(radius_override)
	_player.ability_system_component.add_passive_instance(probe)
	_broadcast(probe_tags, AbilityEvent.Phase.ENDED, {}, Vector3(6.0, _floor_y, 0.0))
	var payload: GroundDamageArea = _newest()
	if check(payload != null and _payload_spawns == 1, "the probe should spawn exactly one payload"):
		check_approx(payload.radius, TEST_RADIUS, "the override should set the payload's property")
	probe.payload_overrides.append(_float_override(&"no_such_property", 99.0))
	var position: Vector3 = Vector3(-6.0, _floor_y, 0.0)
	_broadcast(probe_tags, AbilityEvent.Phase.ENDED, {}, position)
	payload = _newest()
	if check(payload != null and _payload_spawns == 2, "an unknown override property should not stop the spawn"):
		check(payload.global_position.is_equal_approx(position), "the payload should still spawn at its event")
		check_approx(payload.radius, TEST_RADIUS, "the valid override should still apply")


# --- End to end -----------------------------------------------------------------

func test_a_dash_detonates_once_at_takeoff_even_when_interrupted() -> void:
	_player.ability_system_component.add_passive(DASH_EXPLOSION_SCENE)
	var takeoff: Vector3 = _player.global_position
	_player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	var explosion: GroundDamageArea = _newest()
	check(explosion != null and _horizontal(explosion.global_position - takeoff).length() < 1.0, "the dash should detonate at its takeoff point")
	await _wait_running("the dash should end")
	await wait_physics_frames(PAYLOAD_FRAMES)
	check_eq(_payload_spawns, 1, "a dash should detonate exactly once")
	_player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	await wait_physics_frames(1)
	_player.state_machine.request_state("PlayerRun")
	await wait_physics_frames(PAYLOAD_FRAMES)
	check_eq(_payload_spawns, 2, "an interrupted dash should keep its takeoff detonation")


func test_a_completion_gated_payload_fires_only_when_the_dash_completes() -> void:
	var strict: PayloadPassiveAbility = PayloadPassiveAbility.new()
	strict.id = &"strict_dash"
	var dash_tags: Array[StringName] = [DASH_TAG]
	strict.trigger_tags = dash_tags
	strict.require_completion = true
	strict.payload_scene = EXPLOSION_SCENE
	_player.ability_system_component.add_passive_instance(strict)
	_player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	await wait_physics_frames(1)
	_player.state_machine.request_state("PlayerRun")
	await wait_physics_frames(PAYLOAD_FRAMES)
	check_eq(_payload_spawns, 0, "an interrupted dash should not fire a completion-gated payload")
	_player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	await _wait_running("the dash should end")
	await wait_physics_frames(PAYLOAD_FRAMES)
	check_eq(_payload_spawns, 1, "a completed dash should fire the completion-gated payload once")


## Regression: a passive reacting inside an Area3D body_entered callback (the
## exit portal's, during a scene transition) spawns its payload while Area3D
## monitoring changes are locked; the payload must still arm and hit.
func test_a_payload_spawned_during_a_physics_callback_still_lands_its_hit() -> void:
	_player.ability_system_component.add_passive(DASH_EXPLOSION_SCENE)
	_flush_origin = Vector3(8.0, _floor_y, -8.0)
	var victim: Character = await _spawn_victim(_flush_origin)
	var health_before: float = _health(victim)
	# Trigger area high above the floor, so only the dropped probe body enters.
	var probe_point: Vector3 = Vector3(-8.0, _floor_y + 5.0, -8.0)
	var trigger: Area3D = autofree(Area3D.new()) as Area3D
	trigger.collision_layer = 0
	trigger.collision_mask = 1
	trigger.add_child(_sphere_shape(2.0))
	_arena.add_child(trigger)
	trigger.global_position = probe_point
	await wait_physics_frames(1)
	trigger.body_entered.connect(_on_probe_body_entered)
	_flush_armed = true
	var probe: StaticBody3D = autofree(StaticBody3D.new()) as StaticBody3D
	probe.collision_layer = 1
	probe.add_child(_sphere_shape(0.5))
	_arena.add_child(probe)
	probe.global_position = probe_point
	if not await wait_until(func() -> bool: return _payload_spawns == 1, "the callback should spawn one payload", PAYLOAD_FRAMES):
		return
	var explosion: GroundDamageArea = _newest()
	check(explosion != null and explosion.global_position.is_equal_approx(_flush_origin), "the payload should spawn at the event position")
	var expected: float = explosion.damage * victim.attribute_component.get_damage_multiplier(&"physical") if explosion != null else 0.0
	await wait_until(func() -> bool: return health_before - _health(victim) > 0.0, "the payload should arm and hit the victim", PAYLOAD_FRAMES)
	check_approx(health_before - _health(victim), expected, "the payload should deal its own damage")
	check_no_engine_errors("arming the payload inside the callback should not hit the Area3D lock")


## The landing blast fires once per airborne episode, whatever state the
## character lands in: a jump turned into a jump kick mid-flight still gives
## exactly one blast, at the landing point.
func test_a_jump_turned_into_a_kick_lands_exactly_one_blast() -> void:
	_player.ability_system_component.add_passive(LANDING_BLAST_SCENE)
	_player.state_machine.request_state("PlayerJump", {"direction": Vector3.ZERO})
	if not await wait_until(func() -> bool: return _player.has_tag(AirborneTracker.TAG_AIRBORNE), "the jump should mark the player airborne", ACTION_FRAMES):
		return
	_player.state_machine.request_state("PlayerJumpKick")
	if not await wait_until(func() -> bool: return not _player.has_tag(AirborneTracker.TAG_AIRBORNE), "the player should land", ACTION_FRAMES):
		return
	await wait_physics_frames(PAYLOAD_FRAMES)
	check_eq(_payload_spawns, 1, "one airborne episode should give exactly one landing blast")
	var explosion: GroundDamageArea = _newest()
	check(explosion != null and _horizontal(explosion.global_position - _player.global_position).length() < 1.0, "the blast should detonate at the landing point")


# --- Helpers ------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is GroundDamageArea:
		_payload_spawns += 1
		_newest_payload = weakref(node)


## Broadcasts the dash STARTED event from inside the body_entered dispatch,
## where Area3D monitoring toggles are locked.
func _on_probe_body_entered(_body: Node3D) -> void:
	if not _flush_armed:
		return
	_flush_armed = false
	_broadcast([DASH_TAG], AbilityEvent.Phase.STARTED, {}, _flush_origin)


## The most recently spawned payload, or null once it freed itself.
func _newest() -> GroundDamageArea:
	return _newest_payload.get_ref() as GroundDamageArea


func _broadcast(tags: Array[StringName], phase: AbilityEvent.Phase, data: Dictionary = {}, at: Vector3 = Vector3.ZERO) -> void:
	var event: AbilityEvent = AbilityEvent.new()
	event.tags = tags
	event.phase = phase
	event.data = data
	event.position = at
	_player.broadcast_ability_event(event)


func _add_counter(tags: Array[StringName]) -> TriggerCounter:
	var counter: TriggerCounter = TriggerCounter.new()
	counter.id = StringName("counter_%d" % _player.ability_system_component.get_child_count())
	counter.trigger_tags = tags
	_player.ability_system_component.add_passive_instance(counter)
	return counter


func _float_override(property: StringName, value: float) -> PayloadPropertyOverride:
	var override: PayloadPropertyOverride = PayloadPropertyOverride.new()
	override.value_type = PayloadPropertyOverride.ValueType.FLOAT
	override.property = property
	override.float_value = value
	return override


## A still melee enemy standing on the given floor point.
func _spawn_victim(at: Vector3) -> Character:
	var victim: Character = spawn(MELEE_SCENE, _arena, at + Vector3.UP) as Character
	disable_ai(victim)
	await wait_until(func() -> bool: return victim.is_on_floor(), "setup: the victim should land")
	victim.global_position = Vector3(at.x, victim.global_position.y, at.z)
	return victim


func _sphere_shape(radius: float) -> CollisionShape3D:
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	return shape


func _wait_running(message: String) -> bool:
	return await wait_until(func() -> bool: return _player.is_on_floor() and _state() == "PlayerRun", message, ACTION_FRAMES)


func _health(character: Character) -> float:
	return character.attribute_component.get_current(AttributeComponent.POOL_HEALTH)


func _horizontal(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)


func _state() -> String:
	return str(_player.state_machine.state.name)
