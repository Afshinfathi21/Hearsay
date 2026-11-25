extends SceneTree
## The character mesh faces +Z. While walking forward its face must lead the movement,
## in every camera mode, even though this level rotates the Player node 90 degrees.
## Run with: godot --headless --path . --script res://tests/player_facing_test.gd

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var level := (load("res://Levels/Balance Scale/auction_chamber.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var player := level.get_node("Player")
	for i in 30:
		await physics_frame
	for mode in ["first person", "third person, face walk direction", "third person, face camera"]:
		player.global_position = Vector3(4.5, 0.95, 4.0)
		player.velocity = Vector3.ZERO
		player._first_person = mode == "first person"
		player.face_camera_direction = mode == "third person, face camera"
		for i in 10:
			await physics_frame
		Input.action_press("move_up")
		for i in 40:
			await physics_frame
		var move := Vector3(player.velocity.x, 0.0, player.velocity.z).normalized()
		var face: Vector3 = player.model.global_transform.basis.z
		_check(move.length() > 0.5 and move.dot(face) > 0.98, "walking forward, face leads the movement (%s)" % mode)
		Input.action_release("move_up")
		for i in 10:
			await physics_frame
	level.queue_free()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)
