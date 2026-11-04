class_name SettingsMenu
extends Control
## Player, audio and graphics settings. Changes apply at once and are saved when the
## menu is closed. All values live in GameSettings.

signal back_requested

@onready var player_tab: Button = %PlayerTab
@onready var audio_tab: Button = %AudioTab
@onready var graphics_tab: Button = %GraphicsTab
@onready var player_page: Control = %PlayerPage
@onready var audio_page: Control = %AudioPage
@onready var graphics_page: Control = %GraphicsPage
@onready var name_edit: LineEdit = %NameEdit
@onready var sensitivity_slider: SettingSlider = %SensitivitySlider
@onready var invert_button: Button = %InvertButton
@onready var master_slider: SettingSlider = %MasterSlider
@onready var music_slider: SettingSlider = %MusicSlider
@onready var sfx_slider: SettingSlider = %SfxSlider
@onready var window_option: OptionButton = %WindowOption
@onready var vsync_button: Button = %VsyncButton
@onready var msaa_option: OptionButton = %MsaaOption
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton

var _pages: Array[Control] = []


func _ready() -> void:
	_pages = [player_page, audio_page, graphics_page]
	var group := ButtonGroup.new()
	var tabs: Array[Button] = [player_tab, audio_tab, graphics_tab]
	for i in tabs.size():
		tabs[i].toggle_mode = true
		tabs[i].button_group = group
		tabs[i].pressed.connect(_show_page.bind(i))

	for text in ["WINDOWED", "FULLSCREEN", "EXCLUSIVE FULLSCREEN"]:
		window_option.add_item(text)
	for text in ["OFF", "2X", "4X", "8X"]:
		msaa_option.add_item(text)

	name_edit.text_changed.connect(func(t: String) -> void: GameSettings.set_value("player", "name", t.strip_edges()))
	sensitivity_slider.value_changed.connect(func(v: float) -> void: GameSettings.set_value("player", "mouse_sensitivity", v))
	invert_button.toggled.connect(func(on: bool) -> void:
		_update_toggle(invert_button)
		GameSettings.set_value("player", "invert_y", on))
	master_slider.value_changed.connect(_on_audio.bind("master"))
	music_slider.value_changed.connect(_on_audio.bind("music"))
	sfx_slider.value_changed.connect(_on_audio.bind("sfx"))
	window_option.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("graphics", "window_mode", i)
		GameSettings.apply_graphics())
	vsync_button.toggled.connect(func(on: bool) -> void:
		_update_toggle(vsync_button)
		GameSettings.set_value("graphics", "vsync", on)
		GameSettings.apply_graphics())
	msaa_option.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("graphics", "msaa", i)
		GameSettings.apply_graphics())
	reset_button.pressed.connect(_on_reset)
	back_button.pressed.connect(back_requested.emit)
	visibility_changed.connect(_on_visibility_changed)


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	if visible:
		player_tab.button_pressed = true
		_show_page(0)
		_load_values()
	else:
		GameSettings.save()


func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = i == index


func _load_values() -> void:
	name_edit.text = GameSettings.get_value("player", "name")
	sensitivity_slider.set_value_silent(GameSettings.get_value("player", "mouse_sensitivity"))
	invert_button.set_pressed_no_signal(GameSettings.get_value("player", "invert_y"))
	master_slider.set_value_silent(GameSettings.get_value("audio", "master"))
	music_slider.set_value_silent(GameSettings.get_value("audio", "music"))
	sfx_slider.set_value_silent(GameSettings.get_value("audio", "sfx"))
	window_option.select(int(GameSettings.get_value("graphics", "window_mode")))
	vsync_button.set_pressed_no_signal(GameSettings.get_value("graphics", "vsync"))
	msaa_option.select(int(GameSettings.get_value("graphics", "msaa")))
	_update_toggle(invert_button)
	_update_toggle(vsync_button)


func _update_toggle(button: Button) -> void:
	button.text = "ON" if button.button_pressed else "OFF"


func _on_audio(value: float, key: String) -> void:
	GameSettings.set_value("audio", key, value)
	GameSettings.apply_audio()


func _on_reset() -> void:
	GameSettings.reset()
	GameSettings.apply_all()
	_load_values()
