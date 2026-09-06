## Specialized enemy variant that attacks from a distance using projectiles.
class_name RangedEnemy
extends Enemy

const ENEMY_PROJECTILE = preload("res://Enemy/enemy_projectile.tscn")

## The bone attachment from which projectiles are launched.
@export var attack_bone: BoneAttachment3D


func _on_weapon_slot_ranged_attack() -> void:
	var projectile: Node3D = ENEMY_PROJECTILE.instantiate() as Node3D
	add_child(projectile)
	projectile.global_position = attack_bone.global_position
	projectile.global_rotation.y = global_rotation.y
