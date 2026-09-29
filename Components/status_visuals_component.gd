## Shows each timed GameplayEffect's status visual (its vfx_scene) while the
## effect instance lives: at vfx_offset on the character's body, or on a bone
## (vfx_bone) so it follows the skeleton's poses and falls with the corpse.
## Refreshes reuse the live visual, stacked instances each get their own, and a
## visual is freed as soon as its instance ends (expiry, removal, clearing).
class_name StatusVisualsComponent
extends Node

## The attribute component whose effects are shown.
@export var attribute_component: AttributeComponent
## The body the visuals attach to (normally the character itself): visuals
## must live under a Node3D to follow it.
@export var visual_parent: Node3D

## Live visuals: effect instance id -> visual node.
var _visuals: Dictionary[StringName, Node] = {}


func _ready() -> void:
	if attribute_component == null or visual_parent == null:
		push_error("%s: attribute_component and visual_parent must be set." % name)
		return
	attribute_component.effect_applied.connect(_on_effect_applied)
	attribute_component.effects_ended.connect(_free_ended_visuals)


## Instances the effect's visual unless the instance already shows one (a
## refresh) or the effect has no vfx_scene.
func _on_effect_applied(instance_id: StringName, effect: GameplayEffect) -> void:
	if effect.vfx_scene == null or _visuals.has(instance_id):
		return
	var visual: Node = effect.vfx_scene.instantiate()
	_parent_for(effect).add_child(visual)
	if visual is Node3D:
		(visual as Node3D).position = effect.vfx_offset
	_visuals[instance_id] = visual


## Frees the visuals whose effect instance no longer exists.
func _free_ended_visuals() -> void:
	var ended: Array[StringName] = []
	for instance_id: StringName in _visuals:
		if not attribute_component.has_effect_instance(instance_id):
			ended.append(instance_id)
	for instance_id: StringName in ended:
		var visual: Node = _visuals[instance_id]
		_visuals.erase(instance_id)
		if is_instance_valid(visual):
			# Hide at once: queue_free only takes effect at the end of the frame.
			if visual is Node3D:
				(visual as Node3D).visible = false
			visual.queue_free()


## The effect's bone (a BoneAttachment3D on the body's skeleton) when vfx_bone
## is set and exists, else visual_parent.
func _parent_for(effect: GameplayEffect) -> Node3D:
	if effect.vfx_bone.is_empty():
		return visual_parent
	var skeleton: Skeleton3D = _body_skeleton()
	if skeleton == null:
		return visual_parent
	var slot: BoneAttachment3D = _bone_slot(skeleton, String(effect.vfx_bone))
	return slot if slot != null else visual_parent


## The body's skeleton: searched under the character's mesh mount first (a
## character may carry other rigs, e.g. riders), then under visual_parent.
func _body_skeleton() -> Skeleton3D:
	var roots: Array[Node] = [visual_parent]
	if visual_parent is Character and (visual_parent as Character).mesh_mount != null:
		roots.push_front((visual_parent as Character).mesh_mount)
	for root: Node in roots:
		var found: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			return found[0] as Skeleton3D
	return null


## The BoneAttachment3D following bone_name on skeleton, created when missing;
## null when the skeleton has no such bone.
func _bone_slot(skeleton: Skeleton3D, bone_name: String) -> BoneAttachment3D:
	for child: Node in skeleton.get_children():
		if child is BoneAttachment3D and (child as BoneAttachment3D).bone_name == bone_name:
			return child as BoneAttachment3D
	var bone_idx: int = skeleton.find_bone(bone_name)
	if bone_idx < 0:
		return null
	var slot: BoneAttachment3D = BoneAttachment3D.new()
	slot.name = bone_name.replace(".", "_").capitalize().replace(" ", "") + "Slot"
	slot.bone_name = bone_name
	slot.bone_idx = bone_idx
	skeleton.add_child(slot)
	return slot
