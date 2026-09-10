extends Node

const TestUtils = preload("res://test/test_utils.gd")

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if condition:
		print("  ok: ", message)
	else:
		failures += 1
		printerr("TEST FAILED: ", message)


func _ready() -> void:
	print("--- RUNNING SIGNAL LIFECYCLE TEST ---")
	_part1_helper_idempotence()
	if failures > 0:
		get_tree().quit(1)
		return
	await _part2_no_stale_attack_callback()
	if failures > 0:
		get_tree().quit(1)
		return
	print("\n====================================================================")
	print("  ALL SIGNAL LIFECYCLE TESTS PASSED!                                ")
	print("  1. connect_one_shot is idempotent, fires once, auto-disconnects  ")
	print("  2. disconnect_safe is a no-op when nothing is connected          ")
	print("  3. PlayerAttack exit removes animation_finished wiring           ")
	print("  4. Dash-cancelled attack never triggers a stale transition       ")
	print("====================================================================")
	get_tree().quit(0)


## Part 1: Unit checks for the State signal lifecycle helpers (TODO #6).
func _part1_helper_idempotence() -> void:
	print("\n>>> PART 1: State.connect_one_shot / disconnect_safe helpers")
	var state: State = State.new()
	add_child(state)
	var count: Array[int] = [0]
	var callback: Callable = func(_next_state_path: String, _data: Dictionary) -> void:
		count[0] += 1

	# Double connect must not duplicate the connection.
	state.connect_one_shot(state.finished, callback)
	state.connect_one_shot(state.finished, callback)
	check(state.finished.get_connections().size() == 1, "connect_one_shot ignores duplicate connects")

	# One-shot delivery: fires once, then auto-disconnects.
	state.finished.emit(" somewhere", {})
	check(count[0] == 1, "one-shot callback fired exactly once")
	check(not state.finished.is_connected(callback), "one-shot callback auto-disconnected after firing")

	# Safe disconnect on a non-connected callback must not error.
	state.disconnect_safe(state.finished, callback)
	check(not state.finished.is_connected(callback), "disconnect_safe is a no-op when not connected")

	# Reconnect then safe disconnect removes the wiring.
	state.connect_one_shot(state.finished, callback)
	check(state.finished.is_connected(callback), "connect_one_shot wires the callback")
	state.disconnect_safe(state.finished, callback)
	check(not state.finished.is_connected(callback), "disconnect_safe removes the wiring")

	state.queue_free()


## Part 2: Interrupting PlayerAttack (dash cancel) must leave no stale
## animation_finished wiring, so the finished attack animation can never
## yank the machine out of a later state.
func _part2_no_stale_attack_callback() -> void:
	print("\n>>> PART 2: Dash-cancelled PlayerAttack leaves no stale callback")
	var level_scene: PackedScene = load("res://Levels/level_template.tscn")
	var level: Node3D = level_scene.instantiate() as Node3D
	add_child(level)
	var player: Character = level.get_node("Player") as Character
	var input_comp: PlayerInputComponent = player.get_node("PlayerInputComponent") as PlayerInputComponent
	var sm: StateMachine = player.get_node("StateMachine") as StateMachine
	var attack_state: CharacterAttack = sm.get_node("PlayerAttack") as CharacterAttack
	var anim_tree: AnimationTree = player.animation_tree

	# Settle: wait for spawn timer, then for the player to land in PlayerRun.
	await get_tree().create_timer(1.1).timeout
	for i: int in range(120):
		await get_tree().physics_frame
		if player.is_on_floor() and sm.state.name == "PlayerRun":
			break
	check(sm.state.name == "PlayerRun", "player settled in PlayerRun before attack")

	# Enter PlayerAttack via click.
	var click := InputEventAction.new()
	click.action = "click"
	click.pressed = true
	sm._unhandled_input(click)
	check(sm.state.name == "PlayerAttack", "click entered PlayerAttack")
	check(anim_tree.animation_finished.is_connected(attack_state.finish_attack), "enter() wired animation_finished via one-shot")

	# Dash-cancel out of the attack (movement held so can_dash() passes).
	Input.action_press("move_forward")
	await get_tree().physics_frame
	var dash_event := InputEventAction.new()
	dash_event.action = "dash"
	dash_event.pressed = true
	sm._unhandled_input(dash_event)
	check(sm.state.name == "PlayerDash", "dash cancel interrupted into PlayerDash")
	check(not anim_tree.animation_finished.is_connected(attack_state.finish_attack), "exit() removed animation_finished wiring")
	Input.action_release("move_forward")

	# Watch the machine well past the end of the interrupted attack animation:
	# only dash completion into PlayerRun may occur, never a stale transition.
	var reached_run := false
	var unexpected_state := ""
	for i: int in range(90):
		await get_tree().physics_frame
		var current: String = sm.state.name
		if current == "PlayerRun":
			reached_run = true
		elif current != "PlayerDash" and unexpected_state.is_empty():
			unexpected_state = current
	check(unexpected_state.is_empty(), "no stale transition after dash cancel (saw: " + unexpected_state + ")")
	check(reached_run, "dash completed normally into PlayerRun")

	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
