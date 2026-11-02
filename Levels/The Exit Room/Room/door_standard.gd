class_name StandardDoor
extends Node3D
## Drives Doors/door_standard.glb. Attach to the root node of the imported scene
## (RoomGrid.spawn_doors() does this for you).
## The import creates an AnimationPlayer with one clip, "Door_Open":
## bolts retract, then the panel swings 100 degrees toward the back (+Y in Blender).
##
## Interaction: the door adds itself to group "door" and creates an invisible InteractZone
## (an Area3D on physics layer 2) over the doorway. A player's RayCast3D that looks at the
## doorway hits the zone in BOTH states, open or closed. Call interact() to toggle.

signal opened
signal closed

const CLIP := "Door_Open"
const AMBER := Color("FFA21F")
const RED := Color("E5201B")
const INTERACT_LAYER := 1 << 1          # physics layer 2

var is_open := false
var is_locked := false
var _target_open := false
var _anim: AnimationPlayer
var _lights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D

# --- What the HUD prompt and this door's monitor show (the host sets these each round) ---
## Points it costs to pass this door.
@export var cost := 1
## Places this round, and how many are already reserved.
var capacity := 0
var reserved := 0
## True for the one real exit door (the building generator sets it). Its monitors keep
## showing the green EXIT sign, so set_round_state() leaves them alone.
var is_exit := false


func _ready() -> void:
	_anim = find_child("AnimationPlayer", true, false) as AnimationPlayer
	_anim.animation_finished.connect(_on_finished)
	for n in ["Door_Status_Light_Front", "Door_Status_Light_Back"]:
		_lights.append(find_child(n, true, false) as MeshInstance3D)
	_light_mat = (_lights[0].mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	_light_mat.emission_enabled = true
	_light_mat.emission_energy_multiplier = 3.0
	for l in _lights:
		l.material_override = _light_mat
	set_locked(false)
	add_to_group("door")
	_make_interact_zone()


## What the player's interact key calls. Ignored while the door is moving, so mashing the
## key can't restart or reverse the animation half way.
func interact() -> void:
	if _anim.is_playing():
		return
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_locked or is_open:
		return
	_target_open = true
	_anim.play(CLIP)


func close() -> void:
	if not is_open:
		return
	_target_open = false
	_anim.play_backwards(CLIP)


## Locked doors keep their bolts out and show a red status light.
func set_locked(locked: bool) -> void:
	is_locked = locked
	_light_mat.emission = RED if locked else AMBER


## Called by the host whenever this round's capacity or reservations change.
## Updates both monitors (digits = capacity, pips = places still open, red when none are open).
func set_round_state(new_capacity: int, new_reserved: int) -> void:
	capacity = maxi(new_capacity, 0)
	reserved = clampi(new_reserved, 0, capacity)
	_refresh_monitor()


## What the HUD's door prompt shows while the player looks at this door.
func get_hud_info() -> Dictionary:
	return {"cost": cost, "capacity": capacity, "reserved": reserved, "locked": is_locked, "exit": is_exit}


func _refresh_monitor() -> void:
	if is_exit:
		return
	var open_slots := capacity - reserved
	# spawn_doors() stores the door's [front, rear] monitors in this meta entry.
	for m in get_meta("monitors", []):
		m.show_number(capacity)
		m.set_capacity(open_slots)
		m.set_locked(open_slots <= 0)


func _on_finished(_name: StringName) -> void:
	# play() ends at the open pose, play_backwards() ends at the closed pose
	is_open = _target_open
	if is_open:
		opened.emit()
	else:
		closed.emit()


## Invisible box over the doorway (1.4 x 2.2 m clear opening, 0.5 m deep so it can be hit from
## either side). It is an Area3D on layer 2: it never blocks movement, only rays that ask for it.
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
