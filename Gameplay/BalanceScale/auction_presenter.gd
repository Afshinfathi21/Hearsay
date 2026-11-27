class_name AuctionPresenter
extends Node
## Connects an AuctionMatch to everything the player sees and hears: HUD, bid panel, pots,
## table bid screens, the wall display, bot characters and sound. It contains no rules.
##
## Flow: the human sits (SeatingController) -> bots take the other chairs -> the match starts.

@export var seating: SeatingController
@export var hud: GameHUD
@export var seats_root: Node3D
@export var pots_root: Node3D
@export var table: Node3D
@export var round_display: Node3D
@export var lights_root: Node3D
@export var config: BalanceScaleConfig
@export_range(1, 3) var bot_count := 3

const BOT_NAMES: Array[String] = ["MIRA", "JONAS", "ILSE"]
const SIDES := ["E", "S", "W", "N"]

var auction: AuctionMatch
var human_id := 1

var _sfx: Sfx
var _bid_panel: BidPanel
var _board: MatchBoard
var _wall: ScreenDisplay
var _table_screens: Dictionary = {}     # seat index -> ScreenDisplay
var _avatars: Dictionary = {}           # player id -> BotAvatar
var _pots: Array[AcidPot] = []
var _glows: Array[OmniLight3D] = []
var _seat_of_player: Dictionary = {}    # player id -> seat index
var _clock := 0.0
var _last_tick := -1


func _ready() -> void:
	if config == null:
		config = BalanceScaleConfig.new()
	_sfx = Sfx.new()
	add_child(_sfx)
	_bid_panel = BidPanel.new()
	add_child(_bid_panel)
	_bid_panel.bid_chosen.connect(_on_human_bid)
	_board = MatchBoard.new()
	add_child(_board)

	if seats_root != null:
		for seat in seating.seats:
			var side := seat.name.trim_prefix("Seat_")
			var pot := pots_root.get_node_or_null("Pot_" + side) as AcidPot
			_pots.append(pot)
			_glows.append(lights_root.get_node_or_null("PotGlow_" + side) as OmniLight3D if lights_root else null)
	_build_screens()
	if hud != null and hud.inventory_bar != null:
		hud.inventory_bar.hide()   # item slots are not used in this level

	seating.all_seated.connect(_on_all_seated)
	if hud != null:
		hud.modal_opened.connect(func() -> void: _bid_panel.input_enabled = false)
		hud.modal_closed.connect(func() -> void: _bid_panel.input_enabled = true)


func _process(delta: float) -> void:
	if auction == null:
		return
	_clock += delta
	if _clock >= 0.2:
		_clock = 0.0
		_refresh_timer_displays()
	if auction.state == AuctionMatch.S.BIDDING or auction.state == AuctionMatch.S.WAITING_FOR_SUBMISSIONS:
		var left := int(ceil(auction.time_left))
		if left <= 5 and left != _last_tick and left > 0 and not _bid_panel.locked:
			_last_tick = left
			_sfx.play("tick")


# ------------------------------------------------------------------ start

func _on_all_seated() -> void:
	var humans := seating.get_players()
	if humans.is_empty():
		return
	var human: Node3D = humans[0]
	human_id = multiplayer.get_unique_id()
	var human_seat_idx := seating.seats.find(human.seat)

	var list: Array[Dictionary] = [{"id": human_id, "name": "YOU", "is_bot": false, "seat": human_seat_idx, "personality": ""}]
	var free: Array[int] = []
	for i in seating.seats.size():
		if i != human_seat_idx:
			free.append(i)
	var bots := mini(bot_count, free.size())
	for b in bots:
		var bot_id := human_id + 1 + b
		list.append({"id": bot_id, "name": BOT_NAMES[b], "is_bot": true, "seat": free[b],
			"personality": BotBidder.PERSONALITIES[b % BotBidder.PERSONALITIES.size()]})
		var avatar := BotAvatar.new()
		add_child(avatar)
		avatar.sit_on(seating.seats[free[b]], BOT_NAMES[b])
		seating.seats[free[b]].take(avatar)
		_avatars[bot_id] = avatar
	for p in list:
		_seat_of_player[p["id"]] = p["seat"]

	# Chairs and pots nobody uses are switched off.
	for i in _pots.size():
		var used := false
		for p in list:
			if p["seat"] == i:
				used = true
		if not used:
			if _pots[i]: _pots[i].visible = false
			if _glows[i]: _glows[i].visible = false
			if i in _table_screens: (_table_screens[i] as ScreenDisplay).show_text("", "", "", Color.DIM_GRAY)

	auction = AuctionMatch.new()
	add_child(auction)
	auction.state_changed.connect(_on_state_changed)
	auction.bid_locked.connect(_on_bid_locked)
	auction.round_revealed.connect(_on_round_revealed)
	auction.winner_announced.connect(_on_winner_announced)
	auction.acid_applied.connect(_on_acid_applied)
	auction.player_eliminated.connect(_on_player_eliminated)
	auction.game_finished.connect(_on_game_finished)
	if not auction.setup(list, config):
		push_error("AuctionPresenter: could not start the match.")
		return
	for i in _pots.size():
		if _pots[i] and _pots[i].visible:
			_pots[i].reset()
			_pots[i].set_danger(0)
	_refresh_all()
	auction.start_rounds()


# ------------------------------------------------------------------ match events

func _on_state_changed(new_state: int, round_number: int) -> void:
	_last_tick = -1
	match new_state:
		AuctionMatch.S.ROUND_INTRO:
			_sfx.play("round")
			_notify("ROUND %d" % round_number, "")
			_set_all_table_screens("ROUND %d" % round_number, "·", "", Color(0.7, 0.8, 0.9))
		AuctionMatch.S.PENALTY_ANNOUNCE:
			_sfx.play("penalty")
			var pen := auction.game.current_penalty()
			_notify("PENALTY  -%d" % pen, "EVERY LOSER PAYS %d POINTS" % pen)
		AuctionMatch.S.BIDDING:
			_open_bid_panel()
			for i in _table_screens:
				if _pot_in_use(i):
					(_table_screens[i] as ScreenDisplay).show_text("BID", "…", "THINKING", Color(0.7, 0.8, 0.9))
		AuctionMatch.S.WAITING_FOR_SUBMISSIONS:
			pass
		AuctionMatch.S.NEXT_ROUND_PREP:
			pass
	_refresh_all()


func _on_bid_locked(id: int, auto: bool) -> void:
	var seat: int = _seat_of_player.get(id, -1)
	if seat in _table_screens:
		(_table_screens[seat] as ScreenDisplay).show_text("BID", "LOCKED", "AUTO: 0" if auto else "SECRET", Color(1.0, 0.8, 0.3), Color(0.08, 0.06, 0.02))
	if id == human_id:
		if not _bid_panel.locked:
			_bid_panel.show_locked(0 if auto else _bid_panel.value)
		_sfx.play("lock")
	_refresh_all()


func _on_round_revealed(result: Dictionary) -> void:
	_bid_panel.close()
	_sfx.play("reveal")
	var bids: Dictionary = result["bids"]
	var order: Array = bids.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return int(_seat_of_player.get(a, 0)) < int(_seat_of_player.get(b, 0)))
	for i in order.size():
		var id: int = order[i]
		var seat: int = _seat_of_player.get(id, -1)
		get_tree().create_timer(0.5 * i).timeout.connect(func() -> void:
			if seat in _table_screens and is_instance_valid(self):
				(_table_screens[seat] as ScreenDisplay).show_text("BID", str(bids[id]), _name_of(id), Color(1.0, 0.95, 0.8), Color(0.05, 0.05, 0.06)))
	_refresh_all()


func _on_winner_announced(result: Dictionary) -> void:
	if result["standoff"]:
		_sfx.play("standoff")
		_notify("STANDOFF", "NO WINNER. EVERYONE PAYS %d POINTS" % result["penalty"])
		for i in _table_screens:
			if _pot_in_use(i):
				var id := _player_at_seat(i)
				if id != -1 and result["bids"].has(id):
					(_table_screens[i] as ScreenDisplay).show_text("STANDOFF", str(result["bids"][id]), "PAYS %d" % result["penalty"], Color(1.0, 0.6, 0.2), Color(0.1, 0.05, 0.0))
	else:
		var wid: int = result["winner_id"]
		_sfx.play("win")
		_notify("%s WINS THE ROUND" % _name_of(wid), "WINNING BID %d  ·  PAYS %d" % [result["winning_bid"], result["winning_bid"]])
		var seat: int = _seat_of_player.get(wid, -1)
		if seat in _table_screens:
			(_table_screens[seat] as ScreenDisplay).show_text("WINNER", str(result["winning_bid"]), _name_of(wid), Color(0.5, 1.0, 0.4), Color(0.0, 0.1, 0.02))
	_refresh_all()


func _on_acid_applied(result: Dictionary) -> void:
	var capacity := config.capacity
	var any_acid := false
	for id in result["deltas"]:
		var d: Dictionary = result["deltas"][id]
		var seat: int = _seat_of_player.get(id, -1)
		var acid: int = result["players"][id]["acid"]
		if seat >= 0 and seat < _pots.size() and _pots[seat] != null:
			if d["acid"] != 0:
				any_acid = true
				_pots[seat].pour_to(minf(float(acid) / float(capacity), 1.175), 2.2)
			elif d["acid"] == 0 and acid == 0:
				_pots[seat].set_fill(0.0)
			_apply_danger(seat, acid)
		if id == human_id:
			var pts: int = int(d["points"])
			if pts < 0:
				_hud_event({"type": "points_deducted", "amount": -pts, "detail": "STANDOFF" if result["standoff"] else ("YOUR BID" if id == result["winner_id"] else "ROUND PENALTY")})
			if d["acid"] > 0:
				_notify("+%d ACID" % d["acid"], "YOUR POT IS AT %d / %d" % [acid, capacity])
	if any_acid:
		_sfx.play("acid")
	_refresh_all()


func _apply_danger(seat: int, acid: int) -> void:
	var level := _danger_level(acid)
	if _pots[seat] != null:
		_pots[seat].set_danger(level)
	if _glows[seat] != null:
		var colors := [Color(0.6, 1.0, 0.3), Color(0.95, 0.85, 0.2), Color(1.0, 0.5, 0.12), Color(1.0, 0.16, 0.1)]
		var glow := _glows[seat]
		var tween := create_tween().set_parallel(true)
		tween.tween_property(glow, "light_color", colors[mini(level, 3)], 0.8)
		tween.tween_property(glow, "light_energy", [0.9, 1.3, 1.8, 2.6][mini(level, 3)], 0.8)
	if level >= 3 and acid > 0:
		_sfx.play("alarm")


func _danger_level(acid: int) -> int:
	var cap := config.capacity
	if acid >= cap:
		return 3
	var ratio := float(acid) / float(cap)
	if ratio >= 0.8: return 2
	if ratio >= 0.6: return 1
	return 0


func _on_player_eliminated(id: int, reason: String) -> void:
	var seat: int = _seat_of_player.get(id, -1)
	if seat >= 0 and seat < _pots.size() and _pots[seat] != null:
		_pots[seat].release()
	if _avatars.has(id):
		(_avatars[id] as BotAvatar).eliminate()
	if seat in _table_screens:
		(_table_screens[seat] as ScreenDisplay).show_text("OUT", "✕", _reason_text(reason), Color(1.0, 0.3, 0.25), Color(0.1, 0.0, 0.0))
	_sfx.play("eliminate")
	if id == human_id:
		var pts := int(auction.game.points[id]) if auction != null else 0
		hud.show_elimination({"reason": _reason_text(reason), "points": maxi(pts, 0), "spectate": true})
		_bid_panel.close()
	else:
		_hud_event({"type": "eliminated", "player": _name_of(id), "reason": _reason_text(reason)})
	_refresh_all()


func _on_game_finished(winner_id: int) -> void:
	_bid_panel.close()
	_sfx.play("gameover" if winner_id != human_id else "win")
	seating.end_game()
	if winner_id == human_id:
		hud.show_victory({
			"points": int(auction.game.points[human_id]), "place": 1, "total_players": auction.players.size(),
			"can_spectate": false,
			"stats": [
				{"label": "Rounds", "value": "%02d" % maxi(auction.game.round_number - 1, 0)},
				{"label": "Acid", "value": str(auction.game.acid[human_id])},
			],
		})
	else:
		_notify("GAME OVER", "%s SURVIVES THE BALANCE SCALE" % _name_of(winner_id) if winner_id != -1 else "NOBODY SURVIVED")
	_set_all_table_screens("GAME OVER", _name_of(winner_id) if winner_id != -1 else "-", "SURVIVOR", Color(0.5, 1.0, 0.4))
	_refresh_all()


# ------------------------------------------------------------------ human input

func _open_bid_panel() -> void:
	var view := auction.private_view(human_id)
	if view.is_empty() or bool(view["eliminated"]):
		return
	_bid_panel.open(int(view["points"]), auction.game.current_penalty(), bool(view["next_loss_is_fatal"]))


func _on_human_bid(amount: int) -> void:
	if auction.submit_bid(human_id, amount):
		_bid_panel.show_locked(amount)


# ------------------------------------------------------------------ views

func _refresh_all() -> void:
	if auction == null:
		return
	var view := auction.public_view()
	_board.update_view(view, human_id)
	_push_hud(view)
	_refresh_timer_displays()


func _push_hud(view: Dictionary) -> void:
	var list: Array = []
	var priv := auction.private_view(human_id)
	for p in view["players"]:
		var entry := {"id": p["id"], "name": p["name"], "alive": p["alive"]}
		if p["id"] == human_id and not priv.is_empty():
			entry["points"] = priv["points"]
		list.append(entry)
	var timed: bool = view["time_total"] > 0.0
	hud.apply_state({
		"local_id": human_id, "round": view["round"], "phase": view["state_label"],
		"time_left": view["time_left"] if timed else -1.0, "time_total": view["time_total"] if timed else -1.0,
		"starting_points": config.start_points, "players": list,
	})


func _refresh_timer_displays() -> void:
	if auction == null:
		return
	if _bid_panel.is_open() and not _bid_panel.locked:
		_bid_panel.set_time(auction.time_left, auction.time_total)
	elif _bid_panel.is_open():
		_bid_panel.set_time(auction.time_left, auction.time_total)
	if _wall != null:
		var view := auction.public_view()
		var timer_text := "%d" % int(ceil(view["time_left"])) if view["time_total"] > 0.0 else ""
		var color := Color(0.85, 0.95, 1.0)
		if auction.state == AuctionMatch.S.BIDDING and view["time_left"] <= 5.0:
			color = Color(1.0, 0.3, 0.25)
		if auction.is_over():
			_wall.show_text("THE BALANCE SCALE", "GAME OVER", "", Color(0.5, 1.0, 0.4))
		else:
			_wall.show_text("ROUND %d   ·   LOSERS PAY %d" % [view["round"], view["penalty"]], view["state_label"], timer_text, color)


func _build_screens() -> void:
	if table != null:
		# The table's own names (BidScreen_E/S/W/N) do not follow our chair names, so every chair
		# is matched to the screen that is physically closest to it.
		var screens: Array[MeshInstance3D] = []
		for n in table.find_children("BidScreen_*", "MeshInstance3D", true, false):
			screens.append(n)
		for i in seating.seats.size():
			var seat_pos := seating.seats[i].global_position
			var best: MeshInstance3D = null
			var best_d := INF
			for mesh in screens:
				var c := mesh.global_transform * mesh.get_aabb().get_center()
				var d := Vector2(c.x - seat_pos.x, c.z - seat_pos.z).length()
				if d < best_d:
					best_d = d
					best = mesh
			if best != null:
				var display := ScreenDisplay.new()
				add_child(display)
				# UV: U is 0.37 m (towards the player), V is 0.6 m (across): turn the content a quarter.
				display.attach(best, Vector2i(256, 416), -1)
				display.show_text("BID", "", "", Color(0.4, 0.5, 0.6))
				_table_screens[i] = display
	if round_display != null:
		var screen := round_display.find_child("Screen", true, false) as MeshInstance3D
		if screen != null:
			_wall = ScreenDisplay.new()
			add_child(_wall)
			_wall.attach(screen, Vector2i(1200, 440))
			_wall.show_text("THE BALANCE SCALE", "TAKE A SEAT", "", Color(0.85, 0.95, 1.0))
			# One copy of the display on every wall so each seat can read it; all share one texture.
			# Added after the level has finished setting up its children.
			_add_wall_copies.call_deferred(screen)


func _add_wall_copies(screen: MeshInstance3D) -> void:
	var parent := round_display.get_parent()
	for entry in [[Vector3(4.8, 0, 0), -90.0], [Vector3(-4.8, 0, 0), 90.0], [Vector3(0, 0, 4.8), 180.0]]:
		var copy := round_display.duplicate() as Node3D
		parent.add_child(copy)
		copy.position = Vector3(entry[0].x, round_display.position.y, entry[0].z)
		copy.rotation_degrees = Vector3(0.0, entry[1], 0.0)
		var m := copy.find_child("Screen", true, false) as MeshInstance3D
		if m != null:
			m.material_override = screen.material_override


# ------------------------------------------------------------------ helpers

func _set_all_table_screens(top: String, big: String, bottom: String, color: Color) -> void:
	for i in _table_screens:
		if _pot_in_use(i):
			(_table_screens[i] as ScreenDisplay).show_text(top, big, bottom, color)


func _pot_in_use(seat: int) -> bool:
	return _seat_of_player.values().has(seat)


func _player_at_seat(seat: int) -> int:
	for id in _seat_of_player:
		if _seat_of_player[id] == seat:
			return id
	return -1


func _name_of(id: int) -> String:
	if auction == null:
		return "?"
	var info := auction.player_info(id)
	return "YOU" if id == human_id else str(info.get("name", "?"))


func _reason_text(reason: String) -> String:
	match reason:
		BalanceScaleGame.REASON_POINTS: return "YOUR POINTS FELL BELOW ZERO"
		BalanceScaleGame.REASON_ACID: return "YOUR ACID POT OVERFLOWED"
		BalanceScaleGame.REASON_DISCONNECTED: return "DISCONNECTED"
	return reason.to_upper()


func _notify(title: String, detail: String) -> void:
	_hud_event({"type": "info", "title": title, "detail": detail})


func _hud_event(event: Dictionary) -> void:
	if hud != null:
		hud.notify(event)
