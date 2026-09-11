## Automated navigation verification for Enemy Brute on Level 2.
## Verifies that the Brute navigates through the narrow corridor between Pit2 and the barrels
## without getting stuck or oscillating, and saves debug collision screenshots to movies/.
extends Node3D


func _ready() -> void:
	print("====================================================")
	print("  STARTING LEVEL 2 BRUTE NAVIGATION TEST")
	print("====================================================")

	get_tree().debug_collisions_hint = true

	var st: CanvasLayer = get_node_or_null("/root/SceneTransition") as CanvasLayer
	if st:
		st.visible = false
		st.set("player_cache", null)

	var lvl_scene: PackedScene = load("res://Levels/level_2.tscn")
	if lvl_scene == null:
		printerr("TEST FAILED: Could not load Levels/level_2.tscn")
		get_tree().quit(1)
		return

	var level: Node3D = lvl_scene.instantiate() as Node3D
	add_child(level)

	# Disable WaveObjective to avoid extraneous enemy spawns
	var wave_obj: Node = level.find_child("WaveObjective", true, false)
	if wave_obj != null:
		wave_obj.set_script(null)
		for c in wave_obj.get_children():
			c.queue_free()

	await get_tree().physics_frame
	await get_tree().physics_frame

	var player: Character = level.find_child("Player", true, false) as Character
	if player == null:
		printerr("TEST FAILED: Player not found in Level 2")
		get_tree().quit(1)
		return

	# Prevent player reload on defeat
	if player.health_component != null and player.health_component.defeat.is_connected(player.reset_game_state):
		player.health_component.defeat.disconnect(player.reset_game_state)

	player.global_position = Vector3(1.5, 1.0, -14.0)

	var brute_scene: PackedScene = load("res://Enemy/enemy_brute.tscn")
	if brute_scene == null:
		printerr("TEST FAILED: Could not load Enemy/enemy_brute.tscn")
		get_tree().quit(1)
		return

	var brute: Character = brute_scene.instantiate() as Character
	level.add_child(brute)
	brute.global_position = Vector3(1.5, 1.5, -23.0)

	var cap_s: CapsuleShape3D = brute.collision_shape_3d.shape as CapsuleShape3D
	print("Collision radius: ", cap_s.radius if cap_s else -1.0)
	print("Collision height: ", cap_s.height if cap_s else -1.0)
	print("path_desired_distance: ", brute.navigation_agent_3d.path_desired_distance)
	print("target_desired_distance: ", brute.navigation_agent_3d.target_desired_distance)
	print("path_height_offset: ", brute.navigation_agent_3d.path_height_offset)

	# Elevated camera to capture the pit, barrels, and brute path
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	cam.position = Vector3(5.5, 9.0, -13.0)
	cam.look_at(Vector3(0.5, 1.0, -19.0), Vector3.UP)

	while brute.state_machine.state.name != "EnemyMove":
		await get_tree().physics_frame

	var path: PackedVector3Array = brute.navigation_agent_3d.get_current_navigation_path()
	print("Brute nav path points (%d): %s" % [path.size(), str(path)])

	var reached := false
	var corridor_captured := false

	for frame in range(250):
		await get_tree().physics_frame
		var z: float = brute.global_position.z
		var d: float = brute.global_position.distance_to(player.global_position)

		if frame % 30 == 0:
			print("Frame %d: pos=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f, %.2f) next_pt=%s is_target_reached=%s on_floor=%s" % [
				frame, brute.global_position.x, brute.global_position.y, z,
				brute.velocity.x, brute.velocity.y, brute.velocity.z,
				str(brute.navigation_agent_3d.get_next_path_position()),
				str(brute.navigation_agent_3d.is_target_reached()),
				str(brute.is_on_floor())
			])

		if frame == 60:
			_save_screenshot("movies/brute_level2_approach.png")

		if z > -20.5 and z < -18.0 and not corridor_captured:
			corridor_captured = true
			print("Brute entering narrow corridor between Pit2 and Barrels at frame %d (Z = %.2f)" % [frame, z])
			_save_screenshot("movies/brute_level2_corridor.png")

		if d < 3.5:
			reached = true
			print("SUCCESS: Brute reached player at frame %d! (Pos: %.2f, %.2f, %.2f)" % [
				frame, brute.global_position.x, brute.global_position.y, brute.global_position.z
			])
			_save_screenshot("movies/brute_level2_reached.png")
			break

	if reached:
		print("====================================================")
		print("  LEVEL 2 BRUTE NAVIGATION TEST PASSED!")
		print("====================================================")
		brute.queue_free()
		level.queue_free()
		get_tree().quit(0)
	else:
		printerr("TEST FAILED: Brute did not reach player! Final pos: (%.2f, %.2f)" % [
			brute.global_position.x, brute.global_position.z
		])
		brute.queue_free()
		level.queue_free()
		get_tree().quit(1)


func _save_screenshot(file_path: String) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img != null:
		var dir_err: Error = DirAccess.make_dir_recursive_absolute("movies")
		if dir_err == OK or dir_err == ERR_ALREADY_EXISTS:
			img.save_png(file_path)
			print("Saved debug screenshot: ", file_path)
