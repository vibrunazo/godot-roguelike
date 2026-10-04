## One active ability slot on a character's body StateMachine. The slot is a
## fixed node wired in the scene (its return, fall, dash and jump states are
## plain exports); the AbilitySystemComponent puts an AbilityResource in it
## (set_ability()) or clears it. Casting runs the shared CharacterAction flow
## (animation, aim toward the auto-aim target, cooldown, tags, events), pays
## the ability's cost, and at release_time spawns its payload from the
## ability's release_point (cast_origin, or the caster's feet;
## release_payload(), aimed then by the ability's aim_mode from where that
## point is at that moment) and applies its caster effects. A slot
## may cast from the air (a jump): an aimed release then angles down to the
## aimed point. An ability with dash_speed lunges from its release (a
## charge), one with attach_payload carries its payload along, and one with
## cast_duration ends on the clock instead of with its animation. An empty
## slot can never be activated.
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
## Ends the cast after the ability's cast_duration (null without one).
var _duration_timer: SceneTreeTimer
## The payload this cast carries along (ability.attach_payload), removed on exit.
var _attached_payload: Node3D


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
		dash_speed = 0.0
		dash_duration = 0.0
		return
	var tags: Array[StringName] = []
	tags.assign(ability.ability_tags)
	ability_tags = tags
	animation_name = ability.cast_animation
	movement_speed = ability.movement_speed
	cancelable = ability.cancelable
	uninterruptable = ability.uninterruptable
	float_in_air = ability.float_in_air
	dash_speed = ability.dash_speed
	dash_duration = ability.dash_duration
	aim_mode = ability.aim_mode
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
	_apply_cast_speed()
	if ability.cost_amount > 0.0 and character.attribute_component != null:
		character.attribute_component.damage_pool(ability.cost_pool, ability.cost_amount)
	_release_timer = get_tree().create_timer(maxf(ability.release_time, 0.0), true, true)
	_release_timer.timeout.connect(_release)
	if ability.cast_duration > 0.0:
		_duration_timer = get_tree().create_timer(ability.cast_duration, true, true)
		_duration_timer.timeout.connect(_end_cast)


## Plays the cast animation at the ability's cast_speed (its state's TimeScale
## node; the AbilitySystemComponent reports a state without one when granted).
func _apply_cast_speed() -> void:
	var param: String = get_cast_speed_param()
	if character.animation_tree != null and character.animation_tree.get(param) is float:
		character.animation_tree.set(param, ability.cast_speed)


## AnimationTree parameter path of the cast animation's TimeScale node.
func get_cast_speed_param() -> String:
	return "parameters/" + animation_name + "/TimeScale/scale"


## Spawns the payload toward the target (or the snapshotted aim; attached to
## the caster when the ability asks), applies the caster effects, starts the
## ability's lunge and reports the ACTIVE lifecycle point.
func _release() -> void:
	if _released or character == null or not character.is_inside_tree() or not character.is_alive():
		return
	if character.state_machine == null or character.state_machine.state != self:
		return
	_released = true
	var origin: Vector3 = _release_origin()
	var direction: Vector3 = release_direction(origin)
	if ability.payload_scene != null:
		var parent: Node3D = character if ability.attach_payload else null
		var payload: Node3D = release_payload(ability.payload_scene, origin, ability.payload_overrides, ability.damage_multiplier, ability.scale_with_attack, parent)
		if ability.attach_payload:
			_attached_payload = payload
	if character.attribute_component != null:
		for effect: GameplayEffect in ability.caster_effects:
			if effect != null:
				character.attribute_component.apply_effect(effect)
	begin_lunge()
	broadcast_ability_event(AbilityEvent.Phase.ACTIVE, {}, direction)
	released.emit(ability)


## Ends the cast when its cast_duration runs out (while it still runs).
func _end_cast() -> void:
	if character == null or character.state_machine == null or character.state_machine.state != self:
		return
	finish_action("")


## Removes the payload this cast carried along: a damage area expires, any
## other payload is freed.
func _clear_attached_payload() -> void:
	if _attached_payload != null and is_instance_valid(_attached_payload):
		if _attached_payload is DamageArea:
			(_attached_payload as DamageArea).expire()
		else:
			_attached_payload.queue_free()
	_attached_payload = null


## Where the payload spawns now, by the ability's release_point.
func _release_origin() -> Vector3:
	if ability.release_point == AbilityResource.ReleasePoint.CASTER_FEET or cast_origin == null:
		return character.get_feet_position()
	return cast_origin.global_position


## Committed until release: no order may interrupt the cast before its
## payload leaves, and a cast that is not cancelable takes no order at all
## (a charge runs its course).
func accepts_orders() -> bool:
	return _released and cancelable


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
	if _duration_timer != null:
		disconnect_safe(_duration_timer.timeout, _end_cast)
		_duration_timer = null
	_clear_attached_payload()
	super.exit()
