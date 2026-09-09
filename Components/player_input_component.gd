## Component that listens to user inputs and translates them into Character intents and actions.
class_name PlayerInputComponent
extends Node

## The Character controlled by this input component.
@export var character: Character
## Cooldown timer preventing dash spamming.
@export var dash_cooldown: Timer
## Sound effect player for dashing.
@export var dash_audio: AudioStreamPlayer3D
## Fullscreen damage vignette/tint ColorRect.
@export var damage_tint: ColorRect


func _ready() -> void:
	if character == null:
		character = get_parent() as Character
	if character != null:
		character.health_changed.connect(_on_character_health_changed)


func _physics_process(_delta: float) -> void:
	if character == null or not is_inside_tree():
		return
	update_movement_intent()
	update_aim_intent()


## Computes camera-relative movement direction from input axes.
func update_movement_intent() -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var input_3d: Vector3 = Vector3(input_vector.x, 0.0, input_vector.y)
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera != null:
		input_3d = input_3d.rotated(Vector3.UP, camera.global_rotation.y)
	character.move_direction = input_3d.normalized()


## Returns the 2D viewport coordinates of the character's 3D global position.
func get_character_position_2d() -> Vector2:
	if character == null:
		return Vector2.ZERO
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(character.global_position)


## Returns the 2D screen vector pointing from the character to the mouse cursor.
func get_mouse_direction() -> Vector2:
	if character == null:
		return Vector2.ZERO
	return character.get_viewport().get_mouse_position() - get_character_position_2d()


## Returns the 3D ground direction vector pointing towards the mouse cursor, aligned with camera rotation.
func get_aim_direction() -> Vector3:
	if character == null:
		return Vector3.ZERO
	var direction: Vector2 = get_mouse_direction()
	var direction_3d: Vector3 = Vector3(direction.x, 0.0, direction.y)
	var camera: Camera3D = character.get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	return direction_3d.rotated(Vector3.UP, camera.global_rotation.y)


## Computes camera-relative aim direction towards mouse cursor and assigns it to the character.
func update_aim_intent() -> void:
	character.aim_direction = get_aim_direction()


## Returns true if the dash ability is currently off cooldown.
func can_dash() -> bool:
	return dash_cooldown != null and dash_cooldown.is_stopped()


## Flashes the red damage vignette when the character takes damage.
func _on_character_health_changed(_value: float) -> void:
	if damage_tint != null and is_inside_tree():
		var tween: Tween = create_tween()
		tween.tween_property(damage_tint, "color", Color(Color.RED, 0.0), 0.2).from(Color(Color.RED, 0.5))
