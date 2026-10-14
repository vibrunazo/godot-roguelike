## Self-test case for `kit.py capture scene ... -- <args>`: a staging scene
## that reads the arguments forwarded after --scene-args, builds its actor and
## its own camera, and leaves the screenshot and quitting to the capturer.
extends Node3D


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var forwarded: PackedStringArray = args.slice(args.find("--scene-args") + 1)
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	add_child(box)
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(2.0, 2.0, 2.0)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(sun)
	print("[StageArgs] %s" % " ".join(forwarded))
