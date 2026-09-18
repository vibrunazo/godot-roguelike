## Display-only player character model for menus and previews.
## Plays idle animation continuously with weapon displayed.
## Excluded from player group, free of combat components, input, and camera overrides.
class_name MenuPlayer
extends Node3D

@onready var animation_player: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	if animation_player != null:
		var anim: Animation = animation_player.get_animation("PlayerAnimations/Idle_A")
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		animation_player.play("PlayerAnimations/Idle_A")
