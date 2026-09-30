## Keeps a level's navmesh in step with its destructible props. The committed
## bake carves every prop out; when a Destructible under the region breaks,
## the navmesh is rebuilt without it, so enemies path through the spot it
## stood on instead of around a hole.
##
## The main thread does almost nothing per rebuild. The static level (every
## collider except destructible bodies, which sit on prop_layers) is parsed
## once, when the level starts, and each prop once, when it appears. A rebuild
## merges the cached geometry of the props still standing and bakes it, both
## on a WorkerThreadPool thread; the main thread only swaps the finished mesh
## in, and the navigation server applies it on its own threads. The result is
## the mesh a full bake of the level as it stands would give.
##
## Rebuilds start at most once every min_rebuild_interval seconds of physics
## time (counted in physics frames, so never sooner), one at a time; props
## that break in between are folded into the next rebuild.
class_name NavmeshRebuilder
extends Node

## Emitted when a rebuild is handed to a worker thread.
signal rebuild_started
## Emitted when a rebuilt mesh is handed to the region. The navigation map
## serves it after the server's next sync.
signal rebuilt

## The level's navigation region. Its mesh at start holds the bake settings
## every rebuild reuses; destructibles under it are tracked.
@export var region: NavigationRegion3D
## Collision layers of destructible props' solid bodies (the Props layer).
## The static level is parsed without them; nothing else may use them.
@export_flags_3d_physics var prop_layers: int = 4
## Minimum physics time, in seconds, between the starts of two rebuilds.
@export var min_rebuild_interval: float = 2.0

## Bake settings: the region's mesh as the level shipped it.
var _settings: NavigationMesh
## The level's geometry without destructible bodies, in region space.
var _static_geometry: NavigationMeshSourceGeometryData3D
## Each standing prop's parsed body geometry, in region space.
var _props: Dictionary[Destructible, NavigationMeshSourceGeometryData3D] = {}
## A rebuild was asked for and has not started yet.
var _pending: bool = false
## Physics frame the last rebuild started on, or -1 before the first.
var _last_start_frame: int = -1
## The running rebuild's WorkerThreadPool task, or -1.
var _task_id: int = -1
## Where the running rebuild's worker leaves the baked mesh.
var _result: Array[NavigationMesh] = []


func _ready() -> void:
	set_physics_process(false)
	if region == null or region.navigation_mesh == null:
		push_error("%s: region with a navigation_mesh is not set." % name)
		return
	_settings = region.navigation_mesh
	get_tree().node_added.connect(_on_node_added)
	# Deferred so the whole level has entered the tree and set itself up.
	_capture_geometry.call_deferred()


## A rebuild must finish before the thread's inputs and this node go away.
func _exit_tree() -> void:
	if _task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1


## Asks for a rebuild. It starts now if none is running and the last one
## started at least min_rebuild_interval ago, else as soon as both hold.
func request_rebuild() -> void:
	_pending = true
	_try_start()


## Parses the static level once and registers the props already placed.
func _capture_geometry() -> void:
	var static_settings: NavigationMesh = _settings.duplicate() as NavigationMesh
	static_settings.geometry_collision_mask = _settings.geometry_collision_mask & ~prop_layers
	_static_geometry = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(static_settings, _static_geometry, region)
	if not _static_geometry.has_data():
		push_error("%s: the level parsed to no navigation geometry; rebuilds are off." % name)
		_static_geometry = null
		return
	for node: Node in region.find_children("*", "Node3D", true, false):
		if node is Destructible:
			_register(node as Destructible)
	_try_start()


## Props added at runtime are registered once their subtree is in the tree.
func _on_node_added(node: Node) -> void:
	if node is Destructible and _static_geometry != null and region.is_ancestor_of(node):
		_register.call_deferred(node as Destructible)


## Parses one prop's body into region space and follows its lifetime.
func _register(prop: Destructible) -> void:
	if not is_instance_valid(prop) or not prop.is_inside_tree() or _props.has(prop):
		return
	var parsed: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(_settings, parsed, prop)
	# A subtree parses in its root's space.
	var to_region: Transform3D = region.global_transform.affine_inverse() * prop.global_transform
	var vertices: PackedFloat32Array = parsed.get_vertices()
	for i: int in range(0, vertices.size(), 3):
		var point: Vector3 = to_region * Vector3(vertices[i], vertices[i + 1], vertices[i + 2])
		vertices[i] = point.x
		vertices[i + 1] = point.y
		vertices[i + 2] = point.z
	var geometry: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	geometry.append_arrays(vertices, parsed.get_indices())
	_props[prop] = geometry
	prop.broke.connect(_on_prop_broke.bind(prop))
	prop.tree_exiting.connect(_forget.bind(prop))


## A broken prop leaves the navmesh with the next rebuild.
func _on_prop_broke(prop: Destructible) -> void:
	_forget(prop)
	request_rebuild()


## Drops a prop that broke or left the level from the rebuild inputs.
func _forget(prop: Destructible) -> void:
	_props.erase(prop)


## Starts the pending rebuild on a worker thread when nothing holds it back.
## While the interval holds it back, _physics_process retries every tick.
func _try_start() -> void:
	if not _pending or _task_id != -1 or _static_geometry == null:
		return
	if not _interval_elapsed():
		set_physics_process(true)
		return
	_pending = false
	_last_start_frame = Engine.get_physics_frames()
	var parts: Array[NavigationMeshSourceGeometryData3D] = [_static_geometry]
	parts.append_array(_props.values())
	_result = [null]
	_task_id = WorkerThreadPool.add_task(_bake.bind(_settings, parts, _result), false, "Navmesh rebuild")
	set_physics_process(true)
	rebuild_started.emit()


## Whether min_rebuild_interval of physics time has passed since the last
## rebuild started.
func _interval_elapsed() -> bool:
	if _last_start_frame < 0:
		return true
	var frames: int = ceili(min_rebuild_interval * Engine.physics_ticks_per_second)
	return Engine.get_physics_frames() - _last_start_frame >= frames


## Worker thread: merges the geometry and bakes a mesh with the level's
## settings into result[0]. Touches only its arguments, which the main thread
## never changes (a new rebuild gets new arrays).
static func _bake(settings: NavigationMesh, parts: Array[NavigationMeshSourceGeometryData3D], result: Array[NavigationMesh]) -> void:
	var merged: NavigationMeshSourceGeometryData3D = NavigationMeshSourceGeometryData3D.new()
	for part: NavigationMeshSourceGeometryData3D in parts:
		merged.merge(part)
	var mesh: NavigationMesh = settings.duplicate() as NavigationMesh
	NavigationServer3D.bake_from_source_geometry_data(mesh, merged)
	result[0] = mesh


## Runs only while a rebuild is on a worker or waits on the interval: hands
## a finished mesh over, then starts the pending rebuild once it may.
func _physics_process(_delta: float) -> void:
	if _task_id != -1:
		if not WorkerThreadPool.is_task_completed(_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_task_id = -1
		_hand_over(_result[0])
	_try_start()
	if _task_id == -1 and not _pending:
		set_physics_process(false)


## Gives the region a baked mesh, unless the bake came out empty.
func _hand_over(mesh: NavigationMesh) -> void:
	if mesh == null or mesh.get_polygon_count() == 0:
		push_error("%s: a rebuild baked an empty navmesh; keeping the old one." % name)
		return
	region.navigation_mesh = mesh
	rebuilt.emit()
