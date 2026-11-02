extends CharacterBody3D


@export var SPEED : float = 5.0
@export var JUMP_VELOCITY : float = 1.0
@export var fall_multiplier : float = 2.5


var gravity : float = ProjectSettings.get_setting("physics/3d/default_gravity")

var mouse_motion := Vector2.ZERO
@onready var head: Node3D = $Head



func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	handle_mouse_motion()
	# Add the gravity.
	if not is_on_floor():
		if velocity.y >= 0:
			velocity += get_gravity() * delta
		if velocity.y < 0:
			velocity += get_gravity() * delta * fall_multiplier

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = sqrt(JUMP_VELOCITY * 2.0 * gravity)

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion :
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_motion = -event.relative * 0.001
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func handle_mouse_motion() -> void :
	rotate_y(mouse_motion.x)
	head.rotate_x(mouse_motion.y)
	head.rotation_degrees.x = clampf(
		head.rotation_degrees.x ,-90.0,90.0
	)
	mouse_motion = Vector2.ZERO
