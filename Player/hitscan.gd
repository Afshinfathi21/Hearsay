extends Node3D
## Put this on the Node3D that has the RayCast3D child, and make that Node3D a child of
## the player's Camera3D, so the ray points where you look.
## Press the "interact" action (E) while looking at a door to open or close it.
##
## While you look at a door you are close enough to use, it emits door_focused(door)
## every frame; when you look away it emits door_unfocused once. The HUD listens to
## these to show the door prompt (see door_hud_bridge.gd).

signal door_focused(door: StandardDoor)
signal door_unfocused

## Doors farther than this from the PLAYER (not the camera) can't be used.
@export var max_interact_distance : float = 3.0

@onready var ray_cast_3d: RayCast3D = $RayCast3D
@onready var label: Label = $RayCast3D/CenterContainer/Label

var _player: Node3D
var _had_door := false


func _ready() -> void:
	add_to_group("hitscan")
	_ensure_interact_action()

	# The player: the scene root this node is saved in, or the node in group "player".
	_player = owner as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

	# The camera is behind the character, so the ray must be long enough to pass it.
	ray_cast_3d.enabled = true
	ray_cast_3d.target_position = Vector3(0, 0, -8.0)
	ray_cast_3d.collide_with_areas = true         # the door's InteractZone is an Area3D (layer 2)
	ray_cast_3d.collide_with_bodies = true        # walls (layer 1) still block the ray
	ray_cast_3d.collision_mask = 0b11             # layers 1 + 2
	if _player is CollisionObject3D:
		ray_cast_3d.add_exception(_player)        # ignore the player's own capsule


func _process(_delta: float) -> void:
	ray_cast_3d.force_raycast_update()             # make sure the hit is from this frame
	var door := _door_in_reach()

	if door != null:
		door_focused.emit(door)
		if Input.is_action_just_pressed("interact"):
			door.interact(_player)
	elif _had_door:
		door_unfocused.emit()
	_had_door = door != null


## The door being looked at, or null if there is none or it is too far from the player.
func _door_in_reach() -> StandardDoor:
	var door := _find_door(ray_cast_3d.get_collider() as Node)
	if door == null:
		return null
	if _player != null and _player.global_position.distance_to(door.global_position) > max_interact_distance:
		return null
	return door


## The ray may hit the zone or the door panel's body; walk up to the node that is the door.
func _find_door(node: Node) -> StandardDoor:
	while node != null:
		if node is StandardDoor:
			return node as StandardDoor
		node = node.get_parent()
	return null


## Creates the "interact" input action (key E) if you haven't added it in Project Settings > Input Map.
func _ensure_interact_action() -> void:
	if InputMap.has_action("interact"):
		return
	InputMap.add_action("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	InputMap.action_add_event("interact", ev)
