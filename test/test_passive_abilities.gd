## Behavioral contract suite for the passive ability system: item granting and
## revoking, ability lifecycle event matching (tags, phases, prefix triggers),
## cooldown and completion gates, payload spawning with property overrides, and
## end-to-end dash detonation through the real state machine. No balance values
## are asserted; damage checks compare against the payload's own configuration.
extends Node

const TestUtils = preload("res://test/test_utils.gd")

var passed_checks: int = 0
var failed: bool = false
## Cumulative count of GroundDamageArea payloads entering the tree. Counting
## spawns (not live nodes) keeps assertions immune to payloads self-freeing on
## their visual_duration while a test part is still awaiting frames.
var payload_spawns: int = 0


## Minimal counting passive used to probe trigger matching without payloads.
class TriggerCounter extends AbilityLifecyclePassive:
	var activations: int = 0

	func _activate(_event: AbilityEvent) -> void:
		activations += 1


func _fail(message: String) -> void:
	failed = true
	printerr("TEST FAILED: " + message)


func _pass(message: String) -> void:
	passed_checks += 1
	print("ok: " + message)


func _make_event(tags: Array[StringName], phase: int, data: Dictionary = {}) -> AbilityEvent:
	var event: AbilityEvent = AbilityEvent.new()
	event.tags = tags
	event.phase = phase
	event.data = data
	return event


func _on_node_added(node: Node) -> void:
	if node is GroundDamageArea:
		payload_spawns += 1


func _newest_payload() -> GroundDamageArea:
	var children: Array[Node] = get_children()
	for i: int in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		if child is GroundDamageArea and not child.is_queued_for_deletion():
			return child as GroundDamageArea
	return null


## Context for the flush-spawn probe: the character to broadcast for and the
## blast origin the payload should spawn at (see _part_flush_spawn).
var _flush_player: Character = null
var _flush_origin: Vector3 = Vector3.ZERO


## Broadcasts a dash lifecycle event from inside an Area3D body_entered
## dispatch: the physics query-flushing context where Area3D monitoring toggles
## are locked (the exit portal's body_entered -> scene transition -> dash cancel
## stack).
func _on_flush_probe_body_entered(_body: Node3D) -> void:
	if _flush_player == null:
		return
	var dash_trigger: Array[StringName] = [&"ability.dash"]
	var event: AbilityEvent = _make_event(dash_trigger, AbilityEvent.Phase.STARTED)
	event.position = _flush_origin
	_flush_player.broadcast_ability_event(event)
	_flush_player = null


func _ready() -> void:
	print("====================================================")
	print("  STARTING PASSIVE ABILITY TEST SUITE")
	print("====================================================")
	get_tree().node_added.connect(_on_node_added)

	# Physical floor so characters stand and payloads ground correctly.
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	var player_scene: PackedScene = load("res://Player/player.tscn") as PackedScene
	if player_scene == null:
		_fail("Could not load Player/player.tscn.")
		return
	var player: Character = player_scene.instantiate() as Character
	player.position = Vector3(0.0, 0.0, 8.0)
	add_child(player)
	await get_tree().process_frame

	if player.passive_ability_component == null:
		_fail("Player has no PassiveAbilityComponent attached.")
		return
	if player.equipment_component == null:
		_fail("Player has no EquipmentComponent attached.")
		return
	_pass("Player PassiveAbilityComponent and EquipmentComponent resolved.")

	await _part_grant_and_revoke(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_matching(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_cooldown(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_completion_filter(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_payload(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_dash_integration(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_flush_spawn(player)
	if failed:
		get_tree().quit(1)
		return
	await _part_landing_blast(player)
	if failed:
		get_tree().quit(1)
		return

	print("\n====================================================")
	print("  PASSIVE ABILITY TEST SUITE PASSED (%d checks)" % passed_checks)
	print("====================================================")
	get_tree().quit(0)


## PART 1: gear equip grants a passive scene and unequip revokes it.
func _part_grant_and_revoke(player: Character) -> void:
	print("\n>>> PART 1: Item Grant and Revoke of Passive Scenes")
	var passive_scene: PackedScene = load("res://Passives/passive_dash_explosion.tscn") as PackedScene
	if passive_scene == null:
		_fail("Could not load Passives/passive_dash_explosion.tscn (parse error?).")
		return
	var gear: GearItemResource = GearItemResource.new()
	gear.id = &"test_passive_gear"
	gear.granted_passives.append(passive_scene)

	if not player.equipment_component.equip_gear(gear):
		_fail("equip_gear returned false for passive-granting gear.")
		return
	if not player.passive_ability_component.has_passive(&"dash_explosion"):
		_fail("Equipping gear did not grant the passive scene.")
		return
	_pass("Gear equip granted the passive scene.")

	var summary: String = gear.get_stat_summary(null)
	if not summary.contains("Dash Detonation"):
		_fail("Stat summary does not list the granted passive display name. Got: " + summary)
		return
	_pass("Stat summary lists the granted passive.")

	if not player.equipment_component.unequip_gear(gear):
		_fail("unequip_gear returned false.")
		return
	if player.passive_ability_component.has_passive(&"dash_explosion"):
		_fail("Unequipping gear did not revoke the passive.")
		return
	_pass("Gear unequip revoked the passive scene.")


## PART 2: trigger matching across tags, phases, prefixes, and character gates.
func _part_matching(player: Character) -> void:
	print("\n>>> PART 2: Lifecycle Event Matching")
	var counter: TriggerCounter = TriggerCounter.new()
	counter.id = &"counter"
	var dash_trigger: Array[StringName] = [&"ability.dash"]
	counter.trigger_tags = dash_trigger
	player.passive_ability_component.add_passive_instance(counter)

	var jump_tag: Array[StringName] = [&"ability.jump"]
	player.broadcast_ability_event(_make_event(jump_tag, AbilityEvent.Phase.ENDED))
	if counter.activations != 0:
		_fail("Passive fired on a non-matching tag.")
		return
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.STARTED))
	if counter.activations != 0:
		_fail("Passive fired on a non-matching phase.")
		return
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 1:
		_fail("Passive did not fire exactly once on its trigger. Got %d" % counter.activations)
		return
	_pass("Tag and phase gates match correctly.")

	# Prefix trigger: &"ability" answers &"ability.dash".
	var prefix_trigger: Array[StringName] = [&"ability"]
	counter.trigger_tags = prefix_trigger
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 2:
		_fail("Prefix trigger tag did not match the hierarchical event tag.")
		return
	_pass("Prefix trigger tags match hierarchically.")
	counter.trigger_tags = dash_trigger

	# Character tag gates.
	var blocked: Array[StringName] = [&"test.blocked"]
	counter.blocked_tags = blocked
	player.add_tag(&"test.blocked")
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 2:
		_fail("Blocked character tag did not suppress the trigger.")
		return
	player.remove_tag(&"test.blocked")
	var required: Array[StringName] = [&"test.ready"]
	counter.required_tags = required
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 2:
		_fail("Missing required character tag did not suppress the trigger.")
		return
	player.add_tag(&"test.ready")
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 3:
		_fail("Required character tag did not allow the trigger.")
		return
	_pass("Character tag gates suppress and allow triggers.")
	player.remove_tag(&"test.ready")
	var empty_tags: Array[StringName] = []
	counter.required_tags = empty_tags
	counter.blocked_tags = empty_tags
	player.passive_ability_component.remove_passive(counter)


## PART 3: cooldown suppresses re-triggers until simulated time elapses.
func _part_cooldown(player: Character) -> void:
	print("\n>>> PART 3: Cooldown Gate (elapsed time simulated via tick_cooldown)")
	var counter: TriggerCounter = TriggerCounter.new()
	counter.id = &"cooldown_counter"
	var dash_trigger: Array[StringName] = [&"ability.dash"]
	counter.trigger_tags = dash_trigger
	counter.cooldown = 0.25
	player.passive_ability_component.add_passive_instance(counter)

	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 1:
		_fail("Cooldown did not suppress the immediate re-trigger. Got %d" % counter.activations)
		return
	counter.tick_cooldown(counter.cooldown)
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if counter.activations != 2:
		_fail("Passive did not re-trigger after its own cooldown elapsed.")
		return
	_pass("Cooldown gate suppresses and re-allows activations.")
	player.passive_ability_component.remove_passive(counter)


## PART 4: the completion filter discriminates interrupted vs completed events.
func _part_completion_filter(player: Character) -> void:
	print("\n>>> PART 4: Built-in Completion Filter")
	var dash_trigger: Array[StringName] = [&"ability.dash"]
	var strict: TriggerCounter = TriggerCounter.new()
	strict.id = &"strict_counter"
	strict.trigger_tags = dash_trigger
	strict.require_completion = true
	var lenient: TriggerCounter = TriggerCounter.new()
	lenient.id = &"lenient_counter"
	lenient.trigger_tags = dash_trigger
	lenient.require_completion = false
	player.passive_ability_component.add_passive_instance(strict)
	player.passive_ability_component.add_passive_instance(lenient)

	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED, {"completed": false}))
	if strict.activations != 0 or lenient.activations != 1:
		_fail("Interrupted event routing wrong (strict %d, lenient %d)." % [strict.activations, lenient.activations])
		return
	player.broadcast_ability_event(_make_event(dash_trigger, AbilityEvent.Phase.ENDED))
	if strict.activations != 1 or lenient.activations != 2:
		_fail("Unreported completion routing wrong (strict %d, lenient %d)." % [strict.activations, lenient.activations])
		return
	_pass("Completion filter discriminates interrupted vs completed events.")
	player.passive_ability_component.remove_passive(strict)
	player.passive_ability_component.remove_passive(lenient)


## PART 5: payloads spawn at the event position with wielder attribution and
## relative damage; property overrides tune a shared payload scene per passive.
func _part_payload(player: Character) -> void:
	print("\n>>> PART 5: Payload Spawning, Attribution, and Property Overrides")
	var passive_scene: PackedScene = load("res://Passives/passive_dash_explosion.tscn") as PackedScene
	player.passive_ability_component.add_passive(passive_scene)

	var enemy_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	var enemy: Character = enemy_scene.instantiate() as Character
	enemy.position = Vector3(2.0, 0.0, 0.0)
	add_child(enemy)
	if enemy.ai_state_machine != null:
		enemy.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if enemy.state_machine != null:
		enemy.state_machine.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().process_frame

	var hp_before: float = enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var blast_origin: Vector3 = Vector3.ZERO
	var dash_trigger: Array[StringName] = [&"ability.dash"]
	var event: AbilityEvent = _make_event(dash_trigger, AbilityEvent.Phase.STARTED)
	event.position = blast_origin
	player.broadcast_ability_event(event)
	for _i: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame

	var explosion: GroundDamageArea = _newest_payload()
	if explosion == null:
		_fail("No explosion payload spawned on the dash STARTED event.")
		return
	if not explosion.position.is_equal_approx(blast_origin):
		_fail("Explosion did not spawn at the event position. Got %s" % explosion.position)
		return
	if explosion.wielder != player:
		_fail("Explosion wielder is not the passive owner.")
		return
	var hp_after: float = enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var expected: float = explosion.damage * enemy.attribute_component.get_damage_multiplier(&"physical")
	if not is_equal_approx(hp_before - hp_after, expected):
		_fail("Enemy took wrong relative damage. Expected %f, got %f" % [expected, hp_before - hp_after])
		return
	_pass("Payload spawns at event position with wielder attribution and scaled relative damage.")

	# Property override plumbing: one shared payload scene, tuned per passive.
	var radius_override: PayloadPropertyOverride = PayloadPropertyOverride.new()
	radius_override.value_type = PayloadPropertyOverride.ValueType.FLOAT
	radius_override.property = &"radius"
	radius_override.float_value = 4.25
	var probe: PayloadPassiveAbility = PayloadPassiveAbility.new()
	probe.id = &"override_probe"
	var probe_trigger: Array[StringName] = [&"ability.probe"]
	probe.trigger_tags = probe_trigger
	probe.payload_scene = load("res://Hazards/explosion.tscn") as PackedScene
	probe.scale_with_attack = false
	probe.payload_overrides.append(radius_override)
	player.passive_ability_component.add_passive_instance(probe)

	var probe_tag: Array[StringName] = [&"ability.probe"]
	var before_probes: int = payload_spawns
	var probe_event: AbilityEvent = _make_event(probe_tag, AbilityEvent.Phase.ENDED)
	probe_event.position = Vector3(20.0, 0.0, 0.0)
	player.broadcast_ability_event(probe_event)
	for _i: int in range(5):
		await get_tree().physics_frame
	await get_tree().process_frame
	var probe_payload: GroundDamageArea = _newest_payload()
	if probe_payload == null or payload_spawns != before_probes + 1:
		_fail("Override probe payload did not spawn exactly once.")
		return
	if not is_equal_approx(probe_payload.radius, radius_override.float_value):
		_fail("Property override was not applied. Expected %f, got %f" % [radius_override.float_value, probe_payload.radius])
		return
	_pass("Property overrides patch shared payload scenes per passive.")

	# Unknown property names warn loudly and leave the payload untouched.
	var bogus: PayloadPropertyOverride = PayloadPropertyOverride.new()
	bogus.value_type = PayloadPropertyOverride.ValueType.FLOAT
	bogus.property = &"no_such_property"
	bogus.float_value = 99.0
	probe.payload_overrides.append(bogus)
	var bogus_event: AbilityEvent = _make_event(probe_tag, AbilityEvent.Phase.ENDED)
	bogus_event.position = Vector3(30.0, 0.0, 0.0)
	player.broadcast_ability_event(bogus_event)
	for _i: int in range(5):
		await get_tree().physics_frame
	var bogus_payload: GroundDamageArea = _newest_payload()
	if bogus_payload == null or not bogus_payload.position.is_equal_approx(Vector3(30.0, 0.0, 0.0)):
		_fail("Payload with an unknown override property failed to spawn at its position.")
		return
	if not is_equal_approx(bogus_payload.radius, radius_override.float_value):
		_fail("An unknown override property modified the payload unexpectedly.")
		return
	_pass("Unknown override properties are ignored without breaking spawns.")

	player.passive_ability_component.remove_passive(probe)
	player.passive_ability_component.remove_passives(&"dash_explosion")
	enemy.queue_free()
	await get_tree().physics_frame


## PART 6: end-to-end dash detonation through the real state machine, including
## interrupted dashes and the require_completion gate.
func _part_dash_integration(player: Character) -> void:
	print("\n>>> PART 6: End-to-End Dash Detonation via the State Machine")
	var passive_scene: PackedScene = load("res://Passives/passive_dash_explosion.tscn") as PackedScene
	player.passive_ability_component.add_passive(passive_scene)
	TestUtils.clear_lock_and_hold_facing(player)

	var before: int = payload_spawns
	var start_pos: Vector3 = player.global_position
	player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	# The takeoff detonation spawns synchronously with the state enter. Assert
	# its position now: payloads self-free on their visual_duration, so node
	# references must never be held across waits in these assertions.
	var takeoff: GroundDamageArea = _newest_payload()
	if takeoff == null or not is_instance_valid(takeoff) or takeoff.position.distance_to(start_pos) > 1.0:
		_fail("Dash explosion did not detonate at the dash start position.")
		return
	for _i: int in range(30):
		await get_tree().physics_frame
	await get_tree().process_frame
	if payload_spawns != before + 1:
		_fail("Dash did not spawn exactly one explosion. Got %d, expected 1" % (payload_spawns - before))
		return
	_pass("Dash detonates exactly once at takeoff.")

	# A dash cancelled right after takeoff keeps its detonation: the STARTED
	# event already fired before any interruption could happen.
	before = payload_spawns
	player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	await get_tree().physics_frame
	player.state_machine.request_state("PlayerRun")
	for _i: int in range(10):
		await get_tree().physics_frame
	await get_tree().process_frame
	if payload_spawns != before + 1:
		_fail("Interrupted dash lost its takeoff explosion. Got %d, expected 1" % (payload_spawns - before))
		return
	_pass("Interrupted dash keeps its takeoff detonation.")

	# The same payload behind a require_completion passive stays silent on
	# interruptions and fires on natural completion.
	player.passive_ability_component.remove_passives(&"dash_explosion")
	var strict: PayloadPassiveAbility = PayloadPassiveAbility.new()
	strict.id = &"strict_dash"
	var dash_trigger: Array[StringName] = [&"ability.dash"]
	strict.trigger_tags = dash_trigger
	strict.require_completion = true
	strict.payload_scene = load("res://Hazards/explosion.tscn") as PackedScene
	player.passive_ability_component.add_passive_instance(strict)

	before = payload_spawns
	player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	await get_tree().physics_frame
	player.state_machine.request_state("PlayerRun")
	for _i: int in range(10):
		await get_tree().physics_frame
	await get_tree().process_frame
	if payload_spawns != before:
		_fail("require_completion passive fired on an interrupted dash.")
		return
	player.state_machine.request_state("PlayerDash", {"direction": Vector3.FORWARD})
	for _i: int in range(30):
		await get_tree().physics_frame
	await get_tree().process_frame
	if payload_spawns != before + 1:
		_fail("require_completion passive did not fire on a completed dash.")
		return
	_pass("Completion filter gates real dash interruptions end-to-end.")
	player.passive_ability_component.remove_passives(&"strict_dash")


## PART 7: payloads spawned from inside physics query flushing (a passive
## reacting to a body_entered callback, e.g. the exit portal's during a scene
## transition) must arm their hitbox without hitting the Area3D lock ("Function
## blocked during in/out signal") and still land hits on pre-existing victims.
func _part_flush_spawn(player: Character) -> void:
	print("\n>>> PART 7: Flush-Context Payload Spawn (exit-portal regression)")
	var passive_scene: PackedScene = load("res://Passives/passive_dash_explosion.tscn") as PackedScene
	player.passive_ability_component.add_passive(passive_scene)

	# Victim standing at the future blast origin.
	var enemy_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	var enemy: Character = enemy_scene.instantiate() as Character
	enemy.position = Vector3(40.0, 0.0, 0.0)
	add_child(enemy)
	if enemy.ai_state_machine != null:
		enemy.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	if enemy.state_machine != null:
		enemy.state_machine.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().process_frame

	# Probe trigger area whose body_entered dispatch runs during physics flush.
	# Elevated clear of the floor so only the dropped probe body enters it.
	var trigger_area: Area3D = Area3D.new()
	trigger_area.collision_layer = 0
	trigger_area.collision_mask = 1
	var trigger_shape: CollisionShape3D = CollisionShape3D.new()
	var trigger_sphere: SphereShape3D = SphereShape3D.new()
	trigger_sphere.radius = 2.0
	trigger_shape.shape = trigger_sphere
	trigger_area.add_child(trigger_shape)
	trigger_area.position = Vector3(40.0, 3.0, 6.0)
	add_child(trigger_area)
	await get_tree().physics_frame
	trigger_area.body_entered.connect(_on_flush_probe_body_entered)

	var hp_before: float = enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var spawns_before: int = payload_spawns
	_flush_player = player
	_flush_origin = Vector3(40.0, 0.0, 0.0)

	var probe_body: StaticBody3D = StaticBody3D.new()
	probe_body.collision_layer = 1
	var body_shape: CollisionShape3D = CollisionShape3D.new()
	var body_sphere: SphereShape3D = SphereShape3D.new()
	body_sphere.radius = 0.5
	body_shape.shape = body_sphere
	probe_body.add_child(body_shape)
	probe_body.position = Vector3(40.0, 3.0, 6.0)
	add_child(probe_body)

	for _i: int in range(6):
		await get_tree().physics_frame
	await get_tree().process_frame

	if payload_spawns != spawns_before + 1:
		_fail("Flush-context spawn did not produce exactly one payload. Got %d" % (payload_spawns - spawns_before))
		return
	var explosion: GroundDamageArea = _newest_payload()
	if explosion == null or not explosion.position.is_equal_approx(_flush_origin):
		_fail("Flush-context payload missing or at the wrong position.")
		return
	var hitbox: Area3D = explosion._get_damage_hitbox()
	if hitbox == null or not hitbox.monitoring:
		_fail("Flush-context payload hitbox never armed (Area3D lock not worked around).")
		return
	var hp_after: float = enemy.attribute_component.get_current(AttributeComponent.POOL_HEALTH)
	var expected: float = explosion.damage * enemy.attribute_component.get_damage_multiplier(&"physical")
	if not is_equal_approx(hp_before - hp_after, expected):
		_fail("Flush-context blast dealt wrong relative damage. Expected %f, got %f" % [expected, hp_before - hp_after])
		return
	_pass("Flush-context payload arms deferred and still lands hits.")

	player.passive_ability_component.remove_passives(&"dash_explosion")
	enemy.queue_free()
	probe_body.queue_free()
	trigger_area.queue_free()
	await get_tree().physics_frame


## PART 8: the landing blast fires exactly once per airborne episode, from
## whatever state the character touches down - a jump that turns into a jump
## kick mid-flight must still give exactly one detonation, because the episode
## is tracked on the Character (grounded<->airborne edge), not on any state.
func _part_landing_blast(player: Character) -> void:
	print("\n>>> PART 8: Landing Blast (jump -> jump kick -> land, one detonation)")
	var passive_scene: PackedScene = load("res://Passives/passive_landing_blast.tscn") as PackedScene
	if passive_scene == null:
		_fail("Could not load Passives/passive_landing_blast.tscn (parse error?).")
		return
	player.passive_ability_component.add_passive(passive_scene)
	TestUtils.clear_lock_and_hold_facing(player)

	var spawns_before: int = payload_spawns
	player.state_machine.request_state("PlayerJump", {"direction": Vector3.ZERO})

	# Switch into the jump kick exactly like the attack input would mid-flight,
	# then ride whatever states follow down to the ground. The movement.airborne
	# character tag marks the episode's span and doubles as its lifecycle check.
	var kick_switched: bool = false
	var landed: bool = false
	for _i: int in range(150):
		await get_tree().physics_frame
		if not kick_switched and player.has_tag(Character.TAG_AIRBORNE):
			player.state_machine.request_state("PlayerJumpKick")
			kick_switched = true
		elif kick_switched and not player.has_tag(Character.TAG_AIRBORNE):
			landed = true
			break
	if not kick_switched:
		_fail("Player never reported the airborne episode during the jump.")
		return
	if not landed:
		_fail("Player never landed after the mid-air jump kick.")
		return

	await get_tree().process_frame
	if payload_spawns != spawns_before + 1:
		_fail("Airborne episode produced %d detonations, expected exactly 1." % (payload_spawns - spawns_before))
		return
	var explosion: GroundDamageArea = _newest_payload()
	if explosion == null or explosion.position.distance_to(player.global_position) > 1.0:
		_fail("Landing blast did not detonate at the landing position.")
		return
	_pass("Jump -> jump kick -> land produced exactly one landing detonation.")
