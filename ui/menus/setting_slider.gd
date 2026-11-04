class_name SettingSlider
extends HBoxContainer
## "NAME ---o--- 80%" : a labelled slider for the settings menu.

signal value_changed(value: float)

@export var label_text := "Setting"
@export var min_value := 0.0
@export var max_value := 1.0
@export var step := 0.01
## false: show the value times display_scale (one decimal) instead of a percentage.
@export var as_percent := true
@export var display_scale := 1.0

@onready var name_label: Label = %NameLabel
@onready var slider: HSlider = %Slider
@onready var value_label: Label = %ValueLabel


func _ready() -> void:
	name_label.text = label_text.to_upper()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value_changed.connect(_on_changed)
	_update_text()


func set_value_silent(v: float) -> void:
	slider.set_value_no_signal(v)
	_update_text()


func get_value() -> float:
	return slider.value


func _on_changed(v: float) -> void:
	_update_text()
	value_changed.emit(v)


func _update_text() -> void:
	if as_percent:
		value_label.text = "%d%%" % roundi(slider.value / maxf(slider.max_value, 0.0001) * 100.0)
	else:
		value_label.text = "%.1f" % (slider.value * display_scale)
