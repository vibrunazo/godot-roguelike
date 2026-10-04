## An equipment visual carried by a bone attachment that keeps its bearer's
## facing: it rides the bone's position (a hand slot) but turns only with the
## character's mesh_mount, never with the arm, so a shield always faces the
## way its bearer faces whatever the animation does with the forearm. Purely
## visual (render clock); hitboxes stay on the slot itself.
class_name HeldFacingVisual
extends Node3D

## Node whose basis this visual copies (the character's mesh_mount).
@export var facing: Node3D


func _ready() -> void:
	if facing == null:
		push_error("%s: facing is not set." % name)


func _process(_delta: float) -> void:
	if facing != null:
		global_basis = facing.global_basis.orthonormalized()
