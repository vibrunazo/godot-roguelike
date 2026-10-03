## Base of status visuals that must stay upright: attached to a character or
## one of its bones, it keeps a world-aligned basis so particles always rise
## along +Y, even when the bone tilts (e.g. on death). Purely visual (render
## clock).
class_name UprightStatusVisual
extends Node3D


func _process(_delta: float) -> void:
	global_basis = Basis.IDENTITY
