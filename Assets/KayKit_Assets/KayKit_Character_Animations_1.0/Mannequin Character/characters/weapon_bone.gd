extends BoneAttachment3D

@export var attacking := false

@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

func _process(delta: float) -> void:
	mesh_instance_3d.visible = attacking
