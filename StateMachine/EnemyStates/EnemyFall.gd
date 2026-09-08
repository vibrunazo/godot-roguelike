class_name EnemyFall
extends EnemyState

## State to transition to after the enemy lands on the floor.
@export var land_state: EnemyState


func physics_update(_delta: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	enemy.velocity = enemy.get_gravity()
	enemy.move_and_slide()
	if enemy.is_on_floor():
		finished.emit(land_state.name)
