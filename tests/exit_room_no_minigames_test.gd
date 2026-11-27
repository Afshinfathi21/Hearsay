extends SceneTree
## The Exit Room level no longer offers any mini-game (the optional "Don't Blink" rooms).
## Run with: godot --headless --path . --script res://tests/exit_room_no_minigames_test.gd

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var level := (load("res://Levels/The Exit Room/BaseLevel.tscn") as PackedScene).instantiate()
	root.add_child(level)
	current_scene = level
	for i in 30:
		await physics_frame
	var generator: Node = null
	for n in level.find_children("*", "", true, false):
		if "minigame_fraction" in n:
			generator = n
	_check(generator != null, "the level has its building generator")
	if generator == null:
		_finish()
		return
	_check(generator.minigame_fraction == 0.0, "the level asks for no mini-game rooms")
	var rooms_with_minigames := 0
	for rd in generator.room_list:
		if rd.minigame:
			rooms_with_minigames += 1
	_check(generator.room_list.size() > 3, "the level still generates its rooms (%d)" % generator.room_list.size())
	_check(rooms_with_minigames == 0, "no generated room has a mini-game")
	_check(level.find_children("DontBlink_*", "", true, false).is_empty(), "no mini-game node exists in the level")
	_finish()


func _finish() -> void:
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)
