extends SceneTree
## Scene-level smoke tests for the acid pot.
## Run with: godot --headless --path . --script res://tests/acid_pot_scene_test.gd

const SCENE_PATH := "res://Levels/Balance Scale/auction_chamber.tscn"

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var chamber_scene := load(SCENE_PATH) as PackedScene
	_check(chamber_scene != null, "auction chamber scene loads")
	if chamber_scene == null:
		_finish()
		return

	var chamber := chamber_scene.instantiate()
	root.add_child(chamber)
	await process_frame

	var pot := chamber.get_node_or_null("AcidPots/Pot_East") as AcidPot
	_check(pot != null, "the east pot is assembled")
	if pot == null:
		_finish()
		return

	var latch_rest := pot.latch.position.x
	pot.fill = 0.5
	_check(is_equal_approx(pot.fill, 0.5) and is_equal_approx(pot.liquid.scale.y, 0.5), "manual fill updates the liquid mesh")

	var overflow_seen := [false]
	pot.overflowed.connect(func() -> void: overflow_seen[0] = true)
	pot.pour_to(1.1, 0.05)
	for i in 300:  # wait for the animation (frame rate varies), at most ~5 s
		if is_equal_approx(pot.fill, 1.1):
			break
		await process_frame
	_check(is_equal_approx(pot.fill, 1.1), "pour animation can reach the overflow range")
	_check(overflow_seen[0] and pot._fx_overflow.emitting, "overflow triggers the signal and overflow particles")

	var released_seen := [false]
	pot.released.connect(func() -> void: released_seen[0] = true)
	pot.release()
	await create_timer(1.1).timeout
	_check(released_seen[0], "release animation completes and emits its signal")
	_check(is_equal_approx(pot.fill, 0.0), "release drains the pot")

	pot.reset()
	pot.release()
	await create_timer(1.1).timeout
	pot.release()
	await create_timer(1.1).timeout
	_check(is_equal_approx(pot.latch.position.x, latch_rest + 0.18), "repeated release does not drift the latch")
	pot.reset()
	_check(is_equal_approx(pot.latch.position.x, latch_rest), "reset restores the latch")
	_check(is_equal_approx(pot.fill, 0.0) and is_equal_approx(pot.hatch.rotation.z, 0.0), "reset restores the pot")
	# Chairs face local -X, pipes run local +X: seats must face the table, pipes must run toward the wall.
	for side in ["East", "South", "West", "North"]:
		var seat := chamber.get_node("Seats/Seat_" + side) as Node3D
		var facing := -seat.global_transform.basis.x.normalized()
		_check(facing.dot((-seat.global_position).normalized()) > 0.99, "seat %s faces the table" % side)
		var pot_node := chamber.get_node("AcidPots/Pot_" + side) as Node3D
		var outward := Vector3(pot_node.global_position.x, 0.0, pot_node.global_position.z).normalized()
		_check(pot_node.global_transform.basis.x.normalized().dot(outward) > 0.99, "pot %s pipes run toward the wall" % side)
		var spawn := chamber.get_node("PlayerSpawns/Spawn_" + side) as Node3D
		var forward := -spawn.global_transform.basis.z
		_check(forward.dot((-spawn.global_position * Vector3(1, 0, 1)).normalized()) > 0.99, "spawn %s faces the table" % side)
	# Ambient light must not come from a sky the scene does not have (that gives pitch-black shadows).
	var env := (chamber.get_node("WorldEnvironment") as WorldEnvironment).environment
	_check(env.ambient_light_source != Environment.AMBIENT_SOURCE_SKY or env.background_mode == Environment.BG_SKY, "room has real ambient light")
	_check(chamber.get_node("Lighting").find_children("*", "SpotLight3D", false, false).size() >= 4, "table is lit by spot lights")
	chamber.queue_free()
	_finish()


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _finish() -> void:
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
