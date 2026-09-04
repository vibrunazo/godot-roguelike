extends PlayerState

@export var run_state: PlayerState
@export var attack_component: AttackComponent

func physics_update(_delta: float) -> void:
	attack_component.deal_damage(5.0, Vector3.ZERO)
	
func enter(_previous_state_path: String, _data := {}) -> void:
	attack_component.reset_exceptions()
	player.mannequin_animation_tree.change_immediate("SlashAttack")
	player.mannequin_animation_tree.animation_finished.connect(finish_attack, CONNECT_ONE_SHOT)
	
func exit() -> void:
	if player.mannequin_animation_tree.animation_finished.is_connected(finish_attack):
		player.mannequin_animation_tree.animation_finished.disconnect(finish_attack)

func finish_attack(_animation_name: String) -> void:
	finished.emit(run_state.name)
