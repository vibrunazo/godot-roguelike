extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect


func _ready() -> void:
	fade_out(create_tween())


func fade_out(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 0.0, 1.0)


func fade_in(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 1.0, 0.25)


func load_scene_path(path_in: String, args: Dictionary = {}) -> void:
	var tween: Tween = create_tween()
	fade_in(tween)
	tween.tween_callback(
		func() -> void:
			get_tree().change_scene_to_file(path_in)
	)
	tween.tween_interval(0.5)
	fade_out(tween)
