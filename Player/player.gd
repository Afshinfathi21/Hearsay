extends CharacterBody3D
## Third-person player controller.
##
## Expected scene tree:
##   Player (CharacterBody3D)   <- this script
##   ├── CollisionShape3D
##   ├── Model                  <- your .glb (set its rotation back to 0,0,0)
##   ├── Animator (Node)        <- character_animator.gd
##   └── Head (Node3D)          <- camera pivot; the SpringArm3D + Camera3D
##                                 are created/arranged automatically if missing

@export_group("Movement")
@export var SPEED : float = 5.0
## Jump HEIGHT in metres (the real velocity is calculated from it).
@export var JUMP_VELOCITY : float = 1.0
@export var fall_multiplier : float = 2.5
@export var acceleration : float = 40.0
@export var friction : float = 50.0
@export var air_control : float = 15.0

@export_group("Camera")
## Used only if the settings menu is not in the project; otherwise the player's setting is used.
@export var mouse_sensitivity : float = 0.002
## How far behind the character the camera sits.
@export var camera_distance : float = 4.0
## Press this key (default V) to switch between third and first person.
@export var start_first_person : bool = false
## Height of the camera pivot above the player's feet.
@export var camera_pivot_height : float = 1.7
## Pushes the camera a little to the side for an over-the-shoulder look. 0 = centred.
@export var camera_shoulder_offset : float = 0.35
## Starting tilt. More negative = camera higher, looking down more.
## Layers the camera should bump into. 0 = camera ignores everything (start here).
@export_flags_3d_physics var camera_collision_mask : int = 0
@export_range(-89.0, 30.0) var start_pitch_deg : float = -15.0
@export_range(-89.0, 0.0) var pitch_min_deg : float = -70.0   # looking down
@export_range(0.0, 89.0) var pitch_max_deg : float = 30.0     # looking up

@export_group("Model")
@export var rotation_speed : float = 12.0
## true  = character always faces where the camera looks (mouse turns the body).
## false = character only turns toward the direction it walks.
@export var face_camera_direction : bool = true
## If the character faces the wrong way, change this (try 180).
@export_range(-180.0, 180.0) var model_yaw_offset_deg : float = 0.0

var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Set to true by the HUD while a full-screen panel (such as point transfer) is open.
var input_blocked : bool = false

var _yaw : float = 0.0
var _first_person : bool = false
var _cam_dist : float = 0.0   # current (smoothed) camera distance
var _pitch : float = 0.0

@onready var head: Node3D = $Head
## The node that holds your character (the .glb). Leave empty to find it automatically.
@export var model: Node3D

var _camera: Camera3D


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_ensure_toggle_action()
	_find_model()
	_first_person = start_first_person
	_cam_dist = 0.0 if _first_person else camera_distance
	_setup_camera()


## Creates the "toggle_camera" action (key V) if it isn't in Project Settings > Input Map.
func _ensure_toggle_action() -> void:
	if InputMap.has_action("toggle_camera"):
		return
	InputMap.add_action("toggle_camera")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_V
	InputMap.action_add_event("toggle_camera", ev)


func _find_model() -> void:
	if model == null:
		model = get_node_or_null("Model") as Node3D
	if model == null:
		# Fall back to the direct child that contains the character's skeleton.
		var skeletons := find_children("*", "Skeleton3D", true, false)
		if skeletons.size() > 0:
			var n: Node = skeletons[0]
			while n.get_parent() != self and n.get_parent() != null:
				n = n.get_parent()
			model = n as Node3D
	if model == null:
		push_warning("player.gd: could not find the character model. Assign it to 'Model' in the Inspector.")
	else:
		print("player.gd: turning model node '", model.name, "'")


func _setup_camera() -> void:
	head.position = Vector3(0.0, camera_pivot_height, 0.0)

	# Find the camera under Head (it may be inside an old SpringArm3D).
	var cams := head.find_children("*", "Camera3D", true, false)
	_camera = cams[0] as Camera3D if cams.size() > 0 else null
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		head.add_child(_camera)

	# Put the camera directly under Head and remove SpringArm3D nodes:
	# the script now positions the camera itself.
	if _camera.get_parent() != head:
		_camera.reparent(head, false)
	for arm in head.find_children("*", "SpringArm3D", true, false):
		arm.queue_free()

	_camera.rotation = Vector3.ZERO
	_camera.scale = Vector3.ONE
	_camera.current = true

	_pitch = clampf(deg_to_rad(start_pitch_deg), deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	head.rotation = Vector3(_pitch, _yaw, 0.0)
	_update_camera()


## Places the camera behind the Head pivot (local +Z is "behind" the look direction).
func _update_camera() -> void:
	# Smoothly slide between first person (distance 0) and third person.
	var target := 0.0 if _first_person else camera_distance
	_cam_dist = lerpf(_cam_dist, target, 1.0 - exp(-12.0 * get_physics_process_delta_time()))
	if absf(_cam_dist - target) < 0.01:
		_cam_dist = target

	# Hide your own body when the camera is (almost) inside the head.
	if model:
		model.visible = _cam_dist > 0.6

	var dist := _cam_dist
	if dist > 0.0 and camera_collision_mask != 0:
		var from := head.global_position
		var to := from + head.global_transform.basis.z * dist
		var query := PhysicsRayQueryParameters3D.create(from, to, camera_collision_mask, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit:
			dist = maxf(from.distance_to(hit.position) - 0.2, 0.3)

	var side := camera_shoulder_offset * clampf(_cam_dist / maxf(camera_distance, 0.01), 0.0, 1.0)
	_camera.position = Vector3(side, 0.0, dist)


## A value from the player's settings (settings menu), or the fallback if it is not there.
func _setting(key: String, fallback: Variant) -> Variant:
	var saved: Variant = GameSettings.get_value("player", key)
	return saved if saved != null else fallback


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Applied immediately, so no mouse movement is lost between physics frames.
		var sensitivity: float = _setting("mouse_sensitivity", mouse_sensitivity)
		var y_sign: float = -1.0 if _setting("invert_y", false) else 1.0
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(
			_pitch - event.relative.y * sensitivity * y_sign,
			deg_to_rad(pitch_min_deg),
			deg_to_rad(pitch_max_deg)
		)
		head.rotation = Vector3(_pitch, _yaw, 0.0)
	elif event.is_action_pressed("toggle_camera"):
		_first_person = not _first_person
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		# Click the game window to take the mouse back.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	# Gravity (falls faster than it rises, for a snappier jump).
	if not is_on_floor():
		if velocity.y >= 0.0:
			velocity += get_gravity() * delta
		else:
			velocity += get_gravity() * delta * fall_multiplier

	# Jump: JUMP_VELOCITY is a height in metres.
	if Input.is_action_just_pressed("jump") and is_on_floor() and not input_blocked:
		velocity.y = sqrt(2.0 * gravity * JUMP_VELOCITY)

	# Movement relative to where the camera is looking.
	var input_dir := Vector2.ZERO if input_blocked else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := (Basis(Vector3.UP, _yaw) * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate : float
	if not is_on_floor():
		rate = air_control
	elif direction != Vector3.ZERO:
		rate = acceleration
	else:
		rate = friction
	horizontal = horizontal.move_toward(direction * SPEED, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()
	_update_camera()

	# Turn only the model; the body and the camera pivot stay put.
	if model:
		var target_yaw : float
		if face_camera_direction or _first_person:
			target_yaw = _yaw + PI + deg_to_rad(model_yaw_offset_deg)
		elif direction != Vector3.ZERO:
			target_yaw = atan2(direction.x, direction.z) + deg_to_rad(model_yaw_offset_deg)
		else:
			return
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, 1.0 - exp(-rotation_speed * delta))
