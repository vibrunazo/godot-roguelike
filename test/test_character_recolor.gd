## Character palette recoloring (CharacterColorComponent):
## - every character (player and each enemy type) recolors all of its body
##   meshes with its own palette material and never its weapons or VFX, and
##   the shader uses the component's palette mode,
## - only slots with an assigned gradient are recolored; setting and clearing
##   a slot switches exactly that slot,
## - the global tint reaches the shader,
## - a component always exposes one gradient slot per palette column.
## Colors, gradients and mesh counts are the artists' choice and are not
## asserted.
extends "res://test/lib/test_suite.gd"

const CHARACTER_SCENES: Array[String] = [
	"res://Player/player.tscn",
	"res://Enemy/melee_enemy.tscn",
	"res://Enemy/ranged_enemy.tscn",
	"res://Enemy/enemy_brute.tscn",
	"res://Enemy/firebomber_enemy.tscn",
	"res://Enemy/enemy_thunder_mage.tscn",
]
const MELEE_SCENE: PackedScene = preload("res://Enemy/melee_enemy.tscn")
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


func _mask(colors: CharacterColorComponent) -> int:
	return int(colors.material.get_shader_parameter("gradient_mask"))


## The mask the assigned (non-null) gradient slots should produce.
func _expected_mask(colors: CharacterColorComponent) -> int:
	var mask: int = 0
	for slot: int in range(colors.gradients.size()):
		if colors.gradients[slot] != null:
			mask |= 1 << slot
	return mask
