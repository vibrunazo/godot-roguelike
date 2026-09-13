## Animation & Character capturer utility for staging, inspecting, and recording animations.
##
## Supports:
## 1. Character scenes (.tscn) - Enemy Brute, Melee Enemy, Firebomber, Player, etc.
## 2. Standalone animation resource files (.res) mounted onto base rigs.
## 3. Source animation GLB archives (e.g. Rig_Medium_CombatMelee.glb).
## Supports target dummy placement, collision shape visualization, slow-motion,
## and exact timestamp screenshot or video recording into the movies/ folder.
class_name AnimCapturer
extends Node3D

var target_path: String = "res://Enemy/enemy_brute.tscn"
var anim_name: String = ""
var state_name: String = ""
var rig_path: String = ""
var output_path: String = ""
var cam_angle: String = "three_quarters"
var speed_scale: float = 1.0
var screenshot_time: float = -1.0 # -1 means auto (apex or mid-point)
var is_video: bool = false
var has_dummy: bool = false
var debug_collisions: bool = false
var duration_sec: float = 0.0

var frame_count: int = 0
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var character_instance: Node3D
var dummy_instance: Node3D
var camera: Camera3D
var total_anim_length: float = 1.0
var target_screenshot_frame: int = 20


func _ready() -> void:
	_parse_arguments()
	_setup_studio()
	_setup_camera()
	_load_target()
	if has_dummy:
		_spawn_dummy()
	_start_playback()


func _physics_process(_delta: float) -> void:
	frame_count += 1
	_hide_transition_overlay()

	if is_video:
		var target_frames: int = int(total_anim_length * 60.0) + 10
		if duration_sec > 0.0:
			target_frames = int(duration_sec * 60.0)
		if frame_count >= target_frames:
			print("[AnimCapturer] Finished video recording (frames: %d)" % frame_count)
			get_tree().quit(0)
		return

	# Screenshot mode
	if frame_count == target_screenshot_frame:
		var file_to_save: String = output_path
		if file_to_save.is_empty():
			file_to_save = _generate_default_screenshot_path()
		_save_screenshot(file_to_save)

	if frame_count >= target_screenshot_frame + 3:
		print("[AnimCapturer] Animation screenshot capture completed.")
		get_tree().quit(0)


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--target="):
			target_path = arg.trim_prefix("--target=").strip_edges()
		elif arg.begins_with("--anim="):
			anim_name = arg.trim_prefix("--anim=").strip_edges()
		elif arg.begins_with("--state="):
			state_name = arg.trim_prefix("--state=").strip_edges()
		elif arg.begins_with("--rig="):
			rig_path = arg.trim_prefix("--rig=").strip_edges()
		elif arg.begins_with("--output="):
			output_path = arg.trim_prefix("--output=").strip_edges()
		elif arg.begins_with("--cam-angle="):
			cam_angle = arg.trim_prefix("--cam-angle=").strip_edges().to_lower()
		elif arg.begins_with("--speed="):
			speed_scale = arg.trim_prefix("--speed=").to_float()
		elif arg.begins_with("--time="):
			screenshot_time = arg.trim_prefix("--time=").to_float()
		elif arg.begins_with("--duration="):
			duration_sec = arg.trim_prefix("--duration=").to_float()
		elif arg == "--video":
			is_video = true
		elif arg == "--dummy":
			has_dummy = true
		elif arg == "--debug-collisions":
			debug_collisions = true

	if not target_path.begins_with("res://") and not target_path.begins_with("user://"):
		target_path = "res://" + target_path.trim_prefix("./").trim_prefix("/")


func _setup_studio() -> void:
	if debug_collisions:
		get_tree().debug_collisions_hint = true

	_hide_transition_overlay()

	# Key light with soft shadow
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	key_light.light_energy = 1.2
	key_light.shadow_enabled = true
	add_child(key_light)

	# Fill light from opposite side
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, -140.0, 0.0)
	fill_light.light_energy = 0.4
	fill_light.shadow_enabled = false
	add_child(fill_light)

	# Floor
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	var floor_col: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(30.0, 1.0, 30.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)

	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0.0, 0.5, 0.0)
	var floor_mat: StandardMaterial3D = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.18, 0.20, 0.23, 1.0)
	floor_mat.roughness = 0.8
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)
	add_child(floor_body)


func _setup_camera() -> void:
	camera = Camera3D.new()
	camera.name = "StudioCamera"
	camera.current = true
	camera.fov = 42.0
	add_child(camera)

	var look_target: Vector3 = Vector3(0.0, 1.1, 0.0)
	match cam_angle:
		"front":
			camera.position = Vector3(0.0, 1.4, 4.2)
		"side":
			camera.position = Vector3(4.2, 1.4, 0.0)
		"top_down":
			camera.position = Vector3(0.0, 5.0, 0.001)
			look_target = Vector3(0.0, 0.0, 0.0)
			camera.look_at(look_target, Vector3(0.0, 0.0, -1.0))
			return
		"three_quarters", _:
			camera.position = Vector3(3.2, 2.0, 3.6)

	camera.look_at(look_target, Vector3.UP)


func _load_target() -> void:
	if not ResourceLoader.exists(target_path):
		printerr("[AnimCapturer] ERROR: Target path not found: ", target_path)
		get_tree().quit(1)
		return

	if target_path.ends_with(".res"):
		_load_animation_resource(target_path)
	elif target_path.ends_with(".glb"):
		_load_glb_target(target_path)
	elif target_path.ends_with(".tscn"):
		_load_tscn_target(target_path)
	else:
		printerr("[AnimCapturer] ERROR: Unsupported file type: ", target_path)
		get_tree().quit(1)


func _load_tscn_target(path: String) -> void:
	var scn: PackedScene = load(path) as PackedScene
	if scn == null:
		printerr("[AnimCapturer] ERROR: Could not load PackedScene: ", path)
		get_tree().quit(1)
		return

	character_instance = scn.instantiate() as Node3D
	character_instance.position = Vector3.ZERO
	add_child(character_instance)

	anim_player = character_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	anim_tree = character_instance.find_child("AnimationTree", true, false) as AnimationTree

	# If Character, prevent movement AI from taking over
	if character_instance is Character:
		var c: Character = character_instance as Character
		if c.ai_state_machine != null:
			c.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED


func _load_glb_target(path: String) -> void:
	var scn: PackedScene = load(path) as PackedScene
	character_instance = scn.instantiate() as Node3D
	character_instance.position = Vector3.ZERO
	add_child(character_instance)
	anim_player = character_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _load_animation_resource(path: String) -> void:
	var anim: Animation = load(path) as Animation
	if anim == null:
		printerr("[AnimCapturer] ERROR: Could not load Animation resource: ", path)
		get_tree().quit(1)
		return

	# Choose appropriate base rig
	var actual_rig: String = rig_path
	if actual_rig.is_empty():
		if path.contains("Rig_Large"):
			actual_rig = "res://Assets/KayKit_Assets/KayKit_GameDevTV_Enemies_Character_Pack_1.0/Characters/gltf/Enemy_Large.glb"
		else:
			actual_rig = "res://Assets/KayKit_Assets/KayKit_GameDevTV_Enemies_Character_Pack_1.0/Characters/gltf/Enemy_Medium.glb"

	if not ResourceLoader.exists(actual_rig):
		printerr("[AnimCapturer] ERROR: Rig model not found: ", actual_rig)
		get_tree().quit(1)
		return

	var rig_scn: PackedScene = load(actual_rig) as PackedScene
	character_instance = rig_scn.instantiate() as Node3D
	character_instance.position = Vector3.ZERO
	add_child(character_instance)

	anim_player = character_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		character_instance.add_child(anim_player)

	var anim_id: String = path.get_file().get_basename()
	var lib: AnimationLibrary = AnimationLibrary.new()
	lib.add_animation(anim_id, anim)
	anim_player.add_animation_library("preview", lib)
	anim_name = "preview/" + anim_id
	total_anim_length = anim.length


func _spawn_dummy() -> void:
	var dummy_path: String = "res://Player/player.tscn"
	# If staging Player, spawn Melee Enemy as dummy; otherwise spawn Player
	if target_path.contains("player"):
		dummy_path = "res://Enemy/melee_enemy.tscn"

	var dummy_scn: PackedScene = load(dummy_path) as PackedScene
	if dummy_scn != null:
		dummy_instance = dummy_scn.instantiate() as Node3D
		dummy_instance.position = Vector3(0.0, 0.0, 1.8)
		dummy_instance.rotation_degrees = Vector3(0.0, 180.0, 0.0) # Facing target
		add_child(dummy_instance)

		# Freeze dummy AI
		if dummy_instance is Character:
			var dc: Character = dummy_instance as Character
			dc.set_physics_process(false)
			if dc.ai_state_machine != null:
				dc.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED
			var tint: CanvasItem = dc.find_child("DamageTint", true, false) as CanvasItem
			if tint != null:
				tint.visible = false


func _start_playback() -> void:
	if not state_name.is_empty():
		_trigger_state(state_name)
		return

	if anim_player == null:
		printerr("[AnimCapturer] WARNING: No AnimationPlayer found on target.")
		return

	# Disable AnimationTree if we are playing directly on AnimationPlayer
	if anim_tree != null:
		anim_tree.active = false

	# Resolve animation name
	var resolved_anim: String = _resolve_animation_name(anim_name)
	if resolved_anim.is_empty():
		var all_anims: PackedStringArray = anim_player.get_animation_list()
		if not all_anims.is_empty():
			# Pick first non-RESET, non-T-Pose
			for a: String in all_anims:
				if a != "RESET" and not a.contains("T-Pose") and not a.contains("T_Pose"):
					resolved_anim = a
					break
			if resolved_anim.is_empty():
				resolved_anim = all_anims[0]
			print("[AnimCapturer] Auto-selected animation: ", resolved_anim)
		else:
			printerr("[AnimCapturer] ERROR: No animations found in AnimationPlayer.")
			return

	var anim_res: Animation = anim_player.get_animation(resolved_anim)
	if anim_res != null:
		total_anim_length = anim_res.length / maxf(speed_scale, 0.01)

	anim_player.speed_scale = speed_scale
	anim_player.play(resolved_anim)
	print("[AnimCapturer] Playing animation: ", resolved_anim, " (length: %.2fs, speed: %.2f)" % [total_anim_length, speed_scale])

	# Calculate screenshot target frame
	if screenshot_time >= 0.0:
		target_screenshot_frame = maxi(int(screenshot_time * 60.0), 5)
	else:
		# Default to apex (midpoint of animation or 0.3s)
		var snap_time: float = minf(total_anim_length * 0.45, 0.5)
		target_screenshot_frame = maxi(int(snap_time * 60.0), 15)


func _trigger_state(p_state: String) -> void:
	if character_instance is Character:
		var c: Character = character_instance as Character
		if c.state_machine != null:
			c.state_machine.request_state(p_state)
			print("[AnimCapturer] Requested StateMachine state: ", p_state)
			total_anim_length = 1.5
			if screenshot_time >= 0.0:
				target_screenshot_frame = maxi(int(screenshot_time * 60.0), 5)
			else:
				target_screenshot_frame = 25


func _resolve_animation_name(query: String) -> String:
	if anim_player == null:
		return ""
	var list: PackedStringArray = anim_player.get_animation_list()
	if list.has(query):
		return query

	# Try with library prefixes
	var candidate: String = "EnemyAnimations/" + query
	if list.has(candidate):
		return candidate

	candidate = "PlayerAnimations/" + query
	if list.has(candidate):
		return candidate

	candidate = "preview/" + query
	if list.has(candidate):
		return candidate

	# Case-insensitive / partial match
	for a: String in list:
		if a.to_lower() == query.to_lower():
			return a
		if a.get_file().to_lower() == query.to_lower():
			return a

	return ""


func _generate_default_screenshot_path() -> String:
	var base: String = target_path.get_file().get_basename()
	var tag: String = anim_name.get_file().get_basename()
	if tag.is_empty():
		tag = state_name
	if tag.is_empty():
		tag = "anim"
	return "movies/%s_%s_%s.png" % [base, tag, cam_angle]


func _hide_transition_overlay() -> void:
	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st != null:
		st.visible = false
		var cr: ColorRect = st.get_node_or_null("ColorRect") as ColorRect
		if cr != null:
			cr.visible = false


func _save_screenshot(file_path: String) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var tex: ViewportTexture = viewport.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return

	var base_dir: String = file_path.get_base_dir()
	if not base_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(base_dir)

	var err: Error = img.save_png(file_path)
	if err == OK:
		print("[AnimCapturer] Screenshot saved successfully: ", file_path, " (", img.get_width(), "x", img.get_height(), ")")
	else:
		printerr("[AnimCapturer] Failed to save screenshot: ", file_path, " error: ", err)
