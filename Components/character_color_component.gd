## Manages character palette recoloring using character_palette.gdshader.
## Enables editing 8 vertical gradients in the Godot Inspector using Godot's built-in
## visual Gradient editor, as well as applying a global tint and switching between
## Enemy and Player UV mapping modes.
@tool
class_name CharacterColorComponent
extends Node

## Palette mapping mode for UV interpretation.
enum PaletteMode {
	ENEMY = 0,
	PLAYER = 1,
	GLOBAL_TINT_ONLY = 2,
}

const PALETTE_SHADER: Shader = preload("res://Shaders/character_palette.gdshader")

## UV interpretation mode: ENEMY (top half 8 columns), PLAYER (bottom half outfit + trim + boots),
## or GLOBAL_TINT_ONLY.
@export var palette_mode: PaletteMode = PaletteMode.ENEMY:
	set(value):
		palette_mode = value
		_update_shader_parameters()

## Global color multiplier applied over all surfaces.
@export var global_tint: Color = Color.WHITE:
	set(value):
		global_tint = value
		_update_shader_parameters()

## Toggles palette gradient replacement on or off.
@export var enable_palette: bool = true:
	set(value):
		enable_palette = value
		_update_shader_parameters()

## Bitmask allowing selective enable/disable of individual gradient slots (0..7).
@export_flags("Slot 0", "Slot 1", "Slot 2", "Slot 3", "Slot 4", "Slot 5", "Slot 6", "Slot 7")
var gradient_mask: int = 255:
	set(value):
		gradient_mask = value
		_update_shader_parameters()

## The 8 gradient color ramps corresponding to palette columns.
## In the Inspector, assign a Gradient to any slot to recolor that part of the character.
## Unassigned (null) slots leave the original character texture untouched underneath.
@export var gradients: Array[Gradient] = [null, null, null, null, null, null, null, null]:
	set(value):
		gradients = value
		_rebind_gradient_signals()
		_rebuild_gradient_textures()
		_update_shader_parameters()

## Surface roughness applied to the character material.
@export_range(0.0, 1.0) var roughness: float = 0.3:
	set(value):
		roughness = value
		_update_shader_parameters()

## Surface metallic factor applied to the character material.
@export_range(0.0, 1.0) var metallic: float = 0.0:
	set(value):
		metallic = value
		_update_shader_parameters()

## Automatically fills empty gradient slots with default color ramps on ready.
@export var auto_populate_defaults: bool = false

## Trigger to reset the gradients to default color ramps for the current palette_mode.
@export var reset_to_defaults: bool = false:
	set(value):
		if value:
			_populate_default_gradients()
			_update_shader_parameters()

## Cached ShaderMaterial instance unique to this character.
var material: ShaderMaterial = null

## Cached Texture2D extracted from original mesh surface.
var original_albedo_texture: Texture2D = null

## Array of 8 GradientTexture1D objects passed to the shader uniform array.
var _gradient_textures: Array[Texture2D] = []

## Track connected gradients to prevent duplicate connections.
var _connected_gradients: Array[Gradient] = []


func _ready() -> void:
	while gradients.size() < 8:
		gradients.append(null)
	
	if auto_populate_defaults:
		_populate_default_gradients()
	
	_setup_material()
	apply_to_meshes()


## Discovers all body MeshInstance3D nodes under the character's Skeleton3D.
## Excludes weapon hitboxes, projectiles, and particle meshes.
func get_body_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	var search_root: Node = self
	
	if get_parent():
		search_root = get_parent()
		var character: Character = search_root as Character
		if character and character.mesh_mount:
			search_root = character.mesh_mount
	
	for child: Node in search_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi and mi.mesh and mi.get_parent() is Skeleton3D:
			meshes.append(mi)
	return meshes


## Applies the configured ShaderMaterial to all character body meshes.
func apply_to_meshes() -> void:
	if not material:
		_setup_material()
	
	var meshes: Array[MeshInstance3D] = get_body_meshes()
	for mi: MeshInstance3D in meshes:
		mi.material_override = material


## Sets a specific gradient slot (0..7) and immediately updates the shader.
func set_gradient(slot: int, grad: Gradient) -> void:
	if slot < 0 or slot >= 8:
		push_warning("CharacterColorComponent: Invalid gradient slot %d (must be 0..7)" % slot)
		return
	
	while gradients.size() <= slot:
		gradients.append(Gradient.new())
	
	gradients[slot] = grad
	_rebind_gradient_signals()
	_rebuild_gradient_textures()
	_update_shader_parameters()


## Convenience function to set a flat color on a gradient slot with automatic shading.
func set_slot_color(slot: int, color: Color) -> void:
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([color.lightened(0.1), color.darkened(0.5)])
	set_gradient(slot, grad)


## Sets the global tint color at runtime.
func set_global_tint(color: Color) -> void:
	global_tint = color


## Pre-populates the 8 gradient slots with defaults matching the asset palette.
func _populate_default_gradients() -> void:
	var default_ramps: Array[Gradient] = []
	if palette_mode == PaletteMode.PLAYER:
		# Player default color ramps (Slots 2..5 intentionally null to preserve face details)
		default_ramps.append(_create_ramp(Color("#42465a"), Color("#242632"))) # 0: Boots & gloves
		default_ramps.append(_create_ramp(Color("#aab8be"), Color("#596064"))) # 1: Trim / Torso accent
		default_ramps.append(null) # 2: Unused
		default_ramps.append(null) # 3: Head / Face (null preserves base texture eyes/mouth)
		default_ramps.append(null) # 4: Unused
		default_ramps.append(null) # 5: Unused
		default_ramps.append(_create_ramp(Color("#9f7459"), Color("#5d4139"))) # 6: Leather belt
		default_ramps.append(_create_ramp(Color("#68cdb9"), Color("#359f98"))) # 7: Main outfit
	else:
		# Enemy default color ramps (matching KayKit columns 0..7)
		default_ramps.append(_create_ramp(Color("#4d4d4d"), Color("#1a1a1a"))) # 0: Dark grey straps
		default_ramps.append(_create_ramp(Color("#596064"), Color("#3c4246"))) # 1: Slate grey armor
		default_ramps.append(_create_ramp(Color("#aab8be"), Color("#596064"))) # 2: Cool grey secondary
		default_ramps.append(_create_ramp(Color("#fbfcfc"), Color("#aebcc1"))) # 3: White rivets
		default_ramps.append(_create_ramp(Color("#29aae1"), Color("#1c216f"))) # 4: Blue
		default_ramps.append(_create_ramp(Color("#00ab5d"), Color("#005d4b"))) # 5: Green
		default_ramps.append(_create_ramp(Color("#fed365"), Color("#f58238"))) # 6: Yellow
		default_ramps.append(_create_ramp(Color("#f15a24"), Color("#a50858"))) # 7: Red / Crimson (Main body)
	
	gradients.clear()
	for i: int in range(8):
		gradients.append(default_ramps[i])
	
	_rebind_gradient_signals()
	_rebuild_gradient_textures()
	_update_shader_parameters()


func _create_ramp(c_top: Color, c_bottom: Color) -> Gradient:
	var grad: Gradient = Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([c_top, c_bottom])
	return grad


func _setup_material() -> void:
	if not material:
		material = ShaderMaterial.new()
		material.shader = PALETTE_SHADER
	
	# Extract original albedo texture from meshes if not yet set
	if not original_albedo_texture:
		var meshes: Array[MeshInstance3D] = get_body_meshes()
		for mi: MeshInstance3D in meshes:
			if mi.mesh and mi.mesh.get_surface_count() > 0:
				var surf_mat: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
				if surf_mat and surf_mat.albedo_texture:
					original_albedo_texture = surf_mat.albedo_texture
					break
	
	if original_albedo_texture:
		material.set_shader_parameter("albedo_texture", original_albedo_texture)
	
	_rebind_gradient_signals()
	_rebuild_gradient_textures()
	_update_shader_parameters()


func _rebind_gradient_signals() -> void:
	# Disconnect old signals
	for grad: Gradient in _connected_gradients:
		if is_instance_valid(grad) and grad.changed.is_connected(_on_gradient_changed):
			grad.changed.disconnect(_on_gradient_changed)
	_connected_gradients.clear()
	
	# Connect current gradients
	for grad: Gradient in gradients:
		if is_instance_valid(grad):
			grad.changed.connect(_on_gradient_changed)
			_connected_gradients.append(grad)


func _on_gradient_changed() -> void:
	_rebuild_gradient_textures()
	_update_shader_parameters()


func _rebuild_gradient_textures() -> void:
	_gradient_textures.clear()
	for i: int in range(8):
		var grad: Gradient = gradients[i] if (i < gradients.size() and gradients[i] != null) else null
		var tex: GradientTexture1D = GradientTexture1D.new()
		if grad:
			tex.gradient = grad
		else:
			var dummy: Gradient = Gradient.new()
			dummy.colors = PackedColorArray([Color.WHITE, Color.WHITE])
			tex.gradient = dummy
		tex.width = 64
		_gradient_textures.append(tex)


func _update_shader_parameters() -> void:
	if not material:
		return
	
	var active_mask: int = 0
	for i: int in range(mini(8, gradients.size())):
		if gradients[i] != null:
			active_mask |= (1 << i)
	
	material.set_shader_parameter("palette_mode", int(palette_mode))
	material.set_shader_parameter("enable_palette", enable_palette)
	material.set_shader_parameter("gradient_mask", gradient_mask)
	material.set_shader_parameter("active_gradient_mask", active_mask)
	material.set_shader_parameter("global_tint", global_tint)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("metallic", metallic)
	
	if _gradient_textures.size() == 8:
		material.set_shader_parameter("gradient_palettes", _gradient_textures)
