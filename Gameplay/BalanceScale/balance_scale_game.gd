class_name BalanceScaleGame
extends RefCounted
## Host-authoritative rules for The Auction / Balance Scale.
## The host creates one instance, calls setup(), then resolves each complete bid set.

signal round_resolved(result: Dictionary)
signal player_eliminated(player_id: int, reason: String)
signal game_ended(winner_id: int)

enum State { NOT_STARTED, RUNNING, ENDED }

var state: State = State.NOT_STARTED
var round_number: int = 1
var points: Dictionary = {}       # player_id -> int
var acid: Dictionary = {}         # player_id -> int
var eliminated: Dictionary = {}  # player_id -> bool
var pot_capacity: int = 0
var winner_id: int = -1


func setup(player_ids: Array[int], starting_points: int, max_pot_capacity: int) -> bool:
	if state != State.NOT_STARTED or player_ids.size() < 2:
		return false
	if starting_points < 0 or max_pot_capacity <= 0:
		return false

	var unique_ids: Dictionary = {}
	for player_id in player_ids:
		if unique_ids.has(player_id):
			return false
		unique_ids[player_id] = true

	pot_capacity = max_pot_capacity
	for player_id in player_ids:
		points[player_id] = starting_points
		acid[player_id] = 0
		eliminated[player_id] = false

	state = State.RUNNING
	return true


## Resolve only when every living player has submitted one valid bid.
## A tie for the highest bid advances the round without changing any player state.
func resolve_round(bids: Dictionary, round_penalty: int) -> Dictionary:
	if state != State.RUNNING:
		return _error("The game is not accepting bids.")
	if round_penalty < 0:
		return _error("The round penalty cannot be negative.")

	var active_ids := active_player_ids()
	if active_ids.size() < 2:
		return _error("At least two active players are required.")
	if bids.size() != active_ids.size():
		return _error("A bid is required from every active player.")

	for player_id in active_ids:
		if not bids.has(player_id):
			return _error("A bid is missing for player %s." % player_id)
		var bid_value: Variant = bids[player_id]
		if typeof(bid_value) != TYPE_INT:
			return _error("Bids must be whole numbers.")
		if int(bid_value) < 0 or int(bid_value) > int(points[player_id]):
			return _error("Player %s submitted an invalid bid." % player_id)

	var highest_bid := -1
	var highest_ids: Array[int] = []
	for player_id in active_ids:
		var bid := int(bids[player_id])
		if bid > highest_bid:
			highest_bid = bid
			highest_ids.clear()
			highest_ids.append(player_id)
		elif bid == highest_bid:
			highest_ids.append(player_id)

	round_number += 1

	if highest_ids.size() != 1:
		var tie_result := {
			"ok": true,
			"tie": true,
			"winner_id": -1,
			"winning_bid": highest_bid,
			"round_penalty": round_penalty,
			"eliminated": [],
			"players": _player_snapshots()
		}
		round_resolved.emit(tie_result)
		return tie_result

	var winner: int = highest_ids[0]
	points[winner] = int(points[winner]) - highest_bid
	var eliminated_this_round: Array[int] = []

	for player_id in active_ids:
		if player_id == winner:
			continue

		var player_bid := int(bids[player_id])
		points[player_id] = int(points[player_id]) - round_penalty
		acid[player_id] = int(acid[player_id]) + (highest_bid - player_bid)

		var reason := ""
		if int(points[player_id]) < 0:
			# Falling below zero causes the pot to release, regardless of its prior fill.
			acid[player_id] = pot_capacity
			reason = "negative_points"
		elif int(acid[player_id]) >= pot_capacity:
			acid[player_id] = pot_capacity
			reason = "pot_full"

		if not reason.is_empty():
			eliminated[player_id] = true
			eliminated_this_round.append(player_id)
			player_eliminated.emit(player_id, reason)

	var remaining := active_player_ids()
	var round_result := {
		"ok": true,
		"tie": false,
		"winner_id": winner,
		"winning_bid": highest_bid,
		"round_penalty": round_penalty,
		"eliminated": eliminated_this_round,
		"players": _player_snapshots()
	}

	if remaining.size() <= 1:
		state = State.ENDED
		winner_id = remaining[0] if remaining.size() == 1 else -1
		round_result["game_over"] = true
		round_result["game_winner_id"] = winner_id
		game_ended.emit(winner_id)
	else:
		round_result["game_over"] = false
		round_result["game_winner_id"] = -1

	round_resolved.emit(round_result)
	return round_result


func active_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for player_id in points:
		if not bool(eliminated[player_id]):
			ids.append(int(player_id))
	ids.sort()
	return ids


func snapshot() -> Dictionary:
	return {
		"state": state,
		"round_number": round_number,
		"winner_id": winner_id,
		"players": _player_snapshots()
	}


func _player_snapshots() -> Dictionary:
	var result: Dictionary = {}
	for player_id in points:
		result[player_id] = {
			"points": int(points[player_id]),
			"acid": int(acid[player_id]),
			"eliminated": bool(eliminated[player_id])
		}
	return result


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
