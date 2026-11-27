class_name BotAvatar
extends CharacterBody3D
## A seated stand-in for another player: the same character model and animator as the real
## player, frozen in the sitting pose. Used for bots until remote players are spawned.

const CHARACTER := "res://assets/common/characters/character_base.glb"
const ANIMATOR := "res://Player/character_animator.gd"

## The animator reads this to blend into the sitting pose.
var seated := true
var display_name := "BOT"

var _model: Node3D


func sit_on(seat: AuctionSeat, player_name: String) -> void:
	display_name = player_name
	_model = (load(CHARACTER) as PackedScene).instantiate() as Node3D
	_model.position = Vector3(0.0, -0.88, 0.0)
	_model.rotation.y = PI
	add_child(_model)
	var animator := Node.new()
	animator.set_script(load(ANIMATOR))
	animator.set("body", self)
	add_child(animator)

	var tag := Label3D.new()
	tag.text = player_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.fixed_size = true
	tag.pixel_size = 0.0009
	tag.font_size = 28
	tag.outline_size = 8
	tag.position = Vector3(0.0, 0.95, 0.0)
	add_child(tag)

	var forward := seat.get_forward()
	rotation.y = atan2(-forward.x, -forward.z)
	var sit := seat.get_sit_position()
	global_position = Vector3(sit.x, sit.y - _hips_above_origin() + 0.02, sit.z)


func eliminate() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.0, 0.02, 1.0), 0.8).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(hide)


func _hips_above_origin() -> float:
	var skeletons := find_children("*", "Skeleton3D", true, false)
	if skeletons.size() > 0:
		var sk := skeletons[0] as Skeleton3D
		var hips := sk.find_bone("Hips")
		if hips != -1:
			return (sk.global_transform * sk.get_bone_global_rest(hips)).origin.y - global_position.y
	return 0.05
