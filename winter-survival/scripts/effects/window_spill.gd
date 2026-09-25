class_name WindowSpill
extends Node3D
## Warm light spill of a lit window (G1, doc 06 §3.10): a SpotLight3D at the glass pointing 45° down with a
## procedural 4-pane projector (Forward+, `Quality.allows("projectors")`) + a small OmniLight3D wash on the frame
## and the snow bank under the sill. No shadows. Energy = base × DayNight.spill_scale (0 by day) × `enabled`
## (the owner: stove lit, dark). Group "window_spill": DayNight pushes its scale into every member.

const COLOR := Color("#FFC070")
const WASH_COLOR := Color("#FFB868")

static var _projector: ImageTexture

var spot: SpotLight3D
var wash: OmniLight3D
var base_energy: float = 3.0
var enabled: bool = false
var _scale: float = 0.0


## Adds one WindowSpill per `Windows*` mesh found under `model`, at the glass centre, facing out of the wall
## (dominant horizontal axis of the mesh centre in model space, like Cutaway does). Returns the spills.
static func attach_to_windows(host: Node3D, model: Node3D, energy: float, range_m: float) -> Array[WindowSpill]:
	var out: Array[WindowSpill] = []
	for mi in model.find_children("Windows*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var c := m.get_aabb().get_center()
		var n: Node3D = m
		while n != null and n != model:
			c = n.transform * c
			n = n.get_parent() as Node3D
		var normal := Vector3(0, 0, 1)
		if absf(c.x) > 0.3 or absf(c.z) > 0.3:
			normal = Vector3(0, 0, signf(c.z)) if absf(c.z) >= absf(c.x) else Vector3(signf(c.x), 0, 0)
		var spill := WindowSpill.new()
		spill.name = "Spill_" + String(m.name)
		spill.base_energy = energy
		host.add_child(spill)
		spill.position = model.position + model.transform.basis * (c + normal * 0.12)
		spill.setup(model.transform.basis * normal, range_m)
		out.append(spill)
	return out


func setup(dir: Vector3, range_m: float) -> void:
	spot = SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = COLOR
	spot.spot_range = range_m
	spot.spot_angle = 48.0
	spot.spot_angle_attenuation = 0.8
	spot.spot_attenuation = 1.2
	spot.shadow_enabled = false
	spot.light_volumetric_fog_energy = 2.0
	spot.light_indirect_energy = 0.0
	if Quality.allows("projectors"):
		spot.light_projector = projector()
	add_child(spot)
	var aim := (dir.normalized() + Vector3.DOWN * 0.95).normalized()
	spot.look_at_from_position(global_position, global_position + aim, Vector3.UP)
	wash = OmniLight3D.new()
	wash.name = "Wash"
	wash.light_color = WASH_COLOR
	wash.omni_range = range_m * 0.45
	wash.omni_attenuation = 1.4
	wash.shadow_enabled = false
	wash.light_indirect_energy = 0.0
	add_child(wash)
	wash.position = dir.normalized() * 0.5
	add_to_group("window_spill")
	_apply()


func set_enabled(value: bool) -> void:
	enabled = value
	_apply()


## Called by DayNight (0 by day, 0.3 dusk, 0.45 night, 0.7 blizzard).
func set_spill_scale(value: float) -> void:
	_scale = value
	_apply()


func _apply() -> void:
	if spot == null:
		return
	var on := enabled and _scale > 0.005
	spot.visible = on
	wash.visible = on
	spot.light_energy = base_energy * _scale
	wash.light_energy = base_energy * 0.25 * _scale


## 4-pane window cookie: bright panes, dark mullions, soft edge (shared by every spill).
static func projector() -> ImageTexture:
	if _projector != null:
		return _projector
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var u := (float(x) + 0.5) / float(s)
			var v := (float(y) + 0.5) / float(s)
			var edge := smoothstep(0.0, 0.10, u) * smoothstep(0.0, 0.10, 1.0 - u) * smoothstep(0.0, 0.10, v) * smoothstep(0.0, 0.10, 1.0 - v)
			var mull := 1.0
			if absf(u - 0.5) < 0.035 or absf(v - 0.5) < 0.035:
				mull = 0.25
			var val := edge * mull
			img.set_pixel(x, y, Color(val, val, val, 1.0))
	_projector = ImageTexture.create_from_image(img)
	return _projector
