class_name DoorMonitor
extends Node3D
## Drives the digits, capacity pips and status lamp of Monitors/door_monitor.glb.
## Attach to the root node of the imported door_monitor.glb (e.g. in an inherited scene).
##
## Usage:
##   $Monitor.show_number(2)      # digits show " 2"
##   $Monitor.set_capacity(2)     # 2 of 4 pips lit
##   $Monitor.set_locked(true)    # digits + lamp turn red

const AMBER := Color("FFA21F")
const RED := Color("E5201B")
const WHITE := Color("E9F2FF")
const MAX_PIPS := 4

## Which segments are lit for each digit (A top, B top-right, C bottom-right,
## D bottom, E bottom-left, F top-left, G middle)
const SEGMENTS := {
	0: "ABCDEF", 1: "BC", 2: "ABGED", 3: "ABGCD", 4: "FGBC",
	5: "AFGCD", 6: "AFGEDC", 7: "ABC", 8: "ABCDEFG", 9: "ABCDFG",
}

@export var emission_energy := 3.0   ## glow strength of lit digits / lights

var _segs := {}                 # "Tens"/"Units" -> {"A": MeshInstance3D, ...}
var _digit_on: StandardMaterial3D
var _digit_off: StandardMaterial3D
var _lamp: MeshInstance3D
var _lamp_mat: StandardMaterial3D
var _pips: Array[MeshInstance3D] = []
var _pip_on: StandardMaterial3D
var _pip_off: StandardMaterial3D


func _ready() -> void:
	for digit in ["Tens", "Units"]:
		var d := {}
		for letter in "ABCDEFG":
			d[letter] = find_child("Mon_Seg_%s_%s" % [digit, letter], true, false)
		_segs[digit] = d
	_lamp = find_child("Mon_Status_Lamp", true, false)
	for i in range(1, MAX_PIPS + 1):
		_pips.append(find_child("Mon_Pip_%d" % i, true, false))

	# Build runtime materials from the imported ones, so colours come from the art.
	_digit_on = _make_lit(_segs["Tens"]["A"], AMBER)
	_digit_off = _make_unlit(_digit_on)
	_lamp_mat = _make_lit(_lamp, AMBER)
	_lamp.material_override = _lamp_mat
	_pip_on = _make_lit(_pips[0], WHITE)
	_pip_off = _make_unlit(_pip_on)

	show_number(0)
	set_capacity(MAX_PIPS)


## Display 0-99. Values above 99 clamp to 99; single digits blank the tens digit.
func show_number(n: int) -> void:
	n = clampi(n, 0, 99)
	_set_digit("Units", n % 10)
	if n < 10:
		_set_digit("Tens", -1)      # blank leading zero
	else:
		_set_digit("Tens", n / 10)


## Light `open_slots` of the four pips (the doorway's remaining capacity).
func set_capacity(open_slots: int) -> void:
	open_slots = clampi(open_slots, 0, MAX_PIPS)
	for i in MAX_PIPS:
		_pips[i].material_override = _pip_on if i < open_slots else _pip_off


## Red = locked / penalty / zero capacity, amber = normal.
func set_locked(locked: bool) -> void:
	var c := RED if locked else AMBER
	_digit_on.emission = c
	_lamp_mat.emission = c


func _set_digit(digit: String, value: int) -> void:
	var lit: String = SEGMENTS.get(value, "")   # -1 -> blank
	for letter in "ABCDEFG":
		var seg: MeshInstance3D = _segs[digit][letter]
		seg.material_override = _digit_on if letter in lit else _digit_off


func _make_lit(mesh_node: MeshInstance3D, colour: Color) -> StandardMaterial3D:
	var m := (mesh_node.mesh.surface_get_material(0) as StandardMaterial3D).duplicate()
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = emission_energy
	return m


func _make_unlit(lit: StandardMaterial3D) -> StandardMaterial3D:
	var m := lit.duplicate() as StandardMaterial3D
	m.emission_enabled = false
	m.albedo_color = Color(0.12, 0.07, 0.01)   # faint "ghost" segment
	return m
