class_name PauseMenu
extends Control
## In-match pause menu (Esc). It does NOT pause the game (this is multiplayer); it only
## frees the mouse and, through GameHUD's modal signals, stops the player's input.

signal opened
signal closed
signal leave_match_requested
signal quit_requested

@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var leave_button: Button = %LeaveButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: SettingsMenu = %SettingsMenu
@onready var confirm_dialog: ConfirmDialog = %ConfirmDialog

var is_open := false

var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _pending := ""


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(close)
	settings_button.pressed.connect(func() -> void: settings_menu.visible = true)
	settings_menu.back_requested.connect(func() -> void:
		settings_menu.visible = false
		resume_button.grab_focus())
	leave_button.pressed.connect(func() -> void:
		_pending = "leave"
		confirm_dialog.ask("Leave the match?", "You will leave the match and cannot rejoin it.", "LEAVE", true))
	quit_button.pressed.connect(func() -> void:
		_pending = "quit"
		confirm_dialog.ask("Quit to desktop?", "The game will close.", "QUIT", true))
	confirm_dialog.confirmed.connect(_on_confirmed)


# Settings and the confirm box handle their own Esc first (in _input),
# so this only sees Esc when nothing on top of the menu used it.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if is_open:
		return
	is_open = true
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	resume_button.grab_focus()
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	closed.emit()


func _on_confirmed() -> void:
	if _pending == "leave":
		close()
		leave_match_requested.emit()
	elif _pending == "quit":
		quit_requested.emit()
