extends SceneTree
## Host-independent tests for The Auction / Balance Scale rules.
## Run with: godot --headless --path . --script res://tests/balance_scale_test.gd

var passed := 0
var failed := 0


func _init() -> void:
	_test_unique_highest_bid()
	_test_tie_changes_nothing()
	_test_invalid_bids_are_rejected()
	_test_zero_points_survive()
	_test_negative_points_eliminate()
	_test_full_pot_eliminates()
	_test_last_player_wins()
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_unique_highest_bid() -> void:
	_title("unique highest bid")
	var game := _new_game([1, 2, 3], 100, 100)
	var result := game.resolve_round({1: 40, 2: 30, 3: 5}, 20)
	_check(result["ok"], "valid bids resolve")
	_check(result["winner_id"] == 1 and game.points[1] == 60, "winner pays their own bid")
	_check(game.points[2] == 80 and game.points[3] == 80, "losers pay the announced point penalty")
	_check(game.acid[2] == 10 and game.acid[3] == 35, "loser acid equals winning bid minus their bid")


func _test_tie_changes_nothing() -> void:
	_title("tie for highest bid")
	var game := _new_game([1, 2, 3], 100, 100)
	game.acid[3] = 12
	var result := game.resolve_round({1: 50, 2: 50, 3: 10}, 20)
	_check(result["ok"] and result["tie"], "equal highest bids produce a tie")
	_check(result["winner_id"] == -1, "nobody wins a tied round")
	_check(game.points[1] == 100 and game.points[2] == 100 and game.points[3] == 100, "no points change on a tie")
	_check(game.acid[1] == 0 and game.acid[2] == 0 and game.acid[3] == 12, "no acid is added on a tie")
	_check(game.round_number == 2 and game.state == BalanceScaleGame.State.RUNNING, "the next round can begin")


func _test_invalid_bids_are_rejected() -> void:
	_title("invalid bids")
	var game := _new_game([1, 2], 50, 100)
	var result := game.resolve_round({1: 51, 2: 10}, 5)
	_check(not result["ok"], "a bid above the player's points is rejected")
	_check(game.round_number == 1 and game.points[1] == 50, "rejected bids do not mutate the game")
	result = game.resolve_round({1: 10}, 5)
	_check(not result["ok"], "a missing player's bid is rejected")


func _test_zero_points_survive() -> void:
	_title("exactly zero points")
	var game := _new_game([1, 2], 10, 100)
	game.resolve_round({1: 5, 2: 0}, 10)
	_check(game.points[2] == 0 and not game.eliminated[2], "a player with exactly zero points is still alive")


func _test_negative_points_eliminate() -> void:
	_title("negative points")
	var game := _new_game([1, 2], 10, 100)
	var result := game.resolve_round({1: 5, 2: 0}, 11)
	_check(result["winner_id"] == 1, "the highest bidder still wins")
	_check(game.points[2] == -1 and game.eliminated[2], "points below zero eliminate the player")
	_check(game.acid[2] == 100, "negative points fill the pot to capacity")
	_check(game.points[1] == 5 and not game.eliminated[1], "the winner remains alive")


func _test_full_pot_eliminates() -> void:
	_title("acid pot capacity")
	var game := _new_game([1, 2], 100, 70)
	game.resolve_round({1: 50, 2: 0}, 0)
	_check(game.acid[2] == 50 and not game.eliminated[2], "partial acid remains in the pot")
	var result := game.resolve_round({1: 30, 2: 0}, 0)
	_check(game.acid[2] == 70 and game.eliminated[2], "reaching capacity releases the pot and eliminates the player")
	_check(result["eliminated"] == [2], "the result reports the eliminated player")


func _test_last_player_wins() -> void:
	_title("last survivor")
	var game := _new_game([1, 2], 10, 100)
	var result := game.resolve_round({1: 5, 2: 0}, 11)
	_check(result["game_over"] and result["game_winner_id"] == 1, "the last surviving player wins")
	_check(game.state == BalanceScaleGame.State.ENDED and game.winner_id == 1, "the game enters the ended state")


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
