## Map capturer utility for headless/CLI screenshot and video capture of levels.
##
## Instantiates target levels, automatically calculates level geometry bounds,
## positions capture cameras according to presets or custom coordinates,
## and saves screenshots or records video directly into the movies/ folder.
class_name MapCapturer
extends Node3D

## Available preset camera angles.
enum CameraPreset {
	ISOMETRIC,
	TOP_DOWN,
	FRONT,
	SIDE,
	OVERVIEW,
	ALL,
	CUSTOM
}

var level_path: String = "res://Levels/level_1.tscn"
var preset_name: String = "isometric"
var output_path: String = ""
var custom_cam_pos: Vector3 = Vector3.ZERO
var custom_cam_target: Vector3 = Vector3.ZERO
var has_custom_pos: bool = false
var has_custom_target: bool = false
var target_node_name: String = ""
var cam_fov: float = 50.0
var cam_dist_mult: float = 1.0
var cam_height_offset: float = 0.0
var is_ortho: bool = false
var ortho_size: float = 30.0
var debug_collisions: bool = false
var freeze_actors: bool = false
var is_video: bool = false
var max_frames: int = 20
var frame_count: int = 0

var camera: Camera3D
var level_instance: Node3D
var level_center: Vector3 = Vector3.ZERO
var level_size: Vector3 = Vector3(20.0, 5.0, 20.0)
var all_presets: Array[String] = ["isometric", "top_down", "front", "side", "overview"]
var all_preset_index: int = 0


func _ready() -> void:
	_parse_arguments()
	_configure_environment()
	_load_level()
	_setup_camera()
	_apply_preset(preset_name)


func _physics_process(_delta: float) -> void:
	frame_count += 1

	# Keep SceneTransition hidden
	_hide_transition_overlay()

	if is_video:
		if frame_count >= max_frames:
			print("[MapCapturer] Video frame recording finished (frames: %d)" % frame_count)
			get_tree().quit(0)
		return

	# Screenshot mode
	if preset_name == "all":
		# Capture each preset sequentially every 5 frames
		var trigger_frame: int = 15 + (all_preset_index * 5)
		if frame_count == trigger_frame and all_preset_index < all_presets.size():
			var current_preset: String = all_presets[all_preset_index]
			_apply_preset(current_preset)
			var preset_file: String = _get_preset_output_path(current_preset)
			_save_screenshot(preset_file)
			all_preset_index += 1

		if all_preset_index >= all_presets.size() and frame_count >= trigger_frame + 2:
			print("[MapCapturer] All presets captured successfully.")
			get_tree().quit(0)
	else:
		# Wait 15 frames for shaders, materials, and lighting to settle
		if frame_count == 15:
			var target_file: String = output_path
			if target_file.is_empty():
				target_file = _get_preset_output_path(preset_name)
			_save_screenshot(target_file)

		if frame_count >= 18:
			print("[MapCapturer] Screenshot capture completed.")
			get_tree().quit(0)


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--level="):
			level_path = arg.trim_prefix("--level=").strip_edges()
		elif arg.begins_with("--preset="):
			preset_name = arg.trim_prefix("--preset=").strip_edges().to_lower()
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=").strip_edges()
		elif arg.begins_with("--cam-pos="):
			var parts: PackedStringArray = arg.trim_prefix("--cam-pos=").split(",")
			if parts.size() == 3:
				custom_cam_pos = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
				has_custom_pos = true
		elif arg.begins_with("--cam-target="):
			var parts: PackedStringArray = arg.trim_prefix("--cam-target=").split(",")
			if parts.size() == 3:
				custom_cam_target = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
				has_custom_target = true
		elif arg.begins_with("--target-node="):
			target_node_name = arg.trim_prefix("--target-node=").strip_edges()
		elif arg.begins_with("--cam-fov="):
			cam_fov = arg.trim_prefix("--cam-fov=").to_float()
		elif arg.begins_with("--cam-dist="):
			cam_dist_mult = arg.trim_prefix("--cam-dist=").to_float()
		elif arg.begins_with("--cam-height="):
			cam_height_offset = arg.trim_prefix("--cam-height=").to_float()
		elif arg.begins_with("--cam-size="):
			ortho_size = arg.trim_prefix("--cam-size=").to_float()
		elif arg == "--cam-ortho":
			is_ortho = true
		elif arg == "--debug-collisions":
			debug_collisions = true
		elif arg == "--freeze":
			freeze_actors = true
		elif arg == "--video":
			is_video = true
		elif arg.begins_with("--frames="):
			max_frames = arg.trim_prefix("--frames=").to_int()
		elif arg.begins_with("--duration="):
			var duration_sec: float = arg.trim_prefix("--duration=").to_float()
			max_frames = int(duration_sec * 60.0)

	# Ensure path begins with res:// if relative
	if not level_path.begins_with("res://") and not level_path.begins_with("user://"):
		level_path = "res://" + level_path.trim_prefix("./").trim_prefix("/")


func _configure_environment() -> void:
	if debug_collisions:
		get_tree().debug_collisions_hint = true

	_hide_transition_overlay()


func _hide_transition_overlay() -> void:
	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st != null:
		st.visible = false
		var cr: ColorRect = st.get_node_or_null("ColorRect") as ColorRect
		if cr != null:
			cr.visible = false


func _load_level() -> void:
	if not ResourceLoader.exists(level_path):
		printerr("[MapCapturer] ERROR: Level path does not exist: ", level_path)
		get_tree().quit(1)
		return

	var scene: PackedScene = load(level_path) as PackedScene
	if scene == null:
		printerr("[MapCapturer] ERROR: Failed to load level scene: ", level_path)
		get_tree().quit(1)
		return

	level_instance = scene.instantiate() as Node3D
	add_child(level_instance)

	_calculate_bounds()

	if freeze_actors:
		_freeze_level_actors(level_instance)


func _calculate_bounds() -> void:
	# If a specific target node is specified, center on it
	if not target_node_name.is_empty():
		var target_node: Node3D = level_instance.find_child(target_node_name, true, false) as Node3D
		if target_node != null:
			level_center = target_node.global_position
			level_size = Vector3(10.0, 5.0, 10.0)
			print("[MapCapturer] Focused on target node: ", target_node_name, " at ", level_center)
			return

	var aabb: AABB = AABB()
	var has_aabb: bool = false

	# Calculate from GridMaps
	var gridmaps: Array[Node] = level_instance.find_children("*", "GridMap", true, false)
	for gm_node: Node in gridmaps:
		var gm: GridMap = gm_node as GridMap
		if gm != null:
			var cells: Array[Vector3i] = gm.get_used_cells()
			for cell: Vector3i in cells:
				var world_pos: Vector3 = gm.to_global(gm.map_to_local(cell))
				var cell_box: AABB = AABB(world_pos - (gm.cell_size * 0.5), gm.cell_size)
				if not has_aabb:
					aabb = cell_box
					has_aabb = true
				else:
					aabb = aabb.merge(cell_box)

	# Calculate from MeshInstances if no GridMaps found
	if not has_aabb:
		var meshes: Array[Node] = level_instance.find_children("*", "MeshInstance3D", true, false)
		for mesh_node: Node in meshes:
			var mi: MeshInstance3D = mesh_node as MeshInstance3D
			if mi != null and mi.mesh != null:
				var mesh_box: AABB = mi.global_transform * mi.mesh.get_aabb()
				if not has_aabb:
					aabb = mesh_box
					has_aabb = true
				else:
					aabb = aabb.merge(mesh_box)

	if has_aabb and aabb.size.length() > 1.0:
		level_center = aabb.get_center()
		level_size = aabb.size
	else:
		# Fallback to level origin
		level_center = Vector3(0.0, 1.0, 0.0)
		level_size = Vector3(24.0, 6.0, 24.0)

	print("[MapCapturer] Level bounds: center = ", level_center, " size = ", level_size)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "CaptureCamera"
	camera.current = true
	camera.fov = cam_fov
	if is_ortho:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = ortho_size
	else:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	add_child(camera)


func _apply_preset(p_preset: String) -> void:
	var target: Vector3 = level_center
	if has_custom_target:
		target = custom_cam_target

	var max_dim: float = maxf(level_size.x, level_size.z)
	max_dim = maxf(max_dim, 14.0)

	if has_custom_pos:
		camera.global_position = custom_cam_pos
		camera.look_at(target, Vector3.UP)
		return

	match p_preset:
		"top_down":
			var cam_y: float = target.y + (max_dim * 1.2 * cam_dist_mult) + cam_height_offset
			camera.global_position = Vector3(target.x, cam_y, target.z + 0.001)
			camera.look_at(target, Vector3(0.0, 0.0, -1.0))
		"front":
			var cam_z: float = target.z + (max_dim * 0.9 * cam_dist_mult)
			var cam_y: float = target.y + (max_dim * 0.3 * cam_dist_mult) + cam_height_offset
			camera.global_position = Vector3(target.x, cam_y, cam_z)
			camera.look_at(target, Vector3.UP)
		"side":
			var cam_x: float = target.x + (max_dim * 0.9 * cam_dist_mult)
			var cam_y: float = target.y + (max_dim * 0.3 * cam_dist_mult) + cam_height_offset
			camera.global_position = Vector3(cam_x, cam_y, target.z)
			camera.look_at(target, Vector3.UP)
		"overview":
			var offset: Vector3 = Vector3(max_dim * 0.5, max_dim * 0.9 + cam_height_offset, max_dim * 0.8) * cam_dist_mult
			camera.global_position = target + offset
			camera.look_at(target, Vector3.UP)
		"isometric", _:
			var offset: Vector3 = Vector3(max_dim * 0.7, max_dim * 0.75 + cam_height_offset, max_dim * 0.7) * cam_dist_mult
			camera.global_position = target + offset
			camera.look_at(target, Vector3.UP)


func _get_preset_output_path(p_preset: String) -> String:
	var level_name: String = level_path.get_file().get_basename()
	var filename: String = "%s_%s.png" % [level_name, p_preset]
	return "movies/" + filename


func _freeze_level_actors(node: Node) -> void:
	if node is Character:
		var c: Character = node as Character
		c.set_physics_process(false)
		c.velocity = Vector3.ZERO
		if c.state_machine != null:
			c.state_machine.set_physics_process(false)
		if c.ai_state_machine != null:
			c.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children():
		_freeze_level_actors(child)


func _save_screenshot(file_path: String) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		printerr("[MapCapturer] Viewport is null, cannot take screenshot.")
		return
	var tex: ViewportTexture = viewport.get_texture()
	if tex == null:
		printerr("[MapCapturer] ViewportTexture is null.")
		return
	var img: Image = tex.get_image()
	if img == null:
		printerr("[MapCapturer] Texture image is null.")
		return

	var base_dir: String = file_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)

	var err: Error = img.save_png(file_path)
	if err == OK:
		print("[MapCapturer] Screenshot saved successfully: ", file_path, " (", img.get_width(), "x", img.get_height(), ")")
	else:
		printerr("[MapCapturer] Failed to save screenshot: ", file_path, " error: ", err)
