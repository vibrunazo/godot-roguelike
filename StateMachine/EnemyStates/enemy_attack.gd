## State handling physical enemy attack execution (melee swing or projectile casting).
class_name EnemyAttack
extends EnemyState

## Knockback impulse applied to entities hit by this attack.
@export var knockback: float = 20.0
## Amount of damage dealt by this attack.
@export var weapon_damage: float = 8.0
## AttackComponent handling hitbox queries and dealing damage.
@export var attack_component: AttackComponent
## Name of the attack animation in the AnimationTree.
@export var attack_name: String
## Potential states to transition to after the attack animation finishes.
@export var next_state: Array[EnemyState]


func physics_update(_delta: float) -> void:
	if character == null or not character.is_inside_tree():
		return
	character.velocity = Vector3.ZERO
	character.move_and_slide()


func enter(_previous_state_path: String, _data := {}) -> void:
	if attack_component != null and character != null:
		attack_component.reset_exceptions()
		attack_component.damage = weapon_damage
		if character.mesh_mount != null:
			attack_component.knockback = character.mesh_mount.global_basis.z * knockback
		else:
			attack_component.knockback = character.global_basis.z * knockback

	if character != null and character.animation_tree != null:
		character.animation_tree.change_immediate(attack_name)
		if not character.animation_tree.animation_finished.is_connected(end_attack):
			character.animation_tree.animation_finished.connect(end_attack, CONNECT_ONE_SHOT)


func exit() -> void:
	if character != null and character.animation_tree != null:
		if character.animation_tree.animation_finished.is_connected(end_attack):
			character.animation_tree.animation_finished.disconnect(end_attack)
	if attack_component != null:
		attack_component.reset_exceptions()


func end_attack(_animation_name: String) -> void:
	if not next_state.is_empty():
		var random_state: EnemyState = next_state.pick_random()
		if random_state != null:
			finished.emit(random_state.name)
