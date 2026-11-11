extends SceneTree
## Generates every Materials/*.tres from the textures in Materials/Textures.
## Run from the project folder:  godot --headless --path . --script res://build_materials.gd
## (Textures must be imported first: run `godot --headless --import` once.)
## Editing this file and re-running is the way to retune the whole library.

const DIR := "res://assets/common/materials/"
const TEX := "res://assets/common/materials/Textures/"


func _tex(file: String) -> Texture2D:
	var t := load(TEX + file) as Texture2D
	assert(t != null, "missing texture " + file)
	return t


## Textured PBR material using Godot's packed ORM layout (R = AO, G = roughness, B = metallic).
func _orm(mat_name: String, set_name: String, uv_scale := 1.0, normal_scale := 1.0,
		tint := Color.WHITE) -> ORMMaterial3D:
	var m := ORMMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_texture = _tex(set_name + "_albedo.png")
	m.albedo_color = tint
	m.orm_texture = _tex(set_name + "_orm.png")
	# ORMMaterial3D reads roughness (G) and metallic (B) straight from the ORM texture, so there
	# are no roughness/metallic multipliers to set here (Godot doesn't even save them).
	m.ao_enabled = true
	m.normal_enabled = true
	m.normal_texture = _tex(set_name + "_normal.png")
	m.normal_scale = normal_scale
	m.uv1_scale = Vector3(uv_scale, uv_scale, 1.0)
	return m


func _emissive(mat_name: String, colour: Color, energy: float, base := Color(0.07, 0.07, 0.08)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = base
	m.roughness = 0.4
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = energy
	return m


func _save(m: Material) -> void:
	var path := DIR + m.resource_name + ".tres"
	var err := ResourceSaver.save(m, path)
	print("%s  %s  (%s)" % ["saved" if err == OK else "FAILED", path, m.get_class()])


func _init() -> void:
	# --- environment (1 UV = 4 m, so a 1024 px map is 256 px/m at uv_scale 1) -------------
	_save(_orm("M_Concrete_Rough", "concrete_rough"))
	_save(_orm("M_Concrete_Painted", "concrete_painted"))
	_save(_orm("M_Steel_Dark_Brushed", "steel_brushed"))
	_save(_orm("M_Paint_Worn", "paint_worn"))
	_save(_orm("M_Polymer_Rubber", "rubber", 2.0))          # 512 px map: tile every 2 m

	# --- frosted glass: translucent, soft highlights, tiny grain in the normal -----------
	var g := StandardMaterial3D.new()
	g.resource_name = "M_Glass_Frosted"
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color = Color(0.78, 0.82, 0.85, 0.55)
	g.roughness = 0.55
	g.normal_enabled = true
	g.normal_texture = _tex("glass_frosted_normal.png")
	g.uv1_scale = Vector3(8, 8, 1)
	_save(g)

	# --- emissive: monitor glass with scanlines, digits, indicator lights ---------------
	var s := _emissive("M_Emissive_Screen", Color("3D2200"), 1.2, Color(0.02, 0.024, 0.027))
	s.roughness = 0.25
	s.emission_texture = _tex("screen_scanlines_emission.png")
	_save(s)
	_save(_emissive("M_Digit_Amber", Color("FFA21F"), 3.0, Color("1A0E00")))
	_save(_emissive("M_Emissive_Light_Amber", Color("FFA21F"), 3.0, Color("1A0E00")))
	_save(_emissive("M_Emissive_Light_White", Color("E9F2FF"), 3.0, Color("101214")))
	_save(_emissive("M_Emissive_Light_Red", Color("E5201B"), 3.0, Color("1A0505")))

	# --- character cloth: one neutral weave, tinted per player by PlayerCharacter --------
	_save(_orm("M_Char_Cloth_Top", "fabric", 20.0, 1.0, Color("A8781F")))
	_save(_orm("M_Char_Cloth_Pants", "fabric", 20.0, 1.0, Color("343A40")))
	_save(_orm("M_Char_Cloth_Accent", "fabric", 20.0, 1.0, Color("C9C6BD")))
	quit()
