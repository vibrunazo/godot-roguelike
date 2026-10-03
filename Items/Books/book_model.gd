## A book built from primitive boxes (front and back covers, pages, spine)
## whose whole look is exports, so each cover style is only a scene: see
## book.tscn (the base) and book_dummies.tscn. The book lies flat, the front
## cover on top (+Y), the spine along -X, the top edge toward -Z. Style
## scenes decorate the cover by adding nodes under cover_anchor (bands,
## labels, art); the anchor sits on the front cover's surface, so a flat
## PlaneMesh child lies on it and a Label3D child needs a -90° X turn.
## show_item() writes the item's title on title_label (shrinking its font
## until the longest word fits the label's width, so no word breaks) and
## optional art on art_sprite. Tool-enabled: changes preview in the editor.
@tool
class_name BookModel
extends ItemDisplay

@export_group("Shape")
## Width (X), thickness (Y) and height (Z) of the closed book, in meters.
@export var size: Vector3 = Vector3(0.66, 0.1, 0.86):
	set(value):
		size = value
		_rebuild()
## Thickness of each cover board, in meters.
@export var cover_thickness: float = 0.012:
	set(value):
		cover_thickness = value
		_rebuild()
## How far the pages sit inside the covers on the three open edges, in meters.
@export var page_inset: float = 0.015:
	set(value):
		page_inset = value
		_rebuild()

@export_group("Colors")
## Color of both cover boards.
@export var cover_color: Color = Color(1.0, 0.82, 0.1):
	set(value):
		cover_color = value
		_rebuild()
## Glow of the covers (0 = none), so the book reads in dark levels.
@export var cover_emission: float = 0.25:
	set(value):
		cover_emission = value
		_rebuild()
## Color of the spine strip.
@export var spine_color: Color = Color(0.05, 0.05, 0.05):
	set(value):
		spine_color = value
		_rebuild()
## Color of the page block.
@export var page_color: Color = Color(0.96, 0.94, 0.86):
	set(value):
		page_color = value
		_rebuild()

@export_group("Cover")
## Node on the front cover's surface that style scenes decorate.
@export var cover_anchor: Node3D:
	set(value):
		cover_anchor = value
		_rebuild()
## Label showing the item's title (the style scene places and styles it).
@export var title_label: Label3D
## Smallest font size the title shrinks to so its longest word fits.
@export var min_title_font_size: int = 30
## Optional sprite showing cover art (e.g. an enemy on an O'Reilly style cover).
@export var art_sprite: Sprite3D
## Cover art shown on art_sprite.
@export var art: Texture2D:
	set(value):
		art = value
		if art_sprite != null:
			art_sprite.texture = art

var _parts: Array[MeshInstance3D] = []
## The title's font size as styled, before any shrinking (-1 until read).
var _styled_font_size: int = -1


func _ready() -> void:
	_rebuild()
	if art_sprite != null:
		art_sprite.texture = art


## Writes item's plain title on the cover.
func show_item(item: ItemResource) -> void:
	if title_label != null and item != null:
		title_label.text = item.get_plain_title()
		_fit_title()


## Shrinks the title's font (from its styled size, down to
## min_title_font_size) until its longest word fits the label's width.
func _fit_title() -> void:
	if _styled_font_size < 0:
		_styled_font_size = title_label.font_size
	var font: Font = title_label.font if title_label.font != null else ThemeDB.fallback_font
	var font_size: int = _styled_font_size
	while font_size > min_title_font_size and _widest_word(font, font_size) + title_label.outline_size * 2.0 > title_label.width:
		font_size -= 1
	title_label.font_size = font_size


## Width in pixels of the title's widest word at font_size.
func _widest_word(font: Font, font_size: int) -> float:
	var widest: float = 0.0
	for word: String in title_label.text.split(" ", false):
		widest = maxf(widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return widest


## Rebuilds the primitive boxes from the shape and color exports.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	for part: MeshInstance3D in _parts:
		part.queue_free()
	_parts.clear()
	var half: Vector3 = size * 0.5
	var covers: StandardMaterial3D = _material(cover_color, cover_emission)
	_add_box(Vector3(size.x, cover_thickness, size.z), Vector3(0.0, half.y - cover_thickness * 0.5, 0.0), covers)
	_add_box(Vector3(size.x, cover_thickness, size.z), Vector3(0.0, -half.y + cover_thickness * 0.5, 0.0), covers)
	var pages: Vector3 = Vector3(size.x - page_inset, size.y - cover_thickness * 2.0, size.z - page_inset * 2.0)
	_add_box(pages, Vector3(page_inset * 0.5, 0.0, 0.0), _material(page_color, 0.0))
	_add_box(Vector3(cover_thickness, size.y, size.z), Vector3(-half.x + cover_thickness * 0.5, 0.0, 0.0), _material(spine_color, 0.0))
	if cover_anchor != null:
		cover_anchor.position = Vector3(0.0, half.y + 0.001, 0.0)


func _add_box(box_size: Vector3, at: Vector3, material: StandardMaterial3D) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box_size
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	add_child(part)
	_parts.append(part)


func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	return material
