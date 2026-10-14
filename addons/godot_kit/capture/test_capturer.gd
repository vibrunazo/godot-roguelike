## Records a test suite as it runs, for `kit.py capture test` (with Godot's
## --write-movie). Instantiates the suite, adds a fallback light and camera when
## the suite has none, draws collision shapes, and keeps every node of
## --track-type (capture.track_type, e.g. "Character") in frame.
extends Node3D

var _test_path: String = ""
var _duration: float = 5.0
var _hide_ui: bool = false
var _hide_paths: Array[String] = []
var _track_type: String = ""
var _elapsed: float = 0.0
var _suite: Node = null
var _camera: Camera3D = null


func _ready() -> void:
	_parse_arguments()
	if "--debug-collisions" in OS.get_cmdline_user_args():
		get_tree().debug_collisions_hint = true
	_add_fallback_light()
	_camera = Camera3D.new()
	_camera.name = "TestCaptureCamera"
	_camera.fov = 48.0
	add_child(_camera)
	_camera.position = Vector3(4.0, 3.5, 6.0)
	_camera.look_at(Vector3(0.0, 1.0, 0.5), Vector3.UP)
	_load_suite()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_hide_overlays()
	_track_nodes()
	if _elapsed >= _duration:
		print("[TestCapturer] Done recording %.2f s." % _elapsed)
		get_tree().quit(0)


func _parse_arguments() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			_test_path = arg.trim_prefix("--test=").strip_edges()
		elif arg.begins_with("--duration="):
			_duration = arg.trim_prefix("--duration=").to_float()
		elif arg.begins_with("--hide-path="):
			_hide_paths.append(arg.trim_prefix("--hide-path="))
		elif arg.begins_with("--track-type="):
			_track_type = arg.trim_prefix("--track-type=").strip_edges()
		elif arg == "--hide-ui":
			_hide_ui = true
	if not _test_path.is_empty() and not _test_path.begins_with("res://"):
		_test_path = "res://" + _test_path.trim_prefix("./").trim_prefix("/")


func _add_fallback_light() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 45.0, 0.0)
	light.shadow_enabled = true
	add_child(light)


func _load_suite() -> void:
	var packed: PackedScene = load(_test_path) as PackedScene if ResourceLoader.exists(_test_path) else null
	if packed == null:
		printerr("[TestCapturer] ERROR: cannot load suite: ", _test_path)
		get_tree().quit(1)
		return
	_suite = packed.instantiate()
	add_child(_suite)
	print("[TestCapturer] Recording ", _test_path)
	# The suite's own current camera wins; otherwise ours shows it.
	var has_current: bool = false
	for node: Node in _suite.find_children("*", "Camera3D", true, false):
		has_current = has_current or (node as Camera3D).current
	if not has_current:
		_camera.make_current()


func _track_nodes() -> void:
	if _track_type.is_empty() or _suite == null or not _camera.current:
		return
	var total: Vector3 = Vector3.ZERO
	var count: int = 0
	for node: Node in _suite.find_children("*", _track_type, true, false):
		if node is Node3D and node.is_inside_tree():
			total += (node as Node3D).global_position
			count += 1
	if count > 0:
		_camera.look_at(total / float(count) + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _hide_overlays() -> void:
	if not _hide_ui:
		return
	for path: String in _hide_paths:
		var node: Node = get_node_or_null(NodePath(path))
		if node != null and "visible" in node:
			node.set("visible", false)
	for node: Node in get_tree().get_nodes_in_group(&"capture_hidden"):
		if "visible" in node:
			node.set("visible", false)
