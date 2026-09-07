class_name EnemyWait
extends EnemyState

## State to transition to after wait timeout.
@export var next_state: EnemyState

var timer: SceneTreeTimer


func physics_update(_delta: float) -> void:
	core_movement(enemy.base_speed, Vector3.ZERO)
	if not enemy.is_on_floor():
		enemy.velocity += enemy.get_gravity() * _delta
	else:
		enemy.velocity.y = 0.0
	enemy.move_and_slide()



func enter(_previous_state_path: String, _data := {}) -> void:
	timer = get_tree().create_timer(2.0)
	timer.timeout.connect(end_wait)
	enemy.animation_tree.change_immediate("WalkSpace")
	enemy.animation_tree.blend_target = -1.0


func exit() -> void:
	if timer and timer.timeout.is_connected(end_wait):
		timer.timeout.disconnect(end_wait)


func end_wait() -> void:
	look_at_player()
	if next_state:
		finished.emit(next_state.name)

