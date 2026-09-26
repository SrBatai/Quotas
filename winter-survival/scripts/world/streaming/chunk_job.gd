class_name ChunkJob
extends RefCounted
## Builds one chunk's data off the main thread (WorkerThreadPool; ARQ v2 §8.3, §8.5–8.6). Pure: reads only the
## immutable HeightFunction / MacroMap / clearing list and the snapshots it was given, writes only its own
## fields. The main thread (WorldChunk) turns the result into nodes within the streaming budget.
##
## Output: 65 × 65 heights (collision + mesh), the terrain mesh arrays (client: smooth normals from the height
## field, COLOR.rgb = slope / lake tint, COLOR.a = contact AO baked from every occluder that reaches the chunk,
## CUSTOM0 = surface mask RGBA8: asphalt, ice, packed track), the scatter entries that live in the chunk (with
## their heights), MultiMesh buffers per (32 m block, variant) and the node entries (pickups, berry bushes, POI
## props).

const N := WorldConst.SAMPLES
const TINT_SLOPE := Color(0.90, 0.93, 1.0)
const TINT_LAKE := Color(0.86, 0.95, 1.0)
const BLOCK := 32.0
## Contact AO rects of the POI props (full w × d, strength, soft edge).
const PROP_OCCLUDERS := {"cabin_small": [6.0, 7.2, 0.45, 1.8], "lookout_tower": [6.4, 6.4, 0.35, 1.4],
	"campsite_remains": [5.6, 4.0, 0.3, 1.0]}

# ---- inputs
var cx: int = 0
var cz: int = 0
var key: int = 0
var hf: HeightFunction
var visual: bool = true
var clearing: Array = []
var static_occ: Array = []
var felled: Dictionary = {}
# ---- bookkeeping
var task_id: int = -1
var usec: int = 0
var cancelled: bool = false
# ---- outputs
var heights := PackedFloat32Array()
var surface := PackedInt32Array()
var entries: Array = []          # own MultiMesh entries (+ "y", "felled")
var nodes: Array = []            # own node entries (+ "y")
var occluders: Array = []        # every occluder that reaches this chunk
var ao := PackedFloat32Array()
var tints := PackedColorArray()
## The terrain is rendered as 4 quadrant meshes of 33 × 33 vertices (32 m: finer frustum culling, and each upload
## is a quarter of the work). Per quadrant q = qz * 2 + qx: vertices, normals, CUSTOM0 bytes, colours.
const QN := 33
var quad_verts: Array[PackedVector3Array] = []
var quad_normals: Array[PackedVector3Array] = []
var quad_custom: Array[PackedByteArray] = []
var quad_colors: Array[PackedColorArray] = []
var verts := PackedVector3Array()
var normals := PackedVector3Array()
var custom := PackedByteArray()
var mm: Dictionary = {}          # block * 64 + variant -> {"buf": PackedFloat32Array, "idx": PackedInt32Array}
var mm_keys: Array[int] = []     # sorted keys of `mm` (deterministic node order)
var region: String = ""


func run() -> void:
	var t0 := Time.get_ticks_usec()
	var ox := WorldConst.chunk_origin_i(cx)
	var oz := WorldConst.chunk_origin_i(cz)
	var rect := Rect2(float(ox), float(oz), WorldConst.CHUNK_SIZE, WorldConst.CHUNK_SIZE)
	# heights (+ one sample of border for the normals)
	var nb := N + 2
	var blk := hf.sample_block(ox - 1, oz - 1, nb)
	var hb: PackedFloat32Array = blk["h"]
	var sb: PackedInt32Array = blk["s"]
	heights.resize(N * N)
	surface.resize(N * N)
	for j in N:
		for i in N:
			heights[j * N + i] = hb[(j + 1) * nb + i + 1]
			surface[j * N + i] = sb[(j + 1) * nb + i + 1]
	if cancelled:
		return
	# scatter: own entries + neighbours' for the AO
	var all_proc := ScatterGen.procedural(hf, rect, true)
	var reach := rect.grow(3.0)
	for e in all_proc:
		_take(e, rect, reach)
	for e in clearing:
		if reach.has_point(Vector2(float(e["x"]), float(e["z"]))):
			_take(e, rect, reach)
	for e in ScatterGen.poi_entries(hf.world_seed, rect.grow(12.0)):
		_take(e, rect, rect.grow(12.0))
	for o in static_occ:
		occluders.append(o)
	var c := WorldConst.chunk_center(cx, cz)
	region = PoiRegistry.region_of_chunk(cx, cz, hf.road_distance(c.x, c.z, 40.0, "highway") < 32.0)
	if visual and not cancelled:
		_build_mesh(ox, oz, hb, nb)
		_build_multimesh(ox, oz)
	usec = Time.get_ticks_usec() - t0


## Height at a world point inside this chunk (bilinear on the own samples = the world height).
func height_local(x: float, z: float) -> float:
	var fx := clampf(x - float(WorldConst.chunk_origin_i(cx)), 0.0, float(N - 1) - 0.0001)
	var fz := clampf(z - float(WorldConst.chunk_origin_i(cz)), 0.0, float(N - 1) - 0.0001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - float(i)
	var tz := fz - float(j)
	var k := j * N + i
	return lerpf(lerpf(heights[k], heights[k + 1], tx), lerpf(heights[k + N], heights[k + N + 1], tx), tz)


func _take(e: Dictionary, rect: Rect2, reach: Rect2) -> void:
	var p := Vector2(float(e["x"]), float(e["z"]))
	if not reach.has_point(p):
		return
	var own := rect.has_point(p)
	var v := int(e["v"])
	var id := str(int(e["wid"]))
	var is_felled := felled.has(int(e["wid"]))
	if v >= 0:
		var o: Dictionary
		if is_felled and ScatterCatalog.is_choppable(v):
			var so := ScatterCatalog.stump_occluder(v, float(e["s"]))
			o = {"id": id, "pos": p, "r": so[0], "strength": so[1]} if float(so[1]) > 0.0 else {}
		else:
			o = ScatterCatalog.occluder(v, p, float(e["s"]), id)
		if not o.is_empty():
			occluders.append(o)
		if own:
			var own_e := e.duplicate()
			own_e["y"] = height_local(p.x, p.y)
			own_e["felled"] = is_felled and ScatterCatalog.is_choppable(v)
			entries.append(own_e)
	else:
		var node := int(e["node"])
		if node == ScatterCatalog.NodeKind.BERRY_BUSH:
			occluders.append({"id": id, "pos": p, "r": 0.8, "strength": 0.4})
		elif node == ScatterCatalog.NodeKind.PROP and PROP_OCCLUDERS.has(str(e["model"])):
			var po: Array = PROP_OCCLUDERS[str(e["model"])]
			occluders.append({"id": id, "pos": p, "size": Vector2(po[0], po[1]), "yaw": float(e["yaw"]), "strength": po[2], "soft": po[3]})
		if own:
			var own_n := e.duplicate()
			own_n["y"] = height_local(p.x, p.y)
			nodes.append(own_n)


# ------------------------------------------------------------------ terrain mesh arrays
func _build_mesh(ox: int, oz: int, hb: PackedFloat32Array, nb: int) -> void:
	var n := N * N
	verts.resize(n)
	normals.resize(n)
	tints.resize(n)
	custom.resize(n * 4)
	ao.resize(n)
	ao.fill(1.0)
	for j in N:
		var z := float(oz + j)
		for i in N:
			var x := float(ox + i)
			var k := j * N + i
			var bk := (j + 1) * nb + i + 1
			var h := hb[bk]
			verts[k] = Vector3(x, h, z)
			var nrm := Vector3(hb[bk - 1] - hb[bk + 1], 2.0, hb[bk - nb] - hb[bk + nb]).normalized()
			normals[k] = nrm
			var slope := clampf((0.97 - nrm.y) / 0.25, 0.0, 1.0)
			var tint := Color.WHITE.lerp(TINT_SLOPE, slope * 0.9)
			var s := surface[k]
			if Vector2(x, z).distance_to(HeightFunction.SMALL_LAKE_CENTER) < HeightFunction.SMALL_LAKE_RADIUS * 0.72:
				tint = TINT_LAKE
			elif ((s >> 8) & 255) > 127:
				tint = TINT_LAKE
			tints[k] = tint
			custom[k * 4] = s & 255
			custom[k * 4 + 1] = (s >> 8) & 255
			custom[k * 4 + 2] = (s >> 16) & 255
			custom[k * 4 + 3] = (s >> 24) & 255
	for o in occluders:
		apply_occluder(o, true)
	for q in 4:
		var qv := PackedVector3Array()
		var qnrm := PackedVector3Array()
		var qc := PackedByteArray()
		qv.resize(QN * QN)
		qnrm.resize(QN * QN)
		qc.resize(QN * QN * 4)
		var i0 := (q % 2) * (QN - 1)
		var j0 := (q / 2) * (QN - 1)
		for jj in QN:
			for ii in QN:
				var k := (j0 + jj) * N + i0 + ii
				var kk := jj * QN + ii
				qv[kk] = verts[k]
				qnrm[kk] = normals[k]
				qc[kk * 4] = custom[k * 4]
				qc[kk * 4 + 1] = custom[k * 4 + 1]
				qc[kk * 4 + 2] = custom[k * 4 + 2]
				qc[kk * 4 + 3] = custom[k * 4 + 3]
		quad_verts.append(qv)
		quad_normals.append(qnrm)
		quad_custom.append(qc)
		quad_colors.append(quad_colors_of(q))


## Multiplies (`apply`) or divides the AO of this chunk's samples inside the occluder's reach (terrain.gd G1
## port on the chunk-local grid; operates on the member array so no packed-array copy is made).
func apply_occluder(o: Dictionary, apply: bool) -> void:
	var ox := WorldConst.chunk_origin_i(cx)
	var oz := WorldConst.chunk_origin_i(cz)
	var s := float(o.get("strength", 0.4))
	if s <= 0.0:
		return
	var pos: Vector2 = o["pos"]
	var reach := occluder_reach(o)
	var ix0 := clampi(int(floor(pos.x - reach)) - ox, 0, N - 1)
	var ix1 := clampi(int(ceil(pos.x + reach)) - ox, 0, N - 1)
	var iz0 := clampi(int(floor(pos.y - reach)) - oz, 0, N - 1)
	var iz1 := clampi(int(ceil(pos.y + reach)) - oz, 0, N - 1)
	if pos.x + reach < float(ox) or pos.x - reach > float(ox + N - 1) or pos.y + reach < float(oz) or pos.y - reach > float(oz + N - 1):
		return
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
		if r <= 0.0:
			return
	for iz in range(iz0, iz1 + 1):
		var z := float(oz + iz)
		for ix in range(ix0, ix1 + 1):
			var x := float(ox + ix)
			var f := 1.0
			if is_rect:
				var dx := x - pos.x
				var dz := z - pos.y
				var lx := dx * cy - dz * sy
				var lz := dx * sy + dz * cy
				var qx := maxf(absf(lx) - hw, 0.0)
				var qz := maxf(absf(lz) - hd, 0.0)
				f = 1.0 - s * (1.0 - HeightFunction.smooth(0.0, soft, sqrt(qx * qx + qz * qz)))
			else:
				f = 1.0 - s * (1.0 - HeightFunction.smooth(r * 0.35, r, Vector2(x, z).distance_to(pos)))
			if f >= 0.9999:
				continue
			var k := iz * N + ix
			ao[k] = clampf(ao[k] * f if apply else ao[k] / f, 0.0, 1.0)


static func occluder_reach(o: Dictionary) -> float:
	if o.has("size"):
		return (o["size"] as Vector2).length() * 0.5 + float(o.get("soft", 1.5))
	return float(o.get("r", 0.0))


## COLOR array of one terrain quadrant for the current `ao`.
func quad_colors_of(q: int) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(QN * QN)
	var i0 := (q % 2) * (QN - 1)
	var j0 := (q / 2) * (QN - 1)
	for jj in QN:
		for ii in QN:
			var k := (j0 + jj) * N + i0 + ii
			var t := tints[k]
			out[jj * QN + ii] = Color(t.r, t.g, t.b, ao[k])
	return out


## COLOR array (tint rgb + AO alpha) for the current `ao`.
func colors() -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(tints.size())
	for k in tints.size():
		var t := tints[k]
		out[k] = Color(t.r, t.g, t.b, ao[k])
	return out


# ------------------------------------------------------------------ MultiMesh buffers (2 × 2 blocks of 32 m)
func _build_multimesh(ox: int, oz: int) -> void:
	var groups := {}
	for ei in entries.size():
		var e: Dictionary = entries[ei]
		if bool(e["felled"]):
			continue
		var bx := clampi(int((float(e["x"]) - float(ox)) / BLOCK), 0, 1)
		var bz := clampi(int((float(e["z"]) - float(oz)) / BLOCK), 0, 1)
		var mk := (bz * 2 + bx) * 64 + int(e["v"])
		if not groups.has(mk):
			groups[mk] = []
			mm_keys.append(mk)
		(groups[mk] as Array).append(ei)
	mm_keys.sort()
	for mk in mm_keys:
		var list: Array = groups[mk]
		var buf := PackedFloat32Array()
		buf.resize(list.size() * 12)
		var idx := PackedInt32Array()
		idx.resize(list.size())
		for n in list.size():
			var row := instance_row(entries[list[n]])
			for q in 12:
				buf[n * 12 + q] = row[q]
			idx[n] = list[n]
		mm[mk] = {"buf": buf, "idx": idx}


## The 12 floats of an instance transform in MultiMesh.buffer layout (rows of the 3 × 4 matrix).
static func instance_row(e: Dictionary) -> PackedFloat32Array:
	var yaw := float(e["yaw"])
	var s := float(e["s"])
	var c := cos(yaw) * s
	var sn := sin(yaw) * s
	return PackedFloat32Array([c, 0.0, sn, float(e["x"]), 0.0, s, 0.0, float(e["y"]), -sn, 0.0, c, float(e["z"])])
