extends Node

const DAMAGE_NUMBER: PackedScene = preload("res://Singletons/VFX/damage_number.tscn")


func spawn_damage_number(source: Node3D, damage: float) -> void:
	if not is_instance_valid(source):
		return
	var damage_number: DamageNumber = DAMAGE_NUMBER.instantiate() as DamageNumber
	add_child(damage_number)
	damage_number.set_damage_text(damage)
	damage_number.target_position = source.global_position
