## Base script for an item's 3D visual scene.
## Handles dynamic discovery or creation of BoneAttachment3D nodes on the character's skeleton.
class_name ItemVisual
extends Node3D

@export_group("Attachment Configuration")
## Target bone name on the character's Skeleton3D (e.g. "hand.r", "hand.l", "spine", "head", "foot.r").
@export var target_bone: String = "hand.r"
## Local translation offset applied relative to the bone attachment slot.
@export var local_offset: Vector3 = Vector3.ZERO
## Local rotation in degrees applied relative to the bone attachment slot.
@export var local_rotation_degrees: Vector3 = Vector3.ZERO


## Attaches this visual scene to the appropriate bone attachment on the given character.
## Overridable for complex visual setups (e.g. multi-mesh gear attached to multiple bones).
func attach_to_character(character: Character) -> void:
	if character == null or not is_instance_valid(character):
		return

	var skeleton: Skeleton3D = _find_skeleton(character)
	if skeleton == null:
		# Fallback: mount to mesh_mount or character body root
		if character.mesh_mount != null:
			character.mesh_mount.add_child(self)
		else:
			character.add_child(self)
		position = local_offset
		rotation_degrees = local_rotation_degrees
		return

	var slot: BoneAttachment3D = _find_or_create_bone_slot(skeleton, target_bone)
	slot.add_child(self)
	position = local_offset
	rotation_degrees = local_rotation_degrees


## Removes and cleans up this visual instance.
func detach_from_character() -> void:
	queue_free()


func _find_skeleton(character: Character) -> Skeleton3D:
	if character.mesh_mount != null:
		var skel_in_mount: Skeleton3D = character.mesh_mount.find_child("*Skeleton*", true, false) as Skeleton3D
		if skel_in_mount != null:
			return skel_in_mount
	return character.find_child("*Skeleton*", true, false) as Skeleton3D


func _find_or_create_bone_slot(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	for child: Node in skeleton.get_children():
		if child is BoneAttachment3D and (child as BoneAttachment3D).bone_name == bone_name:
			return child as BoneAttachment3D

	var bone_idx: int = skeleton.find_bone(bone_name)
	var new_slot: BoneAttachment3D = BoneAttachment3D.new()
	new_slot.name = bone_name.replace(".", "_").capitalize().replace(" ", "") + "Slot"
	new_slot.bone_name = bone_name
	if bone_idx >= 0:
		new_slot.bone_idx = bone_idx
	skeleton.add_child(new_slot)
	return new_slot
