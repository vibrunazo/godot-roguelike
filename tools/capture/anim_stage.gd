## Staging scene for animation captures: a lit studio floor, a camera, and a
## target playing one animation or StateMachine state, optionally facing a
## frozen dummy. It only stages: `kit.py capture scene` takes the screenshot,
## contact sheet or video and ends the run.
##
##   python addons/godot_kit/kit.py capture scene tools/capture/anim_stage.tscn --scene-camera --at 0.5 -- --target=Enemy/enemy_brute.tscn --state=EnemyPunch --dummy
##
## Targets: a character scene (.tscn), an animation resource (.res) mounted on
## a base rig, or a source GLB (.glb). Arguments after `--` (read after the
## kit's --scene-args marker): --target=, --anim=, --state=, --rig=,
## --cam-angle=three_quarters|front|side|top_down, --cam-dist=, --cam-height=,
## --cam-fov=, --speed= (playback speed scale) and --dummy.
extends Node3D

var target_path: String = "res://Enemy/enemy_brute.tscn"
var anim_name: String = ""
var state_name: String = ""
var rig_path: String = ""
var cam_angle: String = "three_quarters"
var speed_scale: float = 1.0
var has_dummy: bool = false
var cam_dist: float = 1.0
var cam_height: float = 0.0
var cam_fov: float = 42.0

var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var character_instance: Node3D
var dummy_instance: Node3D
var camera: Camera3D


func _ready() -> void:
	_parse_arguments()
	_setup_studio()
	_setup_camera()
	_load_target()
	if has_dummy:
		_spawn_dummy()
	_start_playback()


func _physics_process(_delta: float) -> void:
	# Actor scenes (the player) bring cameras of their own.
	if camera != null and not camera.is_current():
		camera.make_current()


func _parse_arguments() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args.slice(args.find("--scene-args") + 1):
		var key: String = arg.get_slice("=", 0)
		var value: String = arg.get_slice("=", 1).strip_edges() if arg.contains("=") else ""
		match key:
			"--target":
				target_path = value
			"--anim":
				anim_name = value
			"--state":
				state_name = value
			"--rig":
				rig_path = value
			"--cam-angle":
				cam_angle = value.to_lower()
			"--cam-dist":
				cam_dist = value.to_float()
			"--cam-height":
				cam_height = value.to_float()
			"--cam-fov":
				cam_fov = value.to_float()
			"--speed":
				speed_scale = value.to_float()
			"--dummy":
				has_dummy = true
	if not target_path.begins_with("res://") and not target_path.begins_with("user://"):
		target_path = "res://" + target_path.trim_prefix("./").trim_prefix("/")


func _setup_studio() -> void:
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
	camera.fov = cam_fov
	add_child(camera)

	var look_target: Vector3 = Vector3(0.0, 1.1, 0.0)
	var base_cam_pos: Vector3 = Vector3(3.2, 2.0, 3.6)
	match cam_angle:
		"front":
			base_cam_pos = Vector3(0.0, 1.4, 4.2)
		"side":
			base_cam_pos = Vector3(4.2, 1.4, 0.0)
		"top_down":
			base_cam_pos = Vector3(0.0, 5.0, 0.001)
			look_target = Vector3(0.0, 0.0, 0.0)
			var td_scale: float = cam_dist if cam_dist > 0.0 else 1.0
			camera.position = Vector3(0.0, (base_cam_pos.y + cam_height) * td_scale, 0.001)
			camera.look_at(look_target, Vector3(0.0, 0.0, -1.0))
			return
		"three_quarters", _:
			base_cam_pos = Vector3(3.2, 2.0, 3.6)

	var offset: Vector3 = base_cam_pos - look_target
	var dist_scale: float = cam_dist if cam_dist > 0.0 else 1.0
	offset.x *= dist_scale
	offset.z *= dist_scale
	offset.y = offset.y * dist_scale + cam_height

	camera.position = look_target + offset
	camera.look_at(look_target, Vector3.UP)


func _load_target() -> void:
	if not ResourceLoader.exists(target_path):
		printerr("[AnimStage] ERROR: Target path not found: ", target_path)
		get_tree().quit(1)
		return

	if target_path.ends_with(".res"):
		_load_animation_resource(target_path)
	elif target_path.ends_with(".glb"):
		_load_glb_target(target_path)
	elif target_path.ends_with(".tscn"):
		_load_tscn_target(target_path)
	else:
		printerr("[AnimStage] ERROR: Unsupported file type: ", target_path)
		get_tree().quit(1)


func _load_tscn_target(path: String) -> void:
	var scn: PackedScene = load(path) as PackedScene
	if scn == null:
		printerr("[AnimStage] ERROR: Could not load PackedScene: ", path)
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
		# Multi-rig characters (e.g. a boss carrying rider rigs) nest extra
		# players and trees; prefer the Character's own rig so captures drive
		# the main body instead of a passenger.
		if c.animation_tree != null:
			anim_tree = c.animation_tree
			var tree_player: Node = anim_tree.get_node_or_null(anim_tree.anim_player)
			if tree_player is AnimationPlayer:
				anim_player = tree_player as AnimationPlayer

	_suppress_actor_cameras(character_instance)


func _load_glb_target(path: String) -> void:
	var scn: PackedScene = load(path) as PackedScene
	character_instance = scn.instantiate() as Node3D
	character_instance.position = Vector3.ZERO
	add_child(character_instance)
	anim_player = character_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _load_animation_resource(path: String) -> void:
	var anim: Animation = load(path) as Animation
	if anim == null:
		printerr("[AnimStage] ERROR: Could not load Animation resource: ", path)
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
		printerr("[AnimStage] ERROR: Rig model not found: ", actual_rig)
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

		_suppress_actor_cameras(dummy_instance)


func _start_playback() -> void:
	if not state_name.is_empty():
		_trigger_state(state_name)
		return

	if anim_player == null:
		printerr("[AnimStage] WARNING: No AnimationPlayer found on target.")
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
			print("[AnimStage] Auto-selected animation: ", resolved_anim)
		else:
			printerr("[AnimStage] ERROR: No animations found in AnimationPlayer.")
			return

	var anim_res: Animation = anim_player.get_animation(resolved_anim)
	var length: float = anim_res.length / maxf(speed_scale, 0.01) if anim_res != null else 0.0
	anim_player.speed_scale = speed_scale
	anim_player.play(resolved_anim)
	print("[AnimStage] Playing animation: ", resolved_anim, " (length: %.2fs, speed: %.2f)" % [length, speed_scale])


func _trigger_state(p_state: String) -> void:
	if character_instance is Character:
		var c: Character = character_instance as Character
		if c.state_machine != null:
			c.state_machine.request_state(p_state)
			print("[AnimStage] Requested StateMachine state: ", p_state)


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


## Recursively suppresses any active Camera3D nodes inside spawned targets/dummies to avoid viewport conflicts.
func _suppress_actor_cameras(actor: Node) -> void:
	if actor == null:
		return
	var actor_cams: Array[Node] = actor.find_children("*", "Camera3D", true, false)
	for cam_node: Node in actor_cams:
		var c: Camera3D = cam_node as Camera3D
		if c != null:
			if c.current:
				print("[AnimStage] Note: Suppressed active actor camera '%s' on %s to preserve studio camera." % [c.name, actor.name])
			c.current = false
	var cam_root: Node = actor.find_child("CameraRoot", true, false)
	if cam_root != null:
		cam_root.queue_free()
	if camera != null and not camera.is_current():
		camera.make_current()
