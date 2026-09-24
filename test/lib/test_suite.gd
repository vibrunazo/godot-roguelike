## Base class for every automated test suite (test/test_*.tscn).
##
## A suite is a scene whose root script extends this file:
##     extends "res://test/lib/test_suite.gd"
## (test/ is .gdignore'd, so class_name would not register; extend by path.)
##
## Every method named test_* runs in declaration order, each in isolation:
## before_each() -> test -> after_each() -> automatic teardown. A failed check
## records the failure and the test keeps going, and a failing test never stops
## later tests. When all tests are done the suite prints a summary and quits
## with exit code 0 (all passed) or 1 (any failure) exactly once.
##
## A test also fails when:
## - a script error happens while it runs (Godot aborts the function but keeps
##   going, so without this the test would silently report PASS), or
## - it leaks orphan nodes. Teardown frees every node registered with
##   autofree()/spawn()/load_arena() (queue_free when in the tree, free when
##   orphaned), flushes frames, then compares the orphan-node count with the
##   count before the test. An orphan is a node that was created but is neither
##   in the tree nor freed; it leaks with all of its server resources.
##
## See test/lib/suite_template.gd for a copyable starting point and
## test/test_character_rotation.gd for a complete suite.
extends Node

## Default frame budget for wait_until()/wait_signal() when a test passes none.
const DEFAULT_WAIT_FRAMES: int = 300
## Scene loaded by load_arena(): flat floor, baked navmesh, light, spawn markers.
const ARENA_SCENE_PATH: String = "res://test/fixtures/arena.tscn"
## Frames flushed after teardown so queue_free and deferred calls settle.
const TEARDOWN_FLUSH_FRAMES: int = 2


## Collects errors reported while a test runs. Script errors fail the test;
## other errors (engine errors, push_error) are printed as notes.
class _ErrorCapture extends Logger:
	var _mutex: Mutex = Mutex.new()
	var _script_errors: Array[String] = []
	var _other_errors: Array[String] = []

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var text: String = code if rationale.is_empty() else "%s (%s)" % [code, rationale]
		var entry: String = "%s @ %s:%d" % [text, file.get_file(), line]
		_mutex.lock()
		if error_type == ERROR_TYPE_SCRIPT:
			_script_errors.append(entry)
		elif error_type == ERROR_TYPE_ERROR:
			_other_errors.append(entry)
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	## Returns and clears [script_errors, other_errors].
	func take() -> Array[Array]:
		_mutex.lock()
		var result: Array[Array] = [_script_errors.duplicate(), _other_errors.duplicate()]
		_script_errors.clear()
		_other_errors.clear()
		_mutex.unlock()
		return result


var _current_failures: Array[String] = []
var _autofree_nodes: Array[Node] = []
var _error_capture: _ErrorCapture = null


## Override to prepare state shared by every test (runs once, may await).
func before_all() -> void:
	pass


## Override to prepare per-test state (runs before each test, may await).
func before_each() -> void:
	pass


## Override to clean up per-test state (runs after each test, may await).
## Nodes registered with autofree() are freed automatically afterwards.
func after_each() -> void:
	pass


func _ready() -> void:
	_run_suite()


func _run_suite() -> void:
	var suite_name: String = name if scene_file_path.is_empty() else scene_file_path.get_file().get_basename()
	var tests: Array[String] = _discover_tests()
	print("=== %s: %d test(s) ===" % [suite_name, tests.size()])
	if tests.is_empty():
		print("FAIL %s: no test_* methods found." % suite_name)
		get_tree().quit(1)
		return
	_error_capture = _ErrorCapture.new()
	OS.add_logger(_error_capture)
	await before_all()
	_error_capture.take()
	var failed_tests: Array[String] = []
	for test_name: String in tests:
		var passed: bool = await _run_test(test_name)
		if not passed:
			failed_tests.append(test_name)
	OS.remove_logger(_error_capture)
	if failed_tests.is_empty():
		print("=== %s: ALL %d PASSED ===" % [suite_name, tests.size()])
		get_tree().quit(0)
	else:
		print("=== %s: %d/%d FAILED: %s ===" % [suite_name, failed_tests.size(), tests.size(), ", ".join(failed_tests)])
		get_tree().quit(1)


## Runs one test with hooks, teardown, the script-error check and the orphan
## check. Returns pass/fail.
func _run_test(test_name: String) -> bool:
	_current_failures.clear()
	_error_capture.take()
	var orphans_before: int = _orphan_count()
	var started_ms: int = Time.get_ticks_msec()
	await before_each()
	await call(test_name)
	await after_each()
	await _teardown()
	var errors: Array[Array] = _error_capture.take()
	for script_error: String in errors[0]:
		_record_failure("script error: " + script_error)
	var leaked: int = _orphan_count() - orphans_before
	if leaked > 0:
		print_orphan_nodes()
		_record_failure("%d orphan node(s) leaked (listed above): something was created and never added to the tree or freed." % leaked)
	var elapsed_ms: int = Time.get_ticks_msec() - started_ms
	if _current_failures.is_empty():
		print("PASS %s (%d ms)" % [test_name, elapsed_ms])
	else:
		print("FAIL %s (%d ms)" % [test_name, elapsed_ms])
		for failure: String in _current_failures:
			print("  - " + failure)
	for other_error: String in errors[1]:
		print("  note: error reported during %s: %s" % [test_name, other_error])
	return _current_failures.is_empty()


func _discover_tests() -> Array[String]:
	var names: Array[String] = []
	for method: Dictionary in (get_script() as Script).get_script_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and not names.has(method_name):
			names.append(method_name)
	return names


func _teardown() -> void:
	for node: Node in _autofree_nodes:
		if not is_instance_valid(node):
			continue
		if node.is_inside_tree():
			node.queue_free()
		else:
			node.free()
	_autofree_nodes.clear()
	for i: int in range(TEARDOWN_FLUSH_FRAMES):
		await get_tree().process_frame


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


# --- Assertions --------------------------------------------------------------

## Soft assertion: records a failure (with the calling line) when condition is
## false and lets the test continue. Returns condition so callers can bail out
## early when later steps depend on it: `if not check(x != null, "..."): return`.
func check(condition: bool, message: String) -> bool:
	if not condition:
		_record_failure(message, _caller_location())
	return condition


## Equality check that prints both values on failure. Compare against values
## the test set itself or read from live nodes, never against literals copied
## from scenes (designers retune those; see AGENTS.md test rules).
func check_eq(actual: Variant, expected: Variant, message: String) -> bool:
	if actual == expected:
		return true
	_record_failure("%s (expected %s, got %s)" % [message, str(expected), str(actual)], _caller_location())
	return false


## Float comparison. tolerance < 0.0 uses is_equal_approx; otherwise passes
## when |actual - expected| <= tolerance.
func check_approx(actual: float, expected: float, message: String, tolerance: float = -1.0) -> bool:
	var ok: bool = is_equal_approx(actual, expected) if tolerance < 0.0 else absf(actual - expected) <= tolerance
	if ok:
		return true
	var tolerance_text: String = "" if tolerance < 0.0 else ", tolerance %s" % str(tolerance)
	_record_failure("%s (expected %s, got %s%s)" % [message, str(expected), str(actual), tolerance_text], _caller_location())
	return false


## Records an unconditional failure. Returns false for `return fail("...")`.
func fail(message: String) -> bool:
	_record_failure(message, _caller_location())
	return false


func _record_failure(message: String, location: String = "") -> void:
	_current_failures.append(message if location.is_empty() else "%s @ %s" % [message, location])


## First stack frame outside this harness file, as "file.gd:line". Only
## meaningful before the caller's first await (a resumed coroutine has no
## caller frames), so waits capture it up front.
func _caller_location() -> String:
	for frame: Dictionary in get_stack():
		var source: String = frame.get("source", "")
		if not source.ends_with("test/lib/test_suite.gd"):
			return "%s:%d" % [source.get_file(), int(frame.get("line", 0))]
	return ""


# --- Waiting -----------------------------------------------------------------

## Waits physics frames until predicate returns true. Returns true on success;
## on timeout records a failure with message and returns false. Always wait on
## a condition instead of a fixed number of frames or seconds.
func wait_until(predicate: Callable, message: String, max_physics_frames: int = DEFAULT_WAIT_FRAMES) -> bool:
	var location: String = _caller_location()
	for i: int in range(max_physics_frames):
		if predicate.call():
			return true
		await get_tree().physics_frame
	if predicate.call():
		return true
	_record_failure("%s (timed out after %d physics frames)" % [message, max_physics_frames], location)
	return false


## Waits until sig emits. Returns true on emission; on timeout records a
## failure with message and returns false.
func wait_signal(sig: Signal, message: String, max_physics_frames: int = DEFAULT_WAIT_FRAMES) -> bool:
	var location: String = _caller_location()
	var fired: Array[bool] = [false]
	var on_emit: Callable = func() -> void: fired[0] = true
	var arg_count: int = _signal_arg_count(sig)
	if arg_count > 0:
		on_emit = on_emit.unbind(arg_count)
	sig.connect(on_emit, CONNECT_ONE_SHOT)
	for i: int in range(max_physics_frames):
		if fired[0]:
			return true
		await get_tree().physics_frame
	if sig.is_connected(on_emit):
		sig.disconnect(on_emit)
	if fired[0]:
		return true
	_record_failure("%s (signal %s not emitted within %d physics frames)" % [message, sig.get_name(), max_physics_frames], location)
	return false


func _signal_arg_count(sig: Signal) -> int:
	for info: Dictionary in sig.get_object().get_signal_list():
		if info["name"] == sig.get_name():
			return (info["args"] as Array).size()
	return 0


## Advances n physics frames. Prefer wait_until(); use this only when the
## number of frames is itself the thing under test, or to let freshly spawned
## nodes run their first tick.
func wait_physics_frames(n: int) -> void:
	for i: int in range(n):
		await get_tree().physics_frame


# --- Scene setup -------------------------------------------------------------

## Registers a node for automatic teardown after the current test. Returns it.
func autofree(node: Node) -> Node:
	if node != null and not _autofree_nodes.has(node):
		_autofree_nodes.append(node)
	return node


## Instantiates scene, adds it under parent (the suite itself when null),
## places it at the given global position (Node3D only) and registers it for
## teardown. Returns the instance.
func spawn(scene: PackedScene, parent: Node = null, at: Vector3 = Vector3.ZERO) -> Node:
	var instance: Node = scene.instantiate()
	autofree(instance)
	(parent if parent != null else self).add_child(instance)
	if instance is Node3D:
		(instance as Node3D).global_position = at
	return instance


## Loads the shared test arena (flat floor with a baked navmesh, a light, and
## PlayerSpawn/EnemySpawn markers; no enemies, no wave, no GI) under the suite
## and registers it for teardown. Use it for mechanics tests instead of real
## levels so level redesigns never break them. Regenerate it with
## test/fixtures/build_arena.gd, never by hand.
func load_arena() -> Node3D:
	return spawn(load(ARENA_SCENE_PATH) as PackedScene) as Node3D


## Stops a character's AI mind so only the test drives it.
func disable_ai(character: Character) -> void:
	if character != null and character.ai_state_machine != null:
		character.ai_state_machine.process_mode = Node.PROCESS_MODE_DISABLED


# --- Input -------------------------------------------------------------------

## Sends a press and a release of an InputMap action through the input
## pipeline (reaches _input/_unhandled_input like a real key press). Always
## refer to actions by name, never by physical key.
func press_action(action: StringName) -> void:
	hold_action(action)
	release_action(action)


## Sends a press of an InputMap action and leaves it held.
func hold_action(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


## Sends a release of an InputMap action.
func release_action(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
