## Registers the prototype pack stairs as Floormap brush 2 without changing
## existing floor items. Run with run_scratch.py. The visual is half-height:
## 4m footprint, 2m rise toward local -X. Smooth ramp collision avoids risers
## blocking CharacterBody3D; its surface sits up to .25m below stair treads.
extends SceneTree

const SOURCE: String = "res://Assets/KayKit_Assets/KayKit_Prototype_Bits_1.1_FREE/Assets/gltf/Primitive_Stairs.gltf"
const LIBRARY: String = "res://Levels/Gridmap/floormap.tres"
const ITEM: int = 2

func _init() -> void:
	var source: Node3D = (load(SOURCE) as PackedScene).instantiate() as Node3D
	var meshes: Array[Node] = source.find_children("*", "MeshInstance3D", true, false)
	assert(not meshes.is_empty(), "Stairs source contains no mesh")
	var visual: MeshInstance3D = meshes[0] as MeshInstance3D
	var mesh: Mesh = visual.mesh
	assert(mesh != null)
	var library: MeshLibrary = load(LIBRARY) as MeshLibrary
	if library.get_item_list().has(ITEM):
		assert(library.get_item_name(ITEM) == "Primitive_Stairs", "Brush ID 2 already used")
	else:
		library.create_item(ITEM)
	library.set_item_name(ITEM, "Primitive_Stairs")
	library.set_item_mesh(ITEM, mesh)
	# Floormap local origin is -1m below its floor tops. Native floor pieces
	# are 1m thick; stairs start at the adjoining floor's TOP, not its base.
	library.set_item_mesh_transform(ITEM, Transform3D(Basis.from_scale(Vector3(1, 0.5, 1)), Vector3(0, 1, 0)))
	var ramp: ConvexPolygonShape3D = ConvexPolygonShape3D.new()
	ramp.points = PackedVector3Array([
		Vector3(-2, 0, -2), Vector3(-2, 0, 2),
		Vector3(2, 0, -2), Vector3(2, 0, 2),
		Vector3(-2, 2, -2), Vector3(-2, 2, 2)])
	library.set_item_shapes(ITEM, [ramp, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))])
	# Small readable stair silhouette for the GridMap brush palette.
	var icon: Image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	icon.fill(Color(0, 0, 0, 0))
	for x: int in range(8, 56):
		var top: int = 10 + (x - 8) / 6 * 5
		for y: int in range(top, 55):
			icon.set_pixel(x, y, Color(0.25, 0.65, 0.85))
	library.set_item_preview(ITEM, ImageTexture.create_from_image(icon))
	assert(ResourceSaver.save(library, LIBRARY) == OK)
	source.free()
	print("Registered Primitive_Stairs brush 2: rise2m, run4m, ascending -X; layer delta4")
	quit(0)
