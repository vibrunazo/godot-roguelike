## The player's shake camera and camera rig:
## - with no trauma the camera has no offset and does no per-frame work,
## - setting trauma above zero turns the work on; back to zero turns it off
##   and resets the offset,
## - quick_shake() offsets the camera and decays back to rest within
##   shake_duration,
## - the rig follows the player horizontally and upward, but never drops
##   below the height it started at.
## Magnitudes and durations are read from the live camera.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned trauma for the direct-assignment check.
const TEST_TRAUMA: float = 0.5

var _player: Character
var _camera: ShakeCamera3D


func before_each() -> void:
	var arena: Node3D = load_arena()
	# Placed before entering the tree, as levels place their player: the
	# camera rig takes its height floor from where it enters the tree.
	_player = autofree(PLAYER_SCENE.instantiate()) as Character
	_player.position = (arena.get_node("PlayerSpawn") as Node3D).global_position
	arena.add_child(_player)
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	_camera = _player.get_node("CameraRoot/ShakeCamera3D") as ShakeCamera3D
	_camera.make_current()
	await wait_until(func() -> bool: return _player.is_on_floor(), "the player should land")


func test_no_trauma_means_no_offset_and_no_work() -> void:
	_camera.trauma = 0.0
	await wait_physics_frames(1)
	check(is_zero_approx(_camera.h_offset) and is_zero_approx(_camera.v_offset), "no trauma should mean no offset")
	check(not _camera.is_physics_processing(), "an idle camera should not process every frame")


func test_setting_trauma_switches_the_work_on_and_off() -> void:
	_camera.trauma = TEST_TRAUMA
	check(_camera.is_physics_processing(), "trauma above zero should switch processing on")
	await wait_physics_frames(1)
	_camera.trauma = 0.0
	check(not _camera.is_physics_processing(), "zero trauma should switch processing off")
	check(is_zero_approx(_camera.h_offset) and is_zero_approx(_camera.v_offset), "zero trauma should reset the offset")


func test_quick_shake_offsets_the_camera_then_settles_within_shake_duration() -> void:
	_camera.quick_shake(1.0)
	await wait_until(func() -> bool: return not is_zero_approx(_camera.h_offset) or not is_zero_approx(_camera.v_offset), "a shake should offset the camera", 10)
	var frames: int = ceili(_camera.shake_duration * Engine.physics_ticks_per_second) + 5
	await wait_until(func() -> bool: return is_zero_approx(_camera.trauma) and not _camera.is_physics_processing(), "the shake should settle within shake_duration", frames)
	check(is_zero_approx(_camera.h_offset) and is_zero_approx(_camera.v_offset), "a settled camera should have no offset")


func test_the_rig_follows_up_freely_but_never_below_its_starting_height() -> void:
	var rig: Node3D = _player.get_node("CameraRoot") as Node3D
	var start_y: float = rig.global_position.y
	# Freeze the body so the test alone moves it; the rig keeps following.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	var home: Vector3 = _player.global_position
	var below: Vector3 = home + Vector3(3.0, -4.0 - (home.y - start_y), -2.0)
	await _move_player(below)
	check(rig.global_position.is_equal_approx(Vector3(below.x, start_y, below.z)), "below its start the rig should follow horizontally but hold its starting height (at %s)" % rig.global_position)
	var above: Vector3 = Vector3(home.x - 2.0, start_y + 4.0, home.z + 1.0)
	await _move_player(above)
	check(rig.global_position.is_equal_approx(above), "above its start the rig should follow freely (at %s)" % rig.global_position)
	await _move_player(Vector3(home.x, start_y - 6.0, home.z))
	check_approx(rig.global_position.y, start_y, "coming back down, the rig should stop at its starting height, not at the highest point it reached")
	_player.process_mode = Node.PROCESS_MODE_INHERIT


## Teleports the player and lets the rig (render clock) catch up.
func _move_player(to: Vector3) -> void:
	_player.global_position = to
	await get_tree().process_frame
	await get_tree().process_frame
