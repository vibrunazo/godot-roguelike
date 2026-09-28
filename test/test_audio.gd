## Gameplay sound effects:
## - the SFX bus exists and sends to Master,
## - taking a hit plays the hurtbox's hit sound,
## - dashing plays the dash sound,
## - player and melee enemy attacks play the swing sound wired to their weapon
##   slot's slash signal when the hit window opens,
## and every one of them plays on the SFX bus, so the SFX volume controls it.
## (The firebomber's leap sound is covered by test_firebomber_enemy.)
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const SFX_BUS: StringName = &"SFX"
## Frame budget for one attack animation.
const ATTACK_FRAMES: int = 600

var _arena: Node3D
var _player: Character


func before_each() -> void:
	_arena = load_arena()
	_player = spawn(PLAYER_SCENE, _arena, (_arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	# Live input polling off: the test alone drives the player.
	(_player.get_node("PlayerInputComponent") as PlayerInputComponent).set_physics_process(false)
	await wait_until(func() -> bool: return _player.is_on_floor() and _player.state_machine.state.name == "PlayerRun", "the player should settle")


func test_the_sfx_bus_sends_to_master() -> void:
	var index: int = AudioServer.get_bus_index(SFX_BUS)
	if check(index != -1, "the SFX bus should exist"):
		check_eq(AudioServer.get_bus_send(index), &"Master", "the SFX bus should send to Master")


func test_a_hit_plays_the_hit_sound() -> void:
	var audio: AudioStreamPlayer3D = _player.hurtbox.hit_audio
	if not check(audio != null, "setup: the player's hurtbox should have a hit sound"):
		return
	_player.hurtbox.receive_hit(1.0, Vector3.ZERO)
	await _check_plays(audio, "a hit should play the hit sound")


func test_a_dash_plays_the_dash_sound() -> void:
	var audio: AudioStreamPlayer3D = (_player.state_machine.get_node("PlayerDash") as PlayerDash).dash_audio
	if not check(audio != null, "setup: the player should have a dash sound"):
		return
	# No target in the empty arena, so the jump button dashes.
	press_action(&"jump")
	await _check_plays(audio, "a dash should play the dash sound")


func test_a_player_attack_plays_its_swing_sound() -> void:
	var attack: CharacterAttack = _player.state_machine.get_node("PlayerRun").get("attack_state") as CharacterAttack
	var audio: AudioStreamPlayer3D = _slash_audio(attack.get_weapon_slot())
	if not check(audio != null, "setup: the attack's weapon slot should play a sound on slash"):
		return
	_player.aim_direction = Vector3.FORWARD
	press_action(&"click")
	await _check_plays(audio, "the attack should play its swing sound when its hit window opens", ATTACK_FRAMES)


func test_a_melee_enemy_attack_plays_its_swing_sound() -> void:
	var enemy: Character = spawn(MELEE_SCENE, _arena, (_arena.get_node("EnemySpawn") as Node3D).global_position) as Character
	disable_ai(enemy)
	if not await wait_until(func() -> bool: return enemy.is_on_floor(), "setup: the enemy should land"):
		return
	var attack: CharacterAttack = enemy.state_machine.get_node("EnemyAttack") as CharacterAttack
	var audio: AudioStreamPlayer3D = _slash_audio(attack.get_weapon_slot())
	if not check(audio != null, "setup: the enemy attack's weapon slot should play a sound on slash"):
		return
	enemy.state_machine.request_state(attack.name, {"aim": Vector3.BACK})
	await _check_plays(audio, "the enemy attack should play its swing sound when its hit window opens", ATTACK_FRAMES)


## Waits until the sound plays, then checks it plays on the SFX bus.
func _check_plays(audio: AudioStreamPlayer3D, message: String, max_frames: int = 10) -> void:
	if await wait_until(func() -> bool: return audio.playing, message, max_frames):
		check_eq(audio.bus, SFX_BUS, "%s should play on the SFX bus" % audio.name)


## The sound player wired to the weapon slot's slash signal, if any.
func _slash_audio(slot: WeaponSlot) -> AudioStreamPlayer3D:
	if slot == null:
		return null
	for connection: Dictionary in slot.slash.get_connections():
		var audio: AudioStreamPlayer3D = (connection["callable"] as Callable).get_object() as AudioStreamPlayer3D
		if audio != null:
			return audio
	return null
