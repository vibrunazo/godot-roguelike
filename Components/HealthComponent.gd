class_name HealthComponent
extends Node

signal health_changed(value: float)
signal defeat()

@export var hit_audio: AudioStreamPlayer3D
@export var max_health: float = 100.0

var current_health: float

func _ready() -> void:
	current_health = max_health
	
func take_damage(damage_in: float) -> void:
	current_health -= damage_in
	print(current_health)
	health_changed.emit(current_health)
	if hit_audio: hit_audio.play()
	if current_health <= 0.0: defeat.emit()
