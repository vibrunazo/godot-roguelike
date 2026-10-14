## Copy this file to {{TEST_DIR}}/test_<feature>.gd and create
## {{TEST_DIR}}/test_<feature>.tscn (a single Node whose script is the copied
## file). `kit.py test` collects every {{TEST_DIR}}/test_*.tscn; this template
## has no .tscn, so it never runs.
##
## One sentence per behavior this suite protects goes here, e.g.
## "Dashing moves the character dash_speed * dash_duration meters and starts
## the dash cooldown; a second dash is refused until the cooldown elapses."
##
## Rules (the write-test skill, .claude/skills/write-test/SKILL.md, adds the
## workflow and known pitfalls):
## - Assert behavior, never tuning: every expected number is either set by the
##   test itself or read from the live node (attack.damage, dash.cooldown...).
##   Comparing two tuned values ("the boss hits harder than the scout") is
##   tuning too: a designer can legitimately swap them. Set the values the
##   mechanism needs in the test instead. Never assert what a .tres contains.
## - Go through the path the game itself uses (AGENTS.md names it), never a
##   helper that only tests call.
## - Wait on conditions (wait_until / wait_signal), never on fixed frame
##   counts or wall-clock timers. Visual feedback (tweens, animations) runs on
##   the render clock: wait for it, don't assume it shows after one tick.
## - A "must not happen" check watches the whole window (poll every frame and
##   remember if it ever happened); one sample at the end misses anything that
##   already faded or decayed.
## - Drive input by action name (press_action(&"jump")), never physical keys.
## - Engine errors only print as notes. When the regression is an engine error
##   (a locked Area3D, an empty mesh surface), end the test with
##   check_no_engine_errors().
## - Use public methods only; if a test needs a hook, add a documented public one.
## - Everything the test creates goes through spawn()/autofree() so teardown
##   frees it; leaked orphan nodes fail the test.
## - A mechanic that must hold at any frame rate declares
##   "## fps_matrix: 12, 20, 30, 60" on a line of its own.
extends "res://{{TEST_DIR}}/lib/project_suite.gd"

## Test-owned speed for the example below: the test sets every number it checks.
const TEST_SPEED: float = 4.0


func test_replace_me_with_a_behavior() -> void:
	var mover: Node3D = autofree(Node3D.new()) as Node3D
	add_child(mover)
	mover.position.x += TEST_SPEED
	check_approx(mover.position.x, TEST_SPEED, "replace this test with the behavior the suite protects")
