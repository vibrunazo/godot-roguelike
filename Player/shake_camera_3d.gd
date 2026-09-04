class_name ShakeCamera3D
extends Camera3D

## Procedural noise generator used to sample pseudo-random camera offsets.
@export var noise: FastNoiseLite
## Current intensity of camera shake. Decays to 0 over time.
@export var trauma: float = 0.0
## Multiplier applied to camera offsets during screen shake.
@export var offset_scale: float = 1.0

func _physics_process(delta: float) -> void:
	if noise == null:
		return
	var time: float = float(Time.get_ticks_msec())
	h_offset = noise.get_noise_2d(time, 0.0) * trauma * offset_scale
	v_offset = noise.get_noise_2d(0.0, time) * trauma * offset_scale

## Triggers a screen shake with the specified magnitude that decays over 0.3 seconds.
func quick_shake(magnitude: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "trauma", 0.0, 0.3).from(magnitude)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		quick_shake(1.0)
