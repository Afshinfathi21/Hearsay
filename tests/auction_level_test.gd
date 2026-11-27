extends SceneTree
## The whole level, played by the test: sit down, bots join, bid with the keyboard, play until
## somebody wins. Uses short timings so it finishes in a few seconds.
## Run with: godot --headless --path . --script res://tests/auction_level_test.gd

var passed := 0
var failed := 0


func _init() -> void:
	call_deferred("_run")


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)


func _run() -> void:
	var level := (load("res://Levels/Balance Scale/auction_chamber.tscn") as PackedScene).instantiate()
	var presenter := level.get_node("Presenter") as AuctionPresenter
	var cfg := BalanceScaleConfig.new()
	cfg.bid_seconds = 3.0
	cfg.intro_seconds = 0.1
	cfg.penalty_seconds = 0.1
	cfg.reveal_seconds = 0.3
	cfg.winner_seconds = 0.2
	cfg.acid_seconds = 0.3
	cfg.elimination_seconds = 0.2
	cfg.next_round_seconds = 0.1
	presenter.config = cfg
	root.add_child(level)
	var player := level.get_node("Player")
	var seating := level.get_node("Seating") as SeatingController
	for i in 30:
		await physics_frame

	_check(presenter.auction == null, "nothing starts before the player sits")
	Input.action_press("interact")
	await physics_frame
	await physics_frame
	Input.action_release("interact")
	for i in 10:
		await physics_frame
	var auction := presenter.auction
	_check(player.seated and auction != null, "sitting down starts the match")
	_check(auction.players.size() == 4, "three bots take the other chairs")
	_check(presenter._avatars.size() == 3 and presenter._avatars.values().all(func(a): return a.visible), "three seated bot characters are in the room")
	var seats_taken := 0
	for seat in seating.seats:
		if not seat.is_free():
			seats_taken += 1
	_check(seats_taken == 4, "all four chairs are occupied")
	_check(auction.state != AuctionMatch.S.SEATING, "the first round has begun")

	# --- play the whole game with the keyboard ---
	var human_bids := 0
	var saw_panel := false
	var saw_wall_text := false
	var elapsed := 0.0
	while not auction.is_over() and elapsed < 120.0:
		await physics_frame
		elapsed += 1.0 / 60.0
		var panel := presenter._bid_panel
		if panel.is_open() and not panel.locked:
			saw_panel = true
			_key(KEY_6)
			_key(KEY_ENTER)
			await physics_frame
			if panel.locked:
				human_bids += 1
	_check(saw_panel, "the bid panel opens during bidding")
	_check(human_bids >= 1, "the human can lock in a bid with the keyboard (%d bids)" % human_bids)
	_check(auction.is_over(), "the match reaches GAME OVER (%.0f s, round %d)" % [elapsed, auction.round_number()])
	_check(auction.game.active_player_ids().size() == 1, "exactly one player survives")
	_check(not presenter._bid_panel.is_open(), "the bid panel is closed at the end")
	await create_timer(1.2).timeout
	var released := 0
	for i in presenter._pots.size():
		if presenter._pots[i] != null and not is_equal_approx(presenter._pots[i]._hatch_rest_z, presenter._pots[i].hatch.rotation.z):
			released += 1
	_check(released == 3, "every eliminated player's pot was released (%d of 3)" % released)
	_check(seating.state == SeatingController.State.GAME_OVER, "the seating lock is lifted when the game ends")
	level.queue_free()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if label == "":
		return
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)
