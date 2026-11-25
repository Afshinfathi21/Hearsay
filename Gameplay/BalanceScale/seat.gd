class_name AuctionSeat
extends Node3D
## One chair at the auction table. Put this script on the chair instance and give it a
## SitPoint (Marker3D) child placed on the middle of the seat surface.
##
## The chair model faces its local -X (back rest on +X), so "forward" and "behind" are
## taken from that. SeatingController decides who may sit and when they may stand.

signal occupied(player: Node3D)
signal vacated(player: Node3D)

## Where the player's hips go (middle of the seat surface).
@export var sit_point: Marker3D
## How far behind the chair the player is put when they stand up.
@export var stand_distance := 1.2

var occupant: Node3D


func is_free() -> bool:
	return occupant == null


## Direction the seated player faces (towards the table), flat on the floor.
func get_forward() -> Vector3:
	var f := -global_transform.basis.x
	f.y = 0.0
	return f.normalized()


func get_sit_position() -> Vector3:
	return sit_point.global_position if sit_point != null else global_position + Vector3.UP * 0.66


## A spot to look at when deciding whether the player is aiming at this chair.
func get_aim_position() -> Vector3:
	return get_sit_position() + Vector3.UP * 0.25


## Floor position (x, z) behind the chair where the player stands up.
func get_stand_position() -> Vector3:
	var p := global_position - get_forward() * stand_distance
	p.y = global_position.y
	return p


func take(player: Node3D) -> void:
	occupant = player
	occupied.emit(player)


func release() -> void:
	var who := occupant
	occupant = null
	if who != null:
		vacated.emit(who)
