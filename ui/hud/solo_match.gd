extends Node
## TEMPORARY stand-in for your host logic, so you can play the building alone with the new UI.
## The rules here are PLACEHOLDERS (they are not your game design):
##   * opening a door costs `door_cost` points and takes one of its `door_capacity` places;
##     a full door locks (red); if you cannot pay, the door closes again
##   * walking into a room with a penalty applies it once (lose points / lockdown notice)
##   * reaching 0 points eliminates you; walking out of the exit wins
## In the real game this logic lives on the HOST, and the UI calls stay exactly the same.
##
## Add it as a child of the level and fill in the three slots.

@export var hud: GameHUD
## The building generator node (building_generator.gd).
@export var generator: Node3D
@export var player: Node3D
@export var starting_points := 10
@export var door_cost := 1
@export var door_capacity := 2

var _points := 0
var _eliminated := false
var _finished := false
var _room_label := ""
var _penalised := {}               # room label -> true
var _reserved := {}                # door record -> places taken
var _doors_opened := 0
var _points_spent := 0
var _start_msec := 0


func _ready() -> void:
	_points = starting_points
	_start_msec = Time.get_ticks_msec()
	await get_tree().process_frame     # let the generator finish building the doors

	# The Generator slot must hold the node that has building_generator.gd (your level root).
	# If it holds something else, look for the right node.
	if generator == null or not ("door_records" in generator):
		generator = _find_generator()
	if generator == null:
		push_error("SoloMatch: could not find the building generator. Put building_generator.gd on your level root and assign it to Generator.")
		return

	for rec in generator.door_records:
		if rec.door == null or rec.is_exit:
			continue
		rec.door.cost = door_cost
		generator.set_door_state(rec, door_capacity, 0)
		rec.door.opened.connect(_on_door_opened.bind(rec))
	generator.room_entered.connect(_on_room_entered)
	generator.exit_reached.connect(_on_exit_reached)
	hud.victory_continue.connect(func() -> void: get_tree().reload_current_scene())
	_push_state()


func _on_door_opened(rec) -> void:
	if _eliminated or _finished:
		return
	if _points < door_cost:
		hud.notify({"type": "info", "title": "NOT ENOUGH POINTS", "detail": "THE DOOR CLOSES AGAIN"})
		rec.door.close()
		return
	var taken: int = _reserved.get(rec, 0) + 1
	_reserved[rec] = taken
	generator.set_door_state(rec, door_capacity, taken)
	if taken >= door_capacity:
		rec.door.set_locked(true)
	_doors_opened += 1
	_spend(door_cost, "DOOR")


func _on_room_entered(room, body: Node3D) -> void:
	if body != player or _eliminated or _finished:
		return
	_room_label = room.label
	if not _penalised.has(room.label):
		_penalised[room.label] = true
		if room.penalty == generator.PENALTY_LOSE_POINTS:
			_spend(room.amount, "ROOM " + room.label)
			return
		elif room.penalty == generator.PENALTY_SKIP_ROUND:
			hud.notify({"type": "lockdown", "rounds": room.amount, "detail": "ROOM " + room.label})
	_push_state()


@warning_ignore("integer_division")
func _on_exit_reached(body: Node3D) -> void:
	if body != player or _eliminated or _finished:
		return
	_finished = true
	var seconds: int = (Time.get_ticks_msec() - _start_msec) / 1000
	hud.show_victory({
		"points": _points, "place": 1, "total_players": 1, "can_spectate": false,
		"stats": [
			{"label": "Doors opened", "value": "%02d" % _doors_opened},
			{"label": "Points spent", "value": "%02d" % _points_spent},
			{"label": "Time", "value": "%02d:%02d" % [seconds / 60, seconds % 60]},
		],
	})


func _spend(amount: int, detail: String) -> void:
	_points = maxi(_points - amount, 0)
	_points_spent += amount
	hud.notify({"type": "points_deducted", "amount": amount, "detail": detail})
	_push_state()
	if _points <= 0 and not _eliminated:
		_eliminated = true
		hud.show_elimination({"reason": "YOU RAN OUT OF POINTS", "points": 0, "spectate": false})
		await get_tree().create_timer(6.0).timeout
		get_tree().reload_current_scene()


func _push_state() -> void:
	hud.apply_state({
		"local_id": 1, "round": 1, "phase": "Explore", "starting_points": starting_points,
		"players": [{
			"id": 1, "name": str(GameSettings.get_value("player", "name")),
			"points": _points, "alive": not _eliminated, "room": _room_label,
		}],
	})


## The first node in the scene that has building_generator.gd on it.
func _find_generator() -> Node3D:
	for n in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if "door_records" in n:
			return n as Node3D
	if "door_records" in get_tree().current_scene:
		return get_tree().current_scene as Node3D
	return null
