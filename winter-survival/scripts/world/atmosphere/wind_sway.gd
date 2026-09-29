class_name WindSway
extends RefCounted
## G2b per-vertex wind materials (PLAN v3.8.2 G2b, doc 08 §3.10): the world_vcol family members that move in the
## wind (assets/shaders/wind_include.gdshaderinc). Nothing per instance and no script per frame: the vertex shader
## reads the `snow_wind` global (DayNight / Atmosphere) and TIME.
##   world_vcol_foliage  pines, birches, dead trees, bushes (scatter MultiMeshes via Assets.instancing_mesh, and the
##                       materialized ChoppableTree, so a hovered tree keeps swaying in step)
##   world_vcol_cloth    tarps / tents / laundry (city: the military tent)
##   world_vcol_cable    hanging cables (AmbientLife strings them between facing street lamps)
## Other lanes put these on their meshes with swap_surfaces(mesh, kind) (a copy; the source mesh is not touched).

const FOLIAGE := "res://assets/materials/world_vcol_foliage.tres"
const CLOTH := "res://assets/materials/world_vcol_cloth.tres"
const CABLE := "res://assets/materials/world_vcol_cable.tres"
## Scatter models that sway, with their reference height (m, model space; the bend grows with (h / height)²).
const TREE_HEIGHTS := {
	"pine_a": 8.0, "pine_b": 7.0, "pine_c": 6.0, "pine_d": 9.0, "pine_e": 8.0, "pine_f": 7.5, "pine_young": 3.5,
	"birch": 8.0, "dead_tree": 7.0, "dead_tree_b": 7.5, "dead_tree_c": 5.0, "bush_a": 1.6, "bush_b": 1.6,
}
## Off switch (tests comparing against G1, or a low preset later).
static var enabled: bool = true
static var _mats: Dictionary = {}          # "kind|height" -> ShaderMaterial
static var _swapped: Dictionary = {}       # original Mesh -> swapped copy


static func is_wind_model(model_name: String) -> bool:
	return TREE_HEIGHTS.has(model_name)


## The material of a wind kind (`foliage` / `cloth` / `cable`) at a reference height / span (shared per value).
static func material(kind: String, height: float = 8.0) -> ShaderMaterial:
	var key := "%s|%.2f" % [kind, height]
	if _mats.has(key):
		return _mats[key]
	var path := FOLIAGE if kind == "foliage" else (CLOTH if kind == "cloth" else CABLE)
	var base := load(path) as ShaderMaterial
	var m := base
	if base != null and not is_equal_approx(float(base.get_shader_parameter("wind_height")), height):
		m = base.duplicate() as ShaderMaterial
		m.set_shader_parameter("wind_height", height)
		m.resource_name = "%s_%d" % [base.resource_name, int(round(height * 10.0))]
	_mats[key] = m
	return m


## Assets.instancing_mesh hook: the swaying copy of a scatter model's instancing mesh (the input for other models).
static func instancing_mesh(model_name: String, mesh: Mesh) -> Mesh:
	if not enabled or mesh == null or not is_wind_model(model_name):
		return mesh
	return swap_surfaces(mesh, "foliage", float(TREE_HEIGHTS[model_name]))


## A copy of `mesh` whose world_vcol surfaces use the wind material of `kind` (cached per source mesh).
static func swap_surfaces(mesh: Mesh, kind: String, height: float = 8.0) -> Mesh:
	if mesh == null:
		return mesh
	var key := "%d|%s|%.2f" % [mesh.get_instance_id(), kind, height]
	if _swapped.has(key):
		return _swapped[key]
	var out: Mesh = mesh
	var wm := material(kind, height)
	if wm != null and mesh is ArrayMesh:
		var copy := (mesh as ArrayMesh).duplicate() as ArrayMesh
		var hit := false
		for i in copy.get_surface_count():
			if _is_world_vcol(copy.surface_get_material(i)):
				copy.surface_set_material(i, wm)
				hit = true
		if hit:
			out = copy
	_swapped[key] = out
	return out


## Materialized scatter tree (ChoppableTree): its model's world_vcol surfaces sway like the MultiMesh instance did.
static func apply_to_model(root: Node, model_name: String) -> void:
	if not enabled or root == null or not is_wind_model(model_name):
		return
	var wm := material("foliage", float(TREE_HEIGHTS[model_name]))
	_apply(root, wm)


## Any node tree (tents, tarps, cables of other lanes): every world_vcol / world_vcol_capsule surface -> `kind`.
static func apply_to_node(root: Node, kind: String, height: float) -> void:
	if root == null:
		return
	_apply(root, material(kind, height))


static func _apply(n: Node, wm: Material) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var cur: Material = mi.get_surface_override_material(i)
			if cur == null:
				cur = mi.mesh.surface_get_material(i)
			if _is_world_vcol(cur):
				mi.set_surface_override_material(i, wm)
	for c in n.get_children():
		_apply(c, wm)


static func _is_world_vcol(m: Material) -> bool:
	if m == null:
		return false
	var n := m.resource_name
	return n == "world_vcol" or n == "world_vcol_capsule"
