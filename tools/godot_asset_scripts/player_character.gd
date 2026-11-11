class_name PlayerCharacter
extends Node3D
## Attach to the root node of the imported Characters/character_base.glb.
## Picks an outfit variant and per-player colours, and can hide the body from the
## local player's own first-person camera (other players still see it, and it
## still casts a shadow).

enum Top { JACKET, HOODIE }
enum Headwear { HAIR, BEANIE }

## One palette per player slot (index 0-3). Values come from the Phase 1 style guide's
## restrained palette; edit freely.
const PALETTES := [
	{"top": Color("A8781F"), "pants": Color("343A40"), "accent": Color("C9C6BD")},  # amber
	{"top": Color("3E6A8A"), "pants": Color("2B2F33"), "accent": Color("B7791F")},  # steel blue
	{"top": Color("5C6B3A"), "pants": Color("3A3F44"), "accent": Color("C9C6BD")},  # olive
	{"top": Color("C9C6BD"), "pants": Color("4A4E52"), "accent": Color("8C2B2B")},  # bone
]

## Visual layer 2. The local player's Camera3D drops this bit from its cull_mask.
const BODY_LAYER := 1 << 1

@export_range(0, 3) var palette_index := 0
@export var top := Top.JACKET
@export var headwear := Headwear.HAIR

const VARIANT_NODES := ["Char_Top_Jacket", "Char_Top_Hoodie", "Char_Hair", "Char_Beanie"]


func _ready() -> void:
	configure(palette_index, top, headwear)


func configure(palette: int, top_variant: Top, head_variant: Headwear) -> void:
	# 1) show only the chosen variants (the GLB contains all of them)
	var show_names := [
		"Char_Top_Jacket" if top_variant == Top.JACKET else "Char_Top_Hoodie",
		"Char_Hair" if head_variant == Headwear.HAIR else "Char_Beanie",
	]
	for n in VARIANT_NODES:
		_mesh(n).visible = n in show_names
	# 2) recolour. We copy the imported material so players don't share one resource.
	var p: Dictionary = PALETTES[palette % PALETTES.size()]
	_tint("Char_Top_Jacket", p["top"])
	_tint("Char_Top_Hoodie", p["top"])
	_tint("Char_Trousers", p["pants"])
	_tint("Char_Beanie", p["accent"])


## Call for the player who owns `camera`: hides this body from that camera only.
func set_local_player(camera: Camera3D) -> void:
	for m in find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).layers = BODY_LAYER
	camera.cull_mask &= ~BODY_LAYER


func _mesh(node_name: String) -> MeshInstance3D:
	return find_child(node_name, true, false) as MeshInstance3D


func _tint(node_name: String, colour: Color) -> void:
	var m := _mesh(node_name)
	# get_active_material() = override if one is set, else the mesh's own (flat or library) material
	var mat := (m.get_active_material(0) as BaseMaterial3D).duplicate() as BaseMaterial3D
	mat.albedo_color = colour
	m.material_override = mat
