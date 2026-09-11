## Helper recording scene to capture video and screenshots of Enemy Brute animations
## with visible debug collision shapes to the movies/ folder.
extends Node3D

var frame_count: int = 0
var brute: Character
var player: Character
var body_sm: StateMachine


func _ready() -> void:
	# Force collision shapes to be drawn in viewport
	get_tree().debug_collisions_hint = true

	# Hide SceneTransition fade overlay so initial frames are not washed out
	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st:
		st.visible = false

	# Directional light
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 45.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	# Camera with clear 3/4 angle
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(4.5, 3.2, 6.0)
	cam.look_at(Vector3(0.0, 1.0, 1.8))

	# Visual floor with checker / grid material
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 2.0, 40.0)
	floor_col.shape = floor_box
	floor_body.add_child(floor_col)

	var floor_mesh := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(40.0, 40.0)
	floor_mesh.mesh = plane_mesh
	floor_mesh.position = Vector3(0.0, 1.0, 0.0) # top surface at y = 0
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.2, 0.22, 0.25, 1.0)
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	# Spawn Enemy Brute
	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn")
	brute = brute_scene.instantiate() as Character
	brute.position = Vector3.ZERO
	add_child(brute)
	body_sm = brute.state_machine

	# Spawn Player target inside AOE impact zone
	var player_scene: PackedScene = load("res://Player/player.tscn")
	player = player_scene.instantiate() as Character
	player.position = Vector3(0.0, 0.0, 2.8)
	var tint: CanvasItem = player.get_node_or_null("DamageTint") as CanvasItem
	if tint:
		tint.visible = false
	add_child(player)


func _physics_process(_delta: float) -> void:
	frame_count += 1

	if frame_count == 12:
		# Walking / Idle phase
		_save_screenshot("movies/brute_walk.png")

	if frame_count == 15:
		# Start 2H Slam attack
		body_sm.request_state("EnemyAttack")

	if frame_count == 40:
		# Windup phase (arms raised high)
		_save_screenshot("movies/brute_slam_windup.png")

	if frame_count == 72:
		# Ground impact apex (hands striking floor, AOE sphere active)
		_save_screenshot("movies/brute_slam_impact.png")

	if frame_count == 98:
		# Recovery phase (hands on ground, hitbox deactivated)
		_save_screenshot("movies/brute_slam_recovery.png")

	if frame_count == 145:
		# Trigger Stun animation
		brute.health_component.take_damage(20.0)

	if frame_count == 160:
		_save_screenshot("movies/brute_stun.png")

	if frame_count == 190:
		# Trigger Defeat animation
		brute.health_component.take_damage(100.0)

	if frame_count == 270:
		_save_screenshot("movies/brute_defeat.png")

	if frame_count >= 290:
		print("Recording sequence completed successfully.")
		get_tree().quit(0)


func _save_screenshot(file_path: String) -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var tex: ViewportTexture = viewport.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img != null:
		var dir_err: Error = DirAccess.make_dir_recursive_absolute("movies")
		if dir_err == OK or dir_err == ERR_ALREADY_EXISTS:
			img.save_png(file_path)
			print("Saved debug screenshot: ", file_path, " (", img.get_width(), "x", img.get_height(), ")")
