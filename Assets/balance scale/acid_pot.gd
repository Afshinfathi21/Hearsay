class_name AcidPot
extends Node3D
## Controls one overhead acid pot. Expected child scenes (all at origin (0,0,0)):
##   Pot     <- acid_pot.glb
##   Liquid  <- acid_liquid.glb
##   Stream  <- acid_stream.glb   (origin at top, hangs down)
##   Release <- release_mechanism.glb  (has Hatch, LatchBolt nodes)
##   Pipes   <- pipes_feed.glb,  Valve <- valve.glb (position y = 1.6)
## Untested starting point: tweak numbers in the editor.

signal overflowed
signal released

const POT_BASE := 0.06      # glass floor (matches build_assets.py)
const LIQ_H := 0.80         # liquid mesh height at scale.y == 1.0 (the MAX line)
const RIM_Y := 1.0          # top of the glass
const OVERFLOW_SCALE := (RIM_Y - POT_BASE) / LIQ_H   # ~1.175

@export var acid_shader: Shader = preload("res://Assets/balance scale/acid_liquid.gdshader")
@export_range(0.0, 1.0) var fill: float = 0.0: set = set_fill

@onready var liquid: Node3D = $Liquid
@onready var stream: Node3D = $Stream
@onready var hatch: Node3D = $Release/Hatch
@onready var latch: Node3D = $Release/LatchBolt
@onready var valve_wheel: Node3D = $Valve/ValveWheel

var _acid_mat: ShaderMaterial
var _fx_bubbles: GPUParticles3D
var _fx_splash: GPUParticles3D
var _fx_overflow: GPUParticles3D
var _fx_drain: GPUParticles3D
var _tween: Tween
var _pouring := false

func _ready() -> void:
	_acid_mat = ShaderMaterial.new()
	_acid_mat.shader = acid_shader
	_override_material(liquid, _acid_mat)
	_override_material(stream, _acid_mat)
	_fx_bubbles = _make_fx(Vector3(0, 0.3, 0), 20, 1.2, Vector3.UP, 15.0, 0.05, 0.15, -0.05, 0.012)
	_fx_splash = _make_fx(Vector3(0, 0.3, 0), 24, 0.6, Vector3.UP, 40.0, 0.4, 0.9, 4.0, 0.015)
	_fx_overflow = _make_fx(Vector3(0, RIM_Y, 0), 40, 0.9, Vector3.DOWN, 70.0, 0.2, 0.6, 5.0, 0.02)
	_fx_drain = _make_fx(Vector3(0, -0.06, 0), 120, 1.0, Vector3.DOWN, 20.0, 1.0, 2.5, 6.0, 0.03)
	(_fx_bubbles.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	(_fx_bubbles.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.25
	_fx_overflow.process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_fx_overflow.process_material.emission_sphere_radius = 0.3
	_fx_drain.one_shot = true
	_fx_drain.explosiveness = 0.8
	_apply()

func set_fill(v: float) -> void:
	fill = clampf(v, 0.0, 1.0)
	if is_node_ready():
		_apply()

func _surface_y() -> float:
	return POT_BASE + LIQ_H * liquid.scale.y

func _apply() -> void:
	liquid.scale.y = maxf(fill, 0.001)
	liquid.visible = fill > 0.002
	_fx_bubbles.emitting = fill > 0.05
	_fx_bubbles.position.y = POT_BASE + 0.5 * LIQ_H * liquid.scale.y

## Pour acid until `target` (0..1, or up to OVERFLOW_SCALE to spill over).
func pour_to(target: float, duration: float = 1.5) -> void:
	_kill_tween()
	_pouring = true
	stream.visible = true
	_tween = create_tween()
	_tween.tween_method(_set_level, liquid.scale.y, maxf(target, 0.001), duration)
	_tween.tween_callback(_finish_pour.bind(target))

func _set_level(s: float) -> void:
	liquid.scale.y = s
	liquid.visible = s > 0.002
	var top := RIM_Y - 0.05
	stream.scale = Vector3(1, maxf(top - _surface_y(), 0.01), 1)
	_fx_splash.position.y = _surface_y()
	_fx_splash.emitting = _pouring
	_fx_bubbles.emitting = s > 0.05
	_fx_overflow.emitting = s > 1.0 + 0.001
	valve_wheel.rotation.y += 0.15

func _finish_pour(target: float) -> void:
	_pouring = false
	stream.visible = false
	_fx_splash.emitting = false
	fill = clampf(target, 0.0, OVERFLOW_SCALE)
	if target > 1.0:
		overflowed.emit()
	else:
		_fx_overflow.emitting = false

## Elimination: pull latch, hatch swings open, everything drops.
func release() -> void:
	_kill_tween()
	stream.visible = false
	_fx_overflow.emitting = false
	_fx_bubbles.emitting = false
	_tween = create_tween()
	_tween.tween_property(latch, "position:x", latch.position.x + 0.18, 0.12)
	_tween.tween_property(hatch, "rotation:z", -PI / 2.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): _fx_drain.restart())
	_tween.tween_method(_set_level, liquid.scale.y, 0.001, 0.6)
	_tween.tween_callback(func(): released.emit())

func reset() -> void:
	_kill_tween()
	hatch.rotation.z = 0.0
	latch.position.x = 0.40
	set_fill(0.0)

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

func _override_material(node: Node, m: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = m
	for c in node.get_children():
		_override_material(c, m)

func _make_fx(pos: Vector3, amount: int, life: float, dir: Vector3, spread: float,
		vmin: float, vmax: float, grav: float, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, -grav, 0)
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var sp := StandardMaterial3D.new()
	sp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp.albedo_color = Color(0.72, 0.95, 0.22)
	sm.material = sp
	p.draw_pass_1 = sm
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	p.position = pos
	add_child(p)
	return p
