class_name CityHlod
extends RefCounted
## Per-chunk HLOD hook for city buildings (G2a doc 08 §3.13, doc 09 §4.6). The play camera never sees past
## 70–95 m and nothing above its own height (the skyline does not exist in play), so this only serves miradores,
## the menu and map renders: one merged, low-poly MeshInstance3D per chunk (one draw call) made from each
## building's ShadowProxy (or its box), vertex-coloured, with a band of lit windows by night through the shared
## window_city material. Visibility: the HLOD shows beyond `Quality.hlod_begin()` and every piece of its
## buildings gets it as `visibility_parent`, so they hide when it shows (Godot's HLOD semantics); nothing is drawn
## twice. The chunk streamer calls build_for(chunk_root) after instancing a city chunk (C1); the bench calls it
## on its block. An impostor provider can replace the mesh builder through `mesh_builder`.

const WALL_COLOR := Color(0.36, 0.39, 0.45)
const ROOF_COLOR := Color(0.78, 0.84, 0.92)

## Optional Callable(buildings: Array[Node3D]) -> Mesh (impostor / baked HLOD instead of the merged proxies).
static var mesh_builder: Callable


## Builds the HLOD of every city building under `chunk_root` and parents it there. Returns null without buildings.
static func build_for(chunk_root: Node3D, begin: float = -1.0) -> MeshInstance3D:
	var roots: Array[Node3D] = []
	if not chunk_root.is_inside_tree():
		return null
	for n in chunk_root.get_tree().get_nodes_in_group(CityBuilding.GROUP):
		if chunk_root.is_ancestor_of(n):
			roots.append(n)
	if roots.is_empty():
		return null
	var mesh: Mesh = mesh_builder.call(roots) if mesh_builder.is_valid() else merged_proxies(roots, chunk_root)
	var mi := MeshInstance3D.new()
	mi.name = "CityHLOD"
	mi.mesh = mesh
	mi.material_override = Assets.get_shared_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = begin if begin > 0.0 else Quality.hlod_begin()
	mi.visibility_range_begin_margin = 10.0
	if Quality.visibility_fade():
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	chunk_root.add_child(mi)
	for r in roots:
		r.set_meta(CityBuilding.HLOD_META, mi)
		for c in r.get_children():
			if CityBuilding.canonical(String(c.name)) == CityBuilding.PROXY or String(c.name).begins_with("Col"):
				continue
			for gi in BuildingCutaway._geometries(c):
				gi.visibility_parent = gi.get_path_to(mi)
	return mi


## C1 streaming in slices (CityChunk): the HLOD mesh of the given roots only (no group scan, no linking) — the
## streamer then links a few buildings per step with link(). Same mesh, material and ranges as build_for.
static func make(chunk_root: Node3D, roots: Array[Node3D], begin: float = -1.0) -> MeshInstance3D:
	if roots.is_empty():
		return null
	var mesh: Mesh = mesh_builder.call(roots) if mesh_builder.is_valid() else merged_proxies(roots, chunk_root)
	var mi := MeshInstance3D.new()
	mi.name = "CityHLOD"
	mi.mesh = mesh
	mi.material_override = Assets.get_shared_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_begin = begin if begin > 0.0 else Quality.hlod_begin()
	mi.visibility_range_begin_margin = 10.0
	if Quality.visibility_fade():
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	chunk_root.add_child(mi)
	return mi


## Links one building's pieces to the HLOD `mi` (what build_for does for each of its roots).
static func link(mi: MeshInstance3D, r: Node3D) -> void:
	r.set_meta(CityBuilding.HLOD_META, mi)
	for c in r.get_children():
		var nm := String(c.name)
		# (collider bodies hold no geometry: a hero tower's FloorsCol has 400–700 shapes to walk through)
		if CityBuilding.canonical(nm) == CityBuilding.PROXY or nm.begins_with("Col") or nm.ends_with("Col") or nm == "Shelter":
			continue
		for gi in BuildingCutaway._geometries(c):
			gi.visibility_parent = gi.get_path_to(mi)


## Undoes build_for (chunk unload, or before a rebuild): clears the pieces' visibility_parent and frees the HLOD.
static func remove_from(chunk_root: Node3D) -> void:
	var mi := chunk_root.get_node_or_null("CityHLOD") as MeshInstance3D
	if mi == null:
		return
	for n in chunk_root.get_tree().get_nodes_in_group(CityBuilding.GROUP):
		if not chunk_root.is_ancestor_of(n):
			continue
		(n as Node).remove_meta(CityBuilding.HLOD_META)
		for gi in BuildingCutaway._geometries(n):
			gi.visibility_parent = NodePath("")
	chunk_root.remove_child(mi)
	mi.queue_free()


## One ArrayMesh (one surface, vertex colours in linear space like the palette) with a box per building: its
## ShadowProxy AABB, or the AABB of its pieces. Walls darker with a lighter snowy top.
static func merged_proxies(roots: Array[Node3D], space: Node3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat normals (the default group 0 averages shared corners)
	var inv := space.global_transform.affine_inverse()
	for r in roots:
		var box := _box_of(r)
		if box.size == Vector3.ZERO:
			continue
		var xf := inv * r.global_transform
		_box(st, xf, box)
	st.generate_normals()
	return st.commit()


static func _box_of(r: Node3D) -> AABB:
	var b := r.get_node_or_null("CityBuilding") as CityBuilding
	if b != null and b.footprint.size != Vector3.ZERO:
		return AABB(Vector3(b.footprint.position.x, 0.0, b.footprint.position.z), Vector3(b.footprint.size.x, b.height, b.footprint.size.z))
	var box := AABB()
	for gi in BuildingCutaway._geometries(r):
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
			var bb := (r.global_transform.affine_inverse() * gi.global_transform) * (gi as MeshInstance3D).get_aabb()
			box = bb if box.size == Vector3.ZERO else box.merge(bb)
	return box


static func _box(st: SurfaceTool, xf: Transform3D, b: AABB) -> void:
	var p0 := b.position
	var p1 := b.end
	var c := [Vector3(p0.x, 0, p0.z), Vector3(p1.x, 0, p0.z), Vector3(p1.x, 0, p1.z), Vector3(p0.x, 0, p1.z)]
	var wall := WALL_COLOR.srgb_to_linear()
	var roof := ROOF_COLOR.srgb_to_linear()
	for k in 4:
		var a: Vector3 = c[k]
		var d: Vector3 = c[(k + 1) % 4]
		_quad(st, xf, Vector3(d.x, p0.y, d.z), Vector3(a.x, p0.y, a.z), Vector3(a.x, p1.y, a.z), Vector3(d.x, p1.y, d.z), wall)
	_quad(st, xf, Vector3(p0.x, p1.y, p1.z), Vector3(p1.x, p1.y, p1.z), Vector3(p1.x, p1.y, p0.z), Vector3(p0.x, p1.y, p0.z), roof)


static func _quad(st: SurfaceTool, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_color(col)
		st.add_vertex(xf * v)
