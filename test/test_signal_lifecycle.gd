## State signal lifecycle:
## - State.connect_one_shot() ignores duplicate connects, fires once and then
##   disconnects itself; State.disconnect_safe() removes a connection and is a
##   no-op when there is none.
## - An attack interrupted by a dash cancel removes its animation_finished
##   wiring on exit, so the interrupted animation can never pull the machine
##   out of a later state.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600

var _count: int = 0


func _on_finished(_next_state_path: String, _data: Dictionary) -> void:
	_count += 1


func test_connect_one_shot_ignores_duplicates_fires_once_and_disconnects() -> void:
	var state: State = autofree(State.new()) as State
	add_child(state)
	_count = 0
	state.connect_one_shot(state.finished, _on_finished)
	state.connect_one_shot(state.finished, _on_finished)
	check_eq(state.finished.get_connections().size(), 1, "a duplicate connect_one_shot should not add a second connection")
	state.finished.emit("Anywhere", {})
	check_eq(_count, 1, "the one-shot callback should fire exactly once")
	check(not state.finished.is_connected(_on_finished), "the one-shot callback should disconnect itself after firing")


func test_disconnect_safe_removes_a_connection_and_is_a_no_op_without_one() -> void:
	var state: State = autofree(State.new()) as State
	add_child(state)
	state.disconnect_safe(state.finished, _on_finished)
	check(not state.finished.is_connected(_on_finished), "disconnect_safe() without a connection should do nothing")
	state.connect_one_shot(state.finished, _on_finished)
	state.disconnect_safe(state.finished, _on_finished)
	check(not state.finished.is_connected(_on_finished), "disconnect_safe() should remove the connection")


func test_a_dash_cancelled_attack_leaves_no_stale_transition() -> void:
	var arena: Node3D = load_arena()
	var player: Character = spawn(PLAYER_SCENE, arena, (arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	(player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	var attack: CharacterAttack = player.state_machine.get_node("PlayerAttack") as CharacterAttack
	if not await wait_until(func() -> bool: return player.is_on_floor() and _state(player) == "PlayerRun", "the player should settle"):
		return
	if not check(attack.dash_cancel, "setup: the first attack should allow dash cancelling"):
		return
	# Measure an uninterrupted attack, so the watch below outlasts its animation.
	press_action(&"click")
	await wait_until(func() -> bool: return _state(player) == attack.name, "the calibration attack should start", 10)
	var attack_frames: Array[int] = [0]
	await wait_until(func() -> bool:
		attack_frames[0] += 1
		return _state(player) == "PlayerRun", "the calibration attack should finish", ATTACK_FRAMES)

	press_action(&"click")
	if not await wait_until(func() -> bool: return _state(player) == attack.name, "the attack should start", 10):
		return
	check(player.animation_tree.animation_finished.is_connected(attack.finish_attack), "entering the attack should wire animation_finished")
	# No auto-aim target in the arena, so the jump button commands a dash.
	press_action(&"jump")
	if not await wait_until(func() -> bool: return _state(player) == "PlayerDash", "the jump button should dash-cancel the attack", 10):
		return
	check(not player.animation_tree.animation_finished.is_connected(attack.finish_attack), "leaving the attack should remove its animation_finished wiring")
	var unexpected: Array[String] = []
	for frame: int in range(attack_frames[0] * 2):
		await get_tree().physics_frame
		var current: String = _state(player)
		if current != "PlayerDash" and current != "PlayerRun" and not unexpected.has(current):
			unexpected.append(current)
	check(unexpected.is_empty(), "after a dash cancel only dash -> run may happen, never a stale transition (saw %s)" % [unexpected])
	check_eq(_state(player), "PlayerRun", "the dash should end in PlayerRun")


func _state(character: Character) -> String:
	return str(character.state_machine.state.name)
