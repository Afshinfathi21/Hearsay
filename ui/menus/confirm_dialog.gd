class_name ConfirmDialog
extends Control
## A small "are you sure?" box. Cancel is focused first, so pressing Enter by accident
## cancels. Esc cancels too.

signal confirmed
signal cancelled

@onready var panel: PanelContainer = %Panel
@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %MessageLabel
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton

var is_open := false


func _ready() -> void:
	visible = false
	cancel_button.pressed.connect(_cancel)
	confirm_button.pressed.connect(_confirm)


## danger: red frame and red confirm button, for things that cannot be undone.
func ask(title: String, message: String, confirm_text := "CONFIRM", danger := false) -> void:
	title_label.text = title.to_upper()
	message_label.text = message.to_upper()
	confirm_button.text = confirm_text
	panel.theme_type_variation = &"DangerPanel" if danger else &"AmberPanel"
	confirm_button.theme_type_variation = &"ButtonDanger" if danger else &"ButtonPrimary"
	is_open = true
	visible = true
	cancel_button.grab_focus()


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	_close()
	confirmed.emit()


func _cancel() -> void:
	_close()
	cancelled.emit()


func _close() -> void:
	is_open = false
	visible = false
