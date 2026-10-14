## Self-test case for `kit.py scratch`: loads game code dynamically (no game
## class types in declarations), reads an autoload and the forwarded arguments.
extends SceneTree


func _initialize() -> void:
	var mover: Node3D = (load("res://game/mover.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(mover)
	var clock: Node = root.get_node("GameClock")
	print("SCRATCH_OK speed=%s clock=%s args=%s" % [mover.get("speed"), clock != null, " ".join(OS.get_cmdline_user_args())])
	quit(0)
