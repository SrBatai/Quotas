class_name Flock
extends MultiMeshInstance3D
## G2b circling flock («bandadas (render)», doc 08 §3.9): `birds` crows wheeling over a spot, all computed in
## assets/shaders/flock.gdshader from per-bird custom data and one clock (1 draw call + the shadow pass, 0 CPU per
## frame beyond setting the clock). The birds cast shadows: from the high game camera the flock is often above the
## frame, but its shadows cross the snow. AmbientLife hides flocks at night and in a blizzard (crows roost).
## Render only; the takeoff / scare behaviour and the server registry are V1's (docs/research/09 §5.3).

const MATERIAL := "res://assets/materials/flock_crow.tres"

@export var birds: int = 14
@export var radius: float = 16.0
@export var height: float = 9.0
@export var seed_value: int = 1

static var _mesh: ArrayMesh
static var _clock_frame: int = -1
static var _clock: float = 0.0


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	material_override = load(MATERIAL)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = bird_mesh()
	mm.instance_count = birds
	for i in birds:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		var h := WorldConst.hash64(seed_value, 0x46C0, i)
		var u := WorldConst.unit(h)
		var v := WorldConst.unit(WorldConst.hash64(h, 1))
		var w := WorldConst.unit(WorldConst.hash64(h, 2))
		var z := WorldConst.unit(WorldConst.hash64(h, 3))
		# most of the flock wheels one way; phase > 0.5 flies the other (the shader reads the sign from it)
		var phase := u * 0.5 if i % 5 != 0 else 0.5 + u * 0.5
		mm.set_instance_custom_data(i, Color(phase, radius * lerpf(0.55, 1.2, v), height * lerpf(0.7, 1.35, w), lerpf(0.8, 1.35, z)))
	multimesh = mm
	var r := radius * 1.6 + 4.0
	custom_aabb = AABB(Vector3(-r, -2.0, -r), Vector3(2.0 * r, height * 2.0 + 6.0, 2.0 * r))


func _process(delta: float) -> void:
	# one clock for every flock (shared material): advance it once per frame
	var f := Engine.get_process_frames()
	if f != _clock_frame:
		_clock_frame = f
		_clock += delta
		(material_override as ShaderMaterial).set_shader_parameter("clock", _clock)


## A crow: body along +Z (0.45 m), wings along ±X (0.9 m span), COLOR.r = 1 on the tips (the shader flaps them).
static func bird_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := Color(0, 0, 0, 1)
	var tip := Color(1, 0, 0, 1)
	var tris := [
		# body (a flat diamond + a raised spine so it has some volume from above)
		[Vector3(0, 0, 0.26), Vector3(0.06, 0, 0.0), Vector3(0, 0.05, 0.02)],
		[Vector3(0, 0, 0.26), Vector3(0, 0.05, 0.02), Vector3(-0.06, 0, 0.0)],
		[Vector3(0.06, 0, 0.0), Vector3(0, 0, -0.2), Vector3(0, 0.05, 0.02)],
		[Vector3(0, 0.05, 0.02), Vector3(0, 0, -0.2), Vector3(-0.06, 0, 0.0)],
		# tail fan
		[Vector3(0, 0, -0.16), Vector3(0.07, 0, -0.3), Vector3(-0.07, 0, -0.3)],
		# wings: inner and outer panels
		[Vector3(0.05, 0, 0.08), Vector3(0.24, 0, 0.06), Vector3(0.05, 0, -0.06)],
		[Vector3(0.24, 0, 0.06), Vector3(0.45, 0, -0.04), Vector3(0.22, 0, -0.08)],
		[Vector3(-0.05, 0, 0.08), Vector3(-0.05, 0, -0.06), Vector3(-0.24, 0, 0.06)],
		[Vector3(-0.24, 0, 0.06), Vector3(-0.22, 0, -0.08), Vector3(-0.45, 0, -0.04)],
	]
	for t in tris:
		for v in t:
			var vv: Vector3 = v
			var tipness := clampf((absf(vv.x) - 0.05) / 0.4, 0.0, 1.0)
			st.set_color(body.lerp(tip, tipness))
			st.set_normal(Vector3.UP)
			st.add_vertex(vv)
	_mesh = st.commit()
	return _mesh
