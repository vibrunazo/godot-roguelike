## Shared physical attack state for all characters (player combo hits and enemy attacks).
## Player chains use combo_next (ordered); enemies use next_states random-pick.
## Queue/cancel run through the same intent-driven checks (default off per node).
class_name CharacterAttack
extends CharacterState

## Speed at which the character can move while executing this attack (0.0 = stationary).
@export var movement_speed: float = 0.0
## Whether this attack state can be cancelled early by dashing.
@export var dash_cancel: bool = false
## Amount of damage dealt to health components caught in this attack.
@export var damage: float = 10.0
## Knockback impulse applied to entities hit by this attack.
@export var knockback: float = 15.0
## States to transition to when the attack animation finishes (random pick;
## single-element arrays behave deterministically for ordered chains).
@export var next_states: Array[CharacterState]
## Next attack state in the combo chain when an attack intent is queued (null = no chain).
@export var combo_next: CharacterState
## Time window (in seconds) after the attack starts to queue the next attack.
@export var queued_attack_time: float = 0.5
## Name of the animation to trigger on the animation tree for this attack.
@export var attack_animation_name: String = "SlashAttack"
## Reference to the AttackComponent handling damage dealing and hit collision exceptions.
@export var attack_component: AttackComponent
## Minimum interval (in seconds) before the same target can be hit again during this attack state.
@export var rehit_interval: float = 0.0
## Forward lunge speed applied from the attack's active phase. Leave at 0.0 to disable the lunge.
@export var dash_speed: float = 0.0
## Duration (in seconds) of the forward lunge. Leave at 0.0 to disable the lunge.
@export var dash_duration: float = 0.0

var queued_attack: bool = false
var attack_timer: SceneTreeTimer
var aim_direction: Vector3 = Vector3.ZERO
var lunging: bool = false
var lunge_direction: Vector3 = Vector3.ZERO
var lunge_timer: SceneTreeTimer
var lunge_slot: WeaponSlot


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	# Same shared checks both controllers drive: dash-cancel is gated by the
	# dash_cancel export below, attack intents queue the combo follow-up.
	check_dash()
	check_attack()
	if lunging:
		character.velocity = lunge_direction * dash_speed
	else:
		character.velocity = character.move_direction * movement_speed
	character.look_toward_direction(aim_direction, 1.0)
	character.move_and_slide()


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	queued_attack = false
	lunging = false
	lunge_direction = Vector3.ZERO
	lunge_slot = null
	if character == null:
		return
	if attack_component != null:
		attack_component.reset_exceptions()
		attack_component.damage = damage * character.get_damage_modifier()
		if character.mesh_mount != null:
			attack_component.knockback = character.mesh_mount.global_basis.z * knockback
		else:
			attack_component.knockback = character.global_basis.z * knockback
		attack_component.rehit_interval = rehit_interval

	if character.animation_tree != null:
		character.animation_tree.change_immediate(attack_animation_name)
		connect_one_shot(character.animation_tree.animation_finished, finish_attack)

	attack_timer = get_tree().create_timer(queued_attack_time)
	attack_timer.timeout.connect(attempt_queue_attack)
	var input_comp: PlayerInputComponent = character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null:
		input_comp.update_aim_intent()
	aim_direction = character.aim_direction
	_arm_lunge()


## Arms the forward lunge when dash exports are set. The lunge starts when the
## weapon slot signals the attack's active phase via its slash signal (emitted
## exactly when the slot enables the hitbox), so no polling or hub is needed.
func _arm_lunge() -> void:
	if dash_speed <= 0.0 or dash_duration <= 0.0:
		return
	if attack_component == null or attack_component.attack_area == null:
		return
	lunge_slot = attack_component.attack_area.get_parent() as WeaponSlot
	if lunge_slot != null:
		connect_one_shot(lunge_slot.slash, _begin_lunge)


## Starts the forward lunge along the locked aim direction.
## The aim vector is pixel-scaled (never normalized upstream), so it must be
## normalized here or dash_speed would scale with screen pixels.
func _begin_lunge() -> void:
	if character == null or not character.is_inside_tree():
		return
	lunge_direction = aim_direction
	if lunge_direction.is_zero_approx() and character.mesh_mount != null:
		lunge_direction = character.mesh_mount.global_basis.z.normalized()
	if lunge_direction.is_zero_approx():
		lunge_direction = Vector3.FORWARD
	lunge_direction = lunge_direction.normalized()
	lunging = true
	lunge_timer = get_tree().create_timer(dash_duration)
	lunge_timer.timeout.connect(_end_lunge)


## Ends the forward lunge window; normal attack motion resumes.
func _end_lunge() -> void:
	lunging = false


## Clears all lunge state: motion flag, timer wiring, and slot signal wiring.
func _clear_lunge() -> void:
	lunging = false
	if lunge_timer != null:
		disconnect_safe(lunge_timer.timeout, _end_lunge)
		lunge_timer = null
	if lunge_slot != null:
		disconnect_safe(lunge_slot.slash, _begin_lunge)
		lunge_slot = null


## Dash-cancel gate: only attacks with dash_cancel set can be interrupted.
## The intent is still consumed when gated off so the press never leaks into a
## later state. Cancelling runs exit(), which already clears lunge and timers.
func check_dash() -> bool:
	if not dash_cancel:
		if character != null:
			character.consume_dash_request()
		return false
	return super.check_dash()


## Queues a combo follow-up instead of transitioning (consumes the intent).
func check_attack() -> bool:
	if character == null:
		return false
	if not character.consume_attack_request():
		return false
	queued_attack = true
	return true


func exit() -> void:
	queued_attack = false
	_clear_lunge()
	if attack_timer != null:
		disconnect_safe(attack_timer.timeout, attempt_queue_attack)
	if character != null and character.animation_tree != null:
		disconnect_safe(character.animation_tree.animation_finished, finish_attack)
	if attack_component != null:
		attack_component.reset_exceptions()


## Transitions to a random pick of next_states when the attack animation finishes.
## A queued intent does NOT chain here (matching legacy behavior): chaining happens
## in attempt_queue_attack inside the queue window; late presses are dropped.
func finish_attack(_animation_name: String) -> void:
	if character == null or character.state_machine == null or next_states.is_empty():
		return
	var next: CharacterState = next_states.pick_random()
	if next != null:
		character.state_machine.request_state(next.name)


## Chains combo_next when an attack intent was queued inside the queue window.
func attempt_queue_attack() -> void:
	if combo_next == null or not queued_attack or character == null or character.state_machine == null:
		return
	var direction: Vector3 = character.move_direction
	if direction.is_zero_approx() and character.mesh_mount != null:
		direction = character.mesh_mount.global_basis.z.normalized()
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	character.state_machine.request_state(combo_next.name, {"direction": direction})
