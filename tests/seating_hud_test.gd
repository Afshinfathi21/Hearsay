extends SceneTree
## Esc opens the HUD pause menu, and players must sit before (and stay seated until) the game ends.
## Run with: godot --headless --path . --script res://tests/seating_hud_test.gd

var passed := 0
var failed := 0

func _init() -> void:
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	var level := (load("res://Levels/Balance Scale/auction_chamber.tscn") as PackedScene).instantiate()
	root.add_child(level)
	var player := level.get_node("Player")
	var hud := level.get_node("UI/GameHUD") as GameHUD
	var seating := level.get_node("Seating") as SeatingController
	await _frames(30)

	# --- HUD / Esc ---
	_check(hud != null and hud.pause_menu != null, "the level has a HUD with a pause menu")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(3)
	_check(hud.pause_menu.is_open, "Esc opens the pause menu")
	_check(player.input_blocked, "the player stops moving while the menu is open")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse is free while the menu is open")
	hud.pause_menu.close()
	await _frames(3)
	_check(not player.input_blocked, "closing the menu gives the player control back")

	# --- must sit first ---
	var all_seated_fired := [false]
	seating.all_seated.connect(func() -> void: all_seated_fired[0] = true)
	_check(seating.state == SeatingController.State.SEATING and not player.seated, "game starts in the seating phase")
	var seat := level.get_node("Seats/Seat_East") as AuctionSeat
	_check(seat != null and seat.is_free(), "the east chair is free")

	# the player spawns behind the east chair, looking at it
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)
	_check(player.seated and seat.occupant == player, "looking at a chair and pressing E sits the player on it")
	_check(all_seated_fired[0] and seating.state == SeatingController.State.PLAYING, "everyone seated -> game phase starts")
	var sit_pos: Vector3 = player.global_position
	_check(absf(sit_pos.x - seat.global_position.x) < 0.05 and absf(sit_pos.z) < 0.05, "player is placed on the chair")

	# --- cannot stand / walk while the game runs ---
	Input.action_press("move_up")
	await _frames(20)
	Input.action_release("move_up")
	_check(player.global_position.distance_to(sit_pos) < 0.01, "a seated player cannot walk away")
	Input.action_press("jump")
	await _frames(5)
	Input.action_release("jump")
	_check(player.global_position.distance_to(sit_pos) < 0.01, "a seated player cannot jump")
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)
	_check(player.seated, "pressing E during the game does not stand the player up")

	# Opening and closing the pause menu must not free a seated player (the HUD unblocks input).
	Input.parse_input_event(esc)
	await _frames(3)
	hud.pause_menu.close()
	await _frames(3)
	Input.action_press("move_up")
	await _frames(20)
	Input.action_release("move_up")
	_check(player.seated and player.global_position.distance_to(sit_pos) < 0.01, "closing the pause menu does not release a seated player")

	# --- game over releases ---
	seating.end_game()
	await _frames(3)
	Input.action_press("interact")
	await _frames(3)
	Input.action_release("interact")
	await _frames(3)
	_check(not player.seated and seat.is_free(), "after the game ends, E stands the player up")
	_check(player.global_position.x > seat.global_position.x + 0.5, "the player stands up behind the chair")

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
