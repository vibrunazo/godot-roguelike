## Unified attack intents, shared by the player and AI controllers:
## - command_attack()/command_dash() raise an edge intent on the character
##   that consume_*_request() returns exactly once, from either controller,
## - Character.can_dash() follows the dash cooldown; a character without a
##   cooldown timer (enemies) can always dash,
## - StateMachine.request_state() rejects missing states and transitions to
##   existing ones; AIStateMachine.order_attack() validates the same way,
## - PlayerInputComponent orders drive transitions: attack from running, dash
##   out of a dash-cancellable attack, no attack mid-dash, no dash on cooldown,
## - an enemy body runs the shared attack: an AI-raised attack intent chains
##   combo_next through the queue window and an AI-raised dash intent
##   dash-cancels it.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
## Test-owned queue window for the enemy combo proof.
const TEST_QUEUE_TIME: float = 0.05
## Frame budget for one attack.
const ATTACK_FRAMES: int = 600

var _arena: Node3D
var _player: Character
var _input: PlayerInputComponent
var _enemy: Character
var _mind: AIStateMachine


func before_each() -> void:
	_arena = load_arena()
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	_input = _player.get_node("PlayerInputComponent") as PlayerInputComponent
	_input.set_physics_process(false)
	_enemy = spawn(MELEE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	_mind = _enemy.ai_state_machine as AIStateMachine
	disable_ai(_enemy)
	await wait_until(func() -> bool: return _player.is_on_floor() and _state(_player) == "PlayerRun" and _enemy.is_on_floor() and _state(_enemy) == "EnemyMove", "player and enemy should settle")
	_player.dash_cooldown.stop()


func test_both_controllers_raise_intents_that_are_consumed_once() -> void:
	_input.command_attack()
	check(_player.consume_attack_request(), "the player's attack command should raise an attack intent")
	check(not _player.consume_attack_request(), "the attack intent should be consumed only once")
	_input.command_dash()
	check(_player.consume_dash_request(), "the player's dash command should raise a dash intent")
	check(not _player.consume_dash_request(), "the dash intent should be consumed only once")
	_mind.command_attack()
	check(_enemy.consume_attack_request() and not _enemy.consume_attack_request(), "the AI's attack command should raise an intent consumed once")
	_mind.command_dash()
	check(_enemy.consume_dash_request() and not _enemy.consume_dash_request(), "the AI's dash command should raise an intent consumed once")


func test_can_dash_follows_the_cooldown_and_enemies_can_always_dash() -> void:
	check(_player.can_dash() and _input.can_dash(), "with the cooldown stopped the player can dash")
	_player.dash_cooldown.start()
	check(not _player.can_dash() and not _input.can_dash(), "while the cooldown runs the player cannot dash")
	_player.dash_cooldown.stop()
	check(_player.can_dash(), "once the cooldown stops the player can dash again")
	check(_enemy.can_dash(), "a character without a cooldown timer can always dash")


func test_request_state_and_order_attack_validate_the_target() -> void:
	check(not _player.state_machine.request_state("NoSuchState"), "request_state() should reject a missing state")
	check(_player.state_machine.request_state("PlayerRun") and _state(_player) == "PlayerRun", "request_state() should transition to an existing state")
	check(not _mind.order_attack("NoSuchState"), "order_attack() should reject a missing state")


func test_player_orders_drive_transitions() -> void:
	var attack: CharacterAttack = _player.state_machine.get_node("PlayerRun").get("attack_state") as CharacterAttack
	attack.dash_cancel = true
	check(_input.order_attack() and _state(_player) == attack.name, "ordering an attack from running should start the attack")
	check(_input.order_dash() and _state(_player) == "PlayerDash", "ordering a dash should cancel a dash-cancellable attack")
	check(not _input.order_attack(), "an attack cannot be ordered mid-dash")
	_player.state_machine.request_state("PlayerRun")
	_player.dash_cooldown.start()
	check(not _input.order_dash() and _state(_player) == "PlayerRun", "a dash order on cooldown should be refused")


func test_an_enemy_body_runs_the_shared_attack_from_ai_intents() -> void:
	var body: StateMachine = _enemy.state_machine
	var move: CharacterState = body.get_node("EnemyMove") as CharacterState
	var attack: CharacterAttack = body.get_node("EnemyAttack") as CharacterAttack
	# Test-only combo link and dash cancel on the enemy's attack.
	var follow_up: CharacterAttack = autofree(CharacterAttack.new()) as CharacterAttack
	follow_up.name = "TestFollowUp"
	follow_up.character = _enemy
	follow_up.attack_animation_name = attack.attack_animation_name
	var after: Array[CharacterState] = [move]
	follow_up.next_states = after
	body.add_child(follow_up)
	attack.combo_next = follow_up
	attack.queued_attack_time = TEST_QUEUE_TIME
	attack.dash_cancel = true
	attack.dash_state = move
	if not check(_mind.order_attack(attack.name) and _state(_enemy) == attack.name, "the AI should order the shared attack onto the enemy body"):
		return
	_mind.command_attack()
	if not await wait_until(func() -> bool: return _state(_enemy) == follow_up.name, "an AI attack intent should chain combo_next through the queue window", ATTACK_FRAMES):
		return
	follow_up.finish_attack(follow_up.attack_animation_name)
	check_eq(_state(_enemy), move.name, "the follow-up should end back in its next state")
	if not check(_mind.order_attack(attack.name), "the AI should order the attack again"):
		return
	_mind.command_dash()
	await wait_until(func() -> bool: return _state(_enemy) == move.name, "an AI dash intent should dash-cancel the attack", ATTACK_FRAMES)


func _state(character: Character) -> String:
	return str(character.state_machine.state.name)
