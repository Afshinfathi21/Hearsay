class_name MainMenu
extends Control
## The game's main menu. It shows the project's name (Project Settings > Application >
## Config > Name) and the version if one is set; it has no branding of its own.

signal play_requested
signal settings_requested
signal quit_requested

@onready var title_label: Label = %TitleLabel
@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var version_label: Label = %VersionLabel


func _ready() -> void:
	title_label.text = str(ProjectSettings.get_setting("application/config/name", "")).to_upper()
	version_label.text = str(ProjectSettings.get_setting("application/config/version", ""))
	play_button.pressed.connect(play_requested.emit)
	settings_button.pressed.connect(settings_requested.emit)
	quit_button.pressed.connect(quit_requested.emit)
	visibility_changed.connect(func() -> void:
		if visible:
			play_button.grab_focus())
