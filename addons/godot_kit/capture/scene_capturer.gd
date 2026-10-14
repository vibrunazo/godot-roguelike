## Captures any 3D scene for `kit.py capture scene`: one screenshot, every
## preset angle, a contact sheet of frames over time, or (with Godot's
## --write-movie) a video. Run by kit.py with user arguments after `--`.
##
## The camera is a preset framing the scene's visual bounds, a custom position,
## or the scene's own current camera (--scene-camera). Game time advances a
## fixed step per frame (kit.py runs it with --fixed-fps or --write-movie), so
## --at and sheet times are exact game seconds.
##
## Projects hide HUDs and fades with capture.hide_paths (node paths such as
## /root/UI) or by adding nodes to the "capture_hidden" group, and keep huge
## props (a ground plane) out of the framing with the "capture_bounds_ignore" group.
##
## User arguments after SCENE_ARGS belong to the captured scene (`kit.py capture
## scene <scene> -- <args>`), which reads them itself; the capturer ignores them.
extends Node3D

const CaptureImage: GDScript = preload("res://addons/godot_kit/capture/capture_image.gd")
## Frames the scene runs before the first capture so shaders and lights settle.
const SETTLE_FRAMES: int = 15
const PRESETS: Array[String] = ["isometric", "top_down", "front", "side", "overview"]
## Marks where the arguments forwarded to the captured scene begin.
const SCENE_ARGS: String = "--scene-args"

var _options: Dictionary = {
	"scene": "", "preset": "isometric", "at": 0.25, "sheet": 0, "duration": 3.0,
	"output": "", "output_dir": "movies", "cam_fov": 50.0, "cam_dist": 1.0, "cam_height": 0.0,
	"cam_size": 30.0, "target_node": "", "video": false, "hide_ui": false, "freeze": false,
	"scene_camera": false, "ortho": false, "debug_collisions": false,
}
var _hide_paths: Array[String] = []
var _custom_pos: Variant = null
var _custom_target: Variant = null
var _scene: Node = null
var _camera: Camera3D = null
var _center: Vector3 = Vector3.ZERO
var _size: Vector3 = Vector3(20.0, 5.0, 20.0)
var _frame: int = 0
var _elapsed: float = 0.0
var _sheet_frames: Array[Image] = []
var _preset_index: int = 0
var _done: bool = false


func _ready() -> void:
	_parse_arguments()
	if _options["debug_collisions"]:
		get_tree().debug_collisions_hint = true
	if not _load_scene():
		return
	_calculate_bounds()
	_setup_camera()


func _process(delta: float) -> void:
	# Sequencing runs on render frames: get_image() returns the last rendered
	# frame, so a camera move and its screenshot must land on different frames.
	_frame += 1
	_elapsed += delta
	_hide_ui()
	if _done:
		return
	if _options["video"]:
		_finish_when(_elapsed >= float(_options["duration"]), "Done recording %.2f s" % _elapsed)
	elif int(_options["sheet"]) > 0:
		_step_sheet()
	elif _options["preset"] == "all" and not _options["scene_camera"]:
		_step_all_presets()
	elif _frame >= SETTLE_FRAMES and _elapsed >= float(_options["at"]):
		_save(_output_path(_options["preset"] if not _options["scene_camera"] else "scene"))
		_finish_when(true, "Screenshot captured at %.2f s" % _elapsed)


func _physics_process(_delta: float) -> void:
	_hide_ui()


func _step_sheet() -> void:
	var count: int = int(_options["sheet"])
	var due: float = float(_options["duration"]) * float(_sheet_frames.size() + 1) / count
	if _frame >= SETTLE_FRAMES and _elapsed >= due:
		_sheet_frames.append(CaptureImage.grab(get_viewport()))
	if _sheet_frames.size() >= count:
		var path: String = _output_path("sheet")
		CaptureImage.save(CaptureImage.contact_sheet(_sheet_frames, mini(count, 3)), path, "SceneCapturer", true)
		_finish_when(true, "Contact sheet of %d frames over %.2f s" % [count, _elapsed])


func _step_all_presets() -> void:
	if _preset_index >= PRESETS.size():
		_finish_when(true, "All presets captured")
		return
	var apply_frame: int = SETTLE_FRAMES + _preset_index * 5
	if _frame == apply_frame:
		_apply_preset(PRESETS[_preset_index])
	elif _frame == apply_frame + 2:
		_save(_output_path(PRESETS[_preset_index]))
		_preset_index += 1


func _finish_when(condition: bool, message: String) -> void:
	if condition and not _done:
		_done = true
		print("[SceneCapturer] %s." % message)
		get_tree().quit(0)


func _parse_arguments() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == SCENE_ARGS:
			break
		var key: String = arg.trim_prefix("--").get_slice("=", 0).replace("-", "_")
		var value: String = arg.get_slice("=", 1) if arg.contains("=") else ""
		match key:
			"hide_path":
				_hide_paths.append(value)
			"hide_ui", "video", "freeze", "scene_camera", "debug_collisions":
				_options[key] = true
			"cam_ortho":
				_options["ortho"] = true
			"cam_pos":
				_custom_pos = _parse_vector(value)
			"cam_target":
				_custom_target = _parse_vector(value)
			"at", "duration", "cam_fov", "cam_dist", "cam_height", "cam_size":
				_options[key] = value.to_float()
			"sheet":
				_options[key] = value.to_int()
			"scene", "preset", "output", "output_dir", "target_node":
				_options[key] = value.strip_edges()
	var scene_path: String = _options["scene"]
	if not scene_path.begins_with("res://") and not scene_path.begins_with("uid://"):
		_options["scene"] = "res://" + scene_path.trim_prefix("./").trim_prefix("/")


func _parse_vector(text: String) -> Variant:
	var parts: PackedStringArray = text.split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()) if parts.size() == 3 else null


func _load_scene() -> bool:
	var scene_path: String = _options["scene"]
	var packed: PackedScene = load(scene_path) as PackedScene if ResourceLoader.exists(scene_path) else null
	if packed == null:
		printerr("[SceneCapturer] ERROR: cannot load scene: ", scene_path)
		get_tree().quit(1)
		return false
	_scene = packed.instantiate()
	add_child(_scene)
	if _options["freeze"]:
		_scene.process_mode = Node.PROCESS_MODE_DISABLED
	return true


func _calculate_bounds() -> void:
	var target_name: String = _options["target_node"]
	if not target_name.is_empty():
		var target: Node3D = _scene.find_child(target_name, true, false) as Node3D
		if target != null:
			_center = target.global_position
			_size = Vector3(10.0, 5.0, 10.0)
			print("[SceneCapturer] Framing node %s at %s" % [target_name, _center])
			return
		printerr("[SceneCapturer] Node %s not found; framing the whole scene." % target_name)
	var box: AABB = AABB()
	var has_box: bool = false
	# Geometry only: a light's range would inflate the framing.
	for node: Node in _scene.find_children("*", "GeometryInstance3D", true, false):
		var visual: GeometryInstance3D = node as GeometryInstance3D
		if visual.is_in_group(&"capture_bounds_ignore") or not visual.is_visible_in_tree():
			continue
		var visual_box: AABB = visual.global_transform * visual.get_aabb()
		box = visual_box if not has_box else box.merge(visual_box)
		has_box = true
	if has_box and box.size.length() > 1.0:
		_center = box.get_center()
		_size = box.size
	print("[SceneCapturer] Scene bounds: center %s, size %s" % [_center, _size])


func _setup_camera() -> void:
	if _options["scene_camera"]:
		if get_viewport().get_camera_3d() != null:
			print("[SceneCapturer] Using the scene's own camera: ", get_viewport().get_camera_3d().name)
			return
		printerr("[SceneCapturer] The scene has no current camera; using the preset instead.")
		_options["scene_camera"] = false
	_camera = Camera3D.new()
	_camera.name = "CaptureCamera"
	_camera.fov = float(_options["cam_fov"])
	if _options["ortho"]:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = float(_options["cam_size"])
	add_child(_camera)
	_camera.make_current()
	_apply_preset(PRESETS[0] if _options["preset"] == "all" else String(_options["preset"]))


func _apply_preset(preset: String) -> void:
	var target: Vector3 = _custom_target if _custom_target != null else _center
	var dim: float = maxf(maxf(_size.x, _size.z), 14.0) * float(_options["cam_dist"])
	var height: float = float(_options["cam_height"])
	var up: Vector3 = Vector3.UP
	if _custom_pos != null:
		_camera.global_position = _custom_pos
	else:
		match preset:
			"top_down":
				_camera.global_position = target + Vector3(0.0, dim * 1.2 + height, 0.001)
				up = Vector3.FORWARD
			"front":
				_camera.global_position = target + Vector3(0.0, dim * 0.3 + height, dim * 0.9)
			"side":
				_camera.global_position = target + Vector3(dim * 0.9, dim * 0.3 + height, 0.0)
			"overview":
				_camera.global_position = target + Vector3(dim * 0.5, dim * 0.9 + height, dim * 0.8)
			_:
				_camera.global_position = target + Vector3(dim * 0.7, dim * 0.75 + height, dim * 0.7)
	_camera.look_at(target, up)


func _hide_ui() -> void:
	if not _options["hide_ui"]:
		return
	for path: String in _hide_paths:
		var node: Node = get_node_or_null(NodePath(path))
		if node != null and "visible" in node:
			node.set("visible", false)
	for node: Node in get_tree().get_nodes_in_group(&"capture_hidden"):
		if "visible" in node:
			node.set("visible", false)


func _output_path(suffix: String) -> String:
	var explicit: String = _options["output"]
	if not explicit.is_empty() and _options["preset"] != "all":
		return explicit
	var scene_name: String = String(_options["scene"]).get_file().get_basename()
	return "%s/%s_%s.png" % [_options["output_dir"], scene_name, suffix]


func _save(path: String) -> void:
	CaptureImage.save(CaptureImage.grab(get_viewport()), path, "SceneCapturer")
