class_name PlayerState
extends State

@export var player: Player
@export var dash_state: PlayerState

## Sets player velocity based on current input direction and speed
func core_movement(delta: float, speed: float) -> void:
	var direction := player.get_movement_direction()
	player.velocity = direction * speed

## changes to Dash State with current input direction if dash action was pressed
func check_dash(event: InputEvent) -> void:
	if player.can_dash() == false:
		return
	if event.is_action_pressed("dash"):
		var direction := player.get_movement_direction()
		finished.emit(dash_state.name, {"direction": direction})
