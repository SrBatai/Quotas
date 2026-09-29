class_name QuadrupedAnimator
extends Node
## Procedural trot for wolf/deer rigs (Body, Head, Tail, LegFL/FR/BL/BR).

var parts: Dictionary = {}
var rest_rot: Dictionary = {}
var rest_pos: Dictionary = {}
var speed: float = 0.0
var running: bool = false
var chasing: bool = false
var phase: float = 0.0
var _t: float = 0.0
var _lunge: float = -1.0
var _hit: float = -1.0


func setup(model: Node3D) -> void:
	for n in ["Body", "Head", "Tail", "LegFL", "LegFR", "LegBL", "LegBR"]:
		var node := model.find_child(n, true, false) as Node3D
		if node != null:
			parts[n] = node
			rest_rot[n] = node.rotation
			rest_pos[n] = node.position


func _process(delta: float) -> void:
	if parts.is_empty():
		return
	_t += delta
	var moving := speed > 0.2
	if moving:
		phase += speed * 2.4 * delta
	var amp := 0.8 if running else 0.5
	var s := sin(phase) if moving else 0.0
	_rot("LegFL", Vector3(s * amp, 0, 0))
	_rot("LegBR", Vector3(s * amp, 0, 0))
	_rot("LegFR", Vector3(-s * amp, 0, 0))
	_rot("LegBL", Vector3(-s * amp, 0, 0))
	if parts.has("Body"):
		var body := parts["Body"] as Node3D
		body.position = rest_pos["Body"] + Vector3(0, absf(s) * 0.03, 0)
	_rot("Tail", Vector3(0, sin(_t * 3.0) * 0.3, 0))
	var head_x := -0.3 if chasing else sin(_t * 1.5) * 0.05
	if _lunge >= 0.0:
		_lunge += delta
		head_x += 0.4 * sin(clampf(_lunge / 0.3, 0.0, 1.0) * PI)
		if _lunge > 0.3:
			_lunge = -1.0
	if _hit >= 0.0:
		_hit += delta
		head_x -= 0.3 * sin(clampf(_hit / 0.25, 0.0, 1.0) * PI)
		if _hit > 0.25:
			_hit = -1.0
	_rot("Head", Vector3(head_x, 0, 0))


func _rot(part: String, offset: Vector3) -> void:
	if parts.has(part):
		(parts[part] as Node3D).rotation = rest_rot[part] + offset


func lunge() -> void:
	_lunge = 0.0


func hit() -> void:
	_hit = 0.0
