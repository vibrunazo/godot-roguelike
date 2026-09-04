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
	var player: Player = player_scene.instantiate() as Player
	add_child(player)
	
	await get_tree().physics_frame
	await get_tree().process_frame
	
	# Check Dash Audio
	if player.dash_audio == null:
		printerr("TEST FAILED: player.dash_audio is null.")
		get_tree().quit(1)
		return
	if player.dash_audio.stream == null:
		printerr("TEST FAILED: player.dash_audio stream is null.")
		get_tree().quit(1)
		return
	if player.dash_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected dash_audio bus to be 'SFX', got: ", player.dash_audio.bus)
		get_tree().quit(1)
		return
	print("player.dash_audio verified: node found, stream assigned, SFX bus assigned.")
	
	# Check Damage Audio
	var health_comp: HealthComponent = player.health_component
	if health_comp == null:
		printerr("TEST FAILED: player.health_component is null.")
		get_tree().quit(1)
		return
	if health_comp.hit_audio == null:
		printerr("TEST FAILED: health_component.hit_audio is null.")
		get_tree().quit(1)
		return
	if health_comp.hit_audio.stream == null:
		printerr("TEST FAILED: health_component.hit_audio stream is null.")
		get_tree().quit(1)
		return
	if health_comp.hit_audio.bus != &"SFX":
		printerr("TEST FAILED: Expected hit_audio bus to be 'SFX', got: ", health_comp.hit_audio.bus)
		get_tree().quit(1)
		return
	print("health_component.hit_audio verified: node found, stream assigned, SFX bus assigned.")
	
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
	
	# ---------------------------------------------------------
	# PART 3: Audio Playback Triggers
	# ---------------------------------------------------------
	print("\n>>> PART 3: Functional Playback Trigger Tests")
	
	# 1. Damage audio plays on take_damage()
	attack_audio.stop()
	player.dash_audio.stop()
	health_comp.hit_audio.stop()
	
	health_comp.take_damage(5.0)
	await get_tree().process_frame
	if not health_comp.hit_audio.playing:
		printerr("TEST FAILED: hit_audio is not playing after take_damage().")
		get_tree().quit(1)
		return
	print("Damage audio playback confirmed on take_damage().")
	health_comp.hit_audio.stop()
	
	# 2. Dash audio plays when entering PlayerDash state
	var state_machine: StateMachine = player.get_node("StateMachine") as StateMachine
	state_machine._transition_to_next_state("PlayerDash", {"direction": Vector3.FORWARD})
	await get_tree().process_frame
	if not player.dash_audio.playing:
		printerr("TEST FAILED: dash_audio is not playing after entering PlayerDash state.")
		get_tree().quit(1)
		return
	print("Dash audio playback confirmed on entering PlayerDash state.")
	player.dash_audio.stop()
	
	# 3. Slash audio plays when WeaponSlot emits slash signal
	weapon_slot.emit_signal("slash")
	await get_tree().process_frame
	if not attack_audio.playing:
		printerr("TEST FAILED: attack_audio is not playing after WeaponSlot emits slash.")
		get_tree().quit(1)
		return
	print("Attack audio playback confirmed on WeaponSlot 'slash' signal emit.")
	attack_audio.stop()
	
	print("\n====================================================================")
	print("  ALL AUDIO & SOUND EFFECTS TESTS PASSED!                           ")
	print("  1. Master and SFX audio bus configuration verified                ")
	print("  2. Player dash_audio assigned, configured to SFX, plays on dash   ")
	print("  3. HealthComponent hit_audio configured to SFX, plays on damage   ")
	print("  4. AttackAudio on WeaponSlot configured to SFX, plays on slash    ")
	print("====================================================================")
	
	player.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
