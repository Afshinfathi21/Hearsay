extends SceneTree
## Match flow, bid validation, secrecy and disconnects (no scene needed, fake clock).
## Run with: godot --headless --path . --script res://tests/auction_match_test.gd

var passed := 0
var failed := 0


func _init() -> void:
	_test_flow_and_states()
	_test_bid_validation()
	_test_secrecy()
	_test_timeout_means_zero()
	_test_all_bots_finish_a_game()
	_test_disconnects()
	_test_one_resolution_per_round()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _new_match(bot_count := 3, seed_value := 1) -> AuctionMatch:
	var m := AuctionMatch.new()
	m.use_process = false
	m.rng.seed = seed_value
	var list: Array[Dictionary] = [{"id": 1, "name": "YOU", "is_bot": false, "seat": 0, "personality": ""}]
	var names := ["MIRA", "JONAS", "ILSE"]
	for i in bot_count:
		list.append({"id": 2 + i, "name": names[i], "is_bot": true, "seat": 1 + i, "personality": BotBidder.PERSONALITIES[i]})
	_check(m.setup(list), "match setup succeeds with %d players" % list.size())
	return m


func _run_until(m: AuctionMatch, target: int, limit := 4000) -> bool:
	for i in limit:
		if m.state == target:
			return true
		m.advance(0.1)
	return m.state == target


func _test_flow_and_states() -> void:
	_title("state flow")
	var m := _new_match()
	_check(m.state == AuctionMatch.S.SEATING, "starts in the seating state")
	m.advance(100.0)
	_check(m.state == AuctionMatch.S.SEATING, "time does not move the match while players are still seating")
	var visited := {}
	m.state_changed.connect(func(s: int, _r: int) -> void: visited[s] = true)
	m.start_rounds()
	_check(m.state == AuctionMatch.S.ROUND_INTRO and m.round_number() == 1, "all seated -> round 1 introduction")
	_check(_run_until(m, AuctionMatch.S.BIDDING), "intro and penalty announcement lead to bidding")
	_check(is_equal_approx(m.time_total, 20.0), "bidding lasts 20 seconds")
	_check(m.submit_bid(1, 10), "the human submits a bid")
	_check(m.state == AuctionMatch.S.WAITING_FOR_SUBMISSIONS, "after the humans lock in the match waits for the bots")
	_check(_run_until(m, AuctionMatch.S.BID_REVEAL), "when everyone has locked in the bids are revealed")
	for s in [AuctionMatch.S.WINNER_ANNOUNCE, AuctionMatch.S.ACID_APPLY]:
		_check(_run_until(m, s), "reaches %s" % AuctionMatch.STATE_LABELS[s])
	_run_until(m, AuctionMatch.S.NEXT_ROUND_PREP, 800)
	_check(m.state == AuctionMatch.S.NEXT_ROUND_PREP or m.state == AuctionMatch.S.ELIMINATION_CHECK or m.is_over(), "after the acid either eliminations or the next round follow")
	m.free()


func _test_bid_validation() -> void:
	_title("bid validation")
	var m := _new_match()
	_check(not m.submit_bid(1, 5), "no bids before bidding opens")
	m.start_rounds()
	_run_until(m, AuctionMatch.S.BIDDING)
	_check(not m.submit_bid(1, 101), "a bid above the player's points is rejected")
	_check(not m.submit_bid(1, -1), "a negative bid is rejected")
	_check(not m.submit_bid(1, 5.5), "a non-integer bid is rejected")
	_check(not m.submit_bid(1, "50"), "a text bid is rejected")
	_check(not m.submit_bid(99, 5), "a stranger cannot bid")
	_check(m.submit_bid(1, 30), "a valid bid is accepted")
	_check(not m.submit_bid(1, 50), "a second bid in the same round is rejected")
	_check(not m.submit_bid(1, 0), "a locked bid can never be changed")
	m.free()


func _test_secrecy() -> void:
	_title("secrecy")
	var m := _new_match()
	m.start_rounds()
	_run_until(m, AuctionMatch.S.BIDDING)
	m.submit_bid(1, 42)
	m.advance(8.0)
	var view := m.public_view()
	_check(not _contains_key(view, "bids") and not _contains_key(view, "points") and not _contains_key(view, "bid"), "the public view has no bids and no points")
	_check(not str(view).contains("42"), "the human's secret bid value does not appear anywhere in the public view")
	var locked := 0
	for p in view["players"]:
		if p["locked"]:
			locked += 1
	_check(locked >= 1, "who has locked in IS public")
	_check(m.private_view(1)["points"] == 100 and m.private_view(1)["bid_locked"], "a player can read their own points")
	_check(m.private_view(2)["points"] == 100, "(host-side) private view exists per player")
	var revealed := [false]
	m.round_revealed.connect(func(r: Dictionary) -> void: revealed[0] = r["bids"].has(1) and r["bids"][1] == 42)
	_run_until(m, AuctionMatch.S.BID_REVEAL)
	_check(revealed[0], "bids appear only in the reveal")
	m.free()


func _test_timeout_means_zero() -> void:
	_title("deadline")
	var m := _new_match()
	m.start_rounds()
	_run_until(m, AuctionMatch.S.BIDDING)
	var autos := []
	m.bid_locked.connect(func(id: int, auto: bool) -> void: if auto: autos.append(id))
	var result := [{}]
	m.round_revealed.connect(func(r: Dictionary) -> void: result[0] = r)
	for i in 400:
		m.advance(0.1)
		if m.state == AuctionMatch.S.BID_REVEAL:
			break
	_check(1 in autos, "a player who does not submit is locked in automatically")
	_check(result[0].get("bids", {}).get(1, -1) == 0, "the automatic bid is 0")
	m.free()


func _test_all_bots_finish_a_game() -> void:
	_title("a whole match")
	for seed_value in [1, 2, 3, 4, 5]:
		var m := _new_match(3, seed_value)
		m.start_rounds()
		var rounds := [0]
		var winner := [-9]
		m.game_finished.connect(func(w: int) -> void: winner[0] = w)
		var humans_bid := true
		for i in 60000:
			if m.state == AuctionMatch.S.BIDDING and humans_bid and not m.private_view(1).get("bid_locked", true):
				m.submit_bid(1, int(m.private_view(1)["points"] * 0.2))
			if m.is_over():
				break
			m.advance(0.1)
		_check(m.is_over() and winner[0] > 0, "seed %d: the match ends with a winner (round %d)" % [seed_value, m.round_number()])
		_check(m.game.active_player_ids().size() == 1, "seed %d: exactly one player is left alive" % seed_value)
		m.free()


func _test_disconnects() -> void:
	_title("disconnects")
	# after submitting
	var m := _new_match()
	m.start_rounds()
	_run_until(m, AuctionMatch.S.BIDDING)
	m.submit_bid(1, 90)
	var gone := []
	m.player_eliminated.connect(func(id: int, reason: String) -> void: gone.append([id, reason]))
	m.player_disconnected(1)
	_check(gone == [[1, "disconnected"]], "a leaving player is eliminated as DISCONNECTED")
	_run_until(m, AuctionMatch.S.BID_REVEAL)
	_check(not m.last_result["bids"].has(1), "the bid of a player who left is discarded, even after submitting")
	_check(m.last_result["bids"].size() == 3, "the round resolves among the players who stayed")
	m.free()
	# everyone else leaves
	var m2 := _new_match(1)
	m2.start_rounds()
	_run_until(m2, AuctionMatch.S.BIDDING)
	var finished := [-9]
	m2.game_finished.connect(func(w: int) -> void: finished[0] = w)
	m2.player_disconnected(2)
	_check(m2.is_over() and finished[0] == 1, "when only one player is left the match ends at once")
	m2.free()
	# leaving during seating phase is harmless
	var m3 := _new_match(2)
	m3.player_disconnected(3)
	_check(m3.state == AuctionMatch.S.SEATING and m3.game.eliminated[3], "a player can leave before the match starts")
	m3.free()


func _test_one_resolution_per_round() -> void:
	_title("no double resolution")
	var m := _new_match()
	m.start_rounds()
	_run_until(m, AuctionMatch.S.BIDDING)
	var resolutions := [0]
	m.game.round_resolved.connect(func(_r: Dictionary) -> void: resolutions[0] += 1)
	for id in [1, 2, 3, 4]:
		m.submit_bid(id, 0)
	m._resolve_and_reveal()
	m._resolve_and_reveal()
	_check(resolutions[0] == 1 and m.game.round_number == 2, "a round is resolved exactly once")
	m.free()


func _contains_key(value: Variant, key: String) -> bool:
	if value is Dictionary:
		for k in value:
			if str(k) == key or _contains_key(value[k], key):
				return true
	elif value is Array:
		for v in value:
			if _contains_key(v, key):
				return true
	return false


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _title(value: String) -> void:
	print("\n== ", value)
