## One active ability slot on a character's body StateMachine. The slot is a
## fixed node wired in the scene (its return, fall, dash and jump states are
## plain exports); the AbilitySystemComponent puts an AbilityResource in it
## (set_ability()) or clears it. Casting runs the shared CharacterAction flow
## (animation, aim toward the auto-aim target, cooldown, tags, events), pays
## the ability's cost, and at release_time spawns its payload from
## cast_origin through PayloadSpawner and applies its caster effects. The
## release is aimed then, from where cast_origin is at that moment, at the
## cast's aim target, as the ability's aim_mode says. A slot may cast from the
## air (a jump): an aimed release then angles down to the aimed point.
## An empty slot can never be activated.
class_name AbilityCastState
extends CharacterAction

## Below this horizontal distance, in meters, between the cast origin and the
## aimed point (the cursor on the caster itself) the point gives no reliable
## heading: the release goes along the cast's aim_direction instead.
const MIN_AIM_DISTANCE: float = 0.3

## Emitted when the payload is released (the cast did its job).
signal released(ability: AbilityResource)

## Where the payload spawns (a marker at chest height, a hand bone, ...).
@export var cast_origin: Node3D

## The ability in this slot; null for an empty slot. Set through set_ability().
var ability: AbilityResource = null

## True once this cast released its payload.
var _released: bool = false
var _release_timer: SceneTreeTimer


func _ready() -> void:
	super._ready()
	if cast_origin == null:
		push_error("%s: cast_origin is not set." % name)


## Puts ability in this slot (null empties it): the shared action fields are
## loaded from the resource and the slot's cooldown restarts from the
## ability's starting_cooldown.
func set_ability(new_ability: AbilityResource) -> void:
	ability = new_ability
	if ability == null:
		ability_tags = []
		cooldown = 0.0
		cooldown_timer = 0.0
		return
	var tags: Array[StringName] = []
	tags.assign(ability.ability_tags)
	ability_tags = tags
	animation_name = ability.cast_animation
	movement_speed = ability.movement_speed
	cancelable = ability.cancelable
	uninterruptable = ability.uninterruptable
	float_in_air = ability.float_in_air
	cooldown = ability.cooldown
	starting_cooldown = ability.starting_cooldown
	cooldown_timer = ability.starting_cooldown
	var required: Array[StringName] = []
	required.assign(ability.required_tags)
	required_tags = required
	var blocked: Array[StringName] = []
	blocked.assign(ability.blocked_tags)
	blocked_tags = blocked
	_was_tag_enabled = _check_tags()


## Fraction of the cooldown still to run (1.0 just cast, 0.0 ready).
func get_cooldown_fraction() -> float:
	if ability == null or cooldown <= 0.0:
		return 0.0
	return clampf(cooldown_timer / cooldown, 0.0, 1.0)


## False for an empty slot; otherwise the cooldown and tag gates plus the
## ability's cost.
func can_activate() -> bool:
	if ability == null:
		return false
	if not super.can_activate():
		return false
	return _can_pay_cost()


func _can_pay_cost() -> bool:
	if ability.cost_amount <= 0.0:
		return true
	var attributes: AttributeComponent = character.attribute_component if character != null else null
	return attributes != null and attributes.get_current(ability.cost_pool) >= ability.cost_amount


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	_released = false
	if ability == null:
		push_error("%s: entered with no ability in the slot." % name)
		finish_action("")
		return
	super.enter(_previous_state_path, _data)
	if character == null:
		return
	if ability.cost_amount > 0.0 and character.attribute_component != null:
		character.attribute_component.damage_pool(ability.cost_pool, ability.cost_amount)
	_release_timer = get_tree().create_timer(maxf(ability.release_time, 0.0), true, true)
	_release_timer.timeout.connect(_release)


## Spawns the payload toward the target (or the snapshotted aim), applies the
## caster effects and reports the ACTIVE lifecycle point.
func _release() -> void:
	if _released or character == null or not character.is_inside_tree() or not character.is_alive():
		return
	if character.state_machine == null or character.state_machine.state != self:
		return
	_released = true
	var origin: Vector3 = cast_origin.global_position if cast_origin != null else character.global_position
	var aim: AimTarget = _release_aim()
	var direction: Vector3 = _release_direction(origin, aim)
	var landing: Vector3 = PayloadSpawner.NO_LANDING_POINT
	if ability.aim_mode == AbilityResource.AimMode.GROUND and aim.has_point:
		landing = aim.floor_point
	if ability.payload_scene != null and cast_origin != null:
		PayloadSpawner.spawn(ability.payload_scene, character, origin, direction, ability.payload_overrides, ability.damage_multiplier, ability.scale_with_attack, landing)
	if character.attribute_component != null:
		for effect: GameplayEffect in ability.caster_effects:
			if effect != null:
				character.attribute_component.apply_effect(effect)
	broadcast_ability_event(AbilityEvent.Phase.ACTIVE, {}, direction)
	released.emit(ability)


## The current target when one is valid (it may have moved since the cast
## started), else the aim snapshotted when the cast started.
func _release_aim() -> AimTarget:
	var target: Node3D = character.current_target
	if target != null and is_instance_valid(target):
		return AimTarget.at_node(target)
	return aim_target


## The direction to release along from origin at aim, by the ability's
## aim_mode: AIMED straight at what the caster sees at its cast height above
## the aimed floor (origin's height above the caster's feet), FLAT level
## toward what it sees at origin's height, GROUND level toward the aimed floor
## point (a lobbed payload is given that point to land on).
func _release_direction(origin: Vector3, aim: AimTarget) -> Vector3:
	var point: Vector3
	match ability.aim_mode:
		AbilityResource.AimMode.FLAT:
			point = aim.point_at_y(origin.y)
		AbilityResource.AimMode.GROUND:
			point = aim.floor_point
		_:
			point = aim.point_at_height(origin.y - character.get_feet_position().y)
	var to_point: Vector3 = point - origin
	var flat: Vector3 = Vector3(to_point.x, 0.0, to_point.z)
	if flat.length() < MIN_AIM_DISTANCE:
		if not aim_direction.is_zero_approx():
			return aim_direction
		return character.mesh_mount.global_basis.z.normalized() if character.mesh_mount != null else Vector3.BACK
	if ability.aim_mode == AbilityResource.AimMode.AIMED:
		return to_point.normalized()
	return flat.normalized()


## Committed until release: no order may interrupt the cast before its
## payload leaves (a dash still can when the ability is cancelable).
func accepts_orders() -> bool:
	return _released


## Before release a jump never cancels the cast; after it, the cancel window applies.
func check_jump(launch_ratio: float = -1.0) -> bool:
	if not _released:
		if character != null:
			character.consume_jump_request()
		return false
	return super.check_jump(launch_ratio)


## Before release another ability never cancels the cast; after it, the
## cancel window applies.
func _allows_ability() -> bool:
	return _released and super._allows_ability()


func _is_completed() -> bool:
	return _released


func exit() -> void:
	if _release_timer != null:
		disconnect_safe(_release_timer.timeout, _release)
		_release_timer = null
	super.exit()
