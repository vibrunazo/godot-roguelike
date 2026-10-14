## The project's main scene loads and runs for a second of game time without
## script errors (the harness fails the test on any script error).
extends "res://test/lib/project_suite.gd"

## Physics frames the main scene runs before the test ends.
const RUN_FRAMES: int = 60


func test_main_scene_runs_without_script_errors() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if not check(not main_scene.is_empty(), "the project should have a main scene"):
		return
	var packed: PackedScene = load(main_scene) as PackedScene
	if not check(packed != null, "the main scene should load"):
		return
	spawn(packed)
	await wait_physics_frames(RUN_FRAMES)
