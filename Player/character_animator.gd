extends Node
## Procedural animation for the humanoid rig (Root, Hips, Spine, Chest, Neck, Head,
## Left/Right Shoulder, UpperArm, LowerArm, Hand, UpperLeg, LowerLeg, Foot, Toes).
##
## Add this as a child Node of the Player (name it "Animator"). It finds the
## Skeleton3D inside your Model on its own and plays: idle, walk/run, jump and fall.
## It works out which way the character faces and which way is "forward" from the
## skeleton itself, so it needs no AnimationPlayer and no re-export from Blender.

@export var body: CharacterBody3D
@export var skeleton: Skeleton3D
@export var max_speed: float = 5.0

@export_group("Walk / Run")
## Full leg cycles per second when moving at max speed.
@export var cycles_per_second: float = 2.0
@export var leg_swing_deg: float = 38.0
@export var knee_bend_deg: float = 65.0
@export var arm_swing_deg: float = 32.0
@export var elbow_bend_deg: float = 55.0
@export var hip_twist_deg: float = 7.0
@export var forward_lean_deg: float = 9.0
@export var hip_bob: float = 0.04

@export_group("Idle")
@export var breathing_deg: float = 1.5
@export var idle_sway_deg: float = 1.2

@export_group("Arms")
## Rotates the arms down from a T-pose / A-pose to a relaxed hanging pose.
@export var relax_arms: bool = true
## How far the relaxed arms hang away from the body.
@export var arm_hang_angle_deg: float = 10.0

@export_group("Air")
@export var air_thigh_deg: float = 25.0
@export var air_knee_deg: float = 45.0
@export var air_arm_deg: float = 40.0

var _bones := {}            # name -> bone index
var _cum := {}              # bone index -> accumulated world-space rotation applied
var _fwd := Vector3.BACK    # horizontal direction the character faces (skeleton space)
var _right := Vector3.RIGHT
var _arm_relax := {}        # "Left"/"Right" -> Quaternion
var _ready_ok := false

var _t := 0.0
var _phase := 0.0
var _move_w := 0.0
var _air_w := 0.0

const BONE_NAMES := [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
	"RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	if skeleton == null and body:
		var found := body.find_children("*", "Skeleton3D", true, false)
		if found.size() > 0:
			skeleton = found[0] as Skeleton3D
	if body == null or skeleton == null:
		push_warning("character_animator: need a CharacterBody3D parent and a Skeleton3D inside your Model.")
		return

	for n in BONE_NAMES:
		var idx := _find_bone(n)
		if idx == -1:
			push_warning("character_animator: bone '%s' not found; animation disabled." % n)
			return
		_bones[n] = idx

	_detect_facing()
	_compute_arm_relax()
	_ready_ok = true


func _find_bone(bone_name: String) -> int:
	var idx := skeleton.find_bone(bone_name)
	if idx != -1:
		return idx
	# Tolerate prefixes such as "mixamorig:" or different case / underscores.
	var want := bone_name.to_lower()
	for i in skeleton.get_bone_count():
		var have := skeleton.get_bone_name(i).to_lower().replace("_", "").replace(":", "")
		if have.ends_with(want):
			return i
	return -1


func _rest_pos(bone_name: String) -> Vector3:
	return skeleton.get_bone_global_rest(_bones[bone_name]).origin


func _detect_facing() -> void:
	# The toes sit in front of the ankle, which tells us where the character faces.
	var d := _rest_pos("LeftToes") - _rest_pos("LeftFoot")
	d.y = 0.0
	if d.length() < 0.001:
		d = _rest_pos("RightToes") - _rest_pos("RightFoot")
		d.y = 0.0
	_fwd = d.normalized() if d.length() > 0.001 else Vector3.BACK
	_right = _fwd.cross(Vector3.UP).normalized()


func _compute_arm_relax() -> void:
	for side in ["Left", "Right"]:
		var q := Quaternion.IDENTITY
		if relax_arms:
			var upper := _rest_pos(side + "UpperArm")
			var lower := _rest_pos(side + "LowerArm")
			var dir := (lower - upper).normalized()
			var out := Vector3(dir.x, 0.0, dir.z)
			if out.length() < 0.01:
				var side_sign := signf((upper - _rest_pos("Hips")).dot(_right))
				out = _right * (side_sign if side_sign != 0.0 else 1.0)
			out = out.normalized()
			var a := deg_to_rad(arm_hang_angle_deg)
			var target := (Vector3.DOWN * cos(a) + out * sin(a)).normalized()
			q = Quaternion(dir, target)
		_arm_relax[side] = q


# --- pose helpers -----------------------------------------------------------
# All rotations are expressed in skeleton space, so they work whatever the
# bone orientations of the rig are.

func _parent_cum(bone: int) -> Quaternion:
	var p := skeleton.get_bone_parent(bone)
	while p != -1:
		if _cum.has(p):
			return _cum[p]
		p = skeleton.get_bone_parent(p)
	return Quaternion.IDENTITY


## Rotate a bone by `delta` (skeleton space) on top of whatever its parents carry.
func _apply(bone_name: String, delta: Quaternion) -> void:
	var bone: int = _bones[bone_name]
	var rp := _parent_cum(bone)
	var g := skeleton.get_bone_global_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	var rest_local := skeleton.get_bone_rest(bone).basis.orthonormalized().get_rotation_quaternion()
	var pose_delta := g.inverse() * rp.inverse() * delta * rp * g
	skeleton.set_bone_pose_rotation(bone, (rest_local * pose_delta).normalized())
	_cum[bone] = (delta * rp).normalized()


## Give a bone an exact skeleton-space rotation (used to keep feet level).
func _apply_abs(bone_name: String, target: Quaternion) -> void:
	_apply(bone_name, target * _parent_cum(_bones[bone_name]).inverse())


# Axis helpers (angles in degrees).
# Limb hanging down:  + = tip swings forward.
# Limb pointing up:   + = tip tilts backward.
func _pitch(deg: float) -> Quaternion:
	return Quaternion(_right, deg_to_rad(deg))

func _yaw(deg: float) -> Quaternion:
	return Quaternion(Vector3.UP, deg_to_rad(deg))

func _roll(deg: float) -> Quaternion:
	return Quaternion(_fwd, deg_to_rad(deg))


func _process(delta: float) -> void:
	if not _ready_ok:
		return

	_t += delta
	var h_speed := Vector2(body.velocity.x, body.velocity.z).length()
	var sr := clampf(h_speed / max_speed, 0.0, 1.0)
	_move_w = lerpf(_move_w, sr, 1.0 - exp(-12.0 * delta))
	_air_w = move_toward(_air_w, 0.0 if body.is_on_floor() else 1.0, delta * 8.0)
	_phase = fmod(_phase + delta * TAU * cycles_per_second * _move_w, TAU)

	var amp := _move_w * (1.0 - _air_w)   # how much ground locomotion is visible
	var idle := (1.0 - _move_w) * (1.0 - _air_w)
	var s := sin(_phase)
	var c := cos(_phase)
	var breath := sin(_t * 1.8)
	var sway := sin(_t * 0.9)

	_cum.clear()

	# --- Hips: bob, twist, weight shift ---
	var hip_twist := hip_twist_deg * s * amp
	var hips_q := _yaw(hip_twist) * _roll(sway * idle_sway_deg * idle)
	_apply("Hips", hips_q)
	var hips_idx: int = _bones["Hips"]
	var hips_parent := skeleton.get_bone_parent(hips_idx)
	var parent_basis := Basis.IDENTITY
	if hips_parent != -1:
		parent_basis = skeleton.get_bone_global_rest(hips_parent).basis
	var bob := hip_bob * cos(_phase * 2.0) * amp - 0.03 * _air_w
	skeleton.set_bone_pose_position(
		hips_idx,
		skeleton.get_bone_rest(hips_idx).origin + parent_basis.inverse() * Vector3(0.0, bob, 0.0)
	)

	# --- Spine / chest / neck / head ---
	var lean := forward_lean_deg * amp
	_apply("Spine", _yaw(-1.6 * hip_twist) * _pitch(-lean))
	_apply("Chest", _pitch(-breath * breathing_deg * idle - breath * 0.5 * breathing_deg * amp))
	_apply("Neck", _pitch(lean * 0.6 + breath * 0.4 * idle))
	_apply("Head", _pitch(lean * 0.4) * _yaw(-0.6 * hip_twist))

	# --- Legs ---
	var thigh_l := leg_swing_deg * s * amp + air_thigh_deg * _air_w
	var thigh_r := -leg_swing_deg * s * amp + air_thigh_deg * 0.2 * _air_w
	var knee_l := knee_bend_deg * maxf(0.0, c) * amp + 4.0 * amp + air_knee_deg * _air_w
	var knee_r := knee_bend_deg * maxf(0.0, -c) * amp + 4.0 * amp + air_knee_deg * 0.4 * _air_w

	_apply("LeftUpperLeg", _pitch(thigh_l))
	_apply("LeftLowerLeg", _pitch(-knee_l))
	_apply("RightUpperLeg", _pitch(thigh_r))
	_apply("RightLowerLeg", _pitch(-knee_r))

	# Feet stay roughly level: toes up when the leg is forward, down when pushing off.
	_apply_abs("LeftFoot", _pitch(0.4 * thigh_l * (1.0 - _air_w) - 10.0 * _air_w))
	_apply_abs("RightFoot", _pitch(0.4 * thigh_r * (1.0 - _air_w) - 10.0 * _air_w))

	# --- Arms (swing opposite to the legs) ---
	var arm_l := -arm_swing_deg * s * amp + air_arm_deg * _air_w + sway * idle_sway_deg * idle
	var arm_r := arm_swing_deg * s * amp + air_arm_deg * _air_w - sway * idle_sway_deg * idle
	var elbow := 14.0 + elbow_bend_deg * amp + 10.0 * _air_w

	_apply("LeftUpperArm", _pitch(arm_l) * _arm_relax["Left"])
	_apply("LeftLowerArm", _pitch(elbow))
	_apply("RightUpperArm", _pitch(arm_r) * _arm_relax["Right"])
	_apply("RightLowerArm", _pitch(elbow))
