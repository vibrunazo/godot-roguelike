extends Node

func _ready() -> void:
	print("--- RUNNING PAUSE MENU & UI_PAUSE TEST ---")

	# ---------------------------------------------------------
	# PART 1: InputMap Verification for "ui_pause"
	# ---------------------------------------------------------
	print("\n>>> PART 1: InputMap Action Verification")
	if not InputMap.has_action("ui_pause"):
		printerr("TEST FAILED: 'ui_pause' action is not registered in InputMap.")
		get_tree().quit(1)
		return
	print("Action 'ui_pause' exists in InputMap.")

	var events: Array[InputEvent] = InputMap.action_get_events("ui_pause")
	var has_p_key: bool = false
	var has_esc_key: bool = false
	for event: InputEvent in events:
		if event is InputEventKey:
			var key_event: InputEventKey = event as InputEventKey
			if key_event.physical_keycode == KEY_P or key_event.keycode == KEY_P:
				has_p_key = true
			elif key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE:
				has_esc_key = true

	if not has_p_key:
		printerr("TEST FAILED: 'ui_pause' action does not have key P assigned.")
		get_tree().quit(1)
		return
	if not has_esc_key:
		printerr("TEST FAILED: 'ui_pause' action does not have key ESCAPE assigned.")
		get_tree().quit(1)
		return
	print("Verified 'ui_pause' is mapped to physical key 'P' (KEY_P = 80) and 'Escape' (KEY_ESCAPE = 4194305).")

	# ---------------------------------------------------------
	# PART 2: GlobalVars Registry Verification
	# ---------------------------------------------------------
	print("\n>>> PART 2: GlobalVars Pause Menu Scene Registration")
	if GlobalVars.pause_menu_scene == null:
		printerr("TEST FAILED: GlobalVars.pause_menu_scene is null.")
		get_tree().quit(1)
		return
	print("GlobalVars.pause_menu_scene verified: ", GlobalVars.pause_menu_scene.resource_path)

	# ---------------------------------------------------------
	# PART 3: UI Pause & Resume State Transitions
	# ---------------------------------------------------------
	print("\n>>> PART 3: UI Pause & Resume Logic")
	var received_signals: Array[bool] = []
	var on_pause_changed: Callable = func(is_paused: bool) -> void:
		received_signals.append(is_paused)

	UI.pause_state_changed.connect(on_pause_changed)

	# Ensure initially unpaused
	if UI.is_paused():
		UI.resume_game()
	received_signals.clear()

	if get_tree().paused:
		printerr("TEST FAILED: Tree is unexpectedly paused at start.")
		get_tree().quit(1)
		return

	# Test pause_game()
	UI.pause_game()

	if not get_tree().paused:
		printerr("TEST FAILED: get_tree().paused is false after UI.pause_game().")
		get_tree().quit(1)
		return
	if not UI.is_paused():
		printerr("TEST FAILED: UI.is_paused() returned false while paused.")
		get_tree().quit(1)
		return
	if received_signals.is_empty() or not received_signals.back():
		printerr("TEST FAILED: UI.pause_state_changed(true) was not received. Signals: ", received_signals)
		get_tree().quit(1)
		return

	var current_menu: PauseMenu = UI._current_pause_menu
	if current_menu == null or not is_instance_valid(current_menu):
		printerr("TEST FAILED: UI._current_pause_menu was not instantiated.")
		get_tree().quit(1)
		return
	if current_menu.process_mode != Node.PROCESS_MODE_ALWAYS:
		printerr("TEST FAILED: PauseMenu process_mode is not PROCESS_MODE_ALWAYS.")
		get_tree().quit(1)
		return
	print("UI.pause_game() verified: tree paused, menu instantiated with PROCESS_MODE_ALWAYS, signal emitted.")

	# Test resume_game()
	received_signals.clear()
	UI.resume_game()

	if get_tree().paused:
		printerr("TEST FAILED: get_tree().paused is still true after UI.resume_game().")
		get_tree().quit(1)
		return
	if UI.is_paused():
		printerr("TEST FAILED: UI.is_paused() returned true after resume.")
		get_tree().quit(1)
		return
	if received_signals.is_empty() or received_signals.back():
		printerr("TEST FAILED: UI.pause_state_changed(false) was not received. Signals: ", received_signals)
		get_tree().quit(1)
		return
	if UI._current_pause_menu != null:
		printerr("TEST FAILED: UI._current_pause_menu reference was not cleared after resume.")
		get_tree().quit(1)
		return
	print("UI.resume_game() verified: tree unpaused, menu freed, signal emitted.")

	# Test toggle_pause()
	UI.toggle_pause()
	if not UI.is_paused():
		printerr("TEST FAILED: toggle_pause() did not pause unpaused tree.")
		get_tree().quit(1)
		return
	UI.toggle_pause()
	if UI.is_paused():
		printerr("TEST FAILED: toggle_pause() did not resume paused tree.")
		get_tree().quit(1)
		return
	print("UI.toggle_pause() verified: toggles state correctly in both directions.")

	# ---------------------------------------------------------
	# PART 4: PauseMenu UI Node Structure & Theme Verification
	# ---------------------------------------------------------
	print("\n>>> PART 4: PauseMenu Scene & Component Verification")
	var menu_instance: PauseMenu = GlobalVars.pause_menu_scene.instantiate() as PauseMenu
	add_child(menu_instance)
	await get_tree().process_frame

	if menu_instance.resume_button == null:
		printerr("TEST FAILED: resume_button is null in PauseMenu.")
		get_tree().quit(1)
		return
	if menu_instance.restart_button == null:
		printerr("TEST FAILED: restart_button is null in PauseMenu.")
		get_tree().quit(1)
		return
	if menu_instance.fullscreen_button == null:
		printerr("TEST FAILED: fullscreen_button is null in PauseMenu.")
		get_tree().quit(1)
		return
	if menu_instance.quit_button == null:
		printerr("TEST FAILED: quit_button is null in PauseMenu.")
		get_tree().quit(1)
		return
	if menu_instance.controls_button == null:
		printerr("TEST FAILED: controls_button is null in PauseMenu.")
		get_tree().quit(1)
		return
	if menu_instance.exit_menu_button == null:
		printerr("TEST FAILED: exit_menu_button is null in PauseMenu.")
		get_tree().quit(1)
		return

	# Concept layout: the four reusable columns. The run gold counter must NOT
	# live here: the HUD scene owns the single gold display and stays visible
	# under the pause menu, so a pause-side label would double-render.
	if menu_instance.get_node_or_null("%GoldLabel") != null:
		printerr("TEST FAILED: PauseMenu must not carry its own GoldLabel; gold lives in the HUD scene.")
		get_tree().quit(1)
		return
	var hud_scene: PackedScene = load("res://UserInterface/hud.tscn") as PackedScene
	if hud_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/hud.tscn.")
		get_tree().quit(1)
		return
	var hud_probe: HUD = hud_scene.instantiate() as HUD
	add_child(hud_probe)
	await get_tree().process_frame
	var hud_gold: Label = hud_probe.get_node_or_null("MarginContainer/HBoxContainer/GoldLabel") as Label
	if hud_gold == null:
		printerr("TEST FAILED: HUD scene is missing the single GoldLabel.")
		hud_probe.queue_free()
		get_tree().quit(1)
		return
	hud_probe.queue_free()
	await get_tree().process_frame
	if menu_instance.list_panel == null or not (menu_instance.list_panel is ItemListPanel):
		printerr("TEST FAILED: PauseMenu is missing the reusable ItemListPanel.")
		get_tree().quit(1)
		return
	if menu_instance.detail_panel == null or not (menu_instance.detail_panel is ItemDetailPanel):
		printerr("TEST FAILED: PauseMenu is missing the reusable ItemDetailPanel.")
		get_tree().quit(1)
		return
	if menu_instance.stats_panel == null or not (menu_instance.stats_panel is CharacterStatsPanel):
		printerr("TEST FAILED: PauseMenu is missing the reusable CharacterStatsPanel.")
		get_tree().quit(1)
		return
	if menu_instance.buttons_panel == null or not (menu_instance.buttons_panel is MenuButtonsPanel):
		printerr("TEST FAILED: PauseMenu is missing the reusable MenuButtonsPanel.")
		get_tree().quit(1)
		return
	var columns: HBoxContainer = menu_instance.get_node_or_null("MainMargin/MainVBox/OuterPanel/Columns") as HBoxContainer
	if columns == null or columns.get_child_count() != 4:
		printerr("TEST FAILED: PauseMenu must host exactly 4 columns.")
		get_tree().quit(1)
		return

	# Verify BBCode title with wave effect (unique-name lookup: the menu now
	# hosts other titled panels, e.g. the inventory, so a recursive name
	# search is no longer specific enough).
	var title_label: RichTextLabel = menu_instance.get_node_or_null("%Title") as RichTextLabel
	if title_label == null:
		printerr("TEST FAILED: Title RichTextLabel not found in PauseMenu.")
		get_tree().quit(1)
		return
	if not title_label.bbcode_enabled:
		printerr("TEST FAILED: Title RichTextLabel does not have bbcode_enabled.")
		get_tree().quit(1)
		return
	if not title_label.text.contains("[wave") or not title_label.text.to_upper().contains("PAUSE"):
		printerr("TEST FAILED: Title RichTextLabel does not contain [wave] BBCode tag or PAUSED text: ", title_label.text)
		get_tree().quit(1)
		return
	print("PauseMenu node structure verified: Title has [wave] BBCode, all 6 buttons and 4 columns present, no duplicate gold label.")

	menu_instance.queue_free()
	await get_tree().process_frame

	# ---------------------------------------------------------
	# PART 5: Button Interactivity & Resume Action
	# ---------------------------------------------------------
	print("\n>>> PART 5: PauseMenu Resume Button Action")
	UI.pause_game()
	var active_menu: PauseMenu = UI._current_pause_menu
	if active_menu == null:
		printerr("TEST FAILED: No active pause menu.")
		get_tree().quit(1)
		return

	var resume_signals: Array[bool] = []
	active_menu.resume_requested.connect(func() -> void: resume_signals.append(true))
	active_menu.resume_button.pressed.emit()

	if resume_signals.is_empty():
		printerr("TEST FAILED: resume_requested signal was not emitted on resume button press.")
		get_tree().quit(1)
		return
	if UI.is_paused():
		printerr("TEST FAILED: UI is still paused after resume button pressed.")
		get_tree().quit(1)
		return
	print("Resume button verified: emitted resume_requested, unpaused tree, closed menu.")

	# ---------------------------------------------------------
	# PART 6: Key Input Event Simulation ("ui_pause")
	# ---------------------------------------------------------
	print("\n>>> PART 6: Key Input Event Simulation (P Key)")
	var key_event_p: InputEventKey = InputEventKey.new()
	key_event_p.physical_keycode = KEY_P
	key_event_p.pressed = true

	# Test pause via simulated key input
	UI._unhandled_key_input(key_event_p)
	if not UI.is_paused():
		printerr("TEST FAILED: _unhandled_key_input with 'ui_pause' key P did not pause the game.")
		get_tree().quit(1)
		return
	print("Simulated 'P' key successfully paused the game.")

	# Test resume via simulated key input
	UI._unhandled_key_input(key_event_p)
	if UI.is_paused():
		printerr("TEST FAILED: Second _unhandled_key_input with 'ui_pause' key P did not resume the game.")
		get_tree().quit(1)
		return
	print("Second simulated 'P' key successfully resumed the game.")

	# ---------------------------------------------------------
	# PART 7: Game-Over Reuse (Red Tint, Title, No Resume, Locked Toggle)
	# ---------------------------------------------------------
	print("\n>>> PART 7: Game-Over Menu Configuration")
	var gameover_menu: PauseMenu = GlobalVars.pause_menu_scene.instantiate() as PauseMenu
	gameover_menu.title_text = "GAME OVER"
	gameover_menu.title_color = Color(0.85, 0.2, 0.2)
	gameover_menu.backdrop_color = Color(0.25, 0.03, 0.03, 0.78)
	gameover_menu.show_resume_button = false
	add_child(gameover_menu)
	await get_tree().process_frame

	var gameover_title: RichTextLabel = gameover_menu.get_node_or_null("%Title") as RichTextLabel
	if gameover_title == null or not gameover_title.text.contains("GAME OVER"):
		printerr("TEST FAILED: Game-over title should read GAME OVER, got: ", gameover_title.text if gameover_title != null else "null")
		get_tree().quit(1)
		return
	var gameover_backdrop: ColorRect = gameover_menu.find_child("Backdrop", true, false) as ColorRect
	if gameover_backdrop == null or gameover_backdrop.color.r < 0.15 or gameover_backdrop.color.b > 0.1:
		printerr("TEST FAILED: Game-over backdrop should be red-tinted.")
		get_tree().quit(1)
		return
	if gameover_menu.resume_button.visible:
		printerr("TEST FAILED: Game-over menu should hide the resume button.")
		get_tree().quit(1)
		return
	if not gameover_menu.restart_button.visible:
		printerr("TEST FAILED: Game-over menu should keep the restart button.")
		get_tree().quit(1)
		return
	print("Game-over configuration verified: red GAME OVER title, red backdrop, resume hidden, restart kept.")
	gameover_menu.queue_free()
	await get_tree().process_frame

	UI.show_game_over()
	await get_tree().process_frame
	if not UI.is_paused():
		printerr("TEST FAILED: UI.show_game_over() should pause the tree.")
		get_tree().quit(1)
		return
	var active_gameover: PauseMenu = UI._current_pause_menu
	if active_gameover == null or not is_instance_valid(active_gameover):
		printerr("TEST FAILED: UI.show_game_over() should track its menu.")
		get_tree().quit(1)
		return
	if active_gameover.resume_button.visible:
		printerr("TEST FAILED: Game-over menu from UI should hide resume.")
		get_tree().quit(1)
		return
	UI.toggle_pause()
	if not UI.is_paused():
		printerr("TEST FAILED: Pause toggle should stay locked on the game-over screen.")
		get_tree().quit(1)
		return
	print("UI.show_game_over() verified: paused, resume hidden, toggle locked.")
	UI.resume_game()
	if UI.is_paused():
		printerr("TEST FAILED: UI.resume_game() should clear the game-over screen.")
		get_tree().quit(1)
		return

	# ---------------------------------------------------------
	# PART 8: Player Defeat Shows Game Over After a Delay
	# ---------------------------------------------------------
	print("\n>>> PART 8: Delayed Game Over on Player Defeat")
	var player: Character = (load("res://Player/player.tscn") as PackedScene).instantiate() as Character
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var player_attrs: AttributeComponent = player.get_node("AttributeComponent") as AttributeComponent
	var saved_difficulty: int = ProgressionState.difficulty_level
	var saved_dungeon_level: int = ProgressionState.dungeon_level
	ProgressionState.difficulty_level = 9
	ProgressionState.dungeon_level = 5
	player_attrs.damage_pool(AttributeComponent.POOL_HEALTH, player_attrs.get_current(AttributeComponent.STAT_MAX_HEALTH))
	await get_tree().create_timer(1.0).timeout
	if UI.is_paused():
		player.queue_free()
		UI.resume_game()
		printerr("TEST FAILED: Game-over screen appeared before the defeat delay elapsed.")
		get_tree().quit(1)
		return
	var player_sm: StateMachine = player.state_machine
	if player_sm == null or player_sm.state == null or player_sm.state.name != "PlayerDefeat":
		ProgressionState.difficulty_level = saved_difficulty
		ProgressionState.dungeon_level = saved_dungeon_level
		player.queue_free()
		UI.resume_game()
		printerr("TEST FAILED: Player defeat should enter the PlayerDefeat state.")
		get_tree().quit(1)
		return
	var playback: AnimationNodeStateMachinePlayback = player.animation_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback == null or playback.get_current_node() != &"Defeat":
		ProgressionState.difficulty_level = saved_difficulty
		ProgressionState.dungeon_level = saved_dungeon_level
		player.queue_free()
		UI.resume_game()
		printerr("TEST FAILED: Player defeat should play the Defeat animation.")
		get_tree().quit(1)
		return
	print("PlayerDefeat state and animation verified.")
	await get_tree().create_timer(1.6).timeout
	await get_tree().process_frame
	if not UI.is_paused():
		player.queue_free()
		UI.resume_game()
		printerr("TEST FAILED: Player defeat should pause into the game-over screen.")
		get_tree().quit(1)
		return
	var defeat_menu: PauseMenu = UI._current_pause_menu
	var defeat_title: RichTextLabel = defeat_menu.get_node_or_null("%Title") as RichTextLabel if defeat_menu != null else null
	if defeat_title == null or not defeat_title.text.contains("GAME OVER"):
		player.queue_free()
		UI.resume_game()
		printerr("TEST FAILED: Defeat menu should read GAME OVER.")
		get_tree().quit(1)
		return
	if ProgressionState.difficulty_level != 9 or ProgressionState.dungeon_level != 5:
		player.queue_free()
		UI.resume_game()
		printerr("TEST FAILED: Death should not reset progression; reset is deferred to restart.")
		get_tree().quit(1)
		return
	print("Delayed game over verified: death plays out, then the GAME OVER menu takes over.")
	ProgressionState.difficulty_level = saved_difficulty
	ProgressionState.dungeon_level = saved_dungeon_level
	player.queue_free()
	UI.resume_game()

	# ---------------------------------------------------------
	# Clean Teardown
	# ---------------------------------------------------------
	UI.resume_game()
	print("\n====================================================================")
	print("  ALL PAUSE MENU TESTS PASSED!                                      ")
	print("  1. 'ui_pause' action and physical key 'P' (KEY_P = 80) verified   ")
	print("  2. GlobalVars.pause_menu_scene registry export verified           ")
	print("  3. UI.pause_game(), resume_game(), toggle_pause() state logic ok   ")
	print("  4. PauseMenu [wave] BBCode title and button components ok         ")
	print("  5. Resume button interaction unpauses and frees menu ok            ")
	print("  6. Simulated 'ui_pause' input event toggles pause cleanly          ")
	print("  7. Game-over reuse (red tint, title, no resume, locked toggle) ok  ")
	print("  8. Delayed GAME OVER menu on player defeat ok                      ")
	print("====================================================================")
	get_tree().quit(0)
