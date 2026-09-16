## AI state that evaluates custom conditions (cooldown, range, stun state) while inactive
## and preemptively interrupts the active AI state to execute a specialized attack.
class_name AIConditionalAttack
extends AIState

## The name of the physical attack state on the body StateMachine to execute.
@export var attack_state_name: String = "EnemyAttack"
## Maximum distance to target to trigger this attack.
@export var trigger_range: float = 3.5
## Minimum distance to target to trigger this attack (0.0 = no minimum).
@export var min_range: float = 0.0
## Whether this attack can be ordered even if the physical body is currently in EnemyStun.
@export var can_break_stun: bool = true
## Total facing cone in degrees toward the target required before ordering the
## attack (90.0 = within 45 degrees either side). 360.0 orders regardless of
## facing; 0.0 waits for perfect alignment. While outside the cone the mind
## turns the body toward the target at its rotation speed limit and only
## orders once inside it, so attacks never start while facing away.
@export var desired_angle: float = 90.0
## AI state to transition to after the attack animation finishes.
@export var next_state: AIState

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

## Remaining cooldown time in seconds before this attack can trigger again (delegates to physical attack state).
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
	var target_name: String = attack_state_name
	if target_name.is_empty() and "ability_state_name" in self:
		var custom_name: Variant = self.get("ability_state_name")
		if custom_name is String and not (custom_name as String).is_empty():
			target_name = custom_name as String
	return character.state_machine.get_node_or_null(target_name) as CharacterState


## Returns true if this attack is currently on cooldown.
func is_on_cooldown() -> bool:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("is_on_cooldown"):
		return att.is_on_cooldown()
	return cooldown_timer > 0.0


## Evaluates whether this conditional attack is ready to trigger and preempt the active state.
func evaluate_trigger(delta: float) -> bool:
	var att: CharacterState = get_attack_state()
	if att != null and att.has_method("tick_cooldown"):
		att.tick_cooldown(delta)
	elif _internal_cooldown_timer > 0.0:
		_internal_cooldown_timer -= delta

	if character == null or not character.is_inside_tree() or not character.is_alive():
		return false
	if is_on_cooldown():
		return false
	if att != null and att.has_method("can_activate") and not att.can_activate():
		return false
	if ai_state_machine == null:
		return false

	var target: Character = ai_state_machine.get_target()
	if target == null:
		return false

	var dist_sq: float = character.global_position.distance_squared_to(target.global_position)
	if dist_sq > (trigger_range * trigger_range):
		return false
	if min_range > 0.0 and dist_sq < (min_range * min_range):
		return false

	if character.state_machine == null or character.state_machine.state == null:
		return false

	var current_body_state: String = character.state_machine.state.name
	if current_body_state == attack_state_name or current_body_state == "EnemyDefeat" or current_body_state == "EnemyFall":
		return false
	if current_body_state == "EnemyStun" and not can_break_stun:
		return false

	ai_state_machine.request_state(name)
	return true


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	cooldown_timer = cooldown
	_attack_ordered = false
	if ai_state_machine != null:
		ai_state_machine.command_stop()
	# Ordering waits for the aim gate in physics_update: the mind first turns
	# the body toward the target and only orders inside the desired_angle cone.


func physics_update(delta: float) -> void:
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
	if not is_facing_within_cone(target, desired_angle):
		return
	# The order only sets the desired facing; the body turns toward it at
	# its rotation speed limit once the attack state snapshots this aim.
	var order_data: Dictionary = build_aim_order_data(target)
	_attack_ordered = ai_state_machine.order_attack(attack_state_name, can_break_stun, order_data)
	if not _attack_ordered:
		# The body is unable to attack (e.g. stunned): leave like a finished
		# attack. Already inside physics_update, so no deferral is needed for
		# the transition.
		_finish_attack()


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
	if next_state != null:
		finished.emit(next_state.name)
