extends Node3D
## Put this on the Node3D that has the RayCast3D child, and make that Node3D a child of
## the player's Camera3D (or the camera itself), so the ray points where you look.
## Press the "interact" action (E) while looking at a door to open or close it.

@onready var ray_cast_3d: RayCast3D = $RayCast3D


func _ready() -> void:
	_ensure_interact_action()
	# Same settings you can set in the inspector. Reach = 2.5 m along the node's -Z (forward).
	ray_cast_3d.enabled = true
	ray_cast_3d.target_position = Vector3(0, 0, -2.5)
	ray_cast_3d.collide_with_areas = true         # the door's InteractZone is an Area3D (layer 2)
	ray_cast_3d.collide_with_bodies = true        # walls (layer 1) still block the ray
	ray_cast_3d.collision_mask = 0b11             # layers 1 + 2


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		interact_with()


func interact_with() -> void:
	ray_cast_3d.force_raycast_update()             # make sure the hit is from this frame
	var door := _find_door(ray_cast_3d.get_collider() as Node)
	if door != null:
		door.interact()


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
