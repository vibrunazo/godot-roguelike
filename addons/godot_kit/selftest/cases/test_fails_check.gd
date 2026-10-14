## Self-test case: a failed check must fail the run with exit code 1.
extends "res://test/lib/project_suite.gd"


func test_deliberately_fails() -> void:
	check(false, "deliberate failure")


func test_later_test_still_runs() -> void:
	check(true, "a failing test never stops later tests")
