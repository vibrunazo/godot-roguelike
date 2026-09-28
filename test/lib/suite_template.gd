## Copy this file to test/test_<feature>.gd and create test/test_<feature>.tscn
## (a single Node whose script is the copied file). The runner collects every
## test/test_*.tscn automatically. This template itself has no .tscn, so it
## never runs.
##
## One sentence per behavior this suite protects goes here, e.g.
## "Dashing moves the character dash_speed * dash_duration meters and starts
## the dash cooldown; a second dash is refused until the cooldown elapses."
##
## Rules (AGENTS.md has the full list):
## - Assert behavior, never tuning: every expected number is either set by the
##   test itself or read from the live node (attack.damage, dash.cooldown...).
##   Comparing two tuned values ("boss hits harder than the brute") is tuning
##   too: a designer can legitimately swap them. Set the values the mechanism
##   needs in the test instead (e.g. give the target full fire resistance).
## - Wait on conditions (wait_until / wait_signal), never on fixed frame
##   counts or wall-clock timers. Visual feedback (tweens, animations) runs on
##   the render clock: wait for it, don't assume it shows after one tick.
## - A "must not happen" check watches the whole window (poll every frame and
##   remember if it ever happened); one sample at the end misses anything that
##   already faded or decayed.
## - Drive input by action name (press_action(&"jump")), never physical keys.
## - Engine errors only print as notes. When the regression is an engine error
##   (a locked Area3D, an empty ImmediateMesh surface), end the test with
##   check_no_engine_errors().
## - Use public methods only; if a test needs a hook, add a documented public one.
## - Everything the test creates goes through spawn()/autofree()/load_arena()
##   so teardown frees it; leaked orphan nodes fail the test.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")

var _arena: Node3D


func before_each() -> void:
	_arena = load_arena()


func test_player_lands_on_arena_floor() -> void:
	var spawn_point: Vector3 = (_arena.get_node("PlayerSpawn") as Node3D).global_position
	var player: Character = spawn(PLAYER_SCENE, _arena, spawn_point) as Character
	if not await wait_until(func() -> bool: return player.is_on_floor(), "player should land on the arena floor"):
		return
	check(player.is_alive(), "player should be alive after spawning")
