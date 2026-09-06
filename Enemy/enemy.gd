## Base class for enemies.
class_name Enemy
extends CharacterBody3D

## The state entered when the enemy takes damage.
@export var stun_state: EnemyState
## The state entered when the enemy is defeated.
@export var defeat_state: EnemyState
## Base movement speed of this enemy in meters per second.
@export var base_speed := 3.5
## The node mount rotated to aim the enemy.
@export var mesh_mount: Node3D

@onready var animation_tree: AnimationTree = $AnimationAnchor/AnimatedEnemy/Enemy_Medium/AnimationTree
@onready var state_machine: StateMachine = $StateMachine
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var player: Player = get_tree().get_first_node_in_group("player") as Player
@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	global_position = NavigationServer3D.map_get_random_point(
		get_world_3d().navigation_map, 1, true
	)


func _on_health_component_health_changed(_value: float) -> void:
	state_machine.state.finished.emit(stun_state.name)


func _on_health_component_defeat() -> void:
	state_machine.state.finished.emit(defeat_state.name)
	collision_shape_3d.set_deferred("disabled", true)
