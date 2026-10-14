## Self-test case for the capturer's automatic framing: the only geometry is a
## GridMap, 15 cells of 2 m along X, so the framed bounds must span 30 m (the
## fallback when nothing is framed is 20 m).
extends Node3D


func _ready() -> void:
	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	library.set_item_mesh(0, box)
	var grid: GridMap = GridMap.new()
	grid.mesh_library = library
	grid.cell_size = Vector3(2.0, 2.0, 2.0)
	add_child(grid)
	for x: int in 15:
		grid.set_cell_item(Vector3i(x, 0, 0), 0)
