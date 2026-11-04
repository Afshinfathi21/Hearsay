extends Node3D

@onready var ray_cast_3d: RayCast3D = $RayCast3D


func _ready() -> void:
	_ensure_interact_action()
	ray_cast_3d.enabled = true
	ray_cast_3d.target_position = Vector3(0, 0, -2.5)
	ray_cast_3d.collide_with_areas = true
	ray_cast_3d.collide_with_bodies = true
	ray_cast_3d.collision_mask = 0b11


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		interact_with()


func interact_with() -> void:
	ray_cast_3d.force_raycast_update()
	var door := _find_door(ray_cast_3d.get_collider() as Node)
	if door != null:
		door.interact(_find_player())


func _find_door(node: Node) -> StandardDoor:
	while node != null:
		if node is StandardDoor:
			return node as StandardDoor
		node = node.get_parent()
	return null


func _find_player() -> Node3D:
	var node: Node = self
	while node != null:
		if node.is_in_group("player") and node is Node3D:
			return node as Node3D
		node = node.get_parent()
	return null


func _ensure_interact_action() -> void:
	if InputMap.has_action("interact"):
		return
	InputMap.add_action("interact")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	InputMap.action_add_event("interact", ev)
