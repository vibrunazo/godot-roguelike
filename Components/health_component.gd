class_name HealthComponent
extends Node

signal health_changed(value: float)
signal defeat()

## Audio player played when damage is taken.
@export var hit_audio: AudioStreamPlayer3D
var is_ready: bool = false

## Maximum health value of this component.
@export var max_health: float = 100.0:
	set(value):
		max_health = value
		if is_ready:
			health_changed.emit(current_health)

var current_health: float:
	set(value):
		current_health = value
		if is_ready:
			health_changed.emit(current_health)

func _ready() -> void:
	current_health = max_health
	is_ready = true
	
func take_damage(damage_in: float) -> void:
	current_health -= damage_in
	var parent: Node = get_parent()
	if parent is Node3D:
		VfxManager.spawn_damage_number(parent as Node3D, damage_in)
	if hit_audio: hit_audio.play()
	if current_health <= 0.0: defeat.emit()
