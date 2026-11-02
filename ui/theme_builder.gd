@tool
extends EditorScript
## Run once to save the theme as a resource:
## open this file in the Script editor, then File > Run (Ctrl+Shift+X).
## Run it again whenever you change ui_style.gd.

const OUT_PATH := "res://ui/theme/game_theme.tres"


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var theme := UIStyle.build_theme()
	var err := ResourceSaver.save(theme, OUT_PATH)
	if err == OK:
		print("Theme saved to ", OUT_PATH)
	else:
		push_error("Could not save theme (error %d)" % err)
