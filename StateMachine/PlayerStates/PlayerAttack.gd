extends PlayerState

@export var attack_component: AttackComponent

func physics_update(_delta: float) -> void:
	attack_component.deal_damage(5.0, Vector3.ZERO)
	
func enter(_previous_state_path: String, _data := {}) -> void:
	attack_component.reset_exceptions()
	player.mannequin_animation_tree.change_immediate("SlashAttack")
