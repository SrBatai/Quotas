class_name MeshBuilder
extends RefCounted
## Builds flat-shaded low-poly ArrayMeshes following ASSET_SPEC v2 §2.5: every palette colour goes into the
## vertex colour of ONE `palette_vcol` surface (rendered with the shared world_vcol ShaderMaterial); only the
## named exception materials (window, ember, glass, …) get a surface of their own.

const VCOL := "palette_vcol"

## When true every emitted point is turned 180° about Y (x, z → −x, −z): the placeholder builders are
## written with the slice's −Z front and this bakes the v2 +Z front (Vector3.MODEL_FRONT) into the mesh.
var yaw180: bool = false

var _tools: Dictionary = {}
var _order: Array[String] = []


static func flip(v: Vector3) -> Vector3:
	return Vector3(-v.x, v.y, -v.z)


func _st(mat: String) -> SurfaceTool:
	if not _tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[mat] = st
		_order.append(mat)
	return _tools[mat]


## Triangle with a flat normal. If `outward` is given the winding is flipped to face it.
func tri(mat: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3 = Vector3.ZERO) -> void:
	if yaw180:
		a = flip(a)
		b = flip(b)
		c = flip(c)
		outward = flip(outward)
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	if outward != Vector3.ZERO and n.dot(outward) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	var exception := Assets.is_exception_material(mat)
	var st := _st(mat if exception else VCOL)
	var col := Assets.palette_linear(mat)
	# Godot's front faces are clockwise: emit a, c, b so the face looks toward `n`.
	for p in [a, c, b]:
		if not exception:
			st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


func quad(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3 = Vector3.ZERO) -> void:
	tri(mat, a, b, c, outward)
	tri(mat, a, c, d, outward)


## Convex polygon (fan), vertices in order.
func poly(mat: String, pts: Array, outward: Vector3 = Vector3.ZERO) -> void:
	for i in range(1, pts.size() - 1):
		tri(mat, pts[0], pts[i], pts[i + 1], outward)


## Axis-aligned box from min to max. `top_mat` overrides the +Y face (snow caps).
func box(mat: String, mn: Vector3, mx: Vector3, top_mat: String = "") -> void:
	var p := [
		Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mn.x, mx.y, mn.z),
		Vector3(mn.x, mn.y, mx.z), Vector3(mx.x, mn.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z),
	]
	quad(mat, p[4], p[5], p[6], p[7])  # +Z
	quad(mat, p[1], p[0], p[3], p[2])  # -Z
	quad(mat, p[5], p[1], p[2], p[6])  # +X
	quad(mat, p[0], p[4], p[7], p[3])  # -X
	quad(top_mat if top_mat != "" else mat, p[3], p[7], p[6], p[2])  # +Y
	quad(mat, p[0], p[1], p[5], p[4])  # -Y


func box_c(mat: String, center: Vector3, size: Vector3, top_mat: String = "") -> void:
	box(mat, center - size * 0.5, center + size * 0.5, top_mat)


## Generic convex solid from its faces (each an Array of Vector3). Faces are oriented away from the centroid.
func solid(mat: String, faces: Array, face_mats: Array = []) -> void:
	var centroid := Vector3.ZERO
	var n := 0
	for f in faces:
		for v in f:
			centroid += v
			n += 1
	if n == 0:
		return
	centroid /= float(n)
	for i in faces.size():
		var f: Array = faces[i]
		var fc := Vector3.ZERO
		for v in f:
			fc += v
		fc /= float(f.size())
		var m: String = mat
		if i < face_mats.size() and face_mats[i] != "":
			m = face_mats[i]
		poly(m, f, fc - centroid)


## Hexahedron from a top quad and a bottom quad (same vertex order).
func hexa(mat: String, top: Array, bottom: Array, top_mat: String = "") -> void:
	var faces := [top, bottom]
	var mats := [top_mat, ""]
	for i in 4:
		var j := (i + 1) % 4
		faces.append([top[i], top[j], bottom[j], bottom[i]])
		mats.append("")
	solid(mat, faces, mats)


## Slab: a quad extruded along its own normal by `thickness` (downward, i.e. the quad is the top).
func slab(mat: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, thickness: float, top_mat: String = "") -> void:
	var nrm := (b - a).cross(c - a).normalized()
	if nrm.y < 0.0:
		nrm = -nrm
	var off := nrm * thickness
	hexa(mat, [a, b, c, d], [a - off, b - off, c - off, d - off], top_mat)


## Triangular prism between two triangles (same vertex order).
func prism(mat: String, t0: Array, t1: Array, cap_mat: String = "") -> void:
	var faces := [t0, t1]
	var mats := [cap_mat, cap_mat]
	for i in 3:
		var j := (i + 1) % 3
		faces.append([t0[i], t0[j], t1[j], t1[i]])
		mats.append("")
	solid(mat, faces, mats)


## Cone / cylinder along local +Y from `base`. Optional ring split at `ring_frac` with a different material above.
## `xform` is applied to every point (for tilted branches/logs).
func cone(mat: String, base: Vector3, r_bottom: float, r_top: float, height: float, sides: int,
		opts: Dictionary = {}) -> void:
	var ring_frac: float = opts.get("ring_frac", -1.0)
	var mat_high: String = opts.get("mat_high", mat)
	var cap_bottom: String = opts.get("cap_bottom", "")
	var cap_top: String = opts.get("cap_top", "")
	var xform: Transform3D = opts.get("xform", Transform3D.IDENTITY)
	var jitter: float = opts.get("jitter", 0.0)
	var rng: RandomNumberGenerator = opts.get("rng", null)
	var levels: Array = []
	levels.append([0.0, r_bottom, mat])
	if ring_frac > 0.0 and ring_frac < 1.0:
		levels.append([ring_frac, lerpf(r_bottom, r_top, ring_frac), mat_high])
	levels.append([1.0, r_top, mat_high])
	var rings: Array = []
	for lv in levels:
		var pts: Array = []
		for i in sides:
			var ang := TAU * float(i) / float(sides)
			var r: float = lv[1]
			if jitter > 0.0 and rng != null and r > 0.001:
				r *= 1.0 + rng.randf_range(-jitter, jitter)
			pts.append(xform * (base + Vector3(cos(ang) * r, lv[0] * height, sin(ang) * r)))
		rings.append(pts)
	var center_base := xform * base
	var center_top := xform * (base + Vector3(0, height, 0))
	for li in range(rings.size() - 1):
		var lo: Array = rings[li]
		var hi: Array = rings[li + 1]
		var m: String = levels[li][2]
		for i in sides:
			var j := (i + 1) % sides
			var mid: Vector3 = (lo[i] + lo[j] + hi[i] + hi[j]) * 0.25
			var axis_pt := center_base.lerp(center_top, (levels[li][0] + levels[li + 1][0]) * 0.5)
			var outward := mid - axis_pt
			if r_top < 0.001 and li == rings.size() - 2:
				tri(m, lo[i], lo[j], hi[i], outward)
			else:
				quad(m, lo[i], lo[j], hi[j], hi[i], outward)
	if cap_bottom != "":
		var pts: Array = rings[0].duplicate()
		pts.reverse()
		poly(cap_bottom, pts, center_base - center_top)
	if cap_top != "" and r_top > 0.001:
		poly(cap_top, rings[rings.size() - 1], center_top - center_base)


## Jittered low-poly sphere; faces get `snow_mat` when their normal.y > snow_limit, `dark_mat` when < dark_limit.
## Vertices below y=0 (local, after centering) are clamped to a flat bottom when flat_bottom is true.
func blob(mat: String, center: Vector3, size: Vector3, opts: Dictionary = {}) -> void:
	var segs: int = opts.get("segments", 8)
	var rings: int = opts.get("rings", 5)
	var jitter: float = opts.get("jitter", 0.1)
	var rng: RandomNumberGenerator = opts.get("rng", null)
	var snow_mat: String = opts.get("snow_mat", "")
	var snow_limit: float = opts.get("snow_limit", 0.55)
	var dark_mat: String = opts.get("dark_mat", "")
	var dark_limit: float = opts.get("dark_limit", 0.1)
	var flat_bottom: bool = opts.get("flat_bottom", false)
	var grid: Array = []
	for r in range(rings + 1):
		var row: Array = []
		var phi := PI * float(r) / float(rings)
		for s in segs:
			var theta := TAU * float(s) / float(segs)
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var k := 1.0
			if jitter > 0.0 and rng != null and r > 0 and r < rings:
				k = 1.0 + rng.randf_range(-jitter, jitter)
			var p := center + Vector3(dir.x * size.x * 0.5 * k, dir.y * size.y * 0.5 * k, dir.z * size.z * 0.5 * k)
			if flat_bottom and p.y < 0.0:
				p.y = 0.0
			row.append(p)
		grid.append(row)
	for r in rings:
		for s in segs:
			var s2 := (s + 1) % segs
			var a: Vector3 = grid[r][s]
			var b: Vector3 = grid[r][s2]
			var c: Vector3 = grid[r + 1][s2]
			var d: Vector3 = grid[r + 1][s]
			var tris := [[a, b, c], [a, c, d]] if r < rings - 1 else [[a, b, c]]
			if r == 0:
				tris = [[a, c, d]]
			for t in tris:
				var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
				if n.length_squared() < 1e-12:
					continue
				n = n.normalized()
				var outward: Vector3 = (t[0] + t[1] + t[2]) / 3.0 - center
				if n.dot(outward) < 0.0:
					n = -n
				var m := mat
				if snow_mat != "" and n.y > snow_limit:
					m = snow_mat
				elif dark_mat != "" and n.y < dark_limit:
					m = dark_mat
				tri(m, t[0], t[1], t[2], outward)


func commit(mesh: ArrayMesh = null) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	for mat in _order:
		var st: SurfaceTool = _tools[mat]
		if mat == VCOL:
			st.set_material(Assets.get_shared_material())
		else:
			st.set_material(Assets.material(mat))
		st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, mat)
	return mesh
