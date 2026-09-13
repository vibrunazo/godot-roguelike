## Overlay presenting the current dungeon level title banner upon starting a level.
class_name LevelTitleOverlay
extends CanvasLayer

signal finished

@onready var label: Label = %LevelLabel
@onready var container: Control = $Control

var _tween: Tween


func _ready() -> void:
	layer = 10


## Displays the level number banner, animates fade-in and fade-out, then frees itself.
func display_level(level_number: int, duration: float = 2.0) -> void:
	if label == null:
		await ready
	label.text = "Level %d" % level_number

	if _tween != null and _tween.is_valid():
		_tween.kill()

	container.modulate.a = 0.0
	_tween = create_tween()
	# Fade in
	_tween.tween_property(container, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Hold
	_tween.tween_interval(duration)
	# Fade out
	_tween.tween_property(container, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(
		func() -> void:
			finished.emit()
			queue_free()
	)
