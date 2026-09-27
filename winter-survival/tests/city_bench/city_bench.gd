extends Node3D
## W0 + G2a city bench scene (tests only, never exported): a downtown street canyon built in code with the game's
## rendering stack — DayNight keys, Quality presets, the terrain shader for the streets (CUSTOM0 road mask, ruts),
## the «corte urbano» materials (world_vcol_struct / window_city / world_vcol_capsule), CityCut, Silhouettes,
## CityLights (windows by cell, lamp pools, nearest real lights), CityHlod, CameraRig + city CameraZone.
##
## Layout (x east, z south; the default camera yaw 45° looks from +x+z toward −x−z):
##   N–S avenue x ∈ [−7, 7] (8 m road + 3 m sidewalks), cross streets at z = 0 and z = 48, blocks of 34 m.
##   Camera-side block (+x, +z): a 30-floor glass tower + a 6-floor block; far side (−x, +z): a 6-floor
##   «ensanche» mid-rise on the avenue (enterable cut groups, generator-powered) + a 20-floor tower behind; north:
##   40 and 12 floors; more towers around for shadows. Buildings follow the city contract (ARQ v2 §9.7): Base /
##   Shaft_<n> (4-floor groups) / Roof / ShadowProxy, closed volumes with thick walls, one slab per floor, a core
##   and a partition per floor (the plan the cut shows). Cars from Kenney / Quaternius CC0 kits winterized by the
##   doc 07 pass (copied to models/ as test-only resources), street lamps, barriers.
## Player at street level mid-block (canyon) — or at the crossing, or on the mid-rise roof — with a group of
## zombies around. `measure_mode` swaps the characters to flat key colours for the visibility gate.

const FLOOR_H := 3.0
const FOUNDATION := 0.3
const STREET_HALF := 7.0
const BLOCK := 34.0
const PERIOD := 48.0
const MODELS := "res://tests/city_bench/models/"
## The art agent's winterized, cut-ready city set (A1). Used when present; the test-only copies in MODELS (and the
## procedural buildings) are the fallback, so the bench never depends on a particular art delivery.
const ART := "res://assets/models/city/"
const KEY_PLAYER := Color(0, 1, 0)
const KEY_ZOMBIE := Color(1, 0, 0)
const KEY_PLAYER_SIL := Color(0, 1, 1)
const KEY_ZOMBIE_SIL := Color(1, 0.5, 0)

## Views: player position and yaw index of the camera.
const VIEWS := {
	"canyon": Vector3(0.0, 0.0, 24.0),
	"crossing": Vector3(-1.5, 0.0, 2.0),
	"rooftop": Vector3(-13.5, 0.0, 26.0),   # y replaced by the mid-rise roof height
	"inside": Vector3(-11.0, 0.0, 22.0),    # 3rd floor of the mid-rise (own-building rule); y = that floor's level
	"north": Vector3(-1.0, 0.0, -30.0),     # the art tower tower_d (100 m) between the camera and the player
}
## Art towers placed in the blocks of the procedural ones (name -> [glb id, x, z]); tower_d sits on the camera side
## of the `north` view.
const ART_TOWERS := {"TowerN": ["towers/tower_d", 16.0, -22.0], "TowerS": ["towers/tower_b", 20.0, 68.0],
	"TowerE": ["towers/tower_a", 68.0, 20.0], "TowerFarW": ["towers/tower_c", -68.0, 24.0], "TowerNW": ["towers/tower_e", -70.0, -24.0],
	"BlockNE": ["buildings/bldg_m", 70.0, -24.0], "BlockSW": ["buildings/bldg_n", -24.0, 70.0]}
var art_used: Array[String] = []

var buildings: Array[Node3D] = []
var occluders: Array[Node3D] = []        # buildings + cars + lamps + barriers (hidden for the reference frame)
var player: Node3D
var player_visual: Node3D
var zombies: Array[Node3D] = []
var rig: CameraRig
var cut: CityCut
var sil: Silhouettes
var lights: CityLights
var day_night: DayNight
var sun: DirectionalLight3D
var env: WorldEnvironment
var hlod: MeshInstance3D
var zone: CameraZone
var midrise: Node3D
var measure_mode: bool = false
var _key_mats: Dictionary = {}
var _ground_mat: ShaderMaterial


func build(p_measure: bool = false) -> void:
	measure_mode = p_measure
	_environment()
	_ground()
	_city()
	_props()
	_characters()
	_camera()
	var chunk := Node3D.new()
	chunk.name = "HlodSpace"
	add_child(chunk)
	hlod = CityHlod.build_for(self)


# ------------------------------------------------------------------ environment (the game's DayNight)
func _environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	add_child(moon)
	env = WorldEnvironment.new()
	env.name = "Env"
	add_child(env)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.menu_hour = 11.0
	add_child(day_night)
	lights = CityLights.new()
	lights.name = "CityLights"
	add_child(lights)
	cut = CityCut.new()
	cut.name = "CityCut"
	add_child(cut)
	sil = Silhouettes.new()
	sil.name = "Silhouettes"
	add_child(sil)
	var drift := SnowDrift.new()
	drift.name = "SnowDrift"
	add_child(drift)
	zone = CameraZone.new()
	zone.name = "DowntownZone"
	zone.size = Vector3(400, 400, 400)
	add_child(zone)
	CityLights.create_power_map(-200.0, -200.0, 400.0, 400.0, 8.0, 1.0)


## Flat day look for the visibility gate: no fog, linear tonemap, no glow, unshaded key colours stay pure.
func flat_environment() -> void:
	day_night.set_process(false)
	var drift := get_node_or_null("SnowDrift") as GPUParticles3D
	if drift != null:
		drift.set_process(false)
		drift.emitting = false
		drift.visible = false
	var e := env.environment
	e.fog_enabled = false
	e.glow_enabled = false
	e.ssao_enabled = false
	e.volumetric_fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.adjustment_enabled = false


# ------------------------------------------------------------------ ground: streets + sidewalks with the terrain shader
func _ground() -> void:
	var size := 360.0
	var step := 2.0
	var n := int(size / step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
	var h0 := -size * 0.5
	for iz in n:
		for ix in n:
			var x0 := h0 + ix * step
			var z0 := h0 + iz * step
			var q := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = q[idx]
				st.set_color(Color(1, 1, 1, 1))
				st.set_normal(Vector3.UP)
				st.set_custom(0, _road_mask(v.x, v.z))
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Streets"
	mi.mesh = st.commit()
	_ground_mat = Assets.get_terrain_material()
	mi.material_override = _ground_mat
	add_child(mi)


## CUSTOM0 of terrain.gdshader: r asphalt road bed, a = lateral offset (128 + 16 m) for the ruts.
func _road_mask(x: float, z: float) -> Color:
	var road_x := absf(x) < 4.2
	var cz := posmod(z + PERIOD * 0.5, PERIOD) - PERIOD * 0.5   # distance to the nearest cross street (z = 0, 48, …)
	var road_z := absf(cz) < 4.2
	if road_x:
		return Color(0.9, 0, 0, clampf((128.0 + 16.0 * x) / 255.0, 0.0, 1.0))
	if road_z:
		return Color(0.9, 0, 0, clampf((128.0 + 16.0 * cz) / 255.0, 0.0, 1.0))
	var walk := absf(x) < STREET_HALF or absf(cz) < STREET_HALF
	return Color(0, 0, 0.8, 0) if walk else Color(0, 0, 0, 0)


# ------------------------------------------------------------------ buildings (city contract)
func _city() -> void:
	# [centre x, centre z, size x, size z, floors, style, ground 4 m, generator, name]
	var list := [
		[20.0, 28.0, 24.0, 24.0, 30, "glass", true, false, "TowerCam"],          # camera side: contains the camera at 24 and 38 m
		[20.0, 10.5, 24.0, 5.0, 6, "brick", false, false, "BlockCam"],
		[-13.5, 24.0, 11.0, 30.0, 6, "ensanche", false, true, "MidRise"],        # on the avenue, beyond the player
		[-31.0, 24.0, 18.0, 26.0, 20, "concrete", true, false, "TowerW"],
		[24.0, -24.0, 24.0, 24.0, 40, "glass", true, false, "TowerN"],
		[-24.0, -24.0, 30.0, 26.0, 12, "concrete", false, false, "BlockNW"],
		[24.0, 72.0, 28.0, 26.0, 24, "glass", true, false, "TowerS"],
		[-24.0, 72.0, 30.0, 28.0, 8, "brick", false, false, "BlockSW"],
		[72.0, 24.0, 26.0, 26.0, 36, "concrete", true, false, "TowerE"],
		[-72.0, 24.0, 28.0, 28.0, 16, "glass", true, false, "TowerFarW"],
		[72.0, -24.0, 26.0, 26.0, 10, "brick", false, false, "BlockNE"],
		[-72.0, -24.0, 26.0, 26.0, 28, "concrete", true, false, "TowerNW"],
	]
	for b in list:
		var node: Node3D = null
		var bname := String(b[8])
		if ART_TOWERS.has(bname):
			var spec: Array = ART_TOWERS[bname]
			node = _art(String(spec[0]))
			if node != null:
				node.name = bname
				node.position = Vector3(float(spec[1]), 0.0, float(spec[2]))
				art_used.append(String(spec[0]))
		if node == null:
			node = make_building(bname, float(b[2]), float(b[3]), int(b[4]), String(b[5]), bool(b[6]), bool(b[7]))
			node.position = Vector3(float(b[0]), 0.0, float(b[1]))
		add_child(node)
		CityBuilding.attach(node)
		buildings.append(node)
		occluders.append(node)
		if node.name == "MidRise":
			midrise = node
		if bool(b[7]):
			CityLights.paint_power(float(b[0]) - float(b[2]) * 0.5, float(b[1]) - float(b[3]) * 0.5,
				float(b[0]) + float(b[2]) * 0.5, float(b[1]) + float(b[3]) * 0.5, 1.0)


## A closed building per the contract. `ground4` = 4 m commercial ground floor (ground_h 4.3).
func make_building(bname: String, sx: float, sz: float, floors: int, style: String, ground4: bool, generator: bool) -> Node3D:
	var root := Node3D.new()
	root.name = bname
	var gh := 4.3 if ground4 else 3.3
	root.set_meta("floor_h", FLOOR_H)
	root.set_meta("ground_h", gh)
	root.set_meta("foundation", FOUNDATION)
	root.set_meta("floors", floors)
	root.set_meta("generator", generator)
	root.set_meta("kind", style)
	var pal := _palette(style, bname.hash())
	var podium := mini(floors, 3 if floors > 8 else floors)
	root.add_child(_piece("Base", sx, sz, 0, podium, gh, style, pal, true))
	var f := podium
	var g := 0
	while f < floors:
		var to := mini(f + 4, floors)
		var s := _piece("Shaft_%d" % g, sx, sz, f, to, gh, style, pal, false)
		s.set_meta("floor_from", f)
		s.set_meta("floor_to", to - 1)
		root.add_child(s)
		f = to
		g += 1
	var top := _level(floors, gh)
	root.add_child(_roof(sx, sz, top, pal))
	# shadow proxy: a closed box from the ground to the parapet (12 tris); the node stays at y = 0 (contract), the
	# box is offset in the mesh
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, top + 1.1, sz)
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i].y += (top + 1.1) * 0.5
	arr[Mesh.ARRAY_VERTEX] = verts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var proxy := MeshInstance3D.new()
	proxy.name = "ShadowProxy"
	proxy.mesh = am
	root.add_child(proxy)
	# collision: one box (cursor / LOS rays)
	var body := StaticBody3D.new()
	body.name = "ColBody"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(sx, top, sz)
	cs.shape = box
	cs.position = Vector3(0, top * 0.5, 0)
	body.add_child(cs)
	root.add_child(body)
	return root


func _level(k: int, gh: float) -> float:
	return FOUNDATION if k <= 0 else gh + float(k - 1) * FLOOR_H


func _palette(style: String, h: int) -> Dictionary:
	var t := float(posmod(h, 97)) / 97.0
	match style:
		"glass":
			return {"wall": Color(0.46 + t * 0.08, 0.50 + t * 0.06, 0.56), "spandrel": Color(0.30, 0.33, 0.38), "band": true}
		"brick":
			return {"wall": Color(0.52 + t * 0.1, 0.33, 0.27), "spandrel": Color(0.44, 0.29, 0.24), "band": false}
		"ensanche":
			return {"wall": Color(0.78, 0.70 + t * 0.05, 0.58), "spandrel": Color(0.70, 0.62, 0.50), "band": false}
	return {"wall": Color(0.62 + t * 0.06, 0.62, 0.60), "spandrel": Color(0.52, 0.52, 0.51), "band": true}


## Floors [f0, f1) of the building as one MeshInstance3D: structure surface (vertex colour) + glass surface.
func _piece(pname: String, sx: float, sz: float, f0: int, f1: int, gh: float, style: String, pal: Dictionary, base: bool) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat normals (the default group 0 averages shared corners)
	var gl := SurfaceTool.new()
	gl.begin(Mesh.PRIMITIVE_TRIANGLES)
	gl.set_smooth_group(-1)   # flat normals (the default group 0 averages shared corners)
	var hx := sx * 0.5
	var hz := sz * 0.5
	var wall: Color = pal["wall"]
	var spandrel: Color = pal["spandrel"]
	var inner := Color(0.74, 0.72, 0.68)
	var slab := Color(0.66, 0.66, 0.64)
	var core := Color(0.40, 0.40, 0.42)
	var t := 0.25   # wall thickness
	for k in range(f0, f1):
		var y0 := _level(k, gh) - (FOUNDATION if k == 0 else 0.0)
		var y1 := _level(k + 1, gh)
		var fl := _level(k, gh)
		var hgt := y1 - y0
		# outer facade: sill / window band / spandrel; the ground floor of towers is a shop front
		var sill := 0.9 if k > 0 else (0.5 if base and gh > 4.0 else 0.9)
		var win_top := hgt - 0.5
		_walls(st, hx, hz, y0, y0 + sill, spandrel, 1.0)
		_walls(st, hx, hz, y0 + win_top, y1, spandrel, 1.0)
		if bool(pal["band"]) or (k == 0 and gh > 4.0):
			_walls(gl, hx, hz, y0 + sill, y0 + win_top, Color(0.2, 0.25, 0.3), 1.0)
		else:
			_bays(st, gl, hx, hz, y0 + sill, y0 + win_top, wall)
		# inner face (plaster, sheltered), thick wall
		_walls(st, hx - t, hz - t, fl, y1 - 0.2, inner, 0.45, true)
		# slab top (the plan) + underside
		_quad_h(st, hx - t, hz - t, fl, true, slab, 0.3)
		if k > 0:
			_quad_h(st, hx - t, hz - t, fl - 0.2, false, slab, 0.3)
		# partition across the long axis + a stair / lift core (open top: reads black in the cut)
		if sx >= sz:
			_box_open(st, Vector3(0, fl, 0), Vector2(0.12, hz - t), y1 - 0.2 - fl, inner, 0.45)
			_box_open(st, Vector3(hx * 0.35, fl, 0), Vector2(2.0, 3.0), y1 - 0.2 - fl, core, 0.3)
		else:
			_box_open(st, Vector3(0, fl, 0), Vector2(hx - t, 0.12), y1 - 0.2 - fl, inner, 0.45)
			_box_open(st, Vector3(0, fl, hz * 0.35), Vector2(3.0, 2.0), y1 - 0.2 - fl, core, 0.3)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, Assets.get_shared_material())
	gl.generate_normals()
	gl.commit(mesh)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _glass_placeholder())
	var mi := MeshInstance3D.new()
	mi.name = pname
	mi.mesh = mesh
	return mi


## The `window` exception material the art exports (CityBuilding swaps it for window_city).
func _glass_placeholder() -> StandardMaterial3D:
	if not _key_mats.has("window"):
		var m := StandardMaterial3D.new()
		m.resource_name = "window"
		_key_mats["window"] = m
	return _key_mats["window"]


## Window bays of 2.4 m along each facade: 0.5 m piers (structure) around a 1.4 m window (glass).
func _bays(st: SurfaceTool, gl: SurfaceTool, hx: float, hz: float, y0: float, y1: float, col: Color) -> void:
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		var length := a.distance_to(b)
		var n := maxi(1, int(round(length / 2.4)))
		var bay := length / float(n)
		var dir := (b - a) / length
		for i in n:
			var s0 := a + dir * (bay * i)
			var s1 := s0 + dir * 0.5
			var s2 := s0 + dir * (bay - 0.5)
			var s3 := s0 + dir * bay
			_wall_quad(st, s0, s1, y0, y1, col, 1.0)
			_wall_quad(gl, s1, s2, y0, y1, Color(0.2, 0.25, 0.3), 1.0)
			_wall_quad(st, s2, s3, y0, y1, col, 1.0)


func _walls(st: SurfaceTool, hx: float, hz: float, y0: float, y1: float, col: Color, ao: float, inward: bool = false) -> void:
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = c[k]
		var b: Vector2 = c[(k + 1) % 4]
		if inward:
			_wall_quad(st, b, a, y0, y1, col, ao)
		else:
			_wall_quad(st, a, b, y0, y1, col, ao)


## Outward-facing wall quad from a to b (counter-clockwise seen from outside, like the prototype).
func _wall_quad(st: SurfaceTool, a: Vector2, b: Vector2, y0: float, y1: float, col: Color, ao: float) -> void:
	_quad(st, Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), col, ao)


## Thin closed box without top / bottom (partition, core): outward faces only.
func _box_open(st: SurfaceTool, centre: Vector3, half: Vector2, h: float, col: Color, ao: float) -> void:
	var c := [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]
	for k in 4:
		var a: Vector2 = c[k] + Vector2(centre.x, centre.z)
		var b: Vector2 = c[(k + 1) % 4] + Vector2(centre.x, centre.z)
		_wall_quad(st, a, b, centre.y, centre.y + h, col, ao)


func _quad_h(st: SurfaceTool, hx: float, hz: float, y: float, up: bool, col: Color, ao: float) -> void:
	if up:
		_quad(st, Vector3(-hx, y, hz), Vector3(hx, y, hz), Vector3(hx, y, -hz), Vector3(-hx, y, -hz), col, ao)
	else:
		_quad(st, Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz), col, ao)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, ao: float) -> void:
	var lin := col.srgb_to_linear()
	lin.a = ao
	for v in [a, c, b, a, d, c]:
		st.set_color(lin)
		st.add_vertex(v)


## Roof: slab, parapet (thick), plant boxes and a water tank; open sky (AO 1) so the shader snow settles.
func _roof(sx: float, sz: float, top: float, pal: Dictionary) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat normals (the default group 0 averages shared corners)
	var hx := sx * 0.5
	var hz := sz * 0.5
	var wall: Color = pal["spandrel"]
	_quad_h(st, hx, hz, top, true, Color(0.55, 0.56, 0.58), 1.0)
	_walls(st, hx, hz, top, top + 1.1, wall, 1.0)
	_walls(st, hx - 0.3, hz - 0.3, top, top + 1.1, wall, 0.8, true)
	_quad_ring_top(st, hx, hz, top + 1.1, 0.3, wall)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(sx * 131.0 + sz * 17.0 + top)
	for i in 3:
		var w := rng.randf_range(1.5, 3.5)
		var d := rng.randf_range(1.5, 3.0)
		var cx := rng.randf_range(-hx + 3.0, hx - 3.0)
		# plant boxes keep to the ends of the roof (the middle is where the rooftop view puts the player)
		var cz := rng.randf_range(4.5, maxf(hz - 3.0, 4.6)) * (1.0 if i % 2 == 0 else -1.0)
		_block(st, Vector3(cx, top, cz), Vector3(w, rng.randf_range(1.2, 2.4), d), Color(0.5, 0.52, 0.55))
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, Assets.get_shared_material())
	var mi := MeshInstance3D.new()
	mi.name = "Roof"
	mi.mesh = mesh
	return mi


func _quad_ring_top(st: SurfaceTool, hx: float, hz: float, y: float, t: float, col: Color) -> void:
	_quad(st, Vector3(-hx, y, -hz + t), Vector3(hx, y, -hz + t), Vector3(hx, y, -hz), Vector3(-hx, y, -hz), col, 1.0)
	_quad(st, Vector3(-hx, y, hz), Vector3(hx, y, hz), Vector3(hx, y, hz - t), Vector3(-hx, y, hz - t), col, 1.0)
	_quad(st, Vector3(-hx, y, hz - t), Vector3(-hx + t, y, hz - t), Vector3(-hx + t, y, -hz + t), Vector3(-hx, y, -hz + t), col, 1.0)
	_quad(st, Vector3(hx - t, y, hz - t), Vector3(hx, y, hz - t), Vector3(hx, y, -hz + t), Vector3(hx - t, y, -hz + t), col, 1.0)


func _block(st: SurfaceTool, base: Vector3, size: Vector3, col: Color) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var c := [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(hx, hz), Vector2(-hx, hz)]
	for k in 4:
		var a: Vector2 = c[k] + Vector2(base.x, base.z)
		var b: Vector2 = c[(k + 1) % 4] + Vector2(base.x, base.z)
		_wall_quad(st, a, b, base.y, base.y + size.y, col, 1.0)
	var y := base.y + size.y
	_quad(st, Vector3(base.x - hx, y, base.z + hz), Vector3(base.x + hx, y, base.z + hz), Vector3(base.x + hx, y, base.z - hz), Vector3(base.x - hx, y, base.z - hz), col, 1.0)


# ------------------------------------------------------------------ street props: cars, lamps, barriers
func _props() -> void:
	# [test-only model, art model, x, z, yaw deg]
	var list := [
		["k_sedan", "vehicles/sedan_snowed", -2.2, 14.0, 5.0], ["k_taxi", "vehicles/taxi_crashed", 2.3, 31.0, 178.0],
		["q_bus", "vehicles/bus_snowed", -2.0, 38.0, -3.0], ["k_van", "vehicles/van_snowed", 2.2, 8.5, 184.0],
		["k_police", "vehicles/police_burnt", -2.4, 55.0, 20.0], ["k_sedan", "vehicles/suv_snowed", 12.0, -1.8, 92.0],
		["k_taxi", "vehicles/taxi_snowed", -14.0, 2.0, -88.0], ["k_van", "vehicles/box_truck_crashed", 2.4, -16.0, 176.0],
		["k_sedan", "vehicles/sedan_crashed", -2.6, -40.0, 8.0],
	]
	for c in list:
		var node := _art(String(c[1]))
		if node != null:
			art_used.append(String(c[1]))
		else:
			node = _model(String(c[0]))
		if node == null:
			continue
		node.position = Vector3(float(c[2]), 0.0, float(c[3]))
		node.rotation_degrees.y = float(c[4])
		add_child(node)
		CityBuilding.apply_prop_materials(node)
		occluders.append(node)
	for z in [-36.0, -12.0, 12.0, 36.0, 60.0]:
		for side in [-1.0, 1.0]:
			var x: float = side * 6.2
			var flicker: bool = z == 36.0 and side > 0.0
			var lamp := _art("props/lamp_street")
			if lamp != null:
				# art lamp: arm along +Z (front), turned toward the road; bulb and pool from its anchors
				art_used.append("props/lamp_street")
				lamp.position = Vector3(x, 0.0, z + side * 6.0)
				lamp.rotation_degrees.y = 90.0 if side < 0.0 else -90.0
				add_child(lamp)
				CityBuilding.apply_prop_materials(lamp)
				occluders.append(lamp)
				var bulb := lamp.find_child("LightAnchor", true, false) as Node3D
				var pool := lamp.find_child("LightPool", true, false) as Node3D
				var bp := bulb.global_position if bulb != null else lamp.global_position + Vector3(-side * 2.4, 6.3, 0)
				var gy := pool.global_position.y if pool != null else 0.0
				lights.add_lamp(bp, gy, -1.0 if flicker else 1.0)
				continue
			lamp = _model("streetlight_q")
			if lamp != null:
				lamp.position = Vector3(x, 0.0, z + side * 6.0)
				lamp.rotation_degrees.y = 90.0 if side < 0.0 else -90.0
				add_child(lamp)
				CityBuilding.apply_prop_materials(lamp)
				occluders.append(lamp)
			lights.add_lamp(Vector3(x - side * 1.2, 6.2, z + side * 6.0), 0.0, -1.0 if flicker else 1.0)
	for i in 4:
		var b := _model("barrier_k")
		if b != null:
			b.position = Vector3(-4.0 + i * 2.6, 0.0, -6.0)
			add_child(b)
			CityBuilding.apply_prop_materials(b)
			occluders.append(b)
	lights.build()


## An A1 art model (res://assets/models/city/<id>.glb) with the shared palette material, or null.
func _art(id: String) -> Node3D:
	var path := ART + id + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	Assets._prepare_meshes(id, root)
	return root


func _model(n: String) -> Node3D:
	var path := MODELS + n + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var root := scene.instantiate() as Node3D
	Assets._prepare_meshes(n, root)
	return root


# ------------------------------------------------------------------ player + zombies
func _characters() -> void:
	player = Node3D.new()
	player.name = "BenchPlayer"
	player.set_script(load("res://tests/city_bench/bench_player.gd"))
	add_child(player)
	player.global_position = VIEWS["canyon"]
	if measure_mode:
		player_visual = _key_capsule(KEY_PLAYER)
	else:
		var cv := (load("res://scenes/player/character_visual.tscn") as PackedScene).instantiate() as CharacterVisual
		cv.name = "Visual"
		player.add_child(cv)
		cv.setup(0)
		cv.rotation.y = PI * 0.75
		player_visual = cv
	if measure_mode:
		player.add_child(player_visual)
	cut.player_override = player
	sil.extra.append({"root": player_visual, "kind": "player", "variant": 0})
	var spots := [Vector2(3.0, 20.0), Vector2(-3.5, 18.0), Vector2(4.5, 28.5), Vector2(-1.0, 30.0), Vector2(5.8, 12.0),
		Vector2(-5.5, 26.0), Vector2(1.5, 36.0), Vector2(-4.0, 10.0), Vector2(6.0, 33.0), Vector2(0.5, 14.5),
		Vector2(-6.0, 34.0), Vector2(3.8, 24.5),
		Vector2(3.0, -26.0), Vector2(-4.0, -34.5), Vector2(4.5, -37.0), Vector2(-3.5, -23.0), Vector2(1.5, -41.0)]   # north view
	for i in spots.size():
		var z: Node3D
		if measure_mode:
			z = Node3D.new()
			z.add_child(_key_capsule(KEY_ZOMBIE))
		else:
			var zv := ZombieView.new()
			z = zv
		z.name = "Zombie%d" % i
		add_child(z)
		if z is ZombieView:
			(z as ZombieView).setup(ZombieKinds.Kind.WALKER, i)
			(z as ZombieView).set_motion(ZombieKinds.State.IDLE, 0.0, false)
		var s: Vector2 = spots[i]
		z.position = Vector3(s.x, 0.0, s.y)
		z.rotation.y = atan2(-s.x, (24.0 if s.y > 0.0 else -30.0) - s.y)
		zombies.append(z)
		sil.extra.append({"root": (z as ZombieView).model if z is ZombieView else z, "kind": "zombie"})


func _key_capsule(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	mi.mesh = cap
	mi.position = Vector3(0, 0.9, 0)
	mi.material_override = key_material(col)
	return mi


func key_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if not _key_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.disable_fog = true
		_key_mats[key] = m
	return _key_mats[key]


# ------------------------------------------------------------------ camera
func _camera() -> void:
	rig = (load("res://tests/city_bench/bench_rig.tscn") as PackedScene).instantiate() as CameraRig
	player.add_child(rig)
	rig.snap_to_player()


## Puts the player at a view, sets zoom / profile and snaps everything (no blending in a test frame).
func set_view(view: String, dist: float, profile: StringName = &"city") -> void:
	var p: Vector3 = VIEWS.get(view, VIEWS["canyon"])
	if view == "rooftop" and midrise != null:
		var b := midrise.get_node("CityBuilding") as CityBuilding
		p.y = b.roof_level + 0.02
	elif view == "inside" and midrise != null:
		var b := midrise.get_node("CityBuilding") as CityBuilding
		p.y = b.floor_level(2) + 0.02
	player.global_position = p
	rig.profile_override = profile
	rig.snap_profile()
	rig.dist = dist
	rig.camera.position = Vector3(0, 0, dist)
	# Deterministic camera: put the rig exactly on its follow target (player + 3 m forward, the game's framing).
	# CameraRig.snap_to_player() only snaps to the player and lets the camera ease the last 3 m with the REAL frame
	# delta, so under a software rasteriser the camera was still creeping between the reference and the measured
	# frame (frame timing differs per machine: CI vs local disagreed by several % of zombie pixels). On its target,
	# the rig's follow lerp is the identity, whatever the frame time.
	rig.snap_to_player()
	rig.global_position = follow_target()
	rig._process(0.0)
	rig.snap_profile()
	cut.update(1.0)


## Where the CameraRig settles for the current player position (CameraRig._process with no motion).
func follow_target() -> Vector3:
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, rig.pivot.rotation.y)
	return player.global_position + fwd * Balance.CAMERA_FORWARD_OFFSET


## Perf reference: the buildings' structure with the plain G1 world_vcol (cull_back, no discard) instead of
## world_vcol_struct, i.e. the cost before W0.
func set_g1_materials(on: bool) -> void:
	for b in buildings:
		var cb := b.get_node("CityBuilding") as CityBuilding
		if on:
			for gi in BuildingCutaway._geometries(b):
				if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
					var mi := gi as MeshInstance3D
					for i in mi.mesh.get_surface_count():
						if mi.get_surface_override_material(i) is ShaderMaterial and (mi.get_surface_override_material(i) as ShaderMaterial).resource_name.begins_with("world_vcol_struct"):
							mi.set_surface_override_material(i, Assets.get_shared_material())
		else:
			CityBuilding.apply_materials(b, cb.ground_h, cb.floor_h)


func set_hour(h: float) -> void:
	day_night.menu_hour = h
	day_night.apply(h)


func set_occluders_visible(v: bool) -> void:
	for o in occluders:
		o.visible = v
	if hlod != null:
		hlod.visible = v


func advance_characters(dt: float) -> void:
	for z in zombies:
		if z is ZombieView:
			(z as ZombieView).advance(dt)
	if player_visual is CharacterVisual:
		(player_visual as CharacterVisual).set_motion(0.0, false, false, false, false)
		(player_visual as CharacterVisual).advance(dt)


## Characters advance a fixed step per rendered frame (not the real delta): the same frame count gives the same
## poses on any machine, so screenshots and perf frames are reproducible.
const ANIM_STEP := 1.0 / 30.0


func _process(_delta: float) -> void:
	advance_characters(ANIM_STEP)
