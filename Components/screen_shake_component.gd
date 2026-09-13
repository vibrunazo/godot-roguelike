## Component that listens to Character combat events and drives camera screen shake.
## Attached exclusively to the Player so enemies and traps never trigger screenshake.
class_name ScreenShakeComponent
extends Node

## The Character to monitor for combat events.
@export var character: Character

## The ShakeCamera3D to apply camera trauma to.
@export var camera: ShakeCamera3D

## Trauma magnitude applied when this character takes damage.
@export var hurt_shake_magnitude: float = 1.0

## Trauma magnitude applied when this character lands an attack with shake_on_damage enabled.
@export var hit_shake_magnitude: float = 0.75


func _ready() -> void:
	if character == null:
		character = get_parent() as Character
	if camera == null and character != null:
		camera = character.get_node_or_null("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	if character != null:
		if not character.health_changed.is_connected(_on_character_health_changed):
			character.health_changed.connect(_on_character_health_changed)
		if not character.hit_landed.is_connected(_on_character_hit_landed):
			character.hit_landed.connect(_on_character_hit_landed)


## Returns the active ShakeCamera3D, resolving dynamically from viewport if not assigned.
func get_camera() -> ShakeCamera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	if is_inside_tree():
		camera = get_viewport().get_camera_3d() as ShakeCamera3D
	return camera


## Triggers camera shake with the specified magnitude.
func quick_shake(magnitude: float) -> void:
	var cam: ShakeCamera3D = get_camera()
	if cam != null and is_inside_tree():
		cam.quick_shake(magnitude)


func _on_character_health_changed(_value: float) -> void:
	quick_shake(hurt_shake_magnitude)


func _on_character_hit_landed(_target: Node, attack_comp: AttackComponent) -> void:
	if attack_comp != null and attack_comp.shake_on_damage:
		quick_shake(hit_shake_magnitude)
