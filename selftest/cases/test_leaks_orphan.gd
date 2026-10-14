## Self-test case: a node created and never freed or added must fail the test.
extends "res://test/lib/project_suite.gd"

var _leaked: Node = null


func test_leaks_a_node() -> void:
	_leaked = Node.new()
	check(_leaked != null, "the node exists")
