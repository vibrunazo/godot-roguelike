## Base class for enemies.
class_name Enemy
extends CharacterBody3D

## The state entered when the enemy takes damage.
@export var stun_state: EnemyState
## The state entered when the enemy is defeated.
@export var defeat_state: EnemyState
## Base movement speed of this enemy in meters per second.
@export var base_speed := 3.5

@onready var animation_tree: AnimationTree = $AnimationAnchor/AnimatedEnemy/Enemy_Medium/AnimationTree
@onready var state_machine: StateMachine = $StateMachine


func _on_health_component_health_changed(_value: float) -> void:
	state_machine.state.finished.emit(stun_state.name)


func _on_health_component_defeat() -> void:
	state_machine.state.finished.emit(defeat_state.name)
