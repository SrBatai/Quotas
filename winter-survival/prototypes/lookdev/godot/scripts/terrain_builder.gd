class_name LookdevTerrain
extends RefCounted
## Smooth-shaded snow terrain with baked contact AO in COLOR.a (look-dev G1).
## Indexed ArrayMesh, `cell` metres per quad, per-vertex normals from the height field (smooth), COLOR.rgb = 1,
## COLOR.a = ambient occlusion from a list of occluders ({"pos": Vector2, "r": float, "strength": float} or
## {"rect": Rect2, "strength": float, "soft": float}).

var size: float = 96.0
var cell: float = 0.5
var seed_value: int = 7
var heights: PackedFloat32Array
var n: int = 0
var pads: Array = []  # {"pos": Vector2, "r": float}
var occluders: Array = []


func height_at(x: float, z: float) -> float:
	if heights.is_empty():
		return 0.0
	var half := size * 0.5
	var fx := clampf((x + half) / cell, 0.0, float(n - 1) - 0.0001)
	var fz := clampf((z + half) / cell, 0.0, float(n - 1) - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := heights[iz * n + ix]
	var h10 := heights[iz * n + ix + 1]
	var h01 := heights[(iz + 1) * n + ix]
	var h11 := heights[(iz + 1) * n + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


static func _smooth(outer: float, inner: float, d: float) -> float:
	var t := clampf((d - outer) / (inner - outer), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func build_heights() -> void:
	n = int(size / cell) + 1
	var half := size * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = 0.03
	var drift := FastNoiseLite.new()
	drift.seed = seed_value + 3
	drift.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	drift.frequency = 0.12
	heights.resize(n * n)
	for iz in n:
		for ix in n:
			var x := float(ix) * cell - half
			var z := float(iz) * cell - half
			var h := noise.get_noise_2d(x, z) * 0.9 + drift.get_noise_2d(x, z) * 0.12
			# rise gently toward the far edges (the clearing sits in a shallow bowl)
			var d := Vector2(x, z).length()
			h += 0.012 * maxf(d - 25.0, 0.0)
			for p in pads:
				var pd: float = Vector2(x, z).distance_to(p["pos"])
				if pd < p["r"]:
					h = lerpf(h, p.get("h", 0.0), _smooth(p["r"], p["r"] * 0.55, pd))
			heights[iz * n + ix] = h


func _ao_at(x: float, z: float) -> float:
	var ao := 1.0
	var p := Vector2(x, z)
	for o in occluders:
		var s: float = o["strength"]
		if o.has("rect"):
			var r: Rect2 = o["rect"]
			var soft: float = o.get("soft", 1.5)
			var dx := maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
			var dz := maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
			var d := Vector2(dx, dz).length()
			ao *= 1.0 - s * (1.0 - _smooth(0.0, soft, d))
		else:
			var d2 := p.distance_to(o["pos"])
			var rr: float = o["r"]
			ao *= 1.0 - s * (1.0 - _smooth(rr * 0.35, rr, d2))
	return clampf(ao, 0.0, 1.0)


func build_mesh() -> ArrayMesh:
	var half := size * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	uvs.resize(n * n)
	for iz in n:
		for ix in n:
			var x := float(ix) * cell - half
			var z := float(iz) * cell - half
			var i := iz * n + ix
			verts[i] = Vector3(x, heights[i], z)
			var hl := heights[iz * n + maxi(ix - 1, 0)]
			var hr := heights[iz * n + mini(ix + 1, n - 1)]
			var hd := heights[maxi(iz - 1, 0) * n + ix]
			var hu := heights[mini(iz + 1, n - 1) * n + ix]
			normals[i] = Vector3(hl - hr, 2.0 * cell, hd - hu).normalized()
			colors[i] = Color(1.0, 1.0, 1.0, _ao_at(x, z))
			uvs[i] = Vector2(float(ix) / float(n - 1), float(iz) / float(n - 1))
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			# clockwise front faces (Godot)
			idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
			idx[k + 3] = b; idx[k + 4] = d; idx[k + 5] = c
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
