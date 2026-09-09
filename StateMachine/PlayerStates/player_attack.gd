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

var queued_attack: bool = false
var attack_timer: SceneTreeTimer
var aim_direction: Vector3 = Vector3.ZERO


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	character.velocity = character.move_direction * movement_speed
	character.look_toward_direction(aim_direction, 1.0)
	character.move_and_slide()


func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	queued_attack = false
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
		character.animation_tree.animation_finished.connect(finish_attack, CONNECT_ONE_SHOT)

	attack_timer = get_tree().create_timer(queued_attack_time)
	attack_timer.timeout.connect(attempt_queue_attack)
	var input_comp: PlayerInputComponent = character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	if input_comp != null:
		input_comp.update_aim_intent()
	aim_direction = character.aim_direction


func handle_input(_event: InputEvent) -> void:
	if dash_cancel and _event.is_action_pressed("dash"):
		var input_comp: PlayerInputComponent = character.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
		if input_comp != null and input_comp.can_dash():
			queued_attack = false
			if attack_timer != null and attack_timer.timeout.is_connected(attempt_queue_attack):
				attack_timer.timeout.disconnect(attempt_queue_attack)
			check_dash(_event)
			return
	if _event.is_action_pressed("click"):
		queued_attack = true


func exit() -> void:
	queued_attack = false
	if attack_timer != null and attack_timer.timeout.is_connected(attempt_queue_attack):
		attack_timer.timeout.disconnect(attempt_queue_attack)
	if character != null and character.animation_tree != null:
		if character.animation_tree.animation_finished.is_connected(finish_attack):
			character.animation_tree.animation_finished.disconnect(finish_attack)
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
