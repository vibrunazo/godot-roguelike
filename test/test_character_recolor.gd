## Character palette recoloring (CharacterColorComponent):
## - every character (player and each enemy type) recolors all of its body
##   meshes with its own palette material and never its weapons or VFX, and
##   the shader uses the component's palette mode,
## - a rig nested in a character (a backpack rider) that has its own
##   component keeps its own palette; one without wears its carrier's,
## - only slots with an assigned gradient are recolored; setting and clearing
##   a slot switches exactly that slot,
## - the global tint reaches the shader,
## - a component always exposes one gradient slot per palette column.
## Colors, gradients and mesh counts are the artists' choice and are not
## asserted.
extends "res://test/lib/project_suite.gd"

const CHARACTER_SCENES: Array[String] = [
	"res://Player/player.tscn",
	"res://Enemy/melee_enemy.tscn",
	"res://Enemy/ranged_enemy.tscn",
	"res://Enemy/enemy_brute.tscn",
	"res://Enemy/firebomber_enemy.tscn",
	"res://Enemy/enemy_thunder_mage.tscn",
]
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
const RIG_SCENE: PackedScene = preload("res://Enemy/animated_enemy.tscn")
## Palette columns the shader reads.
const SLOT_COUNT: int = 8
## Test-owned colors.
const TEST_TINT: Color = Color(0.2, 0.8, 0.4, 1.0)
const TEST_SLOT_COLOR: Color = Color.PURPLE


func test_every_character_recolors_its_body_but_never_its_gear() -> void:
	for path: String in CHARACTER_SCENES:
		var character: Character = spawn(load(path) as PackedScene) as Character
		await get_tree().process_frame
		var colors: CharacterColorComponent = character.color_component
		if not check(colors != null, "%s should have a color component" % path.get_file()):
			continue
		var body: Array[MeshInstance3D] = colors.get_body_meshes()
		check(not body.is_empty(), "%s should have body meshes to recolor" % path.get_file())
		for mesh: MeshInstance3D in body:
			check(mesh.material_override == colors.material, "%s body mesh %s should use the palette material" % [path.get_file(), mesh.name])
		# Gear: anything carried by a weapon slot (weapons, trails, hitbox shapes).
		for slot: Node in character.find_children("*", "WeaponSlot", true, false):
			for mesh: Node in slot.find_children("*", "MeshInstance3D", true, false):
				check((mesh as MeshInstance3D).material_override != colors.material, "%s must not recolor its gear (%s)" % [path.get_file(), mesh.name])
		check_eq(int(colors.material.get_shader_parameter("palette_mode")), int(colors.palette_mode), "%s shader should use the component's palette mode" % path.get_file())
		character.queue_free()


func test_a_nested_rig_keeps_its_own_palette_and_one_without_wears_its_carriers() -> void:
	var carrier: Character = autofree(MELEE_SCENE.instantiate()) as Character
	var own_rig: Node3D = _nested_rig(carrier, true)
	var plain_rig: Node3D = _nested_rig(carrier, false)
	add_child(carrier)
	await get_tree().process_frame
	var own_colors: CharacterColorComponent = own_rig.get_node("CharacterColorComponent") as CharacterColorComponent
	var own_meshes: Array[MeshInstance3D] = _skinned_meshes(own_rig)
	check(not own_meshes.is_empty(), "setup: the nested rig should have body meshes")
	for mesh: MeshInstance3D in own_meshes:
		check(mesh.material_override == own_colors.material, "a nested rig with its own palette should keep it (%s)" % mesh.name)
		check(not carrier.color_component.get_body_meshes().has(mesh), "the carrier must not count a nested rig with its own palette as its body (%s)" % mesh.name)
	for mesh: MeshInstance3D in _skinned_meshes(plain_rig):
		check(mesh.material_override == carrier.color_component.material, "a nested rig without a palette should wear its carrier's (%s)" % mesh.name)


func test_only_slots_with_a_gradient_are_recolored() -> void:
	var colors: CharacterColorComponent = (spawn(MELEE_SCENE) as Character).color_component
	await get_tree().process_frame
	check_eq(_mask(colors), _expected_mask(colors), "the shader mask should match the assigned slots")
	colors.set_gradient(0, null)
	check_eq(_mask(colors) & 1, 0, "clearing a slot should stop recoloring it")
	colors.set_slot_color(0, TEST_SLOT_COLOR)
	check_eq(_mask(colors) & 1, 1, "setting a slot color should recolor that slot")
	check_eq(_mask(colors), _expected_mask(colors), "only that slot should change")


func test_the_global_tint_reaches_the_shader() -> void:
	var colors: CharacterColorComponent = (spawn(MELEE_SCENE) as Character).color_component
	await get_tree().process_frame
	colors.set_global_tint(TEST_TINT)
	check_eq(colors.material.get_shader_parameter("global_tint"), TEST_TINT, "the tint should reach the shader")


func test_a_component_exposes_one_slot_per_palette_column() -> void:
	var colors: CharacterColorComponent = autofree(CharacterColorComponent.new()) as CharacterColorComponent
	add_child(colors)
	check_eq(colors.gradients.size(), SLOT_COUNT, "a component should expose one gradient slot per palette column")
	check(colors.material != null and colors.material.shader != null, "a component should build its palette material")


## A rig seated in the carrier's mesh mount (like a backpack rider), with its
## own CharacterColorComponent when own_palette.
func _nested_rig(carrier: Character, own_palette: bool) -> Node3D:
	var seat: Node3D = Node3D.new()
	seat.add_child(RIG_SCENE.instantiate())
	if own_palette:
		var colors: CharacterColorComponent = CharacterColorComponent.new()
		colors.name = "CharacterColorComponent"
		seat.add_child(colors)
	carrier.get_node("AnimationAnchor").add_child(seat)
	return seat


## The meshes under root parented to a Skeleton3D (a rig's body meshes).
func _skinned_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		if node.get_parent() is Skeleton3D:
			meshes.append(node as MeshInstance3D)
	return meshes


func _mask(colors: CharacterColorComponent) -> int:
	return int(colors.material.get_shader_parameter("gradient_mask"))


## The mask the assigned (non-null) gradient slots should produce.
func _expected_mask(colors: CharacterColorComponent) -> int:
	var mask: int = 0
	for slot: int in range(colors.gradients.size()):
		if colors.gradients[slot] != null:
			mask |= 1 << slot
	return mask
