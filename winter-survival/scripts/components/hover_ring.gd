class_name HoverRing
extends MeshInstance3D
## Flat accent ring shown under the hovered interactable.

const COLOR_OK := Color("#FFB454")
const COLOR_BAD := Color("#FF5A5A")

var _mat: StandardMaterial3D
var _t: float = 0.0


func _ready() -> void:
	top_level = true
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.65
	torus.rings = 24
	torus.ring_segments = 6
	mesh = torus
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = COLOR_OK
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.no_depth_test = false
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var pulse := 1.0 + 0.06 * sin(_t * 6.0)
	scale = Vector3(pulse, 1.0, pulse) * _base_scale
	_mat.albedo_color.a = 0.75 + 0.2 * sin(_t * 6.0)


var _base_scale: float = 1.0


func show_at(pos: Vector3, radius: float, ok: bool) -> void:
	global_position = pos + Vector3(0, 0.06, 0)
	_base_scale = radius / 0.6
	_mat.albedo_color = COLOR_OK if ok else COLOR_BAD
	visible = true


func hide_ring() -> void:
	visible = false
