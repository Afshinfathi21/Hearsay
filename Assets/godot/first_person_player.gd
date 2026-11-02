class_name FirstPersonPlayer
extends CharacterBody3D
## Example: movement and camera live on the CharacterBody3D; the visible character is
## just a child model. Nothing about the camera depends on the mesh or its skeleton.
##
## Models face +Z in Godot, but a CharacterBody3D moves toward -Z, so the model child is
## turned 180 degrees. Feet are at the body's origin; the capsule is centred 0.9 m up.

const SPEED := 3.5
const MOUSE_SENS := 0.0025
const EYE_HEIGHT := 1.65               # matches the character's eye line
const GRAVITY := 18.0

@export var character_scene: PackedScene = preload("res://Characters/character_base.glb")
@export var palette_index := 0

var camera: Camera3D
var model: PlayerCharacter


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)

	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	add_child(camera)

	var inst: Node3D = character_scene.instantiate()
	inst.set_script(preload("res://player_character.gd"))   # before add_child so _ready() runs
	inst.palette_index = palette_index
	inst.rotation.y = PI
	add_child(inst)                        # _ready() configures the outfit
	model = inst as PlayerCharacter
	model.set_local_player(camera)         # hide own body from own camera


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * MOUSE_SENS, -1.4, 1.4)


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1.0
	dir = (transform.basis * dir).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
