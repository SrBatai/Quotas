class_name HangingCables
extends Node3D
## G2b hanging cables (tram / power wires across a street) that swing in the wind (world_vcol_cable,
## wind_include WV_WIND_CABLE: the swing grows toward mid-span). One MultiMesh per span bucket (a cable mesh built
## for that span: a sagging cross-section ribbon, readable from the high camera), rotation only per instance so the
## shader's model-space span maths holds. Owners add and remove sets of cables (AmbientLife: across the Gran Vía
## between facing street lamps, per city chunk).

const SEGMENTS := 20
const THICK := 0.045
const SAG_PER_M := 0.035
const COLOR := Color(0.035, 0.037, 0.045, 1.0)   # linear vertex colour (COLOR_0 is linear, ASSET_SPEC v2 §2.5)

var _by_owner: Dictionary = {}                  # owner -> Array of [a: Vector3, b: Vector3]
var _mmis: Dictionary = {}                      # span bucket (m) -> MultiMeshInstance3D
static var _meshes: Dictionary = {}


func put_set(key: int, spans: Array) -> void:
	if spans.is_empty():
		_by_owner.erase(key)
	else:
		_by_owner[key] = spans
	_rebuild()


func remove_set(key: int) -> void:
	if _by_owner.erase(key):
		_rebuild()


func count() -> int:
	var n := 0
	for k in _by_owner:
		n += (_by_owner[k] as Array).size()
	return n


func _rebuild() -> void:
	var buckets := {}
	for k in _by_owner:
		for s in _by_owner[k]:
			var a: Vector3 = s[0]
			var b: Vector3 = s[1]
			var span := int(round(Vector2(b.x - a.x, b.z - a.z).length()))
			if span < 2:
				continue
			if not buckets.has(span):
				buckets[span] = []
			(buckets[span] as Array).append(s)
	for span in _mmis.keys():
		if not buckets.has(span):
			(_mmis[span] as Node).queue_free()
			_mmis.erase(span)
	for span in buckets:
		var list: Array = buckets[span]
		var mmi: MultiMeshInstance3D = _mmis.get(span)
		if mmi == null:
			mmi = MultiMeshInstance3D.new()
			mmi.name = "Cables%d" % span
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			_mmis[span] = mmi
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cable_mesh(float(span))
		mm.instance_count = list.size()
		for i in list.size():
			var a: Vector3 = list[i][0]
			var b: Vector3 = list[i][1]
			var mid := (a + b) * 0.5
			var yaw := atan2(-(b.z - a.z), b.x - a.x)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), mid))
		mmi.multimesh = mm
		mmi.material_override = WindSway.material("cable", float(span))


## A cable of `span` metres along model X, centred on its origin, sagging SAG_PER_M per metre at mid-span: two
## crossed ribbons (flat + upright) so it reads from above and from the side.
static func cable_mesh(span: float) -> ArrayMesh:
	var key := int(round(span))
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sag := SAG_PER_M * span
	for i in SEGMENTS:
		var t0 := float(i) / SEGMENTS
		var t1 := float(i + 1) / SEGMENTS
		var p0 := Vector3((t0 - 0.5) * span, -sag * 4.0 * t0 * (1.0 - t0), 0.0)
		var p1 := Vector3((t1 - 0.5) * span, -sag * 4.0 * t1 * (1.0 - t1), 0.0)
		for side in [Vector3(0, 0, THICK), Vector3(0, THICK, 0)]:
			var s: Vector3 = side
			var n := Vector3.UP if s.z != 0.0 else Vector3.BACK
			_quad(st, p0 - s * 0.5, p1 - s * 0.5, p1 + s * 0.5, p0 + s * 0.5, n)
	var m := st.commit()
	_meshes[key] = m
	return m


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.set_color(COLOR)
		st.set_normal(n)
		st.add_vertex(v)
