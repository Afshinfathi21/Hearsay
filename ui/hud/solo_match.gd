extends Node

@export var hud: GameHUD
@export var generator: Node3D
@export var player: Node3D
@export var starting_points := 10
@export var door_cost := 1
## Reward items (see Gameplay/Rewards). Trading and re-use are undecided in the design, so they are off.
@export var reward_slots := 4
@export var rewards_tradable := false
@export var rewards_reusable := false

var _points := 0
var _eliminated := false
var _finished := false
var _room_label := ""
var _penalised := {}
var _doors_crossed := 0
var _points_spent := 0
var _start_msec := 0
var _pending_door: StandardDoor
var _rewards := RewardManager.new()
var _current_room                           # RoomData of the room the player is in
var _offered := {}                          # room label -> true: the mini-game offer was already shown
var _minigames := {}                        # room label -> DontBlinkRoom

const PLAYER_ID := 1


func _ready() -> void:
	_points = starting_points
	_rewards.slots = reward_slots
	_rewards.tradable = rewards_tradable
	_rewards.reusable = rewards_reusable
	_rewards.add_player(PLAYER_ID)
	_start_msec = Time.get_ticks_msec()
	await get_tree().process_frame

	if generator == null or not ("door_records" in generator):
		generator = _find_generator()
	if generator == null:
		push_error("SoloMatch: could not find the building generator. Put building_generator.gd on your level root and assign it to Generator.")
		return

	if "point_budget" in generator and (generator.point_budget != starting_points or generator.door_cost != door_cost):
		push_warning("SoloMatch: starting_points/door_cost differ from the generator's point_budget/door_cost; the route guarantee only holds when they match.")

	for rec in generator.door_records:
		if rec.door == null or rec.is_exit:
			continue
		rec.door.cost = door_cost
		rec.door.passage_validator = _can_cross
		generator.set_door_state(rec, rec.capacity, 0)
		rec.door.interaction_requested.connect(_on_door_interaction_requested)
		rec.door.passage_completed.connect(_on_door_passage_completed.bind(rec.door))
		rec.door.passage_cancelled.connect(_on_door_passage_cancelled.bind(rec.door))
		rec.door.reservation_expired.connect(_on_door_reservation_expired)
		rec.door.passage_rejected.connect(_on_door_passage_rejected)
	generator.room_entered.connect(_on_room_entered)
	generator.exit_reached.connect(_on_exit_reached)
	hud.victory_continue.connect(func() -> void: get_tree().change_scene_to_file("res://Levels/Balance Scale/auction_chamber.tscn"))
	hud.item_use_requested.connect(_on_item_use_requested)
	_current_room = generator.rooms.get(generator.start_room)
	_setup_minigames()
	_push_state()


## The player pressed interact on a door: cancel their reservation if they hold one,
## otherwise try to reserve a place. The door itself checks capacity and lockdown.
func _on_door_interaction_requested(door: StandardDoor, body: Node3D) -> void:
	if body != player or _eliminated or _finished:
		return
	if door.has_reservation(player):
		if door.release_passage(player):
			hud.notify({"type": "info", "title": "RESERVATION CANCELLED", "detail": "YOUR PLACE WAS RELEASED; DOOR COST IS NOT REFUNDED"})
		return
	if _pending_door != null:
		hud.notify({"type": "info", "title": "ONE DOOR AT A TIME", "detail": "CANCEL YOUR CURRENT RESERVATION FIRST"})
		return
	_pending_door = door
	if not door.reserve_passage(player):
		_pending_door = null
		return
	_spend(door.cost, "DOOR")


## Asked by the door when the paid reservation holder enters the doorway.
## The cost was already deducted when the reservation opened the door.
func _can_cross(body: Node3D, door: StandardDoor) -> bool:
	return body == player and _pending_door == door and not _eliminated and not _finished


func _on_door_reservation_expired(body: Node3D) -> void:
	if body == player:
		_pending_door = null
		hud.notify({"type": "info", "title": "RESERVATION EXPIRED", "detail": "YOU DID NOT CROSS THE DOOR"})


func _on_door_passage_rejected(body: Node3D) -> void:
	if body == player:
		_pending_door = null
		hud.notify({"type": "info", "title": "PASSAGE REJECTED", "detail": "YOU NO LONGER MEET THE REQUIREMENTS"})


func _on_door_passage_completed(body: Node3D, door: StandardDoor) -> void:
	if body != player or _pending_door != door:
		return
	_pending_door = null
	_doors_crossed += 1


func _on_door_passage_cancelled(body: Node3D, door: StandardDoor) -> void:
	if body == player and _pending_door == door:
		_pending_door = null


func _on_room_entered(room, body: Node3D) -> void:
	if body != player or _eliminated or _finished:
		return
	_room_label = room.label
	_current_room = room
	if not _penalised.has(room.label):
		_penalised[room.label] = true
		_apply_room_effect(room)
	if room.minigame and not _eliminated and not _offered.has(room.label) and not _rewards.minigame_claimed(PLAYER_ID, room.label):
		_offered[room.label] = true
		hud.notify({"type": "info", "title": "MINI-GAME: DON'T BLINK", "detail": "ROOM " + room.label + ": STEP ON THE AMBER PAD. OPTIONAL"})
	_push_state()


## A room's effect hits the player once, when they first enter it. Armed protections are applied here.
func _apply_room_effect(room) -> void:
	if room.penalty == generator.PENALTY_LOSE_POINTS:
		var hit := _rewards.resolve_lose_points(PLAYER_ID, room.amount)
		if hit["by"] != "":
			hud.notify({"type": "protected", "title": "PENALTY BLOCKED" if hit["blocked"] else "PENALTY REDUCED",
				"detail": "ROOM " + room.label})
		if int(hit["amount"]) > 0:
			_spend(int(hit["amount"]), "ROOM " + room.label)
	elif room.penalty == generator.PENALTY_SKIP_ROUND:
		if _rewards.resolve_lockdown(PLAYER_ID):
			hud.notify({"type": "protected", "title": "LOCKDOWN AVOIDED", "detail": "ROOM " + room.label})
		else:
			hud.notify({"type": "lockdown", "rounds": room.amount, "detail": "ROOM " + room.label})


## Host API for mini-games: the game played in `room_label` ended with won / lost. A win puts one reward item in
## the inventory. Only valid while the player is in that room, so a result cannot be claimed from afar.
## Returns the RewardManager result ({ok, reason, kind, title, text, ...}).
func report_minigame_result(room_label: String, won: bool, reward_kind := "") -> Dictionary:
	var room = _room_by_label(room_label)
	if room == null or not room.minigame or _current_room == null or _current_room.label != room_label \
			or _eliminated or _finished:
		return {"ok": false, "reason": "no_minigame", "kind": "", "uid": 0, "title": "", "text": "NO MINI-GAME HERE", "data": {}}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("reward:%d:%s:%d" % [generator.seed_value, room_label, PLAYER_ID])
	var result := _rewards.complete_minigame(PLAYER_ID, room_label, won, room.zone, rng, false, reward_kind)   # solo: nobody to target
	if result["ok"]:
		hud.notify({"type": "info", "title": "REWARD: " + str(result["title"]), "detail": str(result["text"])})
	else:
		hud.notify({"type": "info", "title": "NO REWARD", "detail": str(result["text"])})
	_push_state()
	return result


## One Don't Blink game per mini-game room. The host reads the result and decides the reward.
func _setup_minigames() -> void:
	for rd in generator.room_list:
		if not rd.minigame:
			continue
		var game_room := DontBlinkRoom.new()
		game_room.name = "DontBlink_" + rd.label
		generator.add_child(game_room)
		game_room.setup(generator, rd, hash("dontblink:%d:%s" % [generator.seed_value, rd.label]))
		game_room.player_won.connect(_on_minigame_won)
		game_room.hud_state_changed.connect(hud.set_minigame)
		_minigames[rd.label] = game_room


## A player reached the exit pad of a Don't Blink room: the reward is a TRAP SCAN (a hint about a nearby room).
func _on_minigame_won(room_label: String, player_id: int) -> void:
	if player_id != PLAYER_ID:
		return
	var result := report_minigame_result(room_label, true, RewardCatalog.TRAP_SCAN)
	if result["ok"] or result["reason"] == "already_done":
		_minigames[room_label].mark_claimed()


## The player pressed an inventory slot: the host validates the use and shows the outcome.
func _on_item_use_requested(slot: int) -> void:
	if _eliminated or _finished:
		return
	var uid := _rewards.inventory_of(PLAYER_ID).slot_uid(slot)
	if uid == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("use:%d:%d:%d" % [generator.seed_value, uid, _doors_crossed])
	var room_coord: Vector2i = _current_room.coord if _current_room != null else generator.start_room
	var result := _rewards.use_item(PLAYER_ID, uid, {"generator": generator, "room": room_coord, "rng": rng})
	if result["ok"]:
		hud.notify({"type": "info", "title": str(result["title"]), "detail": str(result["text"])})
	else:
		hud.notify({"type": "info", "title": "CANNOT USE ITEM", "detail": str(result["text"])})
	_push_state()


func _room_by_label(label: String):
	for rd in generator.room_list:
		if rd.label == label:
			return rd
	return null


@warning_ignore("integer_division")
func _on_exit_reached(body: Node3D) -> void:
	if body != player or _eliminated or _finished:
		return
	_finished = true
	var seconds: int = (Time.get_ticks_msec() - _start_msec) / 1000
	hud.show_victory({
		"points": _points, "place": 1, "total_players": 1, "can_spectate": false,
		"stats": [
			{"label": "Doors crossed", "value": "%02d" % _doors_crossed},
			{"label": "Points spent", "value": "%02d" % _points_spent},
			{"label": "Time", "value": "%02d:%02d" % [seconds / 60, seconds % 60]},
		],
	})


func _spend(amount: int, detail: String) -> void:
	_points = _points - amount
	_points_spent += amount
	hud.notify({"type": "points_deducted", "amount": amount, "detail": detail})
	_push_state()
	if _points < 0 and not _eliminated:
		_eliminated = true
		hud.show_elimination({"reason": "YOU RAN OUT OF POINTS", "points": 0, "spectate": false})
		await get_tree().create_timer(6.0).timeout
		get_tree().reload_current_scene()


func _push_state() -> void:
	hud.set_inventory(_rewards.inventory_of(PLAYER_ID).snapshot(), _rewards.armed_names(PLAYER_ID))
	hud.apply_state({
		"local_id": 1, "round": 1, "phase": "Explore", "starting_points": starting_points,
		"players": [{
			"id": 1, "name": str(GameSettings.get_value("player", "name")),
			"points": _points, "alive": not _eliminated, "room": _room_label,
		}],
	})


func _find_generator() -> Node3D:
	for n in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if "door_records" in n:
			return n as Node3D
	if "door_records" in get_tree().current_scene:
		return get_tree().current_scene as Node3D
	return null
