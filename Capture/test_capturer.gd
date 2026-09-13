## Test capturer utility for running and visually recording test suites.
##
## Instantiates any test scene (*.tscn), provides fallback camera & lighting
## if needed, enables collision debug visualization, and allows recording video
## or taking screenshots of current and future test executions.
class_name TestCapturer
extends Node3D

var test_scene_path: String = ""
var is_video: bool = false
var hide_ui: bool = true
var debug_collisions: bool = true
var max_frames: int = 300
var frame_count: int = 0
var test_instance: Node

var camera: Camera3D


func _ready() -> void:
	_parse_arguments()
	_configure_environment()
	_setup_camera()
	_load_test()


func _physics_process(_delta: float) -> void:
	frame_count += 1
	_disable_all_ui()

	# Dynamically frame characters if found in the test
	_track_characters()

	if is_video and frame_count >= max_frames:
		print("[TestCapturer] Max recording frames reached (%d). Quitting." % max_frames)
		get_tree().quit(0)


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--test="):
			test_scene_path = arg.trim_prefix("--test=").strip_edges()
		elif arg.begins_with("--frames="):
			max_frames = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--duration="):
			var dur: float = arg.trim_prefix("--duration=").to_float()
			max_frames = int(dur * 60.0)
		elif arg == "--video":
			is_video = true
		elif arg == "--no-debug-collisions":
			debug_collisions = false
		elif arg == "--show-ui":
			hide_ui = false
		elif arg == "--hide-ui":
			hide_ui = true

	if not test_scene_path.is_empty():
		if not test_scene_path.begins_with("res://") and not test_scene_path.begins_with("user://"):
			test_scene_path = "res://" + test_scene_path.trim_prefix("./").trim_prefix("/")


func _configure_environment() -> void:
	if debug_collisions:
		get_tree().debug_collisions_hint = true

	_disable_all_ui()

	# Ensure lighting in case test doesn't supply any
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 45.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "TestCaptureCamera"
	camera.fov = 48.0
	add_child(camera)
	camera.position = Vector3(4.0, 3.5, 6.0)
	camera.look_at(Vector3(0.0, 1.0, 0.5), Vector3.UP)


func _load_test() -> void:
	if test_scene_path.is_empty():
		printerr("[TestCapturer] ERROR: No test scene path specified (--test=<path>)")
		get_tree().quit(1)
		return

	if not ResourceLoader.exists(test_scene_path):
		printerr("[TestCapturer] ERROR: Test scene not found: ", test_scene_path)
		get_tree().quit(1)
		return

	var scn: PackedScene = load(test_scene_path) as PackedScene
	if scn == null:
		printerr("[TestCapturer] ERROR: Could not load PackedScene: ", test_scene_path)
		get_tree().quit(1)
		return

	test_instance = scn.instantiate()
	add_child(test_instance)
	print("[TestCapturer] Instantiated test scene: ", test_scene_path)

	# If the test already has a current Camera3D, give it priority unless requested
	var existing_cams: Array[Node] = test_instance.find_children("*", "Camera3D", true, false)
	if not existing_cams.is_empty():
		var has_current: bool = false
		for c: Node in existing_cams:
			var cam_node: Camera3D = c as Camera3D
			if cam_node != null and cam_node.current:
				has_current = true
				break
		if not has_current:
			camera.current = true
	else:
		camera.current = true


func _track_characters() -> void:
	if test_instance == null or camera == null or not camera.current:
		return

	var chars: Array[Node] = test_instance.find_children("*", "Character", true, false)
	if chars.is_empty():
		return

	var sum_pos: Vector3 = Vector3.ZERO
	var count: int = 0
	for ch_node: Node in chars:
		var ch: Character = ch_node as Character
		if ch != null and is_instance_valid(ch) and ch.is_inside_tree():
			sum_pos += ch.global_position
			count += 1

	if count > 0:
		var target: Vector3 = (sum_pos / float(count)) + Vector3(0.0, 1.0, 0.0)
		camera.look_at(target, Vector3.UP)


func _disable_all_ui() -> void:
	if hide_ui:
		var ui_node: Node = get_node_or_null("/root/UI")
		if ui_node != null and ui_node.has_method("set_overlays_visible"):
			ui_node.set_overlays_visible(false)
		var overlays: Array[Node] = get_tree().root.find_children("*", "LevelTitleOverlay", true, false)
		for ov: Node in overlays:
			ov.queue_free()

	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st != null:
		st.visible = false
		var cr: ColorRect = st.get_node_or_null("ColorRect") as ColorRect
		if cr != null:
			cr.visible = false
