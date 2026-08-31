class_name MannequinAnimationTree
extends AnimationTree

@export var animation_speed := 6.0

@onready var playback: AnimationNodeStateMachinePlayback = self["parameters/playback"]

var walk_blend := "parameters/WalkSpace/blend_position"
