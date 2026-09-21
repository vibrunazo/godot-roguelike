## Persistent burning status VFX. Attached to characters or character bones.
## Maintains world-upright orientation so fire particles always emit and rise
## vertically upwards (+Y) even when the parent bone tilts or rotates (e.g. on death).
class_name StatusBurning
extends Node3D


func _process(_delta: float) -> void:
	global_basis = Basis.IDENTITY
