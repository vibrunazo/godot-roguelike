extends PlayerState

## State to transition into after this attack finishes without a queued combo
@export var run_state: PlayerState
## Next attack state in the combo chain to transition to if an attack input is queued
@export var next_attack: PlayerState
## Time window (in seconds) after the attack starts for the player to press the attack button to queue the next attack.
## When this time expires, the state transitions to next_attack if an attack was queued.
@export var queued_attack_time: float = 0.5
## Name of the animation to trigger on the mannequin animation tree for this attack
@export var attack_animation_name: String = "SlashAttack"
## Reference to the AttackComponent handling damage dealing and hit collision exceptions
@export var attack_component: AttackComponent


var queued_attack: bool = false

func physics_update(_delta: float) -> void:
	attack_component.deal_damage(5.0, Vector3.ZERO)
	
func enter(_previous_state_path: String, _data: Dictionary = {}) -> void:
	queued_attack = false
	attack_component.reset_exceptions()
	player.mannequin_animation_tree.change_immediate(attack_animation_name)
	player.mannequin_animation_tree.animation_finished.connect(finish_attack, CONNECT_ONE_SHOT)
	var timer: SceneTreeTimer = get_tree().create_timer(queued_attack_time)
	timer.timeout.connect(attempt_queue_attack)

func handle_input(_event: InputEvent) -> void:
	if _event.is_action_pressed("click"):
		queued_attack = true

func exit() -> void:
	if player.mannequin_animation_tree.animation_finished.is_connected(finish_attack):
		player.mannequin_animation_tree.animation_finished.disconnect(finish_attack)

func finish_attack(_animation_name: String) -> void:
	finished.emit(run_state.name)

func attempt_queue_attack() -> void:
	if next_attack and queued_attack:
		var direction: Vector3 = player.get_movement_direction()
		finished.emit(next_attack.name, {"direction": direction})
