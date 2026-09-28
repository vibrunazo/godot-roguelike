## Mouse aim (no auto-aim target):
## - The aim direction follows the mouse: pointing to either side of the
##   player on screen gives opposite horizontal aim directions.
## - With no auto-aim target in range, an attack turns the player toward the
##   mouse aim at the player's rotation speed.
## (Attacks turning toward an auto-aim target instead of the mouse are covered
## by test_targeting.)
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned screen offset of the mouse from the player, in pixels.
const MOUSE_OFFSET: float = 200.0
## Minimum facing alignment (cosine) that counts as "turned toward the aim".
const TURNED: float = 0.85

var _player: Character
var _input: PlayerInputComponent


func before_each() -> void:
	var arena: Node3D = load_arena()
	_player = spawn(PLAYER_SCENE, arena, (arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_input = _player.get_node("PlayerInputComponent") as PlayerInputComponent
	(_player.get_node("CameraRoot/ShakeCamera3D") as Camera3D).make_current()
	# The headless window is tiny, so the stretch transform would scale mouse
	# coordinates; a window at the project's base size maps them one to one.
	var base_size: Vector2i = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width") as int, ProjectSettings.get_setting("display/window/size/viewport_height") as int)
	get_window().size = base_size
	await wait_until(func() -> bool: return Vector2i(get_viewport().get_visible_rect().size) == base_size, "the viewport should take the window size", 30)
	# The camera's projection catches up with the new size on a later render
	# frame: wait until the player's screen position holds still between two
	# render frames (physics ticks alone would not show the change).
	var last: Vector2 = Vector2.INF
	for frame: int in range(10):
		await get_tree().process_frame
		var now: Vector2 = _input.get_character_position_2d()
		if now.is_equal_approx(last):
			return
		last = now
	fail("the player's screen position should settle")
	await wait_until(func() -> bool: return _player.is_on_floor() and _player.state_machine.state.name == "PlayerRun", "the player should settle")


func test_aim_direction_follows_the_mouse() -> void:
	var on_screen: Vector2 = _input.get_character_position_2d()
	await _move_mouse(on_screen + Vector2(MOUSE_OFFSET, 0.0))
	var aim_right: Vector3 = _input.get_aim_direction()
	await _move_mouse(on_screen - Vector2(MOUSE_OFFSET, 0.0))
	var aim_left: Vector3 = _input.get_aim_direction()
	if not check(not aim_right.is_zero_approx() and not aim_left.is_zero_approx(), "the aim direction should not be zero"):
		return
	check(is_zero_approx(aim_right.y) and is_zero_approx(aim_left.y), "the aim direction should be horizontal")
	check(aim_right.normalized().dot(aim_left.normalized()) < -0.9, "aiming to opposite sides of the player should give opposite directions")


func test_attack_turns_toward_the_mouse_aim_without_a_target() -> void:
	check(_player.current_target == null, "setup: nothing to auto-aim at in an empty arena")
	var facing: Vector3 = _flat(_player.mesh_mount.global_basis.z)
	# Put the mouse on screen at a point 90 degrees to the player's side.
	var side: Vector3 = Vector3(-facing.z, 0.0, facing.x)
	var camera: Camera3D = _player.get_viewport().get_camera_3d()
	await _move_mouse(camera.unproject_position(_player.global_position + side * 3.0))
	var aim: Vector3 = _flat(_input.get_aim_direction())
	if not check(aim.dot(facing) < TURNED, "setup: the mouse aim should point away from the current facing"):
		return
	press_action(&"click")
	var budget: int = ceili(180.0 / _player.get_rotation_speed() * Engine.physics_ticks_per_second) + 5
	await wait_until(func() -> bool: return _flat(_player.mesh_mount.global_basis.z).dot(aim) >= TURNED, "the attack should turn the player toward the mouse aim", budget)


## Moves the mouse and waits until the viewport reports the new position
## (input is flushed per render frame, so at a low frame rate several physics
## ticks can pass before the mouse position updates).
func _move_mouse(screen_position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = screen_position
	motion.global_position = screen_position
	Input.parse_input_event(motion)
	_player.get_viewport().warp_mouse(screen_position)
	await wait_until(func() -> bool: return _player.get_viewport().get_mouse_position().distance_to(screen_position) < 1.0, "the mouse should move to %s" % screen_position, 30)


func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z).normalized()
