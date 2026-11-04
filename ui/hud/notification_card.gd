class_name NotificationCard
extends PanelContainer
## One notification: a coloured bar, a title, an optional detail line and an optional
## big number ("-2"). It fades in, stays for a moment and removes itself.

@onready var accent: ColorRect = %AccentBar
@onready var title_label: Label = %TitleLabel
@onready var detail_label: Label = %DetailLabel
@onready var delta_label: Label = %DeltaLabel

var _tween: Tween


## delta: text for the big number, "" hides it. critical cards get a glowing frame.
func setup(title: String, detail: String, delta: String, colour: Color,
		duration: float, critical: bool) -> void:
	title_label.text = title
	detail_label.text = detail
	detail_label.visible = detail != ""
	delta_label.text = delta
	delta_label.visible = delta != ""
	accent.color = colour
	title_label.add_theme_color_override("font_color", colour if critical else UIStyle.TEXT)
	delta_label.add_theme_color_override("font_color", colour)
	if critical:
		theme_type_variation = &"DangerPanel" if colour == UIStyle.RED else &"AmberPanel"

	modulate.a = 0.0
	accent.modulate = Color(2.0, 2.0, 2.0)
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, UIStyle.DUR_FAST)
	_tween.parallel().tween_property(accent, "modulate", Color.WHITE, UIStyle.DUR_SLOW)
	_tween.tween_interval(duration)
	_tween.tween_property(self, "modulate:a", 0.0, UIStyle.DUR_NORMAL)
	_tween.tween_callback(queue_free)


## Remove immediately (used when too many cards are on screen).
func dismiss() -> void:
	if _tween:
		_tween.kill()
	queue_free()
