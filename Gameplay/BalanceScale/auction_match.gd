class_name AuctionMatch
extends Node
## Host-side match flow for the Balance Scale level: the 12 states of
## docs/balance_scale_design.md section 4, the bidding timer, bot bidders and all bid
## validation. It owns the BalanceScaleGame rules object and never touches the scene.
##
## Everything a client may see comes from public_view() / private_view(); a bid is only
## revealed through `round_revealed`. Presentation code (AuctionPresenter) listens to the
## signals. Time only moves through advance(), so tests can drive it with a fake clock.

signal state_changed(new_state: int, round_number: int)
signal bid_locked(player_id: int, auto: bool)
signal round_revealed(result: Dictionary)
signal winner_announced(result: Dictionary)
signal acid_applied(result: Dictionary)
signal player_eliminated(player_id: int, reason: String)
signal game_finished(winner_id: int)

enum S {
	WAITING_FOR_PLAYERS, SEATING, ROUND_INTRO, PENALTY_ANNOUNCE, BIDDING,
	WAITING_FOR_SUBMISSIONS, BID_REVEAL, WINNER_ANNOUNCE, ACID_APPLY,
	ELIMINATION_CHECK, NEXT_ROUND_PREP, GAME_OVER,
}

const STATE_LABELS := {
	S.WAITING_FOR_PLAYERS: "WAITING", S.SEATING: "TAKE YOUR SEAT", S.ROUND_INTRO: "NEW ROUND",
	S.PENALTY_ANNOUNCE: "PENALTY", S.BIDDING: "BIDDING", S.WAITING_FOR_SUBMISSIONS: "WAITING FOR BIDS",
	S.BID_REVEAL: "REVEAL", S.WINNER_ANNOUNCE: "RESULT", S.ACID_APPLY: "ACID",
	S.ELIMINATION_CHECK: "ELIMINATION", S.NEXT_ROUND_PREP: "NEXT ROUND", S.GAME_OVER: "GAME OVER",
}

var config: BalanceScaleConfig = BalanceScaleConfig.new()
var game: BalanceScaleGame
var state: int = S.WAITING_FOR_PLAYERS
var time_left := 0.0
var time_total := 0.0
## true: the node advances itself every frame. Tests set false and call advance().
var use_process := true
var rng := RandomNumberGenerator.new()

var players: Array[Dictionary] = []   # {id, name, is_bot, seat, personality}
var last_result: Dictionary = {}

var _bids: Dictionary = {}            # id -> int. HOST PRIVATE until the reveal.
var _locked: Dictionary = {}          # id -> true
var _think: Dictionary = {}           # bot id -> seconds until it submits
var _bid_elapsed := 0.0
var _elim_queue: Array = []
var _revealed := false


func _process(delta: float) -> void:
	if use_process:
		advance(delta)


## players: [{id, name, is_bot, seat, personality}]. Needs at least two. Moves to SEATING.
func setup(player_list: Array[Dictionary], cfg: BalanceScaleConfig = null) -> bool:
	if cfg != null:
		config = cfg
	players = player_list.duplicate()
	var ids: Array[int] = []
	for p in players:
		ids.append(int(p["id"]))
	game = BalanceScaleGame.new()
	if not game.setup_with_config(ids, config):
		return false
	game.rng.seed = rng.randi()
	_set_state(S.SEATING, 0.0)
	return true


## Everybody is seated: the first round begins.
func start_rounds() -> void:
	if state == S.SEATING:
		_enter_intro()


func round_number() -> int:
	return game.round_number if game != null else 0


func is_over() -> bool:
	return state == S.GAME_OVER


func state_label() -> String:
	return str(STATE_LABELS.get(state, ""))


func is_bidding() -> bool:
	return state == S.BIDDING or state == S.WAITING_FOR_SUBMISSIONS


# ------------------------------------------------------------------ bids

## The only way a bid enters the game. Returns true when the bid was accepted.
func submit_bid(player_id: int, amount: Variant) -> bool:
	if not is_bidding() or game == null or game.state != BalanceScaleGame.State.RUNNING:
		return false
	if typeof(amount) != TYPE_INT:
		return false
	if not game.points.has(player_id) or bool(game.eliminated[player_id]):
		return false
	if _locked.has(player_id):
		return false                       # one bid per round, never changeable
	if int(amount) < 0 or int(amount) > int(game.points[player_id]):
		return false
	_lock(player_id, int(amount), false)
	_after_lock()
	return true


## A player left. Their bid (even a submitted one) is discarded and they are eliminated.
func player_disconnected(player_id: int) -> void:
	if game == null or game.state != BalanceScaleGame.State.RUNNING:
		return
	if not game.points.has(player_id) or bool(game.eliminated[player_id]):
		return
	_bids.erase(player_id)
	_locked.erase(player_id)
	_think.erase(player_id)
	var result := game.forfeit(player_id)
	if not bool(result.get("ok", false)):
		return
	player_eliminated.emit(player_id, BalanceScaleGame.REASON_DISCONNECTED)
	if game.state == BalanceScaleGame.State.ENDED:
		_enter_game_over()
	elif is_bidding():
		_after_lock()


# ------------------------------------------------------------------ views

## What every client may know. Never contains a bid or anybody's points.
func public_view() -> Dictionary:
	var list: Array = []
	for p in players:
		var id: int = p["id"]
		list.append({
			"id": id, "name": p["name"], "seat": p["seat"], "is_bot": p["is_bot"],
			"alive": not bool(game.eliminated[id]),
			"acid": int(game.acid[id]),
			"locked": _locked.has(id),
		})
	return {
		"state": state, "state_label": state_label(), "round": game.round_number,
		"penalty": game.current_penalty(), "capacity": config.capacity,
		"time_left": time_left, "time_total": time_total, "players": list,
	}


## Only this player's own secret data.
func private_view(player_id: int) -> Dictionary:
	var snap := game.private_snapshot(player_id)
	if snap.is_empty():
		return snap
	snap["bid_locked"] = _locked.has(player_id)
	snap["next_loss_is_fatal"] = int(snap["points"]) < game.current_penalty()
	return snap


func alive_humans() -> int:
	var n := 0
	for p in players:
		if not bool(p["is_bot"]) and not bool(game.eliminated[p["id"]]):
			n += 1
	return n


func player_info(player_id: int) -> Dictionary:
	for p in players:
		if int(p["id"]) == player_id:
			return p
	return {}


# ------------------------------------------------------------------ clock

func advance(delta: float) -> void:
	if state == S.WAITING_FOR_PLAYERS or state == S.SEATING or state == S.GAME_OVER:
		return
	# With no human left alive the bots finish the game quickly.
	if alive_humans() == 0:
		delta *= 4.0
	if is_bidding():
		_bid_elapsed += delta
		_run_bots()
		if not is_bidding():
			return
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_on_timeout()


func _on_timeout() -> void:
	match state:
		S.ROUND_INTRO:
			_set_state(S.PENALTY_ANNOUNCE, config.penalty_seconds)
		S.PENALTY_ANNOUNCE:
			_enter_bidding()
		S.BIDDING, S.WAITING_FOR_SUBMISSIONS:
			# Nothing submitted by the deadline means a bid of 0.
			for id in game.active_player_ids():
				if not _locked.has(id):
					_lock(id, 0, true)
			_resolve_and_reveal()
		S.BID_REVEAL:
			_set_state(S.WINNER_ANNOUNCE, config.winner_seconds)
			winner_announced.emit(last_result)
		S.WINNER_ANNOUNCE:
			_set_state(S.ACID_APPLY, config.acid_seconds)
			acid_applied.emit(last_result)
		S.ACID_APPLY:
			_elim_queue = last_result.get("eliminations", []).duplicate()
			_next_elimination()
		S.ELIMINATION_CHECK:
			_next_elimination()
		S.NEXT_ROUND_PREP:
			_enter_intro()


# ------------------------------------------------------------------ transitions

func _enter_intro() -> void:
	_bids.clear()
	_locked.clear()
	_revealed = false
	_set_state(S.ROUND_INTRO, config.intro_seconds)


func _enter_bidding() -> void:
	_bid_elapsed = 0.0
	_think.clear()
	var latest := maxf(3.0, config.bid_seconds - 4.0)
	for p in players:
		var id: int = p["id"]
		if bool(p["is_bot"]) and not bool(game.eliminated[id]):
			_think[id] = rng.randf_range(2.0, latest)
	_set_state(S.BIDDING, config.bid_seconds)
	if alive_humans() == 0:
		return


func _run_bots() -> void:
	for id in _think.keys():
		if _locked.has(id) or bool(game.eliminated[id]):
			continue
		if _bid_elapsed >= float(_think[id]):
			var info := player_info(id)
			var bid := BotBidder.choose_bid(str(info.get("personality", "adaptive")),
				int(game.points[id]), int(game.acid[id]), config.capacity, game.current_penalty(), rng)
			submit_bid(id, bid)
			if not is_bidding():
				return


func _lock(player_id: int, amount: int, auto: bool) -> void:
	_bids[player_id] = amount
	_locked[player_id] = true
	bid_locked.emit(player_id, auto)


func _after_lock() -> void:
	if not is_bidding():
		return
	var humans_waiting := false
	var anyone_waiting := false
	for id in game.active_player_ids():
		if _locked.has(id):
			continue
		anyone_waiting = true
		if not bool(player_info(id).get("is_bot", false)):
			humans_waiting = true
	if not anyone_waiting:
		_resolve_and_reveal()
	elif not humans_waiting and state == S.BIDDING:
		_set_state_keep_time(S.WAITING_FOR_SUBMISSIONS)


func _resolve_and_reveal() -> void:
	if _revealed:
		return                                 # a round is resolved exactly once
	last_result = game.resolve_round(_bids)
	if not bool(last_result.get("ok", false)):
		push_error("AuctionMatch: round could not be resolved: %s" % last_result.get("error", "?"))
		_enter_game_over()
		return
	_revealed = true
	_set_state(S.BID_REVEAL, config.reveal_seconds)
	round_revealed.emit(last_result)


func _next_elimination() -> void:
	if _elim_queue.is_empty():
		_after_round()
		return
	var entry: Dictionary = _elim_queue.pop_front()
	_set_state(S.ELIMINATION_CHECK, config.elimination_seconds)
	player_eliminated.emit(int(entry["id"]), str(entry["reason"]))


func _after_round() -> void:
	if game.state == BalanceScaleGame.State.ENDED:
		_enter_game_over()
	else:
		_set_state(S.NEXT_ROUND_PREP, config.next_round_seconds)


func _enter_game_over() -> void:
	if state == S.GAME_OVER:
		return
	_set_state(S.GAME_OVER, 0.0)
	game_finished.emit(game.winner_id)


func _set_state(new_state: int, duration: float) -> void:
	state = new_state
	time_total = duration
	time_left = duration
	state_changed.emit(state, game.round_number if game != null else 0)


## BIDDING -> WAITING_FOR_SUBMISSIONS keeps the same deadline.
func _set_state_keep_time(new_state: int) -> void:
	state = new_state
	state_changed.emit(state, game.round_number)
