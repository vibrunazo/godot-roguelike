class_name ShakeCamera3D
extends Camera3D

## Procedural noise generator used to sample pseudo-random camera offsets.
@export var noise: FastNoiseLite
## Current intensity of camera shake. Decays to 0 over time.
## Setting trauma above 0.0 enables physics processing; decaying back to 0.0
## resets the offsets and disables physics processing again so the camera
## costs nothing while idle.
@export var trauma: float = 0.0:
	set(value):
		trauma = value
		if value > 0.0:
			set_physics_process(true)
		else:
			h_offset = 0.0
			v_offset = 0.0
			set_physics_process(false)
## Multiplier applied to camera offsets during screen shake.
@export var offset_scale: float = 1.0

func _ready() -> void:
	set_physics_process(trauma > 0.0)

func _physics_process(delta: float) -> void:
	if noise == null:
		return
	if trauma <= 0.0:
		if h_offset != 0.0 or v_offset != 0.0:
			h_offset = 0.0
			v_offset = 0.0
		set_physics_process(false)
		return
	var time: float = float(Time.get_ticks_msec())
	h_offset = noise.get_noise_2d(time, 0.0) * trauma * offset_scale
	v_offset = noise.get_noise_2d(0.0, time) * trauma * offset_scale

## Triggers a screen shake with the specified magnitude that decays over 0.3 seconds.
func quick_shake(magnitude: float) -> void:
	set_physics_process(true)
	var tween: Tween = create_tween()
	tween.tween_property(self, "trauma", 0.0, 0.3).from(magnitude)
