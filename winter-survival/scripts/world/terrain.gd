class_name Terrain
extends StaticBody3D
## Procedural snow terrain: 81×81 height grid, flat-shaded ArrayMesh with vertex colors, HeightMapShape3D.

const SNOW := Color("#F1F5FA")
const SNOW_SHADOW := Color("#B9CBE3")

var size_n: int = int(Balance.WORLD_SIZE / Balance.TERRAIN_CELL) + 1
var heights: PackedFloat32Array = PackedFloat32Array()
var lake_level: float = 0.0
var lake_center: Vector2 = Regions.LAKE_CENTER
var lake_radius: float = Regions.LAKE_RADIUS
var mesh_instance: MeshInstance3D
var shape_node: CollisionShape3D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("terrain")


## pads: [{"center": Vector2, "radius": float}]. Deterministic from the seed.
func generate(seed_value: int, pads: Array) -> void:
	var n := size_n
	var half := Balance.WORLD_SIZE * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = 0.012
	var noise2 := FastNoiseLite.new()
	noise2.seed = seed_value + 7
	noise2.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise2.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise2.frequency = 0.004
	heights.resize(n * n)
	var raw := func(x: float, z: float) -> float:
		return noise.get_noise_2d(x, z) * 6.0 + noise2.get_noise_2d(x, z) * 3.0
	lake_level = raw.call(lake_center.x, lake_center.y) - 1.0
	var pad_heights: Array[float] = []
	for p in pads:
		pad_heights.append(raw.call(p["center"].x, p["center"].y))
	for iz in n:
		for ix in n:
			var x := float(ix) * Balance.TERRAIN_CELL - half
			var z := float(iz) * Balance.TERRAIN_CELL - half
			var h: float = raw.call(x, z)
			var dl := Vector2(x, z).distance_to(lake_center)
			if dl < lake_radius:
				h = lerpf(h, lake_level, _smooth(lake_radius, lake_radius * 0.7, dl))
			for i in pads.size():
				var p: Dictionary = pads[i]
				var r: float = p["radius"]
				var d := Vector2(x, z).distance_to(p["center"])
				if d < r:
					h = lerpf(h, pad_heights[i], _smooth(r, r * 0.6, d))
			heights[iz * n + ix] = h
	_build_mesh(seed_value)
	_build_collision()


## 1 when d <= inner, 0 when d >= outer, smooth in between.
static func _smooth(outer: float, inner: float, d: float) -> float:
	var t := clampf((d - outer) / (inner - outer), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _build_mesh(seed_value: int) -> void:
	var n := size_n
	var half := Balance.WORLD_SIZE * 0.5
	var cnoise := FastNoiseLite.new()
	cnoise.seed = seed_value + 99
	cnoise.frequency = 0.05
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n - 1:
		for ix in n - 1:
			var x0 := float(ix) * Balance.TERRAIN_CELL - half
			var z0 := float(iz) * Balance.TERRAIN_CELL - half
			var x1 := x0 + Balance.TERRAIN_CELL
			var z1 := z0 + Balance.TERRAIN_CELL
			var a := Vector3(x0, heights[iz * n + ix], z0)
			var b := Vector3(x1, heights[iz * n + ix + 1], z0)
			var c := Vector3(x1, heights[(iz + 1) * n + ix + 1], z1)
			var d := Vector3(x0, heights[(iz + 1) * n + ix], z1)
			# alternate the diagonal for a more natural low-poly look
			if (ix + iz) % 2 == 0:
				_face(st, a, c, b, cnoise)
				_face(st, a, d, c, cnoise)
			else:
				_face(st, a, d, b, cnoise)
				_face(st, b, d, c, cnoise)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.metallic_specular = 0.1
	mesh.surface_set_material(0, mat)
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		add_child(mesh_instance)
	mesh_instance.mesh = mesh


func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, cnoise: FastNoiseLite) -> void:
	var nrm := (b - a).cross(c - a).normalized()
	var center := (a + b + c) / 3.0
	var slope := clampf((0.97 - nrm.y) / 0.25, 0.0, 1.0)
	var col := SNOW.lerp(SNOW_SHADOW, slope * 0.9)
	var v := cnoise.get_noise_2d(center.x, center.z) * 0.04
	col = Color(col.r + v, col.g + v, col.b + v * 0.6)
	var dl := Vector2(center.x, center.z).distance_to(lake_center)
	if dl < lake_radius * 0.72:
		col = Color("#BFE3F0")
	st.set_normal(nrm)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.set_color(col)
	st.add_vertex(b)
	st.set_normal(nrm)
	st.set_color(col)
	st.add_vertex(c)


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = size_n
	shape.map_depth = size_n
	shape.map_data = heights
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = "Shape"
		add_child(shape_node)
	shape_node.shape = shape
	shape_node.scale = Vector3(Balance.TERRAIN_CELL, 1.0, Balance.TERRAIN_CELL)


func get_height(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var n := size_n
	var half := Balance.WORLD_SIZE * 0.5
	var fx := clampf((x + half) / Balance.TERRAIN_CELL, 0.0, float(n - 1) - 0.0001)
	var fz := clampf((z + half) / Balance.TERRAIN_CELL, 0.0, float(n - 1) - 0.0001)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := heights[iz * n + ix]
	var h10 := heights[iz * n + ix + 1]
	var h01 := heights[(iz + 1) * n + ix]
	var h11 := heights[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func get_normal(x: float, z: float) -> Vector3:
	var e := 0.5
	var hl := get_height(x - e, z)
	var hr := get_height(x + e, z)
	var hd := get_height(x, z - e)
	var hu := get_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func is_lake(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(lake_center) < lake_radius


func in_bounds(x: float, z: float) -> bool:
	return absf(x) < Balance.BOUNDS and absf(z) < Balance.BOUNDS


func random_point(rng: RandomNumberGenerator, min_dist_from_origin: float) -> Vector3:
	for i in 64:
		var x := rng.randf_range(-Balance.BOUNDS + 2.0, Balance.BOUNDS - 2.0)
		var z := rng.randf_range(-Balance.BOUNDS + 2.0, Balance.BOUNDS - 2.0)
		if Vector2(x, z).length() < min_dist_from_origin:
			continue
		if is_lake(x, z):
			continue
		return Vector3(x, get_height(x, z), z)
	return Vector3(0, get_height(0, 0), 0)
