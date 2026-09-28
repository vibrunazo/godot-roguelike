## Shared execution half of the AI states that order a body attack or ability
## (AIAttack, AIConditionalAttack): on entry the mind stops the body, turns it
## toward the target at its rotation speed limit, and orders body_state once
## the facing falls inside desired_angle; it then waits for the body to leave
## that state and moves to _next_state(). Subclasses decide when the state is
## entered (by flow, or preemptively from evaluate_trigger) and where it goes
## next. The cooldown belongs to the body state, which ticks it and starts it
## when the attack actually runs: this state only reads it, so an order the
## body refuses costs nothing.
class_name AIAttackBase
extends AIState

## The body state (an attack or ability on the body StateMachine) this state
## orders.
@export var body_state: CharacterState
## Total facing cone in degrees toward the target required before ordering the
## attack (90.0 = within 45 degrees either side). 360.0 orders regardless of
## facing; 0.0 waits for perfect alignment. While outside the cone the mind
## turns the body toward the target at its rotation speed limit and only
## orders once inside it, so attacks never start while facing away.
@export var desired_angle: float = 90.0

## True once the body took the order; the state then waits for it to finish.
var _attack_ordered: bool = false


func _ready() -> void:
	super._ready()
	if body_state == null:
		push_error("%s: body_state is not set." % name)


## Whether body_state is on its cooldown (read from the body state).
func is_on_cooldown() -> bool:
	return body_state != null and body_state.is_on_cooldown()


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
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
		if character.state_machine == null or character.state_machine.state != body_state:
			_finish_attack()
		return
	_try_order_attack(delta)


func exit() -> void:
	_attack_ordered = false


## Whether the order may break the body out of its stun state.
func _breaks_stun() -> bool:
	return false


## The mind state to move to once the attack is over (or was refused); null
## stays put.
func _next_state() -> AIState:
	return null


## Turns the body toward the current target at its rotation speed limit and
## orders the attack once facing falls inside the desired_angle cone. After
## ordering the mind stops rotating entirely: later tracking is the body's own
## snapshot aim, so sidestepping after the animation starts can still dodge it.
func _try_order_attack(delta: float) -> void:
	var target: Character = ai_state_machine.get_target()
	if target == null:
		_finish_attack()
		return
	character.look_at_target(target.global_position, delta)
	if not is_facing_within_cone(target, desired_angle):
		return
	# The order only sets the desired facing; the body turns toward it at
	# its rotation speed limit once the attack state snapshots this aim.
	_attack_ordered = ai_state_machine.order_attack(body_state, _breaks_stun(), build_aim_order_data(target))
	if not _attack_ordered:
		# The body is unable to attack (e.g. stunned or falling): leave like a
		# finished attack. Already inside physics_update, so no deferral is
		# needed for the transition.
		_finish_attack()


## Faces the target once more and hands over to _next_state().
func _finish_attack() -> void:
	_attack_ordered = false
	if character != null and not character.is_alive():
		return
	if ai_state_machine != null:
		var target: Character = ai_state_machine.get_target()
		if target != null and character != null:
			character.look_at_target(target.global_position, character.get_physics_process_delta_time())
	var next: AIState = _next_state()
	if next != null:
		finished.emit(next.name)
