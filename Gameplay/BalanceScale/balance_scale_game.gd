class_name BalanceScaleGame
extends RefCounted
## Host-authoritative rules for The Auction / Balance Scale. No scenes, no timers, no UI.
## The host creates one instance, calls setup(), then resolves each complete bid set.
##
## Rules (docs/balance_scale_design.md, section 3):
##   * Highest UNIQUE bid wins and pays that bid; the winner takes no penalty and no acid.
##   * Every other living player loses `penalty` points and gains acid = winning bid - own bid.
##   * A tie for the highest bid is a STANDOFF: nobody wins, nobody pays a bid, EVERY living
##     player loses `penalty` points, no acid. If that would kill everyone, one player survives
##     (most points, then least acid, then a coin flip).
##   * Eliminated when points < 0 or acid > capacity. Exactly 0 points / exactly full are alive.
##   * Acid is public, points are private. Bids are revealed in the round result.

signal round_resolved(result: Dictionary)
signal player_eliminated(player_id: int, reason: String)
signal game_ended(winner_id: int)

enum State { NOT_STARTED, RUNNING, ENDED }

const REASON_POINTS := "negative_points"
const REASON_ACID := "acid_overflow"
const REASON_DISCONNECTED := "disconnected"

var state: State = State.NOT_STARTED
var round_number: int = 1
var points: Dictionary = {}       # player_id -> int (private)
var acid: Dictionary = {}         # player_id -> int (public)
var eliminated: Dictionary = {}   # player_id -> bool
var pot_capacity: int = 0
var winner_id: int = -1
var config: BalanceScaleConfig
## Used only for the last-stand coin flip. Call rng.seed = n in tests for repeatable results.
var rng := RandomNumberGenerator.new()


## Simple setup: default penalty schedule, custom points / capacity.
func setup(player_ids: Array[int], starting_points: int, max_pot_capacity: int) -> bool:
	var cfg := BalanceScaleConfig.new()
	cfg.start_points = starting_points
	cfg.capacity = max_pot_capacity
	return setup_with_config(player_ids, cfg)


func setup_with_config(player_ids: Array[int], cfg: BalanceScaleConfig) -> bool:
	if state != State.NOT_STARTED or player_ids.size() < 2 or cfg == null:
		return false
	if cfg.start_points < 0 or cfg.capacity <= 0:
		return false

	var unique_ids: Dictionary = {}
	for player_id in player_ids:
		if unique_ids.has(player_id):
			return false
		unique_ids[player_id] = true

	config = cfg
	pot_capacity = cfg.capacity
	for player_id in player_ids:
		points[player_id] = cfg.start_points
		acid[player_id] = 0
		eliminated[player_id] = false

	rng.randomize()
	state = State.RUNNING
	return true


## Penalty for the round that is about to be resolved.
func current_penalty() -> int:
	return config.penalty_for_round(round_number) if config != null else 0


## Resolve only when every living player has submitted one valid bid. Bids from players who
## are not alive are ignored. round_penalty < 0 means "use the configured schedule".
func resolve_round(bids: Dictionary, round_penalty: int = -1) -> Dictionary:
	if state != State.RUNNING:
		return _error("The game is not accepting bids.")

	var penalty := current_penalty() if round_penalty < 0 else round_penalty
	var active_ids := active_player_ids()
	if active_ids.size() < 2:
		return _error("At least two active players are required.")

	var clean: Dictionary = {}
	for player_id in active_ids:
		if not bids.has(player_id):
			return _error("A bid is missing for player %s." % player_id)
		var bid_value: Variant = bids[player_id]
		if typeof(bid_value) != TYPE_INT:
			return _error("Bids must be whole numbers.")
		if int(bid_value) < 0 or int(bid_value) > int(points[player_id]):
			return _error("Player %s submitted an invalid bid." % player_id)
		clean[player_id] = int(bid_value)

	var highest_bid := -1
	var highest_ids: Array[int] = []
	for player_id in active_ids:
		var bid: int = clean[player_id]
		if bid > highest_bid:
			highest_bid = bid
			highest_ids.clear()
			highest_ids.append(player_id)
		elif bid == highest_bid:
			highest_ids.append(player_id)

	var resolved_round := round_number
	var points_before := points.duplicate()
	var acid_before := acid.duplicate()
	var standoff := highest_ids.size() > 1
	var winner := -1
	var dying: Array[Dictionary] = []   # [{id, reason}]
	var last_stand := -1

	if standoff:
		for player_id in active_ids:
			points[player_id] = int(points[player_id]) - penalty
		var below_zero: Array[int] = []
		for player_id in active_ids:
			if int(points[player_id]) < 0:
				below_zero.append(player_id)
		if below_zero.size() == active_ids.size():
			# Last-stand rule: somebody has to survive a standoff.
			last_stand = _pick_last_stand(active_ids)
			points[last_stand] = 0
			below_zero.erase(last_stand)
		for player_id in below_zero:
			dying.append({"id": player_id, "reason": REASON_POINTS})
	else:
		winner = highest_ids[0]
		points[winner] = int(points[winner]) - highest_bid
		for player_id in active_ids:
			if player_id == winner:
				continue
			points[player_id] = int(points[player_id]) - penalty
			acid[player_id] = int(acid[player_id]) + (highest_bid - int(clean[player_id]))
			if int(points[player_id]) < 0:
				dying.append({"id": player_id, "reason": REASON_POINTS})
			elif int(acid[player_id]) > pot_capacity:
				dying.append({"id": player_id, "reason": REASON_ACID})

	var eliminated_ids: Array[int] = []
	for entry in dying:
		eliminated[entry["id"]] = true
		eliminated_ids.append(entry["id"])

	if config.acid_drain_per_round > 0:
		for player_id in active_ids:
			if not bool(eliminated[player_id]):
				acid[player_id] = maxi(0, int(acid[player_id]) - config.acid_drain_per_round)

	round_number += 1

	var deltas: Dictionary = {}
	for player_id in active_ids:
		deltas[player_id] = {
			"points": int(points[player_id]) - int(points_before[player_id]),
			"acid": int(acid[player_id]) - int(acid_before[player_id]),
		}

	for entry in dying:
		player_eliminated.emit(entry["id"], entry["reason"])

	var remaining := active_player_ids()
	var round_result := {
		"ok": true,
		"round": resolved_round,
		"standoff": standoff,
		"tie": standoff,                    # kept for older callers
		"winner_id": winner,
		"winning_bid": highest_bid,
		"round_penalty": penalty,
		"penalty": penalty,
		"bids": clean,                      # revealed to everybody
		"deltas": deltas,                   # points never appear as totals, only changes
		"eliminated": eliminated_ids,
		"eliminations": dying,
		"last_stand_id": last_stand,
		"players": _public_player_snapshots(),
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


## A player left the match: they are eliminated at once and take no part in the round.
## The caller must also drop any bid that player had submitted.
func forfeit(player_id: int, reason: String = REASON_DISCONNECTED) -> Dictionary:
	if state != State.RUNNING:
		return _error("The game is not running.")
	if not points.has(player_id) or bool(eliminated[player_id]):
		return _error("Player %s is not an active player." % player_id)

	eliminated[player_id] = true
	player_eliminated.emit(player_id, reason)

	var remaining := active_player_ids()
	var result := {
		"ok": true,
		"player_id": player_id,
		"reason": reason,
		"game_over": remaining.size() <= 1,
		"game_winner_id": remaining[0] if remaining.size() == 1 else -1,
		"players": _public_player_snapshots(),
	}
	if remaining.size() <= 1:
		state = State.ENDED
		winner_id = int(result["game_winner_id"])
		game_ended.emit(winner_id)
	return result


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
		"players": _public_player_snapshots()
	}


## Public state deliberately excludes points. Use private_snapshot() for one player's own data.
func _public_player_snapshots() -> Dictionary:
	var result: Dictionary = {}
	for player_id in points:
		result[player_id] = {
			"acid": int(acid[player_id]),
			"eliminated": bool(eliminated[player_id])
		}
	return result


## Return only the requesting player's private state. Unknown IDs receive an empty dictionary.
func private_snapshot(player_id: int) -> Dictionary:
	if not points.has(player_id):
		return {}
	return {
		"player_id": player_id,
		"points": int(points[player_id]),
		"acid": int(acid[player_id]),
		"eliminated": bool(eliminated[player_id])
	}


## Most points, then least acid, then a coin flip.
func _pick_last_stand(candidates: Array[int]) -> int:
	var best: Array[int] = []
	for player_id in candidates:
		if best.is_empty():
			best.append(player_id)
			continue
		var cur := best[0]
		var more_points := int(points[player_id]) > int(points[cur])
		var same_points := int(points[player_id]) == int(points[cur])
		var less_acid := int(acid[player_id]) < int(acid[cur])
		var same_acid := int(acid[player_id]) == int(acid[cur])
		if more_points or (same_points and less_acid):
			best = [player_id]
		elif same_points and same_acid:
			best.append(player_id)
	return best[rng.randi_range(0, best.size() - 1)]


func _error(message: String) -> Dictionary:
	return {"ok": false, "error": message}
