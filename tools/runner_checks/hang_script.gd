## Runner-check fixture: a -s script stuck in _init() (an endless loop), so no
## frame ever runs and --quit-after cannot end it. run_scratch.py must kill it
## at its timeout.
extends SceneTree


func _init() -> void:
	while true:
		OS.delay_msec(100)
	quit(0)
