class_name Steering
extends Node
## Seek / flee / wander helpers with whisker (RayCast3D) obstacle avoidance for quadrupeds.

var _body: Node3D
var _whisker_l: RayCast3D
var _whisker_r: RayCast3D


func _ready() -> void:
	_body = get_parent()
	_whisker_l = _body.get_node_or_null("WhiskerL")
	_whisker_r = _body.get_node_or_null("WhiskerR")


## Desired velocity toward a point (horizontal), with avoidance.
func seek(target: Vector3, speed: float) -> Vector3:
	var d := flat(target - _body.global_position)
	if d.length() < 0.05:
		return Vector3.ZERO
	return avoid(d.normalized()) * speed


func flee(from: Vector3, speed: float) -> Vector3:
	var d := flat(_body.global_position - from)
	if d.length() < 0.05:
		d = Vector3.FORWARD
	return avoid(d.normalized()) * speed


## Steers a direction away from whisker hits.
func avoid(dir: Vector3) -> Vector3:
	var l := _whisker_l != null and _whisker_l.is_colliding()
	var r := _whisker_r != null and _whisker_r.is_colliding()
	if l and not r:
		return dir.rotated(Vector3.UP, -0.9).normalized()
	if r and not l:
		return dir.rotated(Vector3.UP, 0.9).normalized()
	if l and r:
		return dir.rotated(Vector3.UP, 1.6).normalized()
	return dir


## Keeps a desired direction outside a circular obstacle (the cabin): slide tangentially.
static func keep_out(pos: Vector3, dir: Vector3, center: Vector3, radius: float) -> Vector3:
	var to_c := flat(center - pos)
	var d := to_c.length()
	if d > radius + 1.0:
		return dir
	var n := to_c.normalized()
	if dir.dot(n) <= 0.0:
		return dir
	var tangent := Vector3(-n.z, 0, n.x)
	if tangent.dot(dir) < 0.0:
		tangent = -tangent
	var push := (radius + 1.0 - d) * 0.5
	return (tangent - n * push).normalized()


static func flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v
