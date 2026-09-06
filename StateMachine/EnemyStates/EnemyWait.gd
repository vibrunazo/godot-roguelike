class_name EnemyWait
extends EnemyState

func physics_update(_delta: float) -> void:
	core_movement(enemy.base_speed, Vector3.ZERO)
	enemy.move_and_slide()

func enter(_previous_state_path: String, _data := {}) -> void:
	enemy.animation_tree.change_immediate("WalkSpace")
	enemy.animation_tree.blend_target = -1.0
