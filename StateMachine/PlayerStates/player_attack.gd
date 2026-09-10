## State handling player attack executions, hitbox activation, aim locking, and attack chaining.
class_name PlayerAttack
extends PlayerState

## Speed at which the player can move while executing this attack.
@export var movement_speed: float = 0.0
## Whether this attack state can be cancelled early by dashing.
@export var dash_cancel: bool = false
## Amount of damage dealt to health components caught in this attack.
@export var damage: float = 10.0
## Knockback impulse applied to entities hit by this attack.
@export var knockback: float = 15.0
## State to transition into after this attack finishes without a queued combo.
@export var run_state: PlayerState
## Next attack state in the combo chain to transition to if an attack input is queued.
@export var next_attack: PlayerState
## Time window (in seconds) after the attack starts for the player to press the attack button to queue the next attack.
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


func handle_input(_event: InputEvent) -> void:
	if dash_cancel and _event.is_action_pressed("dash"):
		var input_comp: PlayerInputComponent = character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
		if input_comp != null and input_comp.can_dash():
			queued_attack = false
			if attack_timer != null:
				disconnect_safe(attack_timer.timeout, attempt_queue_attack)
			_clear_lunge()
			check_dash(_event)
			return
	if _event.is_action_pressed("click"):
		queued_attack = true


func exit() -> void:
	queued_attack = false
	_clear_lunge()
	if attack_timer != null:
		disconnect_safe(attack_timer.timeout, attempt_queue_attack)
	if character != null and character.animation_tree != null:
		disconnect_safe(character.animation_tree.animation_finished, finish_attack)
	if attack_component != null:
		attack_component.reset_exceptions()


func finish_attack(_animation_name: String) -> void:
	if run_state != null:
		finished.emit(run_state.name)


func attempt_queue_attack() -> void:
	if next_attack != null and queued_attack and character != null:
		var direction: Vector3 = character.move_direction
		if direction.is_zero_approx() and character.mesh_mount != null:
			direction = character.mesh_mount.global_basis.z.normalized()
		if direction.is_zero_approx():
			direction = Vector3.FORWARD
		finished.emit(next_attack.name, {"direction": direction})
