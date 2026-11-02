class_name UIStyle
extends RefCounted
## Single source of truth for the game's UI look (phase 1: style guide).
## Every colour, size and spacing value lives here. Scenes use the Theme built by
## build_theme(); the physical door monitors can read these constants directly.
##
## Colour meaning (keep it strict, it is what makes the UI readable):
##   TEXT (warm white)  = primary information
##   AMBER              = active, available, selected, "this matters"
##   RED                = danger, elimination, critical warning ONLY
##   greys              = structure, secondary information

# --- Surfaces (darkest to lightest) ---
const BLACK        := Color("0b0c0d")
const SURFACE_0    := Color("111214")
const SURFACE_1    := Color("181a1d")
const SURFACE_2    := Color("212428")
const METAL        := Color("3a3f45")   # default thin border
const METAL_LIGHT  := Color("5b626a")   # hover / emphasised border

# --- Text ---
const TEXT          := Color("ebe8e1")
const TEXT_MUTED    := Color("9aa0a6")
const TEXT_DISABLED := Color("5a5f65")

# --- Signal colours ---
const AMBER       := Color("f0a030")
const AMBER_DIM   := Color("8c5c18")
const AMBER_GLOW  := Color(0.94, 0.63, 0.19, 0.28)
const RED         := Color("d6372b")
const RED_DIM     := Color("6b1d18")
const RED_GLOW    := Color(0.84, 0.22, 0.17, 0.30)

# --- Overlays ---
const SCRIM  := Color(0.04, 0.04, 0.05, 0.72)   # dims the world behind menus
const HUD_BG := Color(0.07, 0.07, 0.08, 0.78)   # HUD panels: the world stays visible

# --- Spacing scale (pixels at the 1920x1080 base size) ---
const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32
const SCREEN_MARGIN := 32   # keep HUD away from the screen edge

# --- Shape ---
const BORDER        := 1   # thin lines everywhere
const BORDER_STRONG := 2   # focus / critical states
# Corners are square on purpose: brutalist, geometric.

# --- Type scale ---
const FONT_CAPTION := 12
const FONT_LABEL   := 14
const FONT_BODY    := 16
const FONT_TITLE   := 24
const FONT_DISPLAY := 48
const FONT_HERO    := 96   # big points number / monitor digits

# --- Motion (seconds). Keep animations short and restrained. ---
const DUR_FAST   := 0.12
const DUR_NORMAL := 0.22
const DUR_SLOW   := 0.45

# --- Fonts ---
# Drop font files here to override the system fallbacks (suggested, both OFL:
# Barlow Condensed or Rajdhani for the UI, JetBrains Mono for numbers).
const FONT_UI_FILE   := "res://ui/fonts/ui.ttf"
const FONT_MONO_FILE := "res://ui/fonts/mono.ttf"


static func font_ui() -> Font:
	if ResourceLoader.exists(FONT_UI_FILE):
		return load(FONT_UI_FILE) as Font
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Barlow Condensed", "Rajdhani", "Bahnschrift", "Roboto Condensed",
		"Noto Sans", "sans-serif",
	])
	return f


static func font_mono() -> Font:
	if ResourceLoader.exists(FONT_MONO_FILE):
		return load(FONT_MONO_FILE) as Font
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"JetBrains Mono", "Consolas", "DejaVu Sans Mono", "monospace",
	])
	return f


## A flat, square-cornered box: the building block for every panel and button.
static func box(bg: Color, border: Color = Color(0, 0, 0, 0), border_w: int = 0,
		pad_h: int = 0, pad_v: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	sb.anti_aliasing = false   # keeps 1px lines crisp
	return sb


## Subtle outer glow for amber / red emphasis.
static func glow(sb: StyleBoxFlat, color: Color, size: int = 6) -> StyleBoxFlat:
	sb.shadow_color = color
	sb.shadow_size = size
	sb.shadow_offset = Vector2.ZERO
	return sb


static func _label_variant(t: Theme, variant: StringName, color: Color,
		size: int = FONT_BODY, font: Font = null) -> void:
	t.set_type_variation(variant, &"Label")
	t.set_color("font_color", variant, color)
	t.set_font_size("font_size", variant, size)
	if font:
		t.set_font("font", variant, font)


static func _panel_variant(t: Theme, variant: StringName, sb: StyleBoxFlat) -> void:
	t.set_type_variation(variant, &"PanelContainer")
	t.set_stylebox("panel", variant, sb)


static func _button_styles(t: Theme, type_name: StringName, normal_border: Color,
		hover_border: Color, accent: Color, glow_color: Color) -> void:
	var normal := box(SURFACE_1, normal_border, BORDER, SP_4, SP_2)
	var hover := box(SURFACE_2, hover_border, BORDER, SP_4, SP_2)
	var pressed := box(Color(accent, 0.18), accent, BORDER, SP_4, SP_2)
	var disabled := box(SURFACE_0, Color(METAL, 0.5), BORDER, SP_4, SP_2)
	var focus := box(Color(0, 0, 0, 0), accent, BORDER_STRONG, SP_4, SP_2)
	focus.draw_center = false
	glow(focus, glow_color, 6)
	t.set_stylebox("normal", type_name, normal)
	t.set_stylebox("hover", type_name, hover)
	t.set_stylebox("pressed", type_name, pressed)
	t.set_stylebox("disabled", type_name, disabled)
	t.set_stylebox("focus", type_name, focus)
	t.set_color("font_color", type_name, TEXT)
	t.set_color("font_hover_color", type_name, TEXT)
	t.set_color("font_pressed_color", type_name, accent)
	t.set_color("font_focus_color", type_name, TEXT)
	t.set_color("font_disabled_color", type_name, TEXT_DISABLED)
	t.set_font_size("font_size", type_name, FONT_BODY)


static func build_theme() -> Theme:
	var t := Theme.new()
	var mono := font_mono()
	t.default_font = font_ui()
	t.default_font_size = FONT_BODY

	# --- Container spacing ---
	t.set_constant("separation", "VBoxContainer", SP_2)
	t.set_constant("separation", "HBoxContainer", SP_2)
	t.set_constant("h_separation", "GridContainer", SP_2)
	t.set_constant("v_separation", "GridContainer", SP_2)
	t.set_constant("h_separation", "HFlowContainer", SP_2)
	t.set_constant("v_separation", "HFlowContainer", SP_2)

	# --- Labels ---
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", FONT_BODY)
	_label_variant(t, &"LabelMuted", TEXT_MUTED)
	_label_variant(t, &"LabelCaption", TEXT_MUTED, FONT_CAPTION)
	_label_variant(t, &"LabelAmber", AMBER)
	_label_variant(t, &"LabelDanger", RED)
	_label_variant(t, &"LabelTitle", TEXT, FONT_TITLE)
	_label_variant(t, &"LabelDisplay", TEXT, FONT_DISPLAY)
	_label_variant(t, &"LabelMono", TEXT, FONT_BODY, mono)
	_label_variant(t, &"LabelNumber", TEXT, FONT_DISPLAY, mono)   # points, round number

	# --- Buttons: default, primary (amber), danger (red) ---
	_button_styles(t, &"Button", METAL, METAL_LIGHT, AMBER, AMBER_GLOW)
	t.set_type_variation(&"ButtonPrimary", &"Button")
	_button_styles(t, &"ButtonPrimary", AMBER_DIM, AMBER, AMBER, AMBER_GLOW)
	t.set_color("font_color", &"ButtonPrimary", AMBER)
	t.set_color("font_focus_color", &"ButtonPrimary", AMBER)
	t.set_type_variation(&"ButtonDanger", &"Button")
	_button_styles(t, &"ButtonDanger", RED_DIM, RED, RED, RED_GLOW)
	t.set_color("font_color", &"ButtonDanger", RED)
	t.set_color("font_focus_color", &"ButtonDanger", RED)

	# --- Panels ---
	var panel := box(SURFACE_1, METAL, BORDER, SP_3, SP_3)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", box(SURFACE_1, METAL, BORDER))
	_panel_variant(t, &"HUDPanel", box(HUD_BG, Color(METAL, 0.8), BORDER, SP_3, SP_2))
	_panel_variant(t, &"AmberPanel", glow(box(HUD_BG, AMBER, BORDER, SP_3, SP_2), AMBER_GLOW, 4))
	_panel_variant(t, &"DangerPanel", glow(box(HUD_BG, RED, BORDER, SP_3, SP_2), RED_GLOW, 6))

	# --- Progress bars (timers, loading) ---
	var bar_bg := box(SURFACE_0, METAL, BORDER)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", box(AMBER))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_type_variation(&"ProgressBarDanger", &"ProgressBar")
	t.set_stylebox("background", &"ProgressBarDanger", bar_bg)
	t.set_stylebox("fill", &"ProgressBarDanger", box(RED))

	# --- Text input ---
	t.set_stylebox("normal", "LineEdit", box(SURFACE_0, METAL, BORDER, SP_3, SP_2))
	t.set_stylebox("focus", "LineEdit", box(SURFACE_0, AMBER, BORDER, SP_3, SP_2))
	t.set_stylebox("read_only", "LineEdit", box(SURFACE_0, Color(METAL, 0.5), BORDER, SP_3, SP_2))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DISABLED)
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("selection_color", "LineEdit", Color(AMBER, 0.35))

	# --- Separators ---
	var line_h := StyleBoxLine.new()
	line_h.color = METAL
	line_h.thickness = BORDER
	t.set_stylebox("separator", "HSeparator", line_h)
	t.set_constant("separation", "HSeparator", SP_3)
	var line_v := StyleBoxLine.new()
	line_v.color = METAL
	line_v.thickness = BORDER
	line_v.vertical = true
	t.set_stylebox("separator", "VSeparator", line_v)
	t.set_constant("separation", "VSeparator", SP_3)

	# --- Scroll bars ---
	for sb_type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb_type, box(SURFACE_0))
		t.set_stylebox("scroll_focus", sb_type, box(SURFACE_0))
		t.set_stylebox("grabber", sb_type, box(METAL))
		t.set_stylebox("grabber_highlight", sb_type, box(METAL_LIGHT))
		t.set_stylebox("grabber_pressed", sb_type, box(AMBER))

	# --- Tooltips ---
	t.set_stylebox("panel", "TooltipPanel", box(SURFACE_2, METAL_LIGHT, BORDER, SP_3, SP_2))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", FONT_LABEL)

	return t
