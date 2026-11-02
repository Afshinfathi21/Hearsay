extends Node3D
## Attach to an empty Node3D and run the scene: builds a small three-room layout with working doors.
## Rooms:   A --door--> B --open-- C        (B and C merge into one long room)
## Read this top to bottom: it is the whole workflow.

func _ready() -> void:
	var gm := GridMap.new()
	gm.name = "Rooms"
	add_child(gm)
	RoomGrid.setup(gm)                                  # loads the library, sets 4 x 3.5 x 4 cells

	var A := Vector2i(0, 0)
	var B := Vector2i(1, 0)
	var C := Vector2i(1, 1)
	var cells: Array[Vector2i] = [A, B, C]
	var links := [
		{"a": A, "b": B, "type": RoomGrid.Side.DOOR},   # doorway owned by A, front of the door faces into A
		{"a": B, "b": C, "type": RoomGrid.Side.OPEN},   # open-plan: no wall between B and C
	]
	RoomGrid.place_rooms(gm, cells, links)              # picks the right one of the 81 items for every cell

	var door_scene: PackedScene = load("res://Doors/door_standard.glb")
	var monitor_scene: PackedScene = load("res://Monitors/door_monitor.glb")
	for door in RoomGrid.spawn_doors(gm, self, door_scene, monitor_scene):
		door.open()                                      # StandardDoor API: open(), close(), set_locked(bool)
	RoomGrid.add_lights(gm, self)                        # one OmniLight3D under each ceiling fixture
