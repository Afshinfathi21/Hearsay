class_name StandardDoor
extends Node3D
## Drives Doors/door_standard.glb. RoomGrid.spawn_doors() attaches this to the imported scene.
##
## An ordinary door is a limited-capacity passage, not a door players open freely:
##   closed -> paid reservation -> opening -> crossing -> closing -> reset
##
##   * capacity is PER ROUND: every completed crossing uses one place until reset_round().
##     available = capacity - passed - reserved.
##   * reserve_passage() is called by the host (the game controller) after it validated the player.
##     It opens the door and lets that player (only) through the PassageGate barrier.
##   * Crossing is detected by the PassageZone: the player must enter on one side and leave on the
##     other. Proximity alone never counts. The host charges the cost when it grants the reservation;
##     that payment is not refunded if the reservation expires, is cancelled or the player backs out.
##     passage_completed fires once after a successful crossing.
##   * The door closes by itself as soon as no reservation is left. A player who already passed the
##     middle of the doorway is never released or locked out; they finish crossing safely.
##   * The real exit door is separate: it has no capacity or cost and simply toggles open/closed.
##
## Everything that changes game state (reserve, release, reset_round, set_locked) is a plain method
## call, so a host-authoritative network layer can drive it later. The door never touches points.

signal opened
signal closed
## The player pressed interact on the door. The host decides whether to reserve or cancel.
signal interaction_requested(door: StandardDoor, body: Node3D)
## The body crossed the doorway completely. The host charges the cost here.
signal passage_completed(body: Node3D)
## A reservation ended WITHOUT a crossing (cancelled, expired, backed out, rejected, round reset).
signal passage_cancelled(body: Node3D)
## Specific reasons, emitted just before passage_cancelled so the host can show a message.
signal reservation_expired(body: Node3D)
signal passage_rejected(body: Node3D)

const CLIP := "Door_Open"
const AMBER := Color("FFA21F")
const RED := Color("E5201B")
const INTERACT_LAYER := 1 << 1          # physics layer 2: the ray that finds the door
const GATE_LAYER := 1                   # physics layer 1: what the player collides with

## Points one passage reservation costs (charged by the host when the door opens for that player).
@export var cost := 1
## Seconds a reservation stays valid if the player does not cross.
@export_range(1.0, 60.0, 0.5) var reservation_timeout := 15.0

## Places per round, places already used by completed crossings, and reservations being held.
var capacity := 0
var passed := 0
var reserved := 0
## Places that can still be reserved.
var available: int:
	get:
		return maxi(capacity - passed - reserved, 0)

var is_open := false
## Administrative lock (lockdown). Not the same as "full": a full door has available == 0.
var is_locked := false
## A generated seal is distinct from a temporary administrative lockdown.
var generation_locked := false
var generation_lock_type := "none"
var room_a_label := ""
var room_b_label := ""
var room_a_center := Vector3.ZERO
var room_b_center := Vector3.ZERO
## True for the one real exit door (the building generator sets it).
var is_exit := false:
	set(value):
		is_exit = value
		_update_gate()

## Host hook: Callable(body: Node3D, door: StandardDoor) -> bool. Asked when a reserved player
## enters the doorway. Return false (e.g. not enough points any more) to cancel the crossing.
var passage_validator := Callable()

var _target_open := false               # what the door should be; the animation follows it
var _opening := false                   # direction of the animation that is running
var _anim: AnimationPlayer
var _lights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D
var _passage_zone: Area3D
var _gate: StaticBody3D

# Instance ID -> body that has paid for and reserved a place.
var _reservations: Dictionary = {}
# Instance ID -> time (door clock) when the reservation expires.
var _expires: Dictionary = {}
# Instance ID -> side (+1 / -1) of the doorway the body entered from.
var _entered_side: Dictionary = {}
var _clock := 0.0


func _ready() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_anim.animation_finished.connect(_on_finished)
	for n in ["Door_Status_Light_Front", "Door_Status_Light_Back"]:
		_lights.append(find_child(n, true, false) as MeshInstance3D)
	_light_mat = (_lights[0].mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_light_mat.emission_enabled = true
	_light_mat.emission_energy_multiplier = 3.0
	for light in _lights:
		light.material_override = _light_mat
	set_locked(false)
	add_to_group("door")
	set_physics_process(false)
	_make_interact_zone()
	_make_passage_zone()
	_make_gate()


## What the player's interact key calls. Ordinary doors only ask the host (reserve or cancel);
## the exit door just toggles.
func interact(body: Node3D = null) -> void:
	if is_exit:
		if not is_locked:
			if _target_open:
				close()
			else:
				open()
		return
	if body == null or is_locked or generation_locked:
		return
	if has_reservation(body) or available > 0:
		interaction_requested.emit(self, body)


## Host: give this body a place. The door opens and only reservation holders can pass.
## The host must already have checked the player (alive, enough points, one reservation at a time).
func reserve_passage(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body) or is_exit or is_locked or generation_locked:
		return false
	var id := body.get_instance_id()
	if _reservations.has(id) or available <= 0:
		return false
	_reservations[id] = body
	_expires[id] = _clock + reservation_timeout
	reserved = _reservations.size()
	_allow_through(body, true)
	set_physics_process(true)
	_refresh_monitor()
	_target_open = true
	_sync_anim()
	# The player may already be standing in the doorway when the reservation is made.
	if body is CollisionObject3D and _passage_zone.overlaps_body(body):
		_begin_crossing(body)
	return true


func has_reservation(body: Node3D) -> bool:
	return body != null and _reservations.has(body.get_instance_id())


## Host or player: give the place back. Free of charge. Refused (false) only when the body has
## already passed the middle of the doorway: it is crossing and must be allowed to finish.
func release_passage(body: Node3D) -> bool:
	if body == null:
		return false
	var id := body.get_instance_id()
	if not _reservations.has(id) or _past_midplane(id):
		return false
	_remove_reservation(id)
	passage_cancelled.emit(body)
	_close_if_empty()
	return true


## Start a new round: unused reservations are released (free), places are restored and the
## door closes. Bodies already crossing finish safely. new_capacity < 0 keeps the capacity.
func reset_round(new_capacity := -1) -> void:
	for id in _reservations.keys():
		if _past_midplane(id):
			continue
		var body = _reservations[id]
		_remove_reservation(id)
		if is_instance_valid(body):
			passage_cancelled.emit(body)
	passed = 0
	if new_capacity >= 0:
		capacity = new_capacity
	_refresh_monitor()
	_close_if_empty()


func open() -> void:
	_target_open = true
	_sync_anim()


func close() -> void:
	_target_open = false
	_sync_anim()


## Administrative lock (lockdown): nobody can reserve while locked. Separate from "full".
func set_locked(locked: bool) -> void:
	is_locked = locked
	_refresh_monitor()


## Set or clear a lock assigned by procedural generation. Sealed doors have zero capacity.
func set_generation_lock(locked: bool, lock_type := "sealed") -> void:
	generation_locked = locked
	generation_lock_type = lock_type if locked else "none"
	if locked:
		capacity = 0
		passed = 0
	_refresh_monitor()


## A key, reward or minigame can open a generated seal by granting fresh places.
func unlock_generation_lock(new_capacity: int) -> bool:
	if not generation_locked or new_capacity <= 0:
		return false
	generation_locked = false
	generation_lock_type = "none"
	capacity = new_capacity
	passed = 0
	_refresh_monitor()
	return true


## Host: set the places for this round. The second argument is kept for older callers;
## reservations are always counted by the door itself.
func set_round_state(new_capacity: int, _new_reserved: int = 0) -> void:
	capacity = maxi(new_capacity, 0)
	_refresh_monitor()


func set_adjacent_room_info(a_label: String, b_label: String, a_center: Vector3, b_center: Vector3) -> void:
	room_a_label = a_label
	room_b_label = b_label
	room_a_center = a_center
	room_b_center = b_center


func get_hud_info(observer_position := Vector3.ZERO) -> Dictionary:
	var room_behind := room_b_label
	if observer_position.distance_squared_to(room_b_center) < observer_position.distance_squared_to(room_a_center):
		room_behind = room_a_label
	return {"cost": cost, "capacity": capacity, "reserved": reserved, "passed": passed,
		"available": available, "locked": is_locked or generation_locked,
		"administrative_locked": is_locked, "generation_locked": generation_locked,
		"lock_type": generation_lock_type, "exit": is_exit, "room_behind": room_behind}


func _physics_process(delta: float) -> void:
	_clock += delta
	for id in _expires.keys():
		if _clock < float(_expires[id]):
			continue
		var body = _reservations.get(id)
		if body == null or not is_instance_valid(body):
			_remove_reservation(id)
			continue
		if _past_midplane(id):
			continue                        # crossing right now: let them finish
		_remove_reservation(id)
		reservation_expired.emit(body)
		passage_cancelled.emit(body)
	_close_if_empty()


# ---- crossing detection ----------------------------------------------------------------------
func _on_passage_entered(body: Node3D) -> void:
	if _reservations.has(body.get_instance_id()):
		_begin_crossing(body)


func _on_passage_exited(body: Node3D) -> void:
	var id := body.get_instance_id()
	if not _reservations.has(id) or not _entered_side.has(id):
		return
	var crossed := body.is_inside_tree() and _side_of(body) != float(_entered_side[id])
	if crossed:
		passed += 1
		_remove_reservation(id)
		passage_completed.emit(body)
		_close_if_empty()
		return
	# The moving door can push a player out of PassageZone before they cross the
	# doorway. Do not interpret that animation-induced exit as backing out: keep
	# their reservation and the door open so they can continue or re-enter.
	if _opening:
		return
	_remove_reservation(id)
	passage_cancelled.emit(body)         # backed out on the side they came from
	_close_if_empty()


## The reserved body is in the doorway: ask the host whether the crossing is still valid.
func _begin_crossing(body: Node3D) -> void:
	var id := body.get_instance_id()
	# A stale or duplicated reservation must never let the number of completed crossings
	# exceed the capacity shown on the monitor.
	if passed >= capacity:
		_remove_reservation(id)
		passage_rejected.emit(body)
		passage_cancelled.emit(body)
		_close_if_empty()
		return
	if passage_validator.is_valid() and not bool(passage_validator.call(body, self)):
		_remove_reservation(id)
		passage_rejected.emit(body)
		passage_cancelled.emit(body)
		_close_if_empty()
		return
	_entered_side[id] = _side_of(body)


func _side_of(body: Node3D) -> float:
	return 1.0 if to_local(body.global_position).z >= 0.0 else -1.0


## True once the body is on the far side of the doorway's middle plane.
func _past_midplane(id: int) -> bool:
	var body = _reservations.get(id)
	if body == null or not is_instance_valid(body) or not _entered_side.has(id):
		return false
	return _side_of(body) != float(_entered_side[id])


# ---- internals -------------------------------------------------------------------------------
func _remove_reservation(id: int) -> void:
	var body = _reservations.get(id)
	if body != null and is_instance_valid(body):
		_allow_through(body, false)
	_reservations.erase(id)
	_expires.erase(id)
	_entered_side.erase(id)
	reserved = _reservations.size()
	if _reservations.is_empty():
		set_physics_process(false)
	_refresh_monitor()


func _close_if_empty() -> void:
	if reserved == 0 and not is_exit:
		_target_open = false
		_sync_anim()


## The animation follows _target_open. If the target changes while the door is moving (a
## reservation made during the closing animation, say), the animation reverses from where it
## is instead of finishing first, so the door reacts at once and never ends up in the wrong state.
func _sync_anim() -> void:
	if _anim.is_playing():
		if _target_open != _opening:
			_opening = _target_open
			if _opening:
				_anim.play(CLIP)
			else:
				_anim.play_backwards(CLIP)
		return
	if _target_open and not is_open:
		_opening = true
		_anim.play(CLIP)
	elif not _target_open and is_open:
		_opening = false
		_anim.play_backwards(CLIP)


func _on_finished(_name: StringName) -> void:
	is_open = _opening
	if is_open:
		opened.emit()
	else:
		closed.emit()
	_sync_anim.call_deferred()


## Monitors show the capacity digits and one pip per available place. Lamp and digits turn red
## when the door is locked or full. The exit door's monitors keep their green EXIT sign.
func _refresh_monitor() -> void:
	var unavailable := is_locked or generation_locked or (not is_exit and available <= 0)
	if _light_mat != null:
		_light_mat.emission = RED if unavailable else AMBER
	if is_exit:
		return
	for monitor in get_meta("monitors", []):
		monitor.show_number(capacity)
		monitor.set_capacity(available)
		monitor.set_locked(unavailable)


## Per-player barrier: the gate blocks everybody except bodies holding a reservation.
func _allow_through(body: Node3D, allowed: bool) -> void:
	if _gate == null or not (body is PhysicsBody3D):
		return
	if allowed:
		_gate.add_collision_exception_with(body)
		(body as PhysicsBody3D).add_collision_exception_with(_gate)
	else:
		_gate.remove_collision_exception_with(body)
		(body as PhysicsBody3D).remove_collision_exception_with(_gate)


func _update_gate() -> void:
	if _gate != null:
		_gate.collision_layer = 0 if is_exit else GATE_LAYER


## The raycast target remains available from either side, but this zone never blocks movement.
func _make_interact_zone() -> void:
	var zone := Area3D.new()
	zone.name = "InteractZone"
	zone.collision_layer = INTERACT_LAYER
	zone.collision_mask = 0
	zone.monitoring = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.2, 0.5)
	shape.shape = box
	shape.position = Vector3(0, 1.1, 0)
	zone.add_child(shape)
	add_child(zone)


## Tracks the complete traversal, not merely proximity to the door.
func _make_passage_zone() -> void:
	_passage_zone = Area3D.new()
	_passage_zone.name = "PassageZone"
	_passage_zone.collision_layer = 0
	_passage_zone.collision_mask = 1
	_passage_zone.monitoring = true
	_passage_zone.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.2, 2.0)
	shape.shape = box
	shape.position = Vector3(0, 1.1, 0)
	_passage_zone.add_child(shape)
	add_child(_passage_zone)
	_passage_zone.body_entered.connect(_on_passage_entered)
	_passage_zone.body_exited.connect(_on_passage_exited)


## A thin solid wall across the doorway. Reserved players get a collision exception, so for
## them it does not exist; everybody else is stopped even while the door stands open.
func _make_gate() -> void:
	_gate = StaticBody3D.new()
	_gate.name = "PassageGate"
	_gate.collision_layer = GATE_LAYER
	_gate.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.6, 0.1)
	shape.shape = box
	shape.position = Vector3(0, 1.3, 0)
	_gate.add_child(shape)
	add_child(_gate)
	_update_gate()
