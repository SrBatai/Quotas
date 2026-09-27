class_name CameraZone
extends Node3D
## A box (local space, centred on the node, `size` metres) that selects a camera profile while the local player
## stands in it (W0, doc 09 §3.7): city districts use `city`, and switch to `rooftop` when the player is more than
## `rooftop_height` above the zone's origin (a roof, a mirador). The highest `priority` wins where zones overlap.
## The world generator (C1) places one per district; the city bench places its own.

const GROUP := &"camera_zone"

@export var profile: StringName = &"city"
@export var size: Vector3 = Vector3(128, 200, 128)
@export var priority: int = 0
## Height above the zone origin from which the `rooftop` profile applies (0 = never).
@export var rooftop_height: float = 7.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func contains(p: Vector3) -> bool:
	var l := global_transform.affine_inverse() * p
	return absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.z * 0.5 and l.y >= -size.y * 0.5 and l.y <= size.y * 0.5


## Profile for a point inside this zone.
func profile_at(p: Vector3) -> StringName:
	if rooftop_height > 0.0 and p.y - global_position.y > rooftop_height:
		return &"rooftop"
	return profile


## Profile id for a point among all zones of the tree (&"default" outside every zone).
static func pick(tree: SceneTree, p: Vector3) -> StringName:
	var best: CameraZone = null
	for z in tree.get_nodes_in_group(GROUP):
		var cz := z as CameraZone
		if cz != null and cz.contains(p) and (best == null or cz.priority > best.priority):
			best = cz
	return best.profile_at(p) if best != null else &"default"
