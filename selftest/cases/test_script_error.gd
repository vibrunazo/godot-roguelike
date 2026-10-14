## Self-test case: a script error inside a test must fail it, even though
## Godot only aborts the function.
extends "res://test/lib/project_suite.gd"


func test_hits_a_script_error() -> void:
	var missing: Node = null
	print(missing.name)
