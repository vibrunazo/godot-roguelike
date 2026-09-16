## AI state where the mind orders an attack action on the physical body and transitions upon completion.
class_name AIAttack
extends AIState

## The name of the physical attack state on the body StateMachine to execute.
@export var attack_state_name: String = "EnemyAttack"
## Potential AI states to transition to randomly after the attack finishes.
@export var next_states: Array[AIState] = []
## Total facing cone in degrees toward the target required before ordering the
## attack (90.0 = within 45 degrees either side). 360.0 orders regardless of
## facing; 0.0 waits for perfect alignment. While outside the cone the mind
## turns the body toward the target at its rotation speed limit and only
## orders once inside it, so attacks never start while facing away.
@export var desired_angle: float = 90.0

var _internal_cooldown: float = 0.0
var _internal_cooldown_timer: float = 0.0
var _attack_ordered: bool = false

## Cooldown time in seconds between attack executions (delegates to physical attack state if present).
var cooldown: float:
	get:
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown" in att:
			return att.cooldown
		return _internal_cooldown
	set(val):
		_internal_cooldown = val
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown" in att:
			att.cooldown = val

## Remaining cooldown time in seconds before this attack can be executed again (delegates to physical attack state).
var cooldown_timer: float:
	get:
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown_timer" in att:
			return att.cooldown_timer
		return _internal_cooldown_timer
	set(val):
		_internal_cooldown_timer = val
		var att: CharacterState = get_attack_state()
		if att != null and "cooldown_timer" in att:
			att.cooldown_timer = val


## Helper to look up the physical attack state on the body StateMachine.
func get_attack_state() -> CharacterState:
	if character == null or character.state_machine == null:
		return null
	return character.state_machine.get_node_or_null(attack_state_name) as CharacterState


## Returns true if this attack is currently on cooldown.
func is_on_cooldown() -> bool:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("is_on_cooldown"):
		return att.is_on_cooldown()
	return cooldown_timer > 0.0


## Updates the cooldown timer while this state is inactive so cooldown progresses.
func evaluate_trigger(delta: float) -> bool:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("tick_cooldown"):
		att.tick_cooldown(delta)
	elif _internal_cooldown_timer > 0.0:
		_internal_cooldown_timer -= delta
	return false


func enter(_previous_state_path: String, _data := {}) -> void:
	cooldown_timer = cooldown
	_attack_ordered = false
	if ai_state_machine != null:
		ai_state_machine.command_stop()
	# Ordering waits for the aim gate in physics_update: the mind first turns
	# the body toward the target and only orders inside the desired_angle cone.


func physics_update(delta: float) -> void:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("tick_cooldown"):
		att.tick_cooldown(delta)
	elif _internal_cooldown_timer > 0.0:
		_internal_cooldown_timer -= delta
	if character == null or not character.is_inside_tree() or ai_state_machine == null or not character.is_alive():
		return
	ai_state_machine.command_stop()
	if _attack_ordered:
		if character.state_machine == null or character.state_machine.state == null or character.state_machine.state.name != attack_state_name:
			_finish_attack()
		return
	_try_order_attack(delta)


## Turns the body toward the current target at its rotation speed limit and
## orders the attack once facing falls inside the desired_angle cone. After
## ordering the mind stops rotating entirely: later tracking is the body's own
## snapshot aim, so sidestepping after the animation starts can still dodge it.
func _try_order_attack(delta: float) -> void:
	if ai_state_machine == null or character == null:
		_finish_attack()
		return
	var target: Character = ai_state_machine.get_target()
	if target == null:
		_finish_attack()
		return
	character.look_at_target(target.global_position, delta)
	if not _is_within_cone(target):
		return
	# The order only sets the desired facing; the body turns toward it at
	# its rotation speed limit once the attack state snapshots this aim.
	var order_data: Dictionary = {}
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if not to_target.is_zero_approx():
		order_data["aim"] = to_target.normalized()
	_attack_ordered = ai_state_machine.order_attack(attack_state_name, false, order_data)
	if not _attack_ordered:
		# The body is unable to attack (e.g. stunned/falling): leave like a
		# finished attack. Already inside physics_update, so no deferral is
		# needed for the transition.
		_finish_attack()


## True when the mount facing falls inside the desired_angle cone centered on
## the target direction (360.0 = anywhere, 0.0 = perfect alignment only). A
## target stacked exactly on the body has no defined direction and counts as
## aligned so the mind can never stall waiting for an aim that cannot exist.
func _is_within_cone(target: Character) -> bool:
	if desired_angle >= 360.0:
		return true
	if character == null or character.mesh_mount == null:
		return false
	var facing: Vector3 = character.mesh_mount.global_transform.basis.z
	facing.y = 0.0
	if facing.is_zero_approx():
		return false
	var to_target: Vector3 = target.global_position - character.global_position
	to_target.y = 0.0
	if to_target.is_zero_approx():
		return true
	var angle: float = rad_to_deg(acos(clampf(facing.normalized().dot(to_target.normalized()), -1.0, 1.0)))
	# The 0.05-degree hair covers float dust from the final exact step, so a
	# 0.0 cone still opens on true alignment instead of stalling forever.
	return angle <= maxf(desired_angle, 0.0) * 0.5 + 0.05


func exit() -> void:
	_attack_ordered = false


func end_attack() -> void:
	_finish_attack()


func _finish_attack() -> void:
	_attack_ordered = false
	if character != null and not character.is_alive():
		return
	if ai_state_machine != null:
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position, character.get_physics_process_delta_time())
	if not next_states.is_empty():
		var chosen_state: AIState = next_states.pick_random()
		if chosen_state != null:
			finished.emit(chosen_state.name)
