extends SceneTree
## Scene-level smoke tests for the acid pot.
## Run with: godot --headless --path . --script res://tests/acid_pot_scene_test.gd

const SCENE_PATH := "res://Levels/Balance Scale/AuctionChamber.tscn"

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

	var pot := chamber.get_node("Pots/East") as AcidPot
	_check(pot != null, "the east pot is assembled")
	if pot == null:
		_finish()
		return

	pot.fill = 0.5
	_check(is_equal_approx(pot.fill, 0.5) and is_equal_approx(pot.liquid.scale.y, 0.5), "manual fill updates the liquid mesh")

	var overflow_seen := false
	pot.overflowed.connect(func() -> void: overflow_seen = true)
	pot.pour_to(1.1, 0.05)
	await create_timer(0.15).timeout
	_check(is_equal_approx(pot.fill, 1.1), "pour animation can reach the overflow range")
	_check(overflow_seen and pot._fx_overflow.emitting, "overflow triggers the signal and overflow particles")

	var released_seen := false
	pot.released.connect(func() -> void: released_seen = true)
	pot.release()
	await create_timer(1.1).timeout
	_check(released_seen, "release animation completes and emits its signal")
	_check(is_equal_approx(pot.fill, 0.0), "release drains the pot")

	pot.reset()
	_check(is_equal_approx(pot.fill, 0.0) and is_equal_approx(pot.hatch.rotation.z, 0.0), "reset restores the pot")
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
