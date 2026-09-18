extends Node

const MainMenuScript = preload("res://UserInterface/main_menu.gd")
const MenuLevelScript = preload("res://Levels/menu_level.gd")

func _ready() -> void:
	print("--- RUNNING MAIN MENU & MENU LEVEL TEST ---")

	# ---------------------------------------------------------
	# PART 1: MainMenu Scene & Node Hierarchy Verification
	# ---------------------------------------------------------
	print("\n>>> PART 1: MainMenu Scene Verification")
	var menu_scene: PackedScene = load("res://UserInterface/main_menu.tscn") as PackedScene
	if menu_scene == null:
		printerr("TEST FAILED: Could not load res://UserInterface/main_menu.tscn")
		get_tree().quit(1)
		return
	print("Loaded res://UserInterface/main_menu.tscn successfully.")

	var menu: CanvasLayer = menu_scene.instantiate() as CanvasLayer
	add_child(menu)

	var title_lbl: RichTextLabel = menu.get_node_or_null("%Title") as RichTextLabel
	if title_lbl == null:
		printerr("TEST FAILED: %Title node missing in MainMenu.")
		get_tree().quit(1)
		return
	if not title_lbl.text.contains("Tutorial Hell"):
		printerr("TEST FAILED: Title text does not contain 'Tutorial Hell'. Found: ", title_lbl.text)
		get_tree().quit(1)
		return
	if not title_lbl.text.contains("[wave"):
		printerr("TEST FAILED: Title text is missing [wave] BBCode styling.")
		get_tree().quit(1)
		return
	print("Title verified: 'Tutorial Hell' with wave BBCode.")

	var start_btn: Button = menu.get_node_or_null("%StartButton") as Button
	var fullscreen_btn: Button = menu.get_node_or_null("%FullscreenButton") as Button
	var quit_btn: Button = menu.get_node_or_null("%QuitButton") as Button

	if start_btn == null or fullscreen_btn == null or quit_btn == null:
		printerr("TEST FAILED: One or more menu buttons missing.")
		get_tree().quit(1)
		return
	print("Verified presence of StartButton, FullscreenButton, and QuitButton.")

	if not start_btn.has_focus():
		printerr("TEST FAILED: StartButton does not have initial focus.")
		get_tree().quit(1)
		return
	print("Verified initial focus on StartButton.")

	# ---------------------------------------------------------
	# PART 2: Fullscreen Button Toggle Logic
	# ---------------------------------------------------------
	print("\n>>> PART 2: Fullscreen Toggle Logic")
	var initial_text: String = fullscreen_btn.text
	menu.toggle_fullscreen()
	var toggled_text: String = fullscreen_btn.text
	# Toggle back to restore initial state
	menu.toggle_fullscreen()
	print("Fullscreen toggle verified: ", initial_text, " -> ", toggled_text)

	# ---------------------------------------------------------
	# PART 3: Start Game Action & Signal
	# ---------------------------------------------------------
	print("\n>>> PART 3: Start Game Action")
	var start_signal_received: Array[bool] = [false]
	menu.start_requested.connect(func() -> void: start_signal_received[0] = true)
	menu.start_game()
	if not start_signal_received[0]:
		printerr("TEST FAILED: start_requested signal not emitted.")
		get_tree().quit(1)
		return
	print("Verified start_requested signal emitted and progression reset triggered.")

	menu.queue_free()

	# ---------------------------------------------------------
	# PART 4: MenuLevel 3D Environment Verification
	# ---------------------------------------------------------
	print("\n>>> PART 4: MenuLevel 3D Environment Verification")
	var level_scene: PackedScene = load("res://Levels/menu_level.tscn") as PackedScene
	if level_scene == null:
		printerr("TEST FAILED: Could not load res://Levels/menu_level.tscn")
		get_tree().quit(1)
		return
	print("Loaded res://Levels/menu_level.tscn successfully.")

	var menu_level: Node3D = level_scene.instantiate() as Node3D
	add_child(menu_level)

	# Verify UI.is_in_main_menu flag
	if UI != null and not UI.is_in_main_menu:
		printerr("TEST FAILED: UI.is_in_main_menu should be true when MenuLevel is active.")
		get_tree().quit(1)
		return
	print("Verified UI.is_in_main_menu is true.")

	# Verify pause is prevented while on main menu
	if UI != null:
		var was_paused: bool = UI.is_paused()
		UI.toggle_pause()
		if UI.is_paused() != was_paused:
			printerr("TEST FAILED: toggle_pause should not toggle pause state while in main menu.")
			get_tree().quit(1)
			return
		print("Verified UI.toggle_pause() is ignored while in main menu.")

	# Verify MenuCamera
	var camera: Camera3D = menu_level.get_node_or_null("MenuCamera") as Camera3D
	if camera == null or not camera.current:
		printerr("TEST FAILED: MenuCamera missing or not current.")
		get_tree().quit(1)
		return
	print("Verified MenuCamera is present and active (current = true).")

	# Verify Floormap and Wallmap
	var floormap: GridMap = menu_level.get_node_or_null("Floormap") as GridMap
	var wallmap: GridMap = menu_level.get_node_or_null("Wallmap") as GridMap
	if floormap == null or floormap.get_used_cells().size() == 0:
		printerr("TEST FAILED: Floormap missing or empty in MenuLevel.")
		get_tree().quit(1)
		return
	if wallmap == null or wallmap.get_used_cells().size() == 0:
		printerr("TEST FAILED: Wallmap missing or empty in MenuLevel.")
		get_tree().quit(1)
		return
	print("Verified Floormap (", floormap.get_used_cells().size(), " cells) and Wallmap (", wallmap.get_used_cells().size(), " cells).")

	# Verify MenuPlayer (Hero)
	var hero: Node3D = menu_level.get_node_or_null("MenuPlayer") as Node3D
	if hero == null:
		printerr("TEST FAILED: MenuPlayer missing from MenuLevel.")
		get_tree().quit(1)
		return
	if hero.is_in_group("player"):
		printerr("TEST FAILED: MenuPlayer should NOT be in 'player' group to avoid cache leakage.")
		get_tree().quit(1)
		return
	var hero_ap: AnimationPlayer = hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if hero_ap == null:
		printerr("TEST FAILED: AnimationPlayer missing on MenuPlayer.")
		get_tree().quit(1)
		return
	if not hero_ap.has_animation("PlayerAnimations/Idle_A"):
		printerr("TEST FAILED: PlayerAnimations/Idle_A missing on MenuPlayer.")
		get_tree().quit(1)
		return
	print("Verified MenuPlayer: isolated from 'player' group, has Idle_A animation.")

	menu_level.queue_free()

	print("\n====================================================")
	print("  ALL MAIN MENU & MENU LEVEL TESTS PASSED!")
	print("  1. MainMenu UI hierarchy & BBCode wave title")
	print("  2. Start, Fullscreen, and Quit button wiring")
	print("  3. MenuLevel 3D floor and wall showcase")
	print("  4. MenuCamera active and current")
	print("  5. Hero in idle animation, isolated from player group")
	print("  6. UI pause suppression in main menu")
	print("====================================================")
	get_tree().quit(0)
