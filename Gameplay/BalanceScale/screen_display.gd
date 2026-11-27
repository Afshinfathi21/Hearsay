class_name ScreenDisplay
extends Node
## Turns a quad in the level (a table bid screen, the wall display) into a small screen that
## shows up to three lines of text. It renders a SubViewport and uses it as the quad's texture.

var viewport: SubViewport
var _top: Label
var _big: Label
var _bottom: Label
var _bg: ColorRect


## `quarter_turns`: rotate the content by 90 degrees steps (clockwise, negative = anticlockwise),
## for quads whose UVs run sideways. `size` is the texture size (the quad's UV rectangle);
## the text is laid out in a rotated rectangle so it reads upright on the quad.
func attach(mesh: MeshInstance3D, size: Vector2i, quarter_turns: int = 0) -> void:
	viewport = SubViewport.new()
	viewport.size = size
	viewport.disable_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.03, 0.04)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(_bg)

	# The content is laid out as a normal landscape page and then turned.
	var turned := absi(quarter_turns) % 2 == 1
	var content_size := Vector2(size.y, size.x) if turned else Vector2(size)
	var content := Control.new()
	content.size = content_size
	content.pivot_offset = content_size * 0.5
	content.rotation = quarter_turns * PI * 0.5
	content.position = (Vector2(size) - content_size) * 0.5
	viewport.add_child(content)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(box)
	var h := content_size.y
	_top = _label(box, int(h * 0.16))
	_big = _label(box, int(h * 0.46))
	_bottom = _label(box, int(h * 0.16))

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mesh.material_override = mat


func show_text(top: String, big: String, bottom: String, color: Color = Color(0.9, 0.95, 1.0), background: Color = Color(0.02, 0.03, 0.04)) -> void:
	_top.text = top
	_big.text = big
	_bottom.text = bottom
	_big.add_theme_color_override("font_color", color)
	_top.add_theme_color_override("font_color", color.darkened(0.25))
	_bottom.add_theme_color_override("font_color", color.darkened(0.25))
	_bg.color = background


## All text currently on the screen (used by tests to prove nothing secret is shown).
func get_text() -> String:
	return "%s %s %s" % [_top.text, _big.text, _bottom.text]


func _label(parent: Control, font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(l)
	return l
