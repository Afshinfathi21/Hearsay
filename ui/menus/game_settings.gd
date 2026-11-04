class_name GameSettings
extends RefCounted
## Saves the player's settings to user://settings.cfg and applies them.
## Use it anywhere:  GameSettings.get_value("player", "mouse_sensitivity")
## Call GameSettings.apply_all() once when the game starts (MenuRoot does this for you).
##
## Audio uses the buses "Master", "Music" and "SFX" (missing buses are skipped).

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"player": {"name": "Player", "mouse_sensitivity": 0.002, "invert_y": false},
	"audio": {"master": 1.0, "music": 0.8, "sfx": 1.0},
	"graphics": {"window_mode": 0, "vsync": true, "msaa": 0},   # window_mode: 0 windowed, 1 fullscreen, 2 exclusive
}

static var _config := ConfigFile.new()
static var _loaded := false


static func _ensure_loaded() -> void:
	if not _loaded:
		_config.load(PATH)     # a missing file is fine: defaults are used
		_loaded = true


static func get_value(section: String, key: String) -> Variant:
	_ensure_loaded()
	return _config.get_value(section, key, DEFAULTS[section][key])


static func set_value(section: String, key: String, value: Variant) -> void:
	_ensure_loaded()
	_config.set_value(section, key, value)


static func save() -> void:
	_ensure_loaded()
	_config.save(PATH)


static func reset() -> void:
	_ensure_loaded()
	_config.clear()
	save()


static func apply_all() -> void:
	apply_audio()
	apply_graphics()


static func apply_audio() -> void:
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"]]:
		var bus := AudioServer.get_bus_index(pair[0])
		if bus == -1:
			continue
		var volume: float = get_value("audio", pair[1])
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
		AudioServer.set_bus_mute(bus, volume <= 0.001)


static func apply_graphics() -> void:
	match int(get_value("graphics", "window_mode")):
		1: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var vsync: bool = get_value("graphics", "vsync")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.msaa_3d = int(get_value("graphics", "msaa")) as Viewport.MSAA
