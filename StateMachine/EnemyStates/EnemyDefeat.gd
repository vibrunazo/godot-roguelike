class_name EnemyDefeat
extends EnemyState


func physics_update(_delta: float) -> void:
	enemy.velocity = Vector3.ZERO
	enemy.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate("Defeat")
