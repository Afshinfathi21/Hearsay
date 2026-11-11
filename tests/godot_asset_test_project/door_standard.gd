class_name StandardDoor
extends Node3D
## Drives Doors/door_standard.glb. Attach to the root node of the imported scene.
## The import creates an AnimationPlayer with one clip, "Door_Open":
## bolts retract, then the panel swings 100 degrees toward the back (+Y in Blender).

signal opened
signal closed

const CLIP := "Door_Open"
const AMBER := Color("FFA21F")
const RED := Color("E5201B")

var is_open := false
var is_locked := false
var _target_open := false
var _anim: AnimationPlayer
var _lights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D


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


func _on_finished(_name: StringName) -> void:
	is_open = _target_open
	if is_open:
		opened.emit()
	else:
		closed.emit()
