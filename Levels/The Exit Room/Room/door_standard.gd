class_name StandardDoor
extends Node3D

signal opened
signal closed
signal interaction_requested(door: StandardDoor, body: Node3D)
signal passage_completed(body: Node3D)
signal passage_cancelled(body: Node3D)

const CLIP := "Door_Open"
const AMBER := Color("FFA21F")
const RED := Color("E5201B")
const INTERACT_LAYER := 1 << 1

var is_open := false
var is_locked := false
var _target_open := false
var _anim: AnimationPlayer
var _lights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D
var _passage_zone: Area3D

@export var cost := 1
@export_range(1.0, 60.0, 0.5) var reservation_timeout := 15.0
var capacity := 0
var reserved := 0
var is_exit := false

# Instance ID -> reserved player. A reservation is not charged until the player crosses.
var _reservations: Dictionary = {}
# Instance ID -> side from which the player entered the doorway.
var _crossing_from: Dictionary = {}
var _release_after_crossing: Dictionary = {}


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
	_make_interact_zone()
	_make_passage_zone()


## Request a passage slot. The game controller decides whether this player may reserve it.
func interact(body: Node3D = null) -> void:
	if body == null or _anim.is_playing() or is_locked or reserved >= capacity:
		return
	interaction_requested.emit(self, body)


## Called by the game controller after validating points, capacity and player state.
func reserve_passage(body: Node3D) -> bool:
	if body == null or not is_instance_valid(body) or is_exit:
		return false
	var id := body.get_instance_id()
	if _reservations.has(id) or reserved >= capacity:
		return false
	_reservations[id] = body
	reserved = _reservations.size()
	_refresh_monitor()
	if not is_open and not _target_open:
		open()
	return true


func has_reservation(body: Node3D) -> bool:
	return body != null and _reservations.has(body.get_instance_id())


## A timeout/cancellation cannot release a player who is physically inside the doorway.
## Their reservation is released when they leave the trigger; a full crossing still completes.
func release_passage(body: Node3D) -> bool:
	if body == null:
		return false
	var id := body.get_instance_id()
	if not _reservations.has(id):
		return false
	if _crossing_from.has(id):
		_release_after_crossing[id] = true
		return false
	_remove_reservation(id)
	passage_cancelled.emit(body)
	_close_if_empty()
	return true


func open() -> void:
	if is_open or _target_open or _anim.is_playing():
		return
	_target_open = true
	_anim.play(CLIP)


func close() -> void:
	if not is_open or _anim.is_playing():
		return
	_target_open = false
	_anim.play_backwards(CLIP)


func set_locked(locked: bool) -> void:
	is_locked = locked
	_light_mat.emission = RED if locked else AMBER


func set_round_state(new_capacity: int, _new_reserved: int) -> void:
	capacity = maxi(new_capacity, 0)
	reserved = _reservations.size()
	_refresh_monitor()


func get_hud_info() -> Dictionary:
	return {"cost": cost, "capacity": capacity, "reserved": reserved, "locked": is_locked, "exit": is_exit}


func _refresh_monitor() -> void:
	if is_exit:
		return
	var open_slots := maxi(capacity - reserved, 0)
	set_locked(open_slots <= 0)
	for monitor in get_meta("monitors", []):
		monitor.show_number(capacity)
		monitor.set_capacity(open_slots)
		monitor.set_locked(open_slots <= 0)


func _remove_reservation(id: int) -> void:
	_reservations.erase(id)
	_crossing_from.erase(id)
	_release_after_crossing.erase(id)
	reserved = _reservations.size()
	_refresh_monitor()


func _close_if_empty() -> void:
	if reserved == 0 and is_open:
		close()


func _on_finished(_name: StringName) -> void:
	is_open = _target_open
	if is_open:
		opened.emit()
		# A reservation may have expired while the opening animation was playing.
		if reserved == 0:
			call_deferred("close")
	else:
		closed.emit()


func _on_passage_entered(body: Node3D) -> void:
	var id := body.get_instance_id()
	if not _reservations.has(id):
		return
	var local_z := to_local(body.global_position).z
	_crossing_from[id] = signf(local_z)


func _on_passage_exited(body: Node3D) -> void:
	var id := body.get_instance_id()
	if not _crossing_from.has(id):
		return
	var entered_side: float = _crossing_from[id]
	var exited_side := signf(to_local(body.global_position).z)
	if exited_side != 0.0 and exited_side != entered_side:
		_remove_reservation(id)
		passage_completed.emit(body)
	else:
		_remove_reservation(id)
		passage_cancelled.emit(body)
	_close_if_empty()


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
