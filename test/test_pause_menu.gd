## Pause and game-over flow (UI autoload + PauseMenu):
## - pause_game()/resume_game()/toggle_pause() pause and unpause the tree and
##   emit pause_state_changed; pausing opens a menu that keeps processing while
##   the tree is paused, and resuming frees it.
## - The menu's resume button and the ui_pause action (by name) resume/toggle.
## - The game-over screen (show_game_over) hides resume, keeps restart, and
##   locks the pause toggle until resume_game() clears it.
## - Player defeat shows the game-over screen only after
##   Character.DEFEAT_MENU_DELAY, and dying never resets run progression.
## - Regression guards: the pause menu never renders its own gold counter (the
##   HUD owns it), and without a selected item the stats panel shows no
##   comparison arrows.
## Key bindings, colors and layout are design choices and are not asserted.
extends "res://test/lib/test_suite.gd"

const PLAYER_SCENE: PackedScene = preload("res://Player/player.tscn")
## Test-owned progression values to prove defeat leaves them untouched.
const TEST_DIFFICULTY: int = 9
const TEST_DUNGEON_LEVEL: int = 5


func after_each() -> void:
	# Never leak a paused tree or a game-over lock into the next test.
	UI.resume_game()


func test_pause_action_is_bound() -> void:
	if check(InputMap.has_action(&"ui_pause"), "the ui_pause action should exist in the InputMap"):
		check(not InputMap.action_get_events(&"ui_pause").is_empty(), "the ui_pause action should have at least one binding")


func test_pause_and_resume_toggle_the_tree_and_report_it() -> void:
	var states: Array[bool] = []
	var record: Callable = func(is_paused: bool) -> void: states.append(is_paused)
	UI.pause_state_changed.connect(record)
	UI.pause_game()
	check(get_tree().paused and UI.is_paused(), "pause_game() should pause the tree")
	UI.resume_game()
	check(not get_tree().paused and not UI.is_paused(), "resume_game() should unpause the tree")
	UI.toggle_pause()
	check(UI.is_paused(), "toggle_pause() should pause an unpaused game")
	UI.toggle_pause()
	check(not UI.is_paused(), "toggle_pause() should resume a paused game")
	UI.pause_state_changed.disconnect(record)
	check_eq(states, [true, false, true, false], "pause_state_changed should report every change in order")


func test_pausing_opens_a_menu_that_works_while_paused_and_resume_frees_it() -> void:
	UI.pause_game()
	var menu: PauseMenu = _open_menu()
	if not check(menu != null, "pausing should open a pause menu"):
		return
	check_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS, "the menu must keep processing while the tree is paused")
	var menu_ref: WeakRef = weakref(menu)
	UI.resume_game()
	await wait_until(func() -> bool: return menu_ref.get_ref() == null, "resuming should free the pause menu", 5)


func test_resume_button_resumes_the_game() -> void:
	UI.pause_game()
	var menu: PauseMenu = _open_menu()
	if not check(menu != null, "pausing should open a pause menu"):
		return
	menu.buttons_panel.resume_button.pressed.emit()
	check(not UI.is_paused(), "pressing resume should unpause the game")


func test_pressing_the_pause_action_toggles_pause() -> void:
	press_action(&"ui_pause")
	if not await wait_until(func() -> bool: return UI.is_paused(), "pressing ui_pause should pause the game", 10):
		return
	press_action(&"ui_pause")
	await wait_until(func() -> bool: return not UI.is_paused(), "pressing ui_pause again should resume the game", 10)


func test_game_over_hides_resume_and_locks_the_pause_toggle() -> void:
	UI.show_game_over()
	var menu: PauseMenu = _open_menu()
	check(UI.is_paused(), "the game-over screen should pause the tree")
	if check(menu != null, "the game-over screen should open a menu"):
		check(not menu.buttons_panel.resume_button.visible, "game over should hide the resume button")
		check(menu.buttons_panel.restart_button.visible, "game over should keep the restart button")
	UI.toggle_pause()
	check(UI.is_paused(), "the pause toggle should stay locked on the game-over screen")
	UI.resume_game()
	check(not UI.is_paused(), "resume_game() should clear the game-over screen")


func test_player_defeat_shows_game_over_after_the_delay_without_resetting_progression() -> void:
	var arena: Node3D = load_arena()
	var player: Character = spawn(PLAYER_SCENE, arena, (arena.get_node("PlayerSpawn") as Node3D).global_position) as Character
	await wait_physics_frames(1)
	var saved_difficulty: int = ProgressionState.difficulty_level
	var saved_dungeon_level: int = ProgressionState.dungeon_level
	ProgressionState.difficulty_level = TEST_DIFFICULTY
	ProgressionState.dungeon_level = TEST_DUNGEON_LEVEL
	player.hurtbox.receive_hit(player.attribute_component.get_current(AttributeComponent.POOL_HEALTH), Vector3.ZERO)
	await wait_physics_frames(_frames_for(Character.DEFEAT_MENU_DELAY * 0.5))
	check(not UI.is_paused(), "the game-over screen must wait for the defeat delay")
	check_eq(str(player.state_machine.state.name), "PlayerDefeat", "a defeated player should enter PlayerDefeat")
	await wait_until(func() -> bool: return UI.is_paused(), "the game-over screen should appear after the defeat delay", _frames_for(Character.DEFEAT_MENU_DELAY))
	var menu: PauseMenu = _open_menu()
	check(menu != null and not menu.buttons_panel.resume_button.visible, "defeat should open the game-over screen")
	check_eq(ProgressionState.difficulty_level, TEST_DIFFICULTY, "dying must not reset the difficulty (reset happens on restart)")
	check_eq(ProgressionState.dungeon_level, TEST_DUNGEON_LEVEL, "dying must not reset the dungeon level (reset happens on restart)")
	ProgressionState.difficulty_level = saved_difficulty
	ProgressionState.dungeon_level = saved_dungeon_level


func test_pause_menu_does_not_duplicate_the_hud_gold_counter() -> void:
	var menu: PauseMenu = autofree(GlobalVars.pause_menu_scene.instantiate()) as PauseMenu
	add_child(menu)
	check(menu.find_child("GoldLabel", true, false) == null, "the pause menu must not render its own gold counter; the HUD's stays visible under it")


func test_stats_panel_shows_no_comparison_arrows_without_a_selected_item() -> void:
	var menu: PauseMenu = autofree(GlobalVars.pause_menu_scene.instantiate()) as PauseMenu
	add_child(menu)
	check(not menu.stats_panel.attack_row.text.contains("->"), "stat comparison arrows need a selected item")


## The pause/game-over menu UI currently shows, or null.
func _open_menu() -> PauseMenu:
	for node: Node in UI.find_children("*", "PauseMenu", true, false):
		if not node.is_queued_for_deletion():
			return node as PauseMenu
	return null


## Physics frames covering the given game time, plus a small margin.
func _frames_for(seconds: float) -> int:
	return ceili(seconds * Engine.physics_ticks_per_second) + 5
