## Base class for enemies.
class_name Enemy
extends CharacterBody3D

## Base movement speed of this enemy in meters per second.
@export var base_speed := 3.5

@onready var animation_tree: AnimationTree = $AnimationAnchor/AnimatedEnemy/Enemy_Medium/AnimationTree
