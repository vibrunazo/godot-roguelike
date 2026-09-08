## Base class for enemies.
class_name Enemy
extends CharacterBody3D

## Emitted when this enemy is defeated.
signal defeat

## The state entered when the enemy takes damage.
@export var stun_state: EnemyState
## The state entered when the enemy is defeated.
@export var defeat_state: EnemyState
## Base movement speed of this enemy in meters per second.
@export var base_speed := 3.5
## The node mount rotated to aim the enemy.
@export var mesh_mount: Node3D
## The weapon ShapeCast3D for melee attacks.
@export var weapon_shape_cast: ShapeCast3D

@onready var animation_tree: AnimationTree = $AnimationAnchor/AnimatedEnemy/Enemy_Medium/AnimationTree
@onready var state_machine: StateMachine = $StateMachine
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D
@onready var player: Player = get_tree().get_first_node_in_group("player") as Player
@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	if weapon_shape_cast:
		weapon_shape_cast.add_exception(self)
	if not is_inside_tree():
		return
	var random_point: Vector3 = NavigationServer3D.map_get_random_point(
		get_world_3d().navigation_map, 1, true
	)
	var half_height: float = 1.0
	if collision_shape_3d and collision_shape_3d.shape is CapsuleShape3D:
		half_height = (collision_shape_3d.shape as CapsuleShape3D).height * 0.5
	global_position = random_point + Vector3(0.0, half_height, 0.0)



func _on_health_component_health_changed(_value: float) -> void:
	state_machine.state.finished.emit(stun_state.name)


func _on_health_component_defeat() -> void:
	defeat.emit()
	state_machine.state.finished.emit(defeat_state.name)
	collision_shape_3d.set_deferred("disabled", true)


## Returns the distance to the player in meters, or INF if no player exists.
func distance_to_player() -> float:
	if not is_instance_valid(player):
		return INF
	return global_position.distance_to(player.global_position)
