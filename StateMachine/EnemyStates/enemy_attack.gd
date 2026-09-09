## State handling enemy attack execution.
class_name EnemyAttack
extends EnemyState

## Knockback impulse applied to entities hit by this attack.
@export var knockback := 20.0
## Amount of damage dealt by this attack.
@export var weapon_damage := 8.0
## AttackComponent handling hitbox queries and dealing damage.
@export var attack_component: AttackComponent
## Name of the attack animation in the AnimationTree.
@export var attack_name: String
## Potential states to transition to randomly after the attack animation finishes.
@export var next_state: Array[EnemyState]


func physics_update(_delta: float) -> void:
	if not is_instance_valid(enemy) or not enemy.is_inside_tree():
		return
	enemy.velocity = Vector3.ZERO
	enemy.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	if attack_component:
		attack_component.reset_exceptions()
		attack_component.damage = weapon_damage
		attack_component.knockback = enemy.mesh_mount.global_basis.z * knockback
	enemy.animation_tree.change_immediate(attack_name)
	if not enemy.animation_tree.animation_finished.is_connected(end_attack):
		enemy.animation_tree.animation_finished.connect(end_attack, CONNECT_ONE_SHOT)


func exit() -> void:
	if enemy.animation_tree.animation_finished.is_connected(end_attack):
		enemy.animation_tree.animation_finished.disconnect(end_attack)
	if attack_component:
		attack_component.reset_exceptions()


func end_attack(_animation_name: String) -> void:
	if not next_state.is_empty():
		var random_state: EnemyState = next_state.pick_random()
		if random_state:
			finished.emit(random_state.name)
