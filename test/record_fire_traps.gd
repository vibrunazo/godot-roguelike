extends Node3D

var frame_count: int = 0
var trap_1: FireTrap
var trap_2: FireTrap
var trap_3: FireTrap


func _ready() -> void:
	# Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	light.light_energy = 0.7
	add_child(light)

	# World environment for dark backdrop
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.08, 0.1, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.22, 0.25, 1.0)
	env_node.environment = env
	add_child(env_node)

	# Camera with top-down 3/4 view of all traps
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 2.8, 4.5)
	cam.look_at(Vector3(0.0, 0.35, 0.0))

	# Dark floor plane to contrast with fire particles
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20.0, 20.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.13, 0.15, 1.0)
	floor_mat.roughness = 0.85
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	var trap_scene: PackedScene = load("res://Hazards/fire_trap.tscn")

	# Trap 1: 1m x 1m (default) on the left
	trap_1 = trap_scene.instantiate() as FireTrap
	add_child(trap_1)
	trap_1.position = Vector3(-2.8, 0.0, 0.0)

	# Trap 2: 2m x 2m in the center
	trap_2 = trap_scene.instantiate() as FireTrap
	add_child(trap_2)
	trap_2.position = Vector3(0.0, 0.0, 0.0)
	trap_2.set_trap_size(Vector2(2.0, 2.0))

	# Trap 3: 3.2m x 1.5m on the right
	trap_3 = trap_scene.instantiate() as FireTrap
	add_child(trap_3)
	trap_3.position = Vector3(3.2, 0.0, 0.0)
	trap_3.set_trap_size(Vector2(3.2, 1.5))


func _physics_process(_delta: float) -> void:
	frame_count += 1

	# Allow particles to emit and fill space
	if frame_count == 20:
		_save_screenshot("movies/fire_trap_comparison.png")
		_save_screenshot("D:/docs/godot/godot-roguelite-starting-project/movies/fire_trap_comparison.png")

	if frame_count == 22:
		print("Screenshots captured successfully.")
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
		var dir_path: String = file_path.get_base_dir()
		DirAccess.make_dir_recursive_absolute(dir_path)
		var err: Error = img.save_png(file_path)
		if err == OK:
			print("Saved screenshot to: ", file_path, " (", img.get_width(), "x", img.get_height(), ")")
		else:
			printerr("Failed to save screenshot: ", err)
