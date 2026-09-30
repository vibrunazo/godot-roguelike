## Base of every item's world visual (ItemResource.world_visual): how an item
## looks lying in a level. ItemPickup instances it and calls show_item(); a
## visual never reaches into the pickup. It can keep facing the gameplay
## camera, tilted toward it, so its front (a book cover) stays readable from
## the top-down view whatever the level's rotation. Purely visual (render
## clock). Tool-enabled so styled subclasses preview in the editor.
@tool
class_name ItemDisplay
extends Node3D

## Turn so the local +Z side faces the camera (on the ground plane).
@export var face_camera: bool = true
## Degrees the top (+Y) face tilts toward the camera, so a flat face such as
## a cover reads from the top-down view (0 = lying flat).
@export_range(0.0, 90.0, 1.0, "suffix:°") var tilt_toward_camera: float = 0.0


## Virtual: shows item (its title on a cover, its icon, ...).
func show_item(_item: ItemResource) -> void:
	pass


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not face_camera:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var to_camera: Vector3 = camera.global_position - global_position
	to_camera.y = 0.0
	if to_camera.is_zero_approx():
		return
	var yaw: float = atan2(to_camera.x, to_camera.z)
	global_basis = Basis.from_euler(Vector3(deg_to_rad(tilt_toward_camera), yaw, 0.0)).scaled(global_basis.get_scale())
