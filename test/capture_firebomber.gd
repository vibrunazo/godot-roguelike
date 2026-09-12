extends Node3D

var frame_count: int = 0
var dest_path: String = "C:/Users/vibru/.gemini/antigravity/brain/bc855baf-9e75-4bce-a2bf-dc53e493b2fe/orange_firebomber.png"
var fb: Character


func _ready() -> void:
	# Disable any screen overlays / transition fades
	if has_node("/root/SceneTransition"):
		var st: CanvasLayer = get_node("/root/SceneTransition") as CanvasLayer
		st.visible = false
		var cr: ColorRect = st.get_node_or_null("ColorRect") as ColorRect
		if cr:
			cr.visible = false

	var scn: PackedScene = load("res://Enemy/firebomber_enemy.tscn") as PackedScene
	fb = scn.instantiate() as Character
	add_child(fb)
	fb.position = Vector3(0.0, 1.0, 0.0)
	fb.rotation_degrees = Vector3(0.0, -25.0, 0.0)
	
	# Freeze physics and state machines so character stays in place
	fb.set_physics_process(false)
	fb.velocity = Vector3.ZERO
	if fb.state_machine:
		fb.state_machine.set_physics_process(false)
		fb.state_machine.set_process(false)
	if fb.ai_state_machine:
		fb.ai_state_machine.set_physics_process(false)
		fb.ai_state_machine.set_process(false)
	
	var anim_tree: AnimationTree = fb.animation_tree
	if anim_tree:
		anim_tree.active = false
	var ap: AnimationPlayer = fb.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap:
		ap.play("EnemyAnimations/Idle_A")
		ap.seek(0.2, true)


func _process(_delta: float) -> void:
	frame_count += 1
	if has_node("/root/SceneTransition"):
		var st: CanvasLayer = get_node("/root/SceneTransition") as CanvasLayer
		st.visible = false
	
	if frame_count == 15:
		_save_screenshot(dest_path)
		_save_screenshot("movies/orange_firebomber.png")
	
	if frame_count >= 20:
		print("Finished capturing orange firebomber.")
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
		print("Saved screenshot to: ", file_path, " err: ", err)
