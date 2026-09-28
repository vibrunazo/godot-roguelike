## The main menu and its 3D diorama level:
## - the Start button has focus on open (keyboard and gamepad can start at
##   once), and no label calls the screen "main menu",
## - the fullscreen button toggles fullscreen and its text follows the mode,
## - while the menu level is up the UI is in menu mode: pausing is ignored,
##   there is no HUD, and the menu camera is current; leaving it ends menu
##   mode,
## - the menu hero idles and stays out of the "player" group (so it is never
##   cached and carried into a run),
## - pressing Start leaves menu mode, clears the carried player and starts
##   loading the first level. That changes the scene, so it runs last.
extends "res://test/lib/test_suite.gd"

const MENU_LEVEL_SCENE: PackedScene = preload("res://Levels/menu_level.tscn")

var _level: MenuLevel
var _menu: CanvasLayer


func before_each() -> void:
	_level = spawn(MENU_LEVEL_SCENE) as MenuLevel
	_menu = _level.main_menu
	await wait_physics_frames(1)


func after_each() -> void:
	UI.resume_game()


func test_start_has_focus_and_nothing_says_main_menu() -> void:
	check((_menu.get_node("%StartButton") as Button).has_focus(), "the Start button should have focus when the menu opens")
	for node: Node in _menu.find_children("*", "Label", true, false):
		check(not (node as Label).text.to_lower().contains("main menu"), "no label should say \"main menu\" (%s)" % node.name)


func test_the_fullscreen_button_toggles_and_its_text_follows_the_mode() -> void:
	var button: Button = _menu.get_node("%FullscreenButton") as Button
	var was_fullscreen: bool = UI.is_fullscreen()
	var text_before: String = button.text
	button.pressed.emit()
	# A headless display may refuse the switch; the text must track the mode
	# either way.
	var mode_changed: bool = UI.is_fullscreen() != was_fullscreen
	check_eq(button.text != text_before, mode_changed, "the button text should change exactly when the window mode changes")
	button.pressed.emit()
	check_eq(UI.is_fullscreen(), was_fullscreen, "pressing twice should restore the window mode")
	check_eq(button.text, text_before, "pressing twice should restore the text")


func test_the_menu_level_is_menu_mode_without_pause_or_hud() -> void:
	check(UI.is_in_main_menu, "the menu level should put the UI in menu mode")
	var was_paused: bool = UI.is_paused()
	UI.toggle_pause()
	check_eq(UI.is_paused(), was_paused, "pausing should be ignored in the menu")
	check(get_tree().get_nodes_in_group("hud").is_empty(), "the menu should show no HUD")
	check(_level.menu_camera.current, "the menu camera should be current")
	_level.queue_free()
	await wait_physics_frames(1)
	check(not UI.is_in_main_menu, "leaving the menu level should end menu mode")


func test_the_menu_hero_idles_outside_the_player_group() -> void:
	check(not _level.hero.is_in_group("player"), "the menu hero must not be in the player group (it would be carried into a run)")
	var animation_player: AnimationPlayer = _level.hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	check(animation_player != null and animation_player.is_playing(), "the menu hero should play its idle animation")


## Changes the scene: keep it the last test.
func test_pressing_start_leaves_menu_mode_and_starts_a_fresh_run() -> void:
	var started: Array[bool] = [false]
	_menu.connect(&"start_requested", func() -> void: started[0] = true)
	(_menu.get_node("%StartButton") as Button).pressed.emit()
	check(started[0], "pressing Start should request a start")
	check(not UI.is_in_main_menu, "starting should leave menu mode")
	check(SceneTransition.player_cache == null, "starting should clear any carried player")
