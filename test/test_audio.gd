extends Node

func _ready() -> void:
	print("--- RUNNING AUDIO & SOUND EFFECTS TEST ---")
	
	# ---------------------------------------------------------
	# PART 1: Audio Bus Layout Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: Audio Bus Configuration")
	var sfx_bus_index: int = AudioServer.get_bus_index(&"SFX")
	if sfx_bus_index == -1:
		printerr("TEST FAILED: 'SFX' audio bus not found in AudioServer.")
		get_tree().quit(1)
		return
	print("SFX bus found at index: ", sfx_bus_index)
	
	var sfx_bus_send: StringName = AudioServer.get_bus_send(sfx_bus_index)
	if sfx_bus_send != &"Master":
		printerr("TEST FAILED: Expected SFX bus to send to 'Master', got: ", sfx_bus_send)
		get_tree().quit(1)
		return
	print("SFX bus output routing verified (sends to Master)")

	# ---------------------------------------------------------
	# PART 2: Player Audio Nodes Verification
	# ---------------------------------------------------------
	print("\n>>> PART 2: Player Audio Components & Wiring")
	var player_scene: PackedScene = load("res://Player/player.tscn")
	var player: Character = player_scene.instantiate() as Character
	add_child(player)
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# Check Dash Audio
	var input_comp: PlayerInputComponent = player.get_node_or_null("PlayerInputComponent") as PlayerInputComponent
	var dash_audio: AudioStreamPlayer3D = input_comp.dash_audio if input_comp != null else player.get_node_or_null("DashAudio") as AudioStreamPlayer3D
	if dash_audio == null:
		printerr("TEST FAILED: dash_audio is null.")
		get_tree().quit(1)
		return
	if dash_audio.stream == null:
		printerr("TEST FAILED: dash_audio stream is null.")
		get_tree().quit(1)
		return
	if dash_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected dash_audio bus to be 'SFX', got: ", dash_audio.bus)
		get_tree().quit(1)
		return
	print("dash_audio verified: node found, stream assigned, SFX bus assigned.")
	
	# Check Damage Audio on the player Hurtbox
	var player_hurtbox: Hurtbox = player.get_node_or_null("Hurtbox") as Hurtbox
	if player_hurtbox == null:
		printerr("TEST FAILED: player Hurtbox is null.")
		get_tree().quit(1)
		return
	if player_hurtbox.hit_audio == null:
		printerr("TEST FAILED: hurtbox.hit_audio is null.")
		get_tree().quit(1)
		return
	if player_hurtbox.hit_audio.stream == null:
		printerr("TEST FAILED: hurtbox.hit_audio stream is null.")
		get_tree().quit(1)
		return
	if player_hurtbox.hit_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected hit_audio bus to be 'SFX', got: ", player_hurtbox.hit_audio.bus)
		get_tree().quit(1)
		return
	print("hurtbox.hit_audio verified: node found, stream assigned, SFX bus assigned.")
	
	# Check Attack Audio & WeaponSlot connection
	var weapon_slot: BoneAttachment3D = player.get_node_or_null("GamedevTV_Mannequin_Medium/Rig_Medium/Skeleton3D/WeaponSlot") as BoneAttachment3D
	if weapon_slot == null:
		printerr("TEST FAILED: WeaponSlot bone attachment not found.")
		get_tree().quit(1)
		return
		
	var attack_audio: AudioStreamPlayer3D = weapon_slot.get_node_or_null("AttackAudio") as AudioStreamPlayer3D
	if attack_audio == null:
		printerr("TEST FAILED: AttackAudio node not found under WeaponSlot.")
		get_tree().quit(1)
		return
	if attack_audio.stream == null:
		printerr("TEST FAILED: AttackAudio stream is null.")
		get_tree().quit(1)
		return
	if attack_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected AttackAudio bus to be 'SFX', got: ", attack_audio.bus)
		get_tree().quit(1)
		return
	print("AttackAudio node verified: found under WeaponSlot, stream assigned, SFX bus assigned.")
	
	# Verify slash signal connection to AttackAudio.play
	var is_slash_connected: bool = weapon_slot.is_connected("slash", attack_audio.play)
	if not is_slash_connected:
		printerr("TEST FAILED: WeaponSlot 'slash' signal is not connected to AttackAudio.play.")
		get_tree().quit(1)
		return
	print("WeaponSlot 'slash' signal connection to AttackAudio.play verified.")
	
	# Check MeleeEnemy Attack Audio & WeaponSlot connection
	var melee_scene: PackedScene = load("res://Enemy/melee_enemy.tscn") as PackedScene
	if melee_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/melee_enemy.tscn")
		get_tree().quit(1)
		return
	var melee_enemy: Node3D = melee_scene.instantiate() as Node3D
	add_child(melee_enemy)
	var melee_weapon_slot: BoneAttachment3D = melee_enemy.get_node_or_null("AnimationAnchor/AnimatedEnemy/Enemy_Medium/Rig_Medium/Skeleton3D/WeaponSlot") as BoneAttachment3D
	if melee_weapon_slot == null:
		printerr("TEST FAILED: WeaponSlot not found on MeleeEnemy.")
		get_tree().quit(1)
		return
	var melee_attack_audio: AudioStreamPlayer3D = melee_weapon_slot.get_node_or_null("AttackAudio") as AudioStreamPlayer3D
	if melee_attack_audio == null:
		printerr("TEST FAILED: AttackAudio node not found under MeleeEnemy WeaponSlot.")
		get_tree().quit(1)
		return
	if melee_attack_audio.stream == null:
		printerr("TEST FAILED: MeleeEnemy AttackAudio stream is null.")
		get_tree().quit(1)
		return
	if melee_attack_audio.stream.resource_path != "res://Assets/Audio/weapon-swing.ogg":
		printerr("TEST FAILED: Expected MeleeEnemy AttackAudio stream to be 'res://Assets/Audio/weapon-swing.ogg', got: ", melee_attack_audio.stream.resource_path)
		get_tree().quit(1)
		return
	if melee_attack_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected MeleeEnemy AttackAudio bus to be 'SFX', got: ", melee_attack_audio.bus)
		get_tree().quit(1)
		return
	var is_melee_slash_connected: bool = melee_weapon_slot.is_connected("slash", melee_attack_audio.play)
	if not is_melee_slash_connected:
		printerr("TEST FAILED: MeleeEnemy WeaponSlot 'slash' signal is not connected to AttackAudio.play.")
		get_tree().quit(1)
		return
	print("MeleeEnemy AttackAudio verified: found under WeaponSlot, weapon-swing.ogg assigned, SFX bus assigned, slash connected to play.")
	
	# Check Firebomber Leap Audio
	var firebomber_scene: PackedScene = load("res://Enemy/firebomber_enemy.tscn") as PackedScene
	if firebomber_scene == null:
		printerr("TEST FAILED: Could not load res://Enemy/firebomber_enemy.tscn")
		get_tree().quit(1)
		return
	var firebomber: Character = firebomber_scene.instantiate() as Character
	add_child(firebomber)
	var leap_audio: AudioStreamPlayer3D = firebomber.get_node_or_null("LeapAudio") as AudioStreamPlayer3D
	if leap_audio == null:
		printerr("TEST FAILED: LeapAudio node not found on Firebomber.")
		get_tree().quit(1)
		return
	if leap_audio.stream == null:
		printerr("TEST FAILED: Firebomber LeapAudio stream is null.")
		get_tree().quit(1)
		return
	if not leap_audio.stream.resource_path.ends_with("140867__juskiddink__boing.wav"):
		printerr("TEST FAILED: Expected Firebomber LeapAudio stream to be 140867__juskiddink__boing.wav, got: ", leap_audio.stream.resource_path)
		get_tree().quit(1)
		return
	if leap_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected Firebomber LeapAudio bus to be 'SFX', got: ", leap_audio.bus)
		get_tree().quit(1)
		return
	print("Firebomber LeapAudio verified: found, 140867__juskiddink__boing.wav assigned, SFX bus assigned.")
	
	# ---------------------------------------------------------
	# PART 3: Audio Playback Triggers
	# ---------------------------------------------------------
	print("\n>>> PART 3: Functional Playback Trigger Tests")
	
	# 1. Damage audio plays on receive_hit()
	attack_audio.stop()
	dash_audio.stop()
	player_hurtbox.hit_audio.stop()
	
	player_hurtbox.receive_hit(5.0, Vector3.ZERO)
	await get_tree().process_frame
	if not player_hurtbox.hit_audio.playing:
		printerr("TEST FAILED: hit_audio is not playing after receive_hit().")
		get_tree().quit(1)
		return
	print("Damage audio playback confirmed on receive_hit().")
	player_hurtbox.hit_audio.stop()
	
	# 2. Dash audio plays when entering PlayerDash state
	var state_machine: StateMachine = player.get_node("StateMachine") as StateMachine
	state_machine._transition_to_next_state("PlayerDash", {"direction": Vector3.FORWARD})
	await get_tree().process_frame
	if not dash_audio.playing:
		printerr("TEST FAILED: dash_audio is not playing after entering PlayerDash state.")
		get_tree().quit(1)
		return
	print("Dash audio playback confirmed on entering PlayerDash state.")
	dash_audio.stop()
	
	# 3. Slash audio plays when WeaponSlot emits slash signal
	weapon_slot.emit_signal("slash")
	await get_tree().process_frame
	if not attack_audio.playing:
		printerr("TEST FAILED: attack_audio is not playing after WeaponSlot emits slash.")
		get_tree().quit(1)
		return
	print("Attack audio playback confirmed on WeaponSlot 'slash' signal emit.")
	attack_audio.stop()

	# 4. Melee enemy slash audio plays when WeaponSlot emits slash signal
	melee_weapon_slot.emit_signal("slash")
	await get_tree().process_frame
	if not melee_attack_audio.playing:
		printerr("TEST FAILED: melee_attack_audio is not playing after MeleeEnemy WeaponSlot emits slash.")
		get_tree().quit(1)
		return
	print("Melee enemy attack audio playback confirmed on WeaponSlot 'slash' signal emit.")
	melee_attack_audio.stop()

	# 5. Firebomber leap audio plays when entering EnemyLeapingDodge state
	leap_audio.stop()
	var fb_state_machine: StateMachine = firebomber.get_node("StateMachine") as StateMachine
	fb_state_machine._transition_to_next_state("EnemyLeapingDodge", {"direction": Vector3.BACK})
	await get_tree().process_frame
	if not leap_audio.playing:
		printerr("TEST FAILED: leap_audio is not playing after entering EnemyLeapingDodge state.")
		get_tree().quit(1)
		return
	print("Firebomber leap audio playback confirmed on entering EnemyLeapingDodge state.")
	leap_audio.stop()
	
	print("\n====================================================================")
	print("  ALL AUDIO & SOUND EFFECTS TESTS PASSED!                           ")
	print("  1. Master and SFX audio bus configuration verified                ")
	print("  2. Player dash_audio assigned, configured to SFX, plays on dash   ")
	print("  3. Hurtbox hit_audio configured to SFX, plays on damage          ")
	print("  4. AttackAudio on WeaponSlot configured to SFX, plays on slash    ")
	print("  5. MeleeEnemy AttackAudio configured to SFX weapon-swing.ogg      ")
	print("  6. Firebomber LeapAudio configured to SFX boing.wav, plays on leap")
	print("====================================================================")
	
	player.queue_free()
	melee_enemy.queue_free()
	firebomber.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
