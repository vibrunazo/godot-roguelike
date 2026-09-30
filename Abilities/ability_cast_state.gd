## One active ability slot on a character's body StateMachine. The slot is a
## fixed node wired in the scene (its return, fall, dash and jump states are
## plain exports); the AbilitySystemComponent puts an AbilityResource in it
## (set_ability()) or clears it. Casting runs the shared CharacterAction flow
## (animation, aim toward the auto-aim target, cooldown, tags, events), pays
## the ability's cost, and at release_time spawns its payload from
## cast_origin through PayloadSpawner and applies its caster effects.
## An empty slot can never be activated.
class_name AbilityCastState
extends CharacterAction

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
	var direction: Vector3 = _release_direction()
	if ability.payload_scene != null and cast_origin != null:
		PayloadSpawner.spawn(ability.payload_scene, character, cast_origin.global_position, direction, ability.payload_overrides, ability.damage_multiplier, ability.scale_with_attack)
	if character.attribute_component != null:
		for effect: GameplayEffect in ability.caster_effects:
			if effect != null:
				character.attribute_component.apply_effect(effect)
	broadcast_ability_event(AbilityEvent.Phase.ACTIVE, {}, direction)
	released.emit(ability)


## Toward the current target when one is valid (it may have moved since the
## cast started), else along the snapshotted aim, else the facing.
func _release_direction() -> Vector3:
	var target: Node3D = character.current_target
	if target != null and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - character.global_position
		to_target.y = 0.0
		if not to_target.is_zero_approx():
			return to_target.normalized()
	var flat: Vector3 = Vector3(aim_direction.x, 0.0, aim_direction.z)
	if not flat.is_zero_approx():
		return flat.normalized()
	if character.mesh_mount != null:
		return character.mesh_mount.global_basis.z
	return Vector3.FORWARD


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
