class_name PlayerAnimator
extends Node
## Procedural walk / idle / chop animation on the rigid-part rig (ASSET_SPEC §4.1).

var parts: Dictionary = {}
var rest_rot: Dictionary = {}
var rest_pos: Dictionary = {}
var phase: float = 0.0
var speed: float = 0.0
var running: bool = false
var torch_pose: bool = false
var _t: float = 0.0
var _chop: float = -1.0
var _lean: float = 0.0


func setup(model: Node3D) -> void:
	for n in ["Hips", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]:
		var node := model.find_child(n, true, false) as Node3D
		if node != null:
			parts[n] = node
			rest_rot[n] = node.rotation
			rest_pos[n] = node.position


func _process(delta: float) -> void:
	if parts.is_empty():
		return
	_t += delta
	var amp := 1.3 if running else 1.0
	if speed > 0.2:
		phase += speed * 2.6 * delta
	else:
		# settle the legs back to rest
		phase = lerpf(phase, round(phase / PI) * PI, 8.0 * delta)
	var s := sin(phase)
	var moving := speed > 0.2
	var leg := s * 0.6 * amp if moving else s * 0.6 * 0.15
	_rot("LegL", Vector3(leg, 0, 0))
	_rot("LegR", Vector3(-leg, 0, 0))
	_rot("ArmL", Vector3(-s * 0.5 * amp if moving else 0.0, 0, 0))
	var arm_r := s * 0.5 * amp if moving else 0.0
	if torch_pose:
		arm_r = -1.2
	if _chop >= 0.0:
		_chop += delta
		var a: float
		if _chop < 0.18:
			a = lerpf(-2.4, 0.6, _chop / 0.18)
			_lean = 0.15 * (_chop / 0.18)
		elif _chop < 0.48:
			var t := (_chop - 0.18) / 0.3
			a = lerpf(0.6, -1.2 if torch_pose else 0.0, t)
			_lean = 0.15 * (1.0 - t)
		else:
			_chop = -1.0
			_lean = 0.0
			a = arm_r
		arm_r = a
	_rot("ArmR", Vector3(arm_r, 0, 0))
	if parts.has("Hips"):
		var hips := parts["Hips"] as Node3D
		var bob := absf(s) * 0.04 * amp if moving else 0.0
		hips.position = rest_pos["Hips"] + Vector3(0, bob, 0)
	if parts.has("Torso"):
		var torso := parts["Torso"] as Node3D
		var breathe := 0.0 if moving else sin(_t * TAU * 1.2) * 0.01
		torso.position = rest_pos["Torso"] + Vector3(0, breathe, 0)
		torso.rotation = rest_rot["Torso"] + Vector3(_lean + (0.06 if running else 0.0), 0, 0)


func _rot(part: String, offset: Vector3) -> void:
	if parts.has(part):
		(parts[part] as Node3D).rotation = rest_rot[part] + offset


func chop() -> void:
	_chop = 0.0
