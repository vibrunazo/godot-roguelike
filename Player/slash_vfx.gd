@tool
extends MeshInstance3D

@export var weapon_slot: WeaponSlot
@export var attack_type: WeaponSlot.mode


func _process(_delta: float) -> void:
	if not weapon_slot or not material_override:
		return
	visible = weapon_slot.attack_mode == attack_type
	material_override.set_shader_parameter("Threshold", weapon_slot.vfx_threshold)

