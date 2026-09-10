## Physical state handling airborne falling physics for enemies.
class_name EnemyFall
extends CharacterState

## State to transition to after the enemy lands on the floor.
@export var land_state: CharacterState


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	character.velocity = character.get_gravity()
	character.move_and_slide()
	if character.is_on_floor() and land_state != null:
		finished.emit(land_state.name)
