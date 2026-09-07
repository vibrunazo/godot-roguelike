extends CanvasLayer

@onready var color_rect: ColorRect = $ColorRect

var player_cache: Player
var levels: Array[String] = [
	"res://Levels/level_1.tscn",
	"res://Levels/level_2.tscn",
	"res://Levels/level_3.tscn"
]


func _ready() -> void:
	levels.shuffle()
	fade_out(create_tween())


func fade_out(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 0.0, 1.0)


func fade_in(tween: Tween) -> void:
	tween.tween_property(color_rect, "color:a", 1.0, 0.25)


func load_scene_path(path_in: String, args: Dictionary = {}) -> void:
	var player: Player = get_tree().get_first_node_in_group("player") as Player
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var tween: Tween = create_tween()
	fade_in(tween)
	tween.tween_callback(
		func() -> void:
			if player:
				player.reparent(self)
				player_cache = player
			get_tree().change_scene_to_file(path_in)
	)
	tween.tween_interval(0.5)
	fade_out(tween)


func load_next_level(args: Dictionary = {}) -> void:
	levels.push_back(levels.pop_front())
	load_scene_path(levels.front(), args)
