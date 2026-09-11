## Helper recording scene to capture video and screenshots of Enemy Brute dual attacks
## (Punch, Slam, Stunlockability, Stun-break, and Hyper-Armor) with visible debug shapes.
extends Node3D

var frame_count: int = 0
var brute: Character
var player: Character
var body_sm: StateMachine
var ai_sm: AIStateMachine
var ai_slam: AIConditionalAttack


func _ready() -> void:
	# Force collision shapes to be drawn in viewport
	get_tree().debug_collisions_hint = true

	# Hide SceneTransition fade overlay so initial frames are not washed out
	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st:
		st.visible = false

	# Directional light
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 45.0, 0.0)
	light.shadow_enabled = true
	add_child(light)

	# Camera with clear 3/4 angle
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(3.8, 2.5, 4.2)
	cam.look_at(Vector3(-0.3, 1.3, 1.5))

	# Visual floor
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
	floor_mesh.position = Vector3(0.0, 1.0, 0.0)
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
	ai_sm = brute.ai_state_machine
	ai_slam = ai_sm.get_node_or_null("AISlam") as AIConditionalAttack

	# Spawn Player target inside punch/slam range
	var player_scene: PackedScene = load("res://Player/player.tscn")
	player = player_scene.instantiate() as Character
	player.position = Vector3(-0.3, 0.0, 2.4)
	var tint: CanvasItem = player.get_node_or_null("DamageTint") as CanvasItem
	if tint:
		tint.visible = false
	add_child(player)


func _physics_process(_delta: float) -> void:
	frame_count += 1

	if frame_count == 10:
		# Trigger Punch Attack
		body_sm.request_state("EnemyPunch")

	if frame_count == 20:
		# Punch windup
		_save_screenshot("movies/brute_punch_windup.png")

	if frame_count == 38:
		# Punch apex strike: fist hitbox visibly active in cyan debug overlapping player
		_save_screenshot("movies/brute_punch_apex.png")

	if frame_count == 70:
		# Trigger second punch to demonstrate stunlockability
		body_sm.request_state("EnemyPunch")

	if frame_count == 76:
		# Hit brute during punch windup -> interrupts punch into EnemyStun
		brute.health_component.take_damage(10.0)

	if frame_count == 84:
		# Stun state screenshot (punch was interrupted)
		_save_screenshot("movies/brute_punch_stunlocked.png")

	if frame_count == 90:
		# Reset player position inside slam range (was knocked back by punch)
		player.position = Vector3(-0.3, 0.0, 2.4)
		player.velocity = Vector3.ZERO
		if player.knockback_component:
			player.knockback_component.magnitude = Vector3.ZERO

	if frame_count == 95:
		# AISlam stun break: while in EnemyStun, AISlam triggers and breaks free into EnemyAttack
		ai_slam.cooldown_timer = 0.0
		ai_slam.evaluate_trigger(0.016)

	if frame_count == 115:
		# Slam windup / stun break screenshot (raising weapon overhead out of stun)
		_save_screenshot("movies/brute_slam_stunbreak.png")

	if frame_count == 130:
		# Test hyper-armor: hit brute with damage during slam windup
		brute.health_component.take_damage(10.0)

	if frame_count == 138:
		# Hyper-armor proof screenshot (brute absorbed damage without entering stun, still swinging)
		_save_screenshot("movies/brute_slam_hyperarmor.png")

	if frame_count == 155:
		# Slam impact apex screenshot (shockwave hitting floor)
		_save_screenshot("movies/brute_slam_impact.png")

	if frame_count == 190:
		# Slam recovery screenshot
		_save_screenshot("movies/brute_slam_recovery.png")

	if frame_count >= 220:
		print("Dual attack recording sequence completed successfully.")
		get_tree().quit(0)


func _save_screenshot(file_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
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
