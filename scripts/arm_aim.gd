extends SkeletonModifier3D
## Points the right arm cannon at `target` on top of whatever animation is playing: the elbow
## and wrist straighten and the upper arm swings so the barrel lines up with the target.
## `recoil` (0..1) kicks the muzzle upward; vela_model.gd sets it on each shot and lets it decay.
## Blend the whole effect in and out with the built-in `influence`.

const RECOIL_KICK := 0.35    # radians the muzzle rises at full recoil

var target := Vector3.ZERO   # global position to aim at
var recoil := 0.0

var _upper := -1
var _lower := -1
var _hand := -1
var _arm_dir := Vector3.ZERO   # shoulder-to-muzzle direction in the upper arm's rest frame


func _ready() -> void:
	var skel := get_skeleton()
	_upper = skel.find_bone("RightUpperArm")
	_lower = skel.find_bone("RightLowerArm")
	_hand = skel.find_bone("RightHand")
	var muzzle := skel.find_bone("RightMuzzle")
	var rest := skel.get_bone_global_rest(_upper)
	_arm_dir = (rest.basis.inverse() * (skel.get_bone_global_rest(muzzle).origin - rest.origin)).normalized()


func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or _upper < 0:
		return
	# Straight arm: elbow and wrist at rest, so the cannon is in line with the upper arm.
	for bone in [_lower, _hand]:
		skel.set_bone_pose_rotation(bone, skel.get_bone_rest(bone).basis.get_rotation_quaternion())
	var shoulder := skel.get_bone_global_pose(_upper)
	var to_target := skel.global_transform.affine_inverse() * target - shoulder.origin
	if to_target.length() < 1.0:
		return
	to_target = to_target.normalized()
	var aimed := Basis(Quaternion((shoulder.basis * _arm_dir).normalized(), to_target)) * shoulder.basis
	if recoil > 0.0:
		var kick_axis := to_target.cross(Vector3.UP)
		if kick_axis.length() > 0.01:
			aimed = Basis(kick_axis.normalized(), recoil * RECOIL_KICK) * aimed
	var parent := skel.get_bone_global_pose(skel.get_bone_parent(_upper))
	skel.set_bone_pose_rotation(_upper, (parent.basis.inverse() * aimed).get_rotation_quaternion())
