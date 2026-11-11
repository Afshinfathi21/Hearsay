class_name AcidPot
extends Node3D
## Controls one overhead acid pot assembled from the level's GLB assets.
## Child layout: Pot, Liquid, Stream, Release/Hatch, Release/LatchBolt, Pipes, Valve/ValveWheel.

signal overflowed
signal released

const POT_BASE := 0.06
const LIQ_H := 0.80
const RIM_Y := 1.0
const OVERFLOW_SCALE := (RIM_Y - POT_BASE) / LIQ_H

@export var acid_shader: Shader = preload("res://assets/balance_scale/acid_liquid.gdshader")
@export_range(0.0, 1.175, 0.001) var fill: float = 0.0: set = set_fill

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
	stream.visible = false
	_apply()


func set_fill(value: float) -> void:
	fill = clampf(value, 0.0, OVERFLOW_SCALE)
	if is_node_ready():
		_apply()


func _surface_y() -> float:
	return POT_BASE + LIQ_H * liquid.scale.y


func _apply() -> void:
	liquid.scale.y = maxf(fill, 0.001)
	liquid.visible = fill > 0.002
	_fx_bubbles.emitting = fill > 0.05 and fill <= 1.0
	_fx_bubbles.position.y = POT_BASE + 0.5 * LIQ_H * liquid.scale.y
	_fx_overflow.emitting = fill > 1.0


## Animate the liquid to a target fill. Values above 1.0 spill over the rim.
func pour_to(target: float, duration: float = 1.5) -> void:
	_kill_tween()
	var safe_target := clampf(target, 0.0, OVERFLOW_SCALE)
	var safe_duration := maxf(duration, 0.01)
	_pouring = true
	stream.visible = true
	_tween = create_tween()
	_tween.tween_method(_set_level, liquid.scale.y, maxf(safe_target, 0.001), safe_duration)
	_tween.parallel().tween_property(
		valve_wheel,
		"rotation:y",
		valve_wheel.rotation.y + TAU,
		safe_duration
	)
	_tween.tween_callback(_finish_pour.bind(safe_target))


func _set_level(level: float) -> void:
	liquid.scale.y = level
	liquid.visible = level > 0.002
	var stream_top := RIM_Y - 0.05
	stream.position.y = stream_top
	stream.scale = Vector3(1.0, maxf(stream_top - _surface_y(), 0.01), 1.0)
	_fx_splash.position.y = _surface_y()
	_fx_splash.emitting = _pouring
	_fx_bubbles.emitting = level > 0.05 and level <= 1.0
	_fx_overflow.emitting = level > 1.0


func _finish_pour(target: float) -> void:
	_pouring = false
	stream.visible = false
	_fx_splash.emitting = false
	fill = target
	if target > 1.0:
		overflowed.emit()


## Pull the latch, open the hatch, and drain the pot.
func release() -> void:
	_kill_tween()
	_pouring = false
	stream.visible = false
	_fx_overflow.emitting = false
	_fx_bubbles.emitting = false
	_tween = create_tween()
	_tween.tween_property(latch, "position:x", latch.position.x + 0.18, 0.12)
	_tween.tween_property(hatch, "rotation:z", -PI / 2.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func() -> void: _fx_drain.restart())
	_tween.tween_method(_set_level, liquid.scale.y, 0.001, 0.6)
	_tween.tween_callback(func() -> void:
		set_fill(0.0)
		released.emit()
	)


func reset() -> void:
	_kill_tween()
	_pouring = false
	hatch.rotation.z = 0.0
	latch.position.x = 0.40
	valve_wheel.rotation.y = 0.0
	_fx_drain.emitting = false
	set_fill(0.0)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _override_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child in node.get_children():
		_override_material(child, material)


func _make_fx(pos: Vector3, amount: int, life: float, direction: Vector3, spread: float,
		vmin: float, vmax: float, grav: float, size: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = direction
	process_material.spread = spread
	process_material.initial_velocity_min = vmin
	process_material.initial_velocity_max = vmax
	process_material.gravity = Vector3(0, -grav, 0)
	particles.process_material = process_material
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	var sphere_material := StandardMaterial3D.new()
	sphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere_material.albedo_color = Color(0.72, 0.95, 0.22)
	sphere.material = sphere_material
	particles.draw_pass_1 = sphere
	particles.amount = amount
	particles.lifetime = life
	particles.emitting = false
	particles.position = pos
	add_child(particles)
	return particles
