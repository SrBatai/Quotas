class_name KitStreet
extends Node3D
## A street of kit buildings placed like a POI (M6a test street; the settlement generator of M6b / C3 will emit the
## same data): res://data/buildings/streets/<id>.json = centre (world x, z; on a flat pad), road (half length /
## half width / sidewalk), lots [{template, style, pos [x, z] from the centre, yaw (0 = front +Z), number, shop}]
## and signs [{board, pos, yaw, text, back}]. Built by KitStreets under the WorldChunk that contains the centre (it
## lives and dies with that chunk; the street is ~90 m long, well inside the 5 x 5 ring around a player standing
## in it), on the server and on every client alike: one building per frame (KitBuilding), then the signs. Visual
## clients also get the road ribbon (asphalt ruts, packed snow, curbs, sidewalks; vertex colour, one draw call).

signal finished

const GEN_STREET := 0x53545254       # "STRT"

var data: Dictionary = {}
var street_id: String = ""
var seed_v: int = 0
var buildings: Array[KitBuilding] = []
var signs: Array[Node3D] = []
var done: bool = false
var _next: int = 0


func setup(p_data: Dictionary, p_seed: int, base_y: float) -> void:
	data = p_data
	street_id = str(p_data.get("id", "street"))
	seed_v = p_seed
	var c: Array = p_data.get("center", [0.0, 0.0])
	position = Vector3(float(c[0]), base_y, float(c[1]))
	name = "Street_%s" % street_id
	set_meta("wid", WorldConst.hash64(p_seed, GEN_STREET, street_id.hash()))
	set_meta("street", street_id)


func _ready() -> void:
	add_to_group("kit_street")
	if KitBuilding.visual():
		_road()


func _process(_delta: float) -> void:
	if done:
		set_process(false)
		return
	_step()


## Builds everything now (tests, screenshots).
func build_all() -> void:
	while not done:
		_step()


func _step() -> void:
	var lots: Array = data.get("lots", [])
	if _next < lots.size():
		var lot: Dictionary = lots[_next]
		var b := KitBuilding.new()
		b.setup(str(lot["template"]), str(lot["style"]), KitBuilding.wid_for(seed_v, street_id, _next), seed_v,
			int(lot.get("number", 0)), str(lot.get("shop", "")))
		var p: Array = lot["pos"]
		b.position = Vector3(float(p[0]), 0.0, float(p[1]))
		b.rotation.y = deg_to_rad(float(lot.get("yaw", 0.0)))
		add_child(b)
		buildings.append(b)
		_next += 1
		return
	for s in data.get("signs", []):
		var p: Array = s["pos"]
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(s.get("yaw", 0.0)))), Vector3(float(p[0]), 0.0, float(p[1])))
		signs.append(SignText.place(self, str(s["board"]), xf, str(s.get("text", "")), str(s.get("back", ""))))
	done = true
	set_process(false)
	if Net.is_server and NavBaker.instance != null:
		var r := float((data.get("road", {}) as Dictionary).get("half_len", 40.0)) + 16.0
		for dx in [-r, 0.0, r]:
			for dz in [-24.0, 0.0, 24.0]:
				NavBaker.instance.mark_dirty_key(WorldConst.key_of(global_position + Vector3(dx, 0.0, dz)))
	print("[STREET] %s built: %d buildings, %d signs" % [street_id, buildings.size(), signs.size()])
	finished.emit()


## The building whose storeys contain the world point (and the storey), or [null, -1].
func building_at(p_world: Vector3) -> Array:
	for b in buildings:
		var k := b.floor_at(p_world)
		if k >= 0:
			return [b, k]
	return [null, -1]


# ------------------------------------------------------------------ road ribbon (visual clients)
## Packed snow over the carriageway, ploughed berms along the curbs and two wheel ruts per lane (the asphalt shows
## through): each rut a strip in 2 m steps whose centre wanders a few cm and whose depth of colour varies along it
## (smooth, deterministic: vertex colours interpolate), so from the camera it reads as tracks, not as painted stripes.
const PACKED := "#CCD7E5"
const RUT := "#99A3B1"
const BERM := "#DDE5EF"
const RUTS := [-2.55, -0.95, 0.95, 2.55]   # rut centres (m) for a 3.5 m half width (lanes at ±1.75)
const RUT_W := 0.42
const SEG := 2.0
const CURB := "#9EA3A8"
const WALK := "#DCE4EE"


func _road() -> void:
	var road: Dictionary = data.get("road", {})
	var L := float(road.get("half_len", 40.0))
	var hw := float(road.get("half_width", 3.5))
	var sw := float(road.get("sidewalk", 2.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var s := hw / 3.5
	_quad_h(st, -L, L, -hw, hw, 0.03, Color(PACKED))
	for i in RUTS.size():
		_rut(st, L, float(RUTS[i]) * s, RUT_W * s, i)
	for side in [-1.0, 1.0]:
		var z0: float = side * hw
		var z1: float = side * (hw + sw)
		var zb: float = side * (hw - 0.55 * s)
		_quad_h(st, -L, L, minf(zb, z0), maxf(zb, z0), 0.045, Color(BERM))
		_quad_h(st, -L, L, minf(z0, z1), maxf(z0, z1), 0.06, Color(WALK))
		# curb face toward the road + outer edge
		_quad_v(st, -L, L, z0, 0.03, 0.06, Color(CURB), -side)
		_quad_v(st, -L, L, z1, 0.0, 0.06, Color(WALK), side)
	var mesh := st.commit()
	mesh.surface_set_material(0, Assets.get_shared_material())
	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _rut(st: SurfaceTool, L: float, zc: float, w: float, i: int) -> void:
	var packed := Color(PACKED)
	var rut := Color(RUT)
	var n := maxi(1, ceili(2.0 * L / SEG))
	var ph := float(i) * 1.7
	for k in n:
		var xa := -L + 2.0 * L * float(k) / float(n)
		var xb := -L + 2.0 * L * float(k + 1) / float(n)
		var za := zc + 0.07 * sin(xa * 0.21 + ph) + 0.03 * sin(xa * 0.57 + ph * 2.3)
		var zb := zc + 0.07 * sin(xb * 0.21 + ph) + 0.03 * sin(xb * 0.57 + ph * 2.3)
		var ca := packed.lerp(rut, clampf(0.6 + 0.28 * sin(xa * 0.37 + ph) + 0.12 * sin(xa * 1.13 + ph * 0.7), 0.15, 1.0))
		var cb := packed.lerp(rut, clampf(0.6 + 0.28 * sin(xb * 0.37 + ph) + 0.12 * sin(xb * 1.13 + ph * 0.7), 0.15, 1.0))
		var v := [Vector3(xa, 0.04, za - w * 0.5), Vector3(xb, 0.04, zb - w * 0.5), Vector3(xb, 0.04, zb + w * 0.5), Vector3(xa, 0.04, za + w * 0.5)]
		var c := [ca, cb, cb, ca]
		for j in [0, 1, 2, 0, 2, 3]:
			var lin := (c[j] as Color).srgb_to_linear()
			lin.a = 1.0
			st.set_color(lin)
			st.set_normal(Vector3.UP)
			st.add_vertex(v[j])


func _quad_h(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float, y: float, col: Color) -> void:
	var lin := col.srgb_to_linear()
	lin.a = 1.0
	var v := [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(lin)
		st.set_normal(Vector3.UP)
		st.add_vertex(v[i])
	# (x0, z0) -> (x1, z0) -> (x1, z1): clockwise seen from above = front face up (Godot winding)


func _quad_v(st: SurfaceTool, x0: float, x1: float, z: float, y0: float, y1: float, col: Color, facing: float) -> void:
	var lin := col.srgb_to_linear()
	lin.a = 1.0
	var n := Vector3(0, 0, facing)
	var v := [Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)]
	var order := [0, 2, 1, 0, 3, 2] if facing > 0.0 else [0, 1, 2, 0, 2, 3]
	for i in order:
		st.set_color(lin)
		st.set_normal(n)
		st.add_vertex(v[i])
