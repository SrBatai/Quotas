class_name PoseAnim
## Code-generated key-pose clips for the humanoid skeleton (ASSET_SPEC v2 §6.1 "acciones por poses clave"), the
## stand-ins used until Opus delivers the real clips (humanoid_combat.glb, zombie_anims.glb): the pose of a base
## animation at t = 0 (usually `Loco_Idle`) plus, per key, rotations of chosen bones expressed in the CHARACTER
## frame (front +Z, up +Y, right −X): [axis, degrees] about the bone's pivot. Built from the skeleton's own rest so
## the axes are right whatever the retarget did. Only the listed bones get tracks (filtered layers keep the rest).
##
## Conventions (character frame): about +X, a positive angle leans the spine forward and a negative one swings a
## hanging arm forward/up; about +Y, a positive angle twists toward the character's left.


## `keys`: [[time, {bone: [axis, deg] or [[axis, deg], [axis, deg]]}], ...] (every key lists the same bones).
static func build(skeleton: Skeleton3D, base: Animation, length: float, loop: bool, keys: Array) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if skeleton == null or keys.is_empty():
		return a
	# pose the skeleton with the base pose at t = 0 to read the parent bases
	var base_rot := {}
	if base != null:
		for t in base.get_track_count():
			if base.track_get_type(t) != Animation.TYPE_ROTATION_3D:
				continue
			var bone := String(base.track_get_path(t)).get_slice(":", 1)
			base_rot[bone] = base.rotation_track_interpolate(t, 0.0)
			var bi := skeleton.find_bone(bone)
			if bi >= 0:
				skeleton.set_bone_pose_rotation(bi, base_rot[bone])
	var bones: Array = (keys[0][1] as Dictionary).keys()
	var globals := {}
	var parents := {}
	for b in bones:
		var bi := skeleton.find_bone(String(b))
		if bi < 0:
			continue
		globals[b] = skeleton.get_bone_global_pose(bi).basis
		var pi := skeleton.get_bone_parent(bi)
		parents[b] = skeleton.get_bone_global_pose(pi).basis if pi >= 0 else Basis.IDENTITY
	skeleton.reset_bone_poses()
	for b in bones:
		if not globals.has(b):
			continue
		var track := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(track, NodePath("%%GeneralSkeleton:%s" % b))
		for k in keys:
			var spec: Array = (k[1] as Dictionary).get(b, [Vector3.RIGHT, 0.0])
			var rot := Basis.IDENTITY
			if not spec.is_empty() and spec[0] is Array:
				for part in spec:
					rot = Basis((part as Array)[0], deg_to_rad(float((part as Array)[1]))) * rot
			else:
				rot = Basis(spec[0], deg_to_rad(float(spec[1])))
			var local: Basis = (parents[b] as Basis).inverse() * (rot * (globals[b] as Basis))
			a.rotation_track_insert_key(track, float(k[0]), local.get_rotation_quaternion())
	return a


## Shorthand for a key: {bone: [axis, deg]} with the X axis (pitch) for every listed bone.
static func pitch(d: Dictionary) -> Dictionary:
	var out := {}
	for b in d:
		out[b] = [Vector3.RIGHT, float(d[b])]
	return out
