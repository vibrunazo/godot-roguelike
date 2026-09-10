## Virtual base class for all states.
## Extend this class and override its methods to implement a state.
class_name State 
extends Node

## Emitted when the state finishes and wants to transition to another state.
signal finished(next_state_path: String, data: Dictionary)

## Called by the state machine when receiving unhandled input events.
func handle_input(_event: InputEvent) -> void:
	pass

## Called by the state machine on the engine's main loop tick.
func update(_delta: float) -> void:
	pass

## Called by the state machine on the engine's physics update tick.
func physics_update(_delta: float) -> void:
	pass

## Called by the state machine upon changing the active state. The `data` parameter
## is a dictionary with arbitrary data the state can use to initialize itself.
func enter(_previous_state_path: String, _data := {}) -> void:
	pass

## Called by the state machine before changing the active state. Use this function
## to clean up the state.
func exit() -> void:
	pass

## Connects a callback to a signal for one-shot delivery, ignoring duplicate
## connects. Use in enter() for fire-once signals (e.g. animation_finished);
## pair with disconnect_safe() in exit() so early interruptions never leave
## stale callbacks that would transition the machine after the state is gone.
func connect_one_shot(sig: Signal, callback: Callable) -> void:
	if not sig.is_connected(callback):
		sig.connect(callback, CONNECT_ONE_SHOT)

## Disconnects a callback from a signal, silently skipping when not connected.
## Use in exit() (and early-cancel paths) for connections made in enter().
## The guard avoids "non-existent connection" errors when a one-shot signal
## already fired and auto-disconnected before the state exited.
func disconnect_safe(sig: Signal, callback: Callable) -> void:
	if sig.is_connected(callback):
		sig.disconnect(callback)
