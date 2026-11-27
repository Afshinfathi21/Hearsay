extends SceneTree
## Host-independent tests for The Auction / Balance Scale rules.
## Run with: godot --headless --path . --script res://tests/balance_scale_test.gd

var passed := 0
var failed := 0


func _init() -> void:
	_test_unique_highest_bid()
	_test_invalid_bids_are_rejected()
	_test_extra_bids_from_dead_players_are_ignored()
	_test_zero_points_survive()
	_test_negative_points_eliminate_without_faking_acid()
	_test_acid_capacity_is_strict()
	_test_last_player_wins()
	_test_penalty_schedule()
	_test_standoff()
	_test_last_stand_rule()
	_test_forfeit()
	_test_acid_drain_option()
	_test_reveal_and_privacy()
	_test_everybody_bids_zero_always_terminates()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_unique_highest_bid() -> void:
	_title("unique highest bid")
	var game := _new_game([1, 2, 3], 100, 100)
	var result := game.resolve_round({1: 40, 2: 30, 3: 5}, 20)
	_check(result["ok"] and not result["standoff"], "valid bids resolve")
	_check(result["winner_id"] == 1 and game.points[1] == 60, "winner pays their own bid and takes no penalty")
	_check(game.points[2] == 80 and game.points[3] == 80, "losers pay the round penalty")
	_check(game.acid[2] == 10 and game.acid[3] == 35, "loser acid equals winning bid minus their bid")
	_check(game.acid[1] == 0, "the winner gets no acid")
	_check(result["deltas"][3] == {"points": -20, "acid": 35}, "the result lists each player's change")


func _test_invalid_bids_are_rejected() -> void:
	_title("invalid bids")
	var game := _new_game([1, 2], 50, 100)
	var result := game.resolve_round({1: 51, 2: 10}, 5)
	_check(not result["ok"], "a bid above the player's points is rejected")
	_check(game.round_number == 1 and game.points[1] == 50, "rejected bids do not change the game")
	_check(not game.resolve_round({1: 10}, 5)["ok"], "a missing bid is rejected")
	_check(not game.resolve_round({1: 10, 2: -1}, 5)["ok"], "a negative bid is rejected")
	_check(not game.resolve_round({1: 10, 2: 5.0}, 5)["ok"], "a non-integer bid is rejected")


func _test_extra_bids_from_dead_players_are_ignored() -> void:
	_title("bids from eliminated players")
	var game := _new_game([1, 2, 3], 10, 100)
	game.forfeit(3)
	var result := game.resolve_round({1: 5, 2: 1, 3: 9}, 1)
	_check(result["ok"] and result["winner_id"] == 1, "an extra bid from an eliminated player is ignored")
	_check(not result["bids"].has(3), "the result does not list the eliminated player's bid")


func _test_zero_points_survive() -> void:
	_title("exactly zero points")
	var game := _new_game([1, 2], 10, 100)
	game.resolve_round({1: 5, 2: 0}, 10)
	_check(game.points[2] == 0 and not game.eliminated[2], "a player with exactly zero points is alive")


func _test_negative_points_eliminate_without_faking_acid() -> void:
	_title("negative points")
	var game := _new_game([1, 2, 3], 10, 100)
	var result := game.resolve_round({1: 5, 2: 3, 3: 0}, 11)
	_check(game.points[2] == -1 and game.eliminated[2], "points below zero eliminate the player")
	_check(result["eliminations"][0]["reason"] == BalanceScaleGame.REASON_POINTS, "the reason is reported")
	_check(game.acid[2] == 2, "the acid number stays true (not forced to capacity)")
	_check(not game.eliminated[1], "the winner remains alive")


func _test_acid_capacity_is_strict() -> void:
	_title("acid capacity")
	var game := _new_game([1, 2], 100, 70)
	game.resolve_round({1: 50, 2: 0}, 0)
	_check(game.acid[2] == 50 and not game.eliminated[2], "partial acid stays in the pot")
	game.resolve_round({1: 20, 2: 0}, 0)
	_check(game.acid[2] == 70 and not game.eliminated[2], "exactly full is NOT an elimination")
	var result := game.resolve_round({1: 1, 2: 0}, 0)
	_check(game.acid[2] == 71 and game.eliminated[2], "one drop over capacity eliminates")
	_check(result["eliminations"][0]["reason"] == BalanceScaleGame.REASON_ACID, "the reason is acid overflow")


func _test_last_player_wins() -> void:
	_title("last survivor")
	var game := _new_game([1, 2], 10, 100)
	var ended := [-2]
	game.game_ended.connect(func(w: int) -> void: ended[0] = w)
	var result := game.resolve_round({1: 5, 2: 0}, 11)
	_check(result["game_over"] and result["game_winner_id"] == 1, "the last surviving player wins")
	_check(game.state == BalanceScaleGame.State.ENDED and ended[0] == 1, "the game ends and announces the winner")
	_check(not game.resolve_round({1: 0, 2: 0}, 1)["ok"], "no more rounds after the game ended")


func _test_penalty_schedule() -> void:
	_title("penalty schedule")
	var cfg := BalanceScaleConfig.new()
	_check(cfg.penalty_for_round(1) == 10 and cfg.penalty_for_round(2) == 13 and cfg.penalty_for_round(5) == 22, "10 +3 per round by default")
	cfg.penalty_start = 20
	cfg.penalty_step = 5
	_check(cfg.penalty_for_round(1) == 20 and cfg.penalty_for_round(3) == 30, "the original 20 +5 schedule is one config change away")
	var game := BalanceScaleGame.new()
	game.setup_with_config([1, 2] as Array[int], cfg)
	_check(game.current_penalty() == 20, "the game uses the configured penalty")
	game.resolve_round({1: 5, 2: 0})
	_check(game.current_penalty() == 25, "the penalty grows after every round")


func _test_standoff() -> void:
	_title("standoff (tie for the highest bid)")
	var game := _new_game([1, 2, 3], 100, 100)
	game.acid[3] = 12
	var result := game.resolve_round({1: 50, 2: 50, 3: 10}, 20)
	_check(result["ok"] and result["standoff"] and result["winner_id"] == -1, "equal highest bids are a standoff with no winner")
	_check(game.points[1] == 80 and game.points[2] == 80 and game.points[3] == 80, "EVERY living player pays the penalty, nobody pays a bid")
	_check(game.acid[1] == 0 and game.acid[2] == 0 and game.acid[3] == 12, "no acid is added in a standoff")
	_check(game.round_number == 2 and not result["game_over"], "the round counts and the game continues")


func _test_last_stand_rule() -> void:
	_title("last-stand rule")
	var game := _new_game([1, 2, 3], 10, 100)
	game.points[1] = 4
	game.points[2] = 7
	game.points[3] = 7
	game.acid[2] = 20
	game.acid[3] = 5
	var result := game.resolve_round({1: 0, 2: 0, 3: 0}, 50)
	_check(result["standoff"], "everybody bidding the same is a standoff")
	_check(result["last_stand_id"] == 3, "the survivor has the most points, then the least acid")
	_check(not game.eliminated[3] and game.eliminated[1] and game.eliminated[2], "everyone else is eliminated")
	_check(game.points[3] == 0, "the survivor's points are clamped to zero")
	_check(result["game_over"] and result["game_winner_id"] == 3, "the survivor wins the game")

	var game2 := _new_game([1, 2], 10, 100)
	game2.rng.seed = 1
	var r2 := game2.resolve_round({1: 0, 2: 0}, 50)
	_check(r2["last_stand_id"] in [1, 2] and r2["game_over"], "a full tie falls back to a coin flip and still ends the game")
	var wins := {1: 0, 2: 0}
	for seed_value in 60:
		var g := _new_game([1, 2], 10, 100)
		g.rng.seed = seed_value
		wins[g.resolve_round({1: 0, 2: 0}, 50)["last_stand_id"]] += 1
	_check(wins[1] > 10 and wins[2] > 10, "the coin flip is not biased towards one seat")


func _test_forfeit() -> void:
	_title("disconnect / forfeit")
	var game := _new_game([1, 2, 3], 100, 100)
	var result := game.forfeit(2)
	_check(result["ok"] and game.eliminated[2] and not result["game_over"], "a leaving player is eliminated")
	_check(game.active_player_ids() == [1, 3], "the others continue")
	_check(not game.forfeit(2)["ok"], "a player cannot forfeit twice")
	result = game.forfeit(3)
	_check(result["game_over"] and result["game_winner_id"] == 1 and game.state == BalanceScaleGame.State.ENDED, "the last player standing wins when everyone else leaves")


func _test_acid_drain_option() -> void:
	_title("acid drain knob")
	var cfg := BalanceScaleConfig.new()
	cfg.acid_drain_per_round = 10
	var game := BalanceScaleGame.new()
	game.setup_with_config([1, 2, 3] as Array[int], cfg)
	game.resolve_round({1: 40, 2: 0, 3: 0}, 0)
	_check(game.acid[2] == 30 and game.acid[1] == 0, "living pots drain by the configured amount after the round")


func _test_reveal_and_privacy() -> void:
	_title("reveal and privacy")
	var game := _new_game([1, 2], 25, 100)
	var public_state := game.snapshot()
	_check(not public_state["players"][1].has("points"), "public snapshot hides player points")
	var result := game.resolve_round({1: 10, 2: 5}, 0)
	_check(not result["players"][1].has("points"), "round result never lists anyone's point total")
	_check(result["bids"] == {1: 10, 2: 5} and result["winning_bid"] == 10, "the result reveals every bid")
	_check(game.private_snapshot(1)["points"] == 15, "a player can retrieve their own points")
	_check(game.private_snapshot(2)["points"] == 25, "private snapshots are scoped to one player")
	_check(game.private_snapshot(99).is_empty(), "unknown players receive no private state")


func _test_everybody_bids_zero_always_terminates() -> void:
	_title("stalling cannot last forever")
	var game := _new_game([1, 2, 3, 4], 100, 100)
	var rounds := 0
	while game.state == BalanceScaleGame.State.RUNNING and rounds < 100:
		var bids := {}
		for id in game.active_player_ids():
			bids[id] = 0
		game.resolve_round(bids)
		rounds += 1
	_check(game.state == BalanceScaleGame.State.ENDED and rounds < 12, "all-zero collusion ends the game in %d rounds with one survivor" % rounds)
	_check(game.winner_id != -1, "the game always produces a winner")


func _new_game(ids: Array[int], points: int, capacity: int) -> BalanceScaleGame:
	var game := BalanceScaleGame.new()
	_check(game.setup(ids, points, capacity), "game setup succeeds")
	return game


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  PASS  ", label)
	else:
		failed += 1
		print("  FAIL  ", label)


func _title(value: String) -> void:
	print("\n== ", value)
