class_name Player
extends CharacterBody3D

## Exponential decay rate for orientation smoothing towards movement direction.
@export var decay := 12.0
## Regular run speed in meters per second. Read by Run and Fall States
@export var movement_speed := 8.0
## Speed during dash in meters per second. Read by Dash State.
@export var dash_speed := 50.0
## Audio player for dashing sound effect.
@export var dash_audio: AudioStreamPlayer3D

@onready var dash_cooldown: Timer = $DashCooldown
@onready var mannequin_animation_tree: AnimationTree = $GamedevTV_Mannequin_Medium/MannequinAnimationTree
@onready var player_root: Node3D = $GamedevTV_Mannequin_Medium
@onready var health_component: HealthComponent = $HealthComponent
@onready var damage_tint: ColorRect = $DamageTint

func _ready() -> void:
	health_component.defeat.connect(get_tree().reload_current_scene, CONNECT_DEFERRED)
	health_component.health_changed.connect(health_component_changed)

## Returns the current input direction towards camera. Normalized. Returns Vector3.ZERO if no input.
func get_movement_direction() -> Vector3:
	var input := Vector3.ZERO
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	input = Vector3(input_vector.x, 0.0, input_vector.y)
	var camera := get_viewport().get_camera_3d()
	var camera_rotation := camera.global_rotation.y
	input = input.rotated(Vector3.UP, camera_rotation)
	return input.normalized()

func can_dash() -> bool:
	if get_movement_direction().is_zero_approx():
		return false
	return dash_cooldown.is_stopped()

func look_toward_direction(direction: Vector3, delta: float) -> void:
	# If player isn't moving (input is zero), keep current facing direction
	if direction.is_zero_approx():
		return
	# Start with the mannequin's current transform
	var target := player_root.global_transform
	# Compute a target transform that points the model's front (+Z) at (position + direction)
	target = target.looking_at(player_root.global_position + direction, Vector3.UP, true)
	# Smoothly interpolate towards target transform using framerate-independent exponential decay
	player_root.global_transform = player_root.global_transform.interpolate_with(
		target,
		1.0 - exp(-decay * delta)
	)

## Returns the 2D viewport coordinates of the player's 3D global position
func get_player_position_2d() -> Vector2:
	return get_viewport().get_camera_3d().unproject_position(global_position)

## Returns the 2D screen vector pointing from the player to the mouse cursor
func get_mouse_direction() -> Vector2:
	return get_viewport().get_mouse_position() - get_player_position_2d()

## Returns the 3D ground direction vector pointing towards the mouse cursor, aligned with camera rotation
func get_aim_direction() -> Vector3:
	var direction := get_mouse_direction()
	var direction_3d := Vector3(direction.x, 0.0, direction.y)
	var camera_rotation := get_viewport().get_camera_3d().global_rotation.y
	return direction_3d.rotated(Vector3.UP, camera_rotation)

func health_component_changed(health_in: float) -> void:
	var camera := get_viewport().get_camera_3d() as ShakeCamera3D
	if camera != null:
		camera.quick_shake(1.0)
	var tween: Tween = create_tween()
	tween.tween_property(damage_tint, "color", Color(Color.RED, 0.0), 0.2).from(Color(Color.RED, 0.5))

#func _input(event: InputEvent) -> void:
#	if event.is_action_pressed("ui_accept"):
#		health_component.take_damage(5.0)
