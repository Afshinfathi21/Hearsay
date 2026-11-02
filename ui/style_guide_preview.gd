extends Control
## Visual check of the style guide. Make a scene with a single Control node as the
## root, attach this script, and run the scene. Nothing here is used by the game.


func _ready() -> void:
	theme = UIStyle.build_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UIStyle.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UIStyle.SCREEN_MARGIN)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UIStyle.SP_5)
	scroll.add_child(col)

	_build_palette(col)
	_build_typography(col)
	_build_buttons(col)
	_build_panels(col)
	_build_progress(col)


func _label(text: String, variant: StringName = &"") -> Label:
	var l := Label.new()
	l.text = text
	if variant != &"":
		l.theme_type_variation = variant
	return l


func _section(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	parent.add_child(box)
	box.add_child(_label(title.to_upper(), &"LabelAmber"))
	box.add_child(HSeparator.new())
	return box


func _swatch(label_text: String, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIStyle.SP_1)
	var rect := ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = Vector2(112, 56)
	box.add_child(rect)
	box.add_child(_label(label_text, &"LabelCaption"))
	return box


func _build_palette(parent: Control) -> void:
	var s := _section(parent, "Colour")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UIStyle.SP_4)
	flow.add_theme_constant_override("v_separation", UIStyle.SP_4)
	s.add_child(flow)
	var colours := {
		"BLACK": UIStyle.BLACK, "SURFACE_0": UIStyle.SURFACE_0,
		"SURFACE_1": UIStyle.SURFACE_1, "SURFACE_2": UIStyle.SURFACE_2,
		"METAL": UIStyle.METAL, "METAL_LIGHT": UIStyle.METAL_LIGHT,
		"TEXT": UIStyle.TEXT, "TEXT_MUTED": UIStyle.TEXT_MUTED,
		"AMBER": UIStyle.AMBER, "AMBER_DIM": UIStyle.AMBER_DIM,
		"RED": UIStyle.RED, "RED_DIM": UIStyle.RED_DIM,
	}
	for key in colours:
		flow.add_child(_swatch(key, colours[key]))


func _build_typography(parent: Control) -> void:
	var s := _section(parent, "Typography")
	s.add_child(_label("124", &"LabelNumber"))
	s.add_child(_label("Display  48", &"LabelDisplay"))
	s.add_child(_label("Title  24", &"LabelTitle"))
	s.add_child(_label("Body 16: the quick brown fox jumps over the lazy dog"))
	s.add_child(_label("Muted 16: secondary information", &"LabelMuted"))
	s.add_child(_label("Caption 12: ROOM 03  /  ROUND 02", &"LabelCaption"))
	s.add_child(_label("Mono 16: 02 / 02", &"LabelMono"))
	s.add_child(_label("Amber: available / selected", &"LabelAmber"))
	s.add_child(_label("Red: critical / eliminated", &"LabelDanger"))


func _build_buttons(parent: Control) -> void:
	var s := _section(parent, "Buttons")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SP_4)
	s.add_child(row)
	var b1 := Button.new()
	b1.text = "Default"
	row.add_child(b1)
	var b2 := Button.new()
	b2.text = "Confirm"
	b2.theme_type_variation = &"ButtonPrimary"
	row.add_child(b2)
	var b3 := Button.new()
	b3.text = "Abandon"
	b3.theme_type_variation = &"ButtonDanger"
	row.add_child(b3)
	var b4 := Button.new()
	b4.text = "Disabled"
	b4.disabled = true
	row.add_child(b4)


func _panel(variant: StringName, text: String, text_variant: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variant
	p.add_child(_label(text, text_variant))
	return p


func _build_panels(parent: Control) -> void:
	var s := _section(parent, "Panels")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIStyle.SP_4)
	s.add_child(row)
	row.add_child(_panel(&"PanelContainer", "Standard panel"))
	row.add_child(_panel(&"HUDPanel", "HUD panel (see-through)"))
	row.add_child(_panel(&"AmberPanel", "Active / selected", &"LabelAmber"))
	row.add_child(_panel(&"DangerPanel", "Critical warning", &"LabelDanger"))


func _build_progress(parent: Control) -> void:
	var s := _section(parent, "Progress")
	var bar := ProgressBar.new()
	bar.value = 70
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	s.add_child(bar)
	var low := ProgressBar.new()
	low.theme_type_variation = &"ProgressBarDanger"
	low.value = 18
	low.show_percentage = false
	low.custom_minimum_size = Vector2(0, 8)
	s.add_child(low)
