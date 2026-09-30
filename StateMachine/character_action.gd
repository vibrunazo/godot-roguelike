## Shared base of every timed body action: melee attacks (CharacterAttack)
## and ability casts (AbilityCastState). It owns what they have in common: the
## cooldown and tag gates, the animation and the return to next_states when it
## finishes, the aim snapshot (toward the auto-aim target when one is locked),
## the cancel window for dash, jump and ability intents, gravity, and the
## STARTED/ENDED lifecycle events. Subclasses add what they do while running.
class_name CharacterAction
extends CharacterState

## Speed in m/s the character can steer at while this action runs (0.0 = stationary).
@export var movement_speed: float = 0.0
## Whether dash, jump and ability intents may cancel this action early. When
## off, those intents are consumed and dropped while it runs.
@export var cancelable: bool = false
## Whether the character keeps its height while this action runs in the air
## (for air combos). Off, gravity applies and the character falls.
@export var float_in_air: bool = false
## States to transition to when the action animation finishes (random pick;
## single-element arrays behave deterministically for ordered chains).
@export var next_states: Array[CharacterState]
## Name of the animation tree state played by this action.
@export var animation_name: String = "SlashAttack"
## Whether this action is uninterruptable (immune to stun interruption while active).
@export var uninterruptable: bool = false
## Cooldown time in seconds between executions (0.0 = ready immediately).
@export var cooldown: float = 0.0
## Initial cooldown in seconds applied when entering the scene (0.0 = ready immediately).
@export var starting_cooldown: float = 0.0
## Gameplay tags required on the character for this action to activate.
@export var required_tags: Array[StringName] = []
## Gameplay tags that block this action from activating if present on the character.
@export var blocked_tags: Array[StringName] = []
## If true, starts the cooldown timer when tag requirements transition from unmet to met.
@export var start_cooldown_on_enabled: bool = false

## Remaining cooldown time in seconds before this action can be executed again.
var cooldown_timer: float = 0.0
## Direction this action is aimed at, snapshotted on entry.
var aim_direction: Vector3 = Vector3.ZERO
var _was_tag_enabled: bool = false
## True once this action pointed character.aim_direction at its target, so
## exit() clears exactly that.
var _wrote_character_aim: bool = false


func _ready() -> void:
	cooldown_timer = starting_cooldown
	_was_tag_enabled = _check_tags()


## Returns true if this action is currently on cooldown.
func is_on_cooldown() -> bool:
	return cooldown_timer > 0.0


## Checks whether all required tags are present and no blocked tags are present.
func _check_tags() -> bool:
	if character == null:
		return true
	for tag: StringName in required_tags:
		if not character.has_tag(tag):
			return false
	for tag: StringName in blocked_tags:
		if character.has_tag(tag):
			return false
	return true


## Updates tag enablement and starts cooldown on transition if configured.
func _update_tag_enablement() -> void:
	var currently_enabled: bool = _check_tags()
	if currently_enabled and not _was_tag_enabled:
		if start_cooldown_on_enabled:
			cooldown_timer = cooldown
	_was_tag_enabled = currently_enabled


func is_uninterruptable() -> bool:
	return uninterruptable


## Returns true if both cooldown and tag requirements allow activation.
func can_activate() -> bool:
	_update_tag_enablement()
	if is_on_cooldown():
		return false
	return _check_tags()


## The action owns its cooldown and ticks it itself, every physics frame,
## whoever controls the body: controllers only read it (is_on_cooldown(),
## can_activate()), so nothing can tick it twice.
func _physics_process(delta: float) -> void:
	_update_tag_enablement()
	if cooldown_timer > 0.0:
		cooldown_timer = maxf(0.0, cooldown_timer - delta)


func physics_update(delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	# Dash and jump intents cancel the action only inside its cancel window
	# (see cancelable); attack intents go to check_attack().
	if check_dash():
		return
	if check_jump():
		return
	if check_ability():
		return
	check_attack()
	_before_motion(delta)
	var planar: Vector3 = _planar_velocity()
	character.velocity.x = planar.x
	character.velocity.z = planar.z
	_apply_gravity(delta)
	if _can_turn():
		character.look_toward_direction(aim_direction, delta)
	character.move_character()


## Virtual: per-frame bookkeeping before the motion is computed (hitstop).
func _before_motion(_delta: float) -> void:
	pass


## Virtual: the horizontal velocity for this frame.
func _planar_velocity() -> Vector3:
	return character.move_direction * movement_speed


## Virtual: whether the character may turn toward the aim this frame.
func _can_turn() -> bool:
	return true


## Falls under gravity while airborne unless float_in_air holds the height.
func _apply_gravity(delta: float) -> void:
	if float_in_air or character.is_on_floor():
		if character.velocity.y < 0.0 or float_in_air:
			character.velocity.y = 0.0
		return
	character.velocity += character.get_gravity() * delta


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	cooldown_timer = cooldown
	if character == null:
		return
	if uninterruptable and character.knockback_component != null:
		character.knockback_component.magnitude = Vector3.ZERO
	if character.animation_tree != null:
		character.animation_tree.change_immediate(animation_name)
		connect_one_shot(character.animation_tree.animation_finished, finish_action)
	character.is_attacking = true
	aim_direction = _resolve_aim(_data)
	_aim_at_current_target()
	broadcast_ability_event(AbilityEvent.Phase.STARTED, {}, aim_direction)


## The direction this action is aimed at, snapshotted on entry: the
## character's aim (the player's controller keeps it current), else the
## order's "aim", the movement direction, the facing, in that order.
func _resolve_aim(data: Dictionary) -> Vector3:
	if not character.aim_direction.is_zero_approx():
		return character.aim_direction
	if data.get("aim") is Vector3:
		return data["aim"]
	if not character.move_direction.is_zero_approx():
		return character.move_direction
	if character.mesh_mount != null:
		return character.mesh_mount.global_basis.z.normalized()
	return Vector3.ZERO


## Overrides the snapshotted aim with the direction to the character's
## current_target when one is valid, so actions rotate toward the auto-aim
## target instead of the mouse aim. Writes back to character.aim_direction so
## snapshot and intent stay consistent for the rest of the action.
func _aim_at_current_target() -> void:
	var target: Node3D = character.current_target
	if target == null or not is_instance_valid(target):
		return
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return
	aim_direction = to_target.normalized()
	character.aim_direction = aim_direction
	_wrote_character_aim = true


## Dash-cancel gate: only cancelable actions can be interrupted.
## The intent is still consumed when gated off so the press never leaks into a
## later state. Cancelling runs exit(), which cleans everything up.
func check_dash() -> bool:
	if not cancelable:
		if character != null:
			character.consume_dash_request()
		return false
	return super.check_dash()


## Jump-cancel gate: only cancelable actions can be jump-cancelled.
## The intent is consumed when gated off so the press never leaks into a later state.
func check_jump(launch_ratio: float = -1.0) -> bool:
	if not cancelable:
		if character != null:
			character.consume_jump_request()
		return false
	return super.check_jump(launch_ratio)


## Ability-cancel gate: only cancelable actions can be cancelled into a cast.
func _allows_ability() -> bool:
	return cancelable


## Attack presses are consumed and dropped while an action runs; attacks
## override this to queue their combo follow-up.
func check_attack() -> bool:
	if character != null:
		character.consume_attack_request()
	return false


## Virtual: whether the action ran to completion, reported with ENDED.
func _is_completed() -> bool:
	return true


func exit() -> void:
	if character != null:
		character.is_attacking = false
		# Undo only the aim this action set (toward its target); a
		# controller's own aim is its business.
		if _wrote_character_aim:
			character.aim_direction = Vector3.ZERO
		if character.animation_tree != null:
			disconnect_safe(character.animation_tree.animation_finished, finish_action)
	_wrote_character_aim = false
	broadcast_ability_event(AbilityEvent.Phase.ENDED, {"completed": _is_completed()}, aim_direction)


## Transitions to a random pick of next_states when the action animation finishes.
func finish_action(_animation_name: String) -> void:
	if character == null or character.state_machine == null or next_states.is_empty():
		return
	var next: CharacterState = next_states.pick_random()
	if next != null:
		character.state_machine.request_state(next.name)
