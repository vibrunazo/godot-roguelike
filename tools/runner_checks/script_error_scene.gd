## Runner-check fixture: hits a script error, then exits 0. Godot only aborts
## the failing function, so the exit code alone would report success; the
## runners must still fail the run.
extends Node


func _ready() -> void:
	_fail_at_runtime()
	get_tree().quit(0)


func _fail_at_runtime() -> void:
	var missing: Node = null
	print(missing.name)
