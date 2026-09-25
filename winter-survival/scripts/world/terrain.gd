class_name Terrain
extends StaticBody3D
## Procedural snow terrain. Simulation side (server AND client, deterministic from the seed): an 81×81 height grid
## (2 m cells) + HeightMapShape3D, never touched by the visuals. Render side (clients only, G1 / doc 06 §3.8):
## a smooth-shaded indexed mesh in CHUNKS×CHUNKS pieces at RENDER_CELL m, per-vertex normals from the height field,
## COLOR.rgb = tint (slope / lake ice), COLOR.a = contact AO baked from the scatter occluders (`bake_ao`), all
## rendered with the single terrain ShaderMaterial (assets/materials/terrain.tres: wrap light, sparkle, trail map).

## Render grid step (m). The collision grid stays at Balance.TERRAIN_CELL; heights in between are bilinear.
const RENDER_CELL := 1.0
## Chunks per axis (20 m pieces: frustum culling of the mesh and of its shadow passes; M3 inherits per-chunk meshes).
const CHUNKS := 8
## Linear multipliers written to COLOR.rgb (the shader multiplies `snow_color` by them).
const TINT_SLOPE := Color(0.90, 0.93, 1.0)
const TINT_LAKE := Color(0.86, 0.95, 1.0)
## Occluder shapes: {"id": String, "pos": Vector2, "r": float, "strength": float} (disc; darkening inner 35 %
## of r, fading to 0 at r) or {"id", "pos": Vector2 (centre), "size": Vector2 (full w×d), "yaw": float,
## "strength", "soft": float} (rect, fading over `soft` metres outside its edge).

var size_n: int = int(Balance.WORLD_SIZE / Balance.TERRAIN_CELL) + 1
var heights: PackedFloat32Array = PackedFloat32Array()
var lake_level: float = 0.0
var lake_center: Vector2 = Regions.LAKE_CENTER
var lake_radius: float = Regions.LAKE_RADIUS
var shape_node: CollisionShape3D
## Container of the chunk MeshInstance3Ds ("Mesh"); null on headless / dedicated servers.
var mesh_root: Node3D
var chunks: Array[MeshInstance3D] = []
## Baked occluders by id (see bake_ao / update_occluder).
var occluders: Dictionary = {}
## True when a render mesh is built (any DisplayServer that is not headless).
var visual: bool = true

var _rn: int = 0                      # render vertices per axis
var _rh := PackedFloat32Array()       # render heights (bilinear from `heights`)
var _ao := PackedFloat32Array()       # per render vertex, 1 = open
var _chunk_verts: Array[PackedVector3Array] = []
var _chunk_normals: Array[PackedVector3Array] = []
var _chunk_tints: Array[PackedColorArray] = []
var _chunk_index: PackedInt32Array = PackedInt32Array()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("terrain")
	visual = DisplayServer.get_name() != "headless"


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
	# gentle rolling clearing near the cabin, hills further out
	var raw := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length()
		var amp := 0.3 + 0.7 * (1.0 - _smooth(45.0, 14.0, d))
		return (noise.get_noise_2d(x, z) * 6.0 + noise2.get_noise_2d(x, z) * 3.0) * amp
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
	_build_collision()
	if visual:
		_build_render_grid()
		_build_chunks()


## 1 when d <= inner, 0 when d >= outer, smooth in between.
static func _smooth(outer: float, inner: float, d: float) -> float:
	var t := clampf((d - outer) / (inner - outer), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


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


# ------------------------------------------------------------------ render mesh

func _build_render_grid() -> void:
	_rn = int(Balance.WORLD_SIZE / RENDER_CELL) + 1
	var half := Balance.WORLD_SIZE * 0.5
	_rh.resize(_rn * _rn)
	_ao.resize(_rn * _rn)
	_ao.fill(1.0)
	for iz in _rn:
		for ix in _rn:
			_rh[iz * _rn + ix] = get_height(float(ix) * RENDER_CELL - half, float(iz) * RENDER_CELL - half)


func _build_chunks() -> void:
	if mesh_root == null:
		mesh_root = Node3D.new()
		mesh_root.name = "Mesh"
		add_child(mesh_root)
	for c in chunks:
		c.queue_free()
	chunks.clear()
	_chunk_verts.clear()
	_chunk_normals.clear()
	_chunk_tints.clear()
	var half := Balance.WORLD_SIZE * 0.5
	var cs := (_rn - 1) / CHUNKS          # cells per chunk
	var cn := cs + 1                      # vertices per chunk axis
	# shared index buffer (clockwise front faces, ARQ: Godot's front faces are clockwise)
	_chunk_index.resize(cs * cs * 6)
	var k := 0
	for iz in cs:
		for ix in cs:
			var a := iz * cn + ix
			var b := a + 1
			var c := a + cn
			var d := c + 1
			_chunk_index[k] = a; _chunk_index[k + 1] = b; _chunk_index[k + 2] = c
			_chunk_index[k + 3] = b; _chunk_index[k + 4] = d; _chunk_index[k + 5] = c
			k += 6
	var mat := Assets.get_terrain_material()
	for cz in CHUNKS:
		for cx in CHUNKS:
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var tints := PackedColorArray()
			verts.resize(cn * cn)
			normals.resize(cn * cn)
			tints.resize(cn * cn)
			for lz in cn:
				var iz := cz * cs + lz
				for lx in cn:
					var ix := cx * cs + lx
					var i := lz * cn + lx
					var x := float(ix) * RENDER_CELL - half
					var z := float(iz) * RENDER_CELL - half
					verts[i] = Vector3(x, _rh[iz * _rn + ix], z)
					var hl := _rh[iz * _rn + maxi(ix - 1, 0)]
					var hr := _rh[iz * _rn + mini(ix + 1, _rn - 1)]
					var hd := _rh[maxi(iz - 1, 0) * _rn + ix]
					var hu := _rh[mini(iz + 1, _rn - 1) * _rn + ix]
					var nrm := Vector3(hl - hr, 2.0 * RENDER_CELL, hd - hu).normalized()
					normals[i] = nrm
					var slope := clampf((0.97 - nrm.y) / 0.25, 0.0, 1.0)
					var tint := Color.WHITE.lerp(TINT_SLOPE, slope * 0.9)
					if Vector2(x, z).distance_to(lake_center) < lake_radius * 0.72:
						tint = TINT_LAKE
					tints[i] = tint
			_chunk_verts.append(verts)
			_chunk_normals.append(normals)
			_chunk_tints.append(tints)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [cx, cz]
			mi.mesh = ArrayMesh.new()
			mi.material_override = mat
			mesh_root.add_child(mi)
			chunks.append(mi)
			_rebuild_chunk(chunks.size() - 1)
	apply_quality()
	if not Quality.preset_changed.is_connected(_on_preset_changed):
		Quality.preset_changed.connect(_on_preset_changed)


func _on_preset_changed(_p: StringName) -> void:
	apply_quality()


## Terrain self-shadowing (hills) only where the preset pays for it: the chunks leave the two shadow splits otherwise.
func apply_quality() -> void:
	var cast := Quality.allows("terrain_shadows")
	for c in chunks:
		c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Rebuilds one chunk's surface from the cached arrays + the current AO (COLOR.a).
func _rebuild_chunk(ci: int) -> void:
	var cs := (_rn - 1) / CHUNKS
	var cn := cs + 1
	var cx := ci % CHUNKS
	var cz := ci / CHUNKS
	var tints := _chunk_tints[ci]
	var colors := PackedColorArray()
	colors.resize(cn * cn)
	for lz in cn:
		var iz := cz * cs + lz
		for lx in cn:
			var ix := cx * cs + lx
			var t := tints[lz * cn + lx]
			colors[lz * cn + lx] = Color(t.r, t.g, t.b, _ao[iz * _rn + ix])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _chunk_verts[ci]
	arrays[Mesh.ARRAY_NORMAL] = _chunk_normals[ci]
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = _chunk_index
	var mesh := chunks[ci].mesh as ArrayMesh
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


# ------------------------------------------------------------------ baked AO (COLOR.a)

## Bakes the contact AO of every occluder into the render vertices and rebuilds the chunks. Called by World after
## the scatter; no-op without a render mesh (headless / dedicated server).
func bake_ao(list: Array) -> void:
	occluders.clear()
	if not visual or _ao.is_empty():
		return
	_ao.fill(1.0)
	for o in list:
		var id := String(o.get("id", ""))
		if id == "":
			id = "occ_%d" % occluders.size()
		occluders[id] = o
		_apply_occluder(o, true)
	for ci in chunks.size():
		_rebuild_chunk(ci)


## Local re-bake (R-G5): replaces one occluder (felled tree -> stump disc; strength 0 = removed) and rebuilds only
## the chunks it touches. Division undoes the old multiplicative factor exactly (factors are >= 0.5).
func update_occluder(id: String, r: float, strength: float) -> void:
	if not visual or not occluders.has(id):
		return
	var old: Dictionary = occluders[id]
	_apply_occluder(old, false)
	var o := old.duplicate()
	o["r"] = r
	o["strength"] = strength
	o.erase("size")
	occluders[id] = o
	_apply_occluder(o, true)
	var rr := maxf(r, _occluder_reach(old))
	var pos: Vector2 = o["pos"]
	for ci in _chunks_touching(Rect2(pos - Vector2(rr, rr), Vector2(rr, rr) * 2.0)):
		_rebuild_chunk(ci)


func _occluder_reach(o: Dictionary) -> float:
	if o.has("size"):
		return (o["size"] as Vector2).length() * 0.5 + float(o.get("soft", 1.5))
	return float(o["r"])


func _chunks_touching(rect: Rect2) -> Array[int]:
	var out: Array[int] = []
	var half := Balance.WORLD_SIZE * 0.5
	var chunk_m := Balance.WORLD_SIZE / float(CHUNKS)
	var c0x := clampi(int(floor((rect.position.x + half) / chunk_m)), 0, CHUNKS - 1)
	var c1x := clampi(int(floor((rect.end.x + half) / chunk_m)), 0, CHUNKS - 1)
	var c0z := clampi(int(floor((rect.position.y + half) / chunk_m)), 0, CHUNKS - 1)
	var c1z := clampi(int(floor((rect.end.y + half) / chunk_m)), 0, CHUNKS - 1)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			out.append(cz * CHUNKS + cx)
	return out


## Multiplies (or divides, `apply` = false) the AO of the render vertices inside the occluder's reach.
func _apply_occluder(o: Dictionary, apply: bool) -> void:
	var s := float(o.get("strength", 0.4))
	if s <= 0.0:
		return
	var pos: Vector2 = o["pos"]
	var half := Balance.WORLD_SIZE * 0.5
	var reach := _occluder_reach(o)
	var ix0 := clampi(int(floor((pos.x - reach + half) / RENDER_CELL)), 0, _rn - 1)
	var ix1 := clampi(int(ceil((pos.x + reach + half) / RENDER_CELL)), 0, _rn - 1)
	var iz0 := clampi(int(floor((pos.y - reach + half) / RENDER_CELL)), 0, _rn - 1)
	var iz1 := clampi(int(ceil((pos.y + reach + half) / RENDER_CELL)), 0, _rn - 1)
	var is_rect := o.has("size")
	var hw := 0.0
	var hd := 0.0
	var soft := 1.5
	var cy := 1.0
	var sy := 0.0
	var r := 1.0
	if is_rect:
		hw = (o["size"] as Vector2).x * 0.5
		hd = (o["size"] as Vector2).y * 0.5
		soft = float(o.get("soft", 1.5))
		cy = cos(-float(o.get("yaw", 0.0)))
		sy = sin(-float(o.get("yaw", 0.0)))
	else:
		r = float(o["r"])
	for iz in range(iz0, iz1 + 1):
		var z := float(iz) * RENDER_CELL - half
		for ix in range(ix0, ix1 + 1):
			var x := float(ix) * RENDER_CELL - half
			var f := 1.0
			if is_rect:
				var dx := x - pos.x
				var dz := z - pos.y
				var lx := dx * cy - dz * sy
				var lz := dx * sy + dz * cy
				var ox := maxf(absf(lx) - hw, 0.0)
				var oz := maxf(absf(lz) - hd, 0.0)
				var d := Vector2(ox, oz).length()
				f = 1.0 - s * (1.0 - _smooth(0.0, soft, d))
			else:
				var d2 := Vector2(x, z).distance_to(pos)
				f = 1.0 - s * (1.0 - _smooth(r * 0.35, r, d2))
			if f >= 0.9999:
				continue
			var i := iz * _rn + ix
			_ao[i] = clampf(_ao[i] * f if apply else _ao[i] / f, 0.0, 1.0)


## AO at a world position (render grid, nearest vertex); 1 when no render mesh exists.
func ao_at(x: float, z: float) -> float:
	if _ao.is_empty():
		return 1.0
	var half := Balance.WORLD_SIZE * 0.5
	var ix := clampi(int(round((x + half) / RENDER_CELL)), 0, _rn - 1)
	var iz := clampi(int(round((z + half) / RENDER_CELL)), 0, _rn - 1)
	return _ao[iz * _rn + ix]


# ------------------------------------------------------------------ queries (simulation grid)

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
