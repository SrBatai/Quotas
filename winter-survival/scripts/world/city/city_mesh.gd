class_name CityMesh
extends RefCounted
## Fast flat-shaded vertex-colour mesh accumulator for the city families (C1). Pure data (PackedArrays): safe in the
## ChunkJob worker threads; `arrays()` gives the Mesh.ARRAY_* list for ArrayMesh.add_surface_from_arrays on the main
## thread. Colours are given in sRGB and stored linear with the baked AO in COLOR.a (the world_vcol contract: ≤ 0.3
## on slabs and interior walls = sheltered, no snow; ≈ 1 outdoors). Normals are the face normals (flat shading, no
## shared vertices), so no SurfaceTool / generate_normals pass is needed (≈ 5× faster in GDScript).
## Winding: Godot's front faces are clockwise seen from the visible side; every quad is given with the direction it
## must be visible from (`facing`) and is wound accordingly.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()


func is_empty() -> bool:
	return v.is_empty()


func tris() -> int:
	return v.size() / 3


static func lin(col: Color, ao: float) -> Color:
	var l := col.srgb_to_linear()
	l.a = ao
	return l


## Quad a-b-c-d (a closed loop, either winding) visible from the side `facing` points to.
func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, facing: Vector3, col: Color, ao: float = 1.0) -> void:
	var l := lin(col, ao)
	var nn := facing.normalized()
	if (b - a).cross(cc - a).dot(facing) >= 0.0:
		v.append_array([a, cc, b, a, d, cc])
	else:
		v.append_array([a, b, cc, a, cc, d])
	for i in 6:
		n.append(nn)
		c.append(l)


## Triangle visible from `facing`.
func tri(a: Vector3, b: Vector3, cc: Vector3, facing: Vector3, col: Color, ao: float = 1.0) -> void:
	var l := lin(col, ao)
	var nn := facing.normalized()
	if (b - a).cross(cc - a).dot(facing) >= 0.0:
		v.append_array([a, cc, b])
	else:
		v.append_array([a, b, cc])
	for i in 3:
		n.append(nn)
		c.append(l)


## Vertical wall quad along the segment a→b (plan points) from y0 to y1, visible from `out` (plan normal).
func wall(a: Vector2, b: Vector2, y0: float, y1: float, out: Vector2, col: Color, ao: float = 1.0) -> void:
	if y1 - y0 < 0.001 or a.distance_squared_to(b) < 1e-6:
		return
	quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y), Vector3(out.x, 0.0, out.y), col, ao)


## Horizontal convex polygon (plan points, any winding) at height y, visible from above (`up`) or below.
func floor_poly(pts: PackedVector2Array, y: float, up: bool, col: Color, ao: float = 1.0) -> void:
	var f := Vector3.UP if up else Vector3.DOWN
	for i in range(1, pts.size() - 1):
		tri(Vector3(pts[0].x, y, pts[0].y), Vector3(pts[i].x, y, pts[i].y), Vector3(pts[i + 1].x, y, pts[i + 1].y), f, col, ao)


## Axis-aligned closed box standing on `base` (centre of its bottom face): 4 sides + top (+ bottom when `bottom`).
func box(base: Vector3, size: Vector3, col: Color, top: Color, ao: float = 1.0, bottom: bool = false) -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := base.y
	var y1 := base.y + size.y
	var x0 := base.x - hx
	var x1 := base.x + hx
	var z0 := base.z - hz
	var z1 := base.z + hz
	wall(Vector2(x0, z1), Vector2(x1, z1), y0, y1, Vector2(0, 1), col, ao)
	wall(Vector2(x1, z0), Vector2(x0, z0), y0, y1, Vector2(0, -1), col, ao)
	wall(Vector2(x1, z1), Vector2(x1, z0), y0, y1, Vector2(1, 0), col, ao)
	wall(Vector2(x0, z0), Vector2(x0, z1), y0, y1, Vector2(-1, 0), col, ao)
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, top, ao)
	if bottom:
		quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN, col, ao * 0.6)


## A box whose plan is the oriented rectangle along a→b (plan), `depth` toward `out` (plan unit), from y0 to y1.
## Used for balconies, cornices, railings and parapets on facades of any direction.
func slab_along(a: Vector2, b: Vector2, out: Vector2, depth: float, y0: float, y1: float, col: Color, top: Color, ao: float = 1.0) -> void:
	var a2 := a + out * depth
	var b2 := b + out * depth
	var d := (b - a).normalized()
	wall(a2, b2, y0, y1, out, col, ao)
	wall(b, a, y0, y1, -out, col, ao * 0.8)
	wall(a, a2, y0, y1, -d, col, ao)
	wall(b2, b, y0, y1, d, col, ao)
	quad(Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b2.x, y1, b2.y), Vector3(a2.x, y1, a2.y), Vector3.UP, top, ao)
	quad(Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b2.x, y0, b2.y), Vector3(a2.x, y0, a2.y), Vector3.DOWN, col, ao * 0.7)


## Mesh arrays (vertex, normal, colour) for ArrayMesh.add_surface_from_arrays; [] when empty.
func arrays() -> Array:
	if v.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	return arr


## Appends another accumulator (moved by `offset`).
func merge(o: CityMesh, offset: Vector3 = Vector3.ZERO) -> void:
	if offset == Vector3.ZERO:
		v.append_array(o.v)
	else:
		for p in o.v:
			v.append(p + offset)
	n.append_array(o.n)
	c.append_array(o.c)
