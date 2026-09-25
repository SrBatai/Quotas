extends Node
## Model loader: uses res://assets/models/<name>.glb when present, primitive placeholders otherwise.
## Always guarantees the anchor nodes from ASSET_SPEC v2 exist (front = +Z, Vector3.MODEL_FRONT).
## Every `palette_vcol` surface is rendered with ONE shared ShaderMaterial (assets/materials/world_vcol.tres);
## the named exception materials (window, ember, …) stay separate surfaces so code can find them by name.

const MODELS_DIR := "res://assets/models/"
const SHARED_MATERIAL_PATH := "res://assets/materials/world_vcol.tres"
## The terrain's single ShaderMaterial (shared by every chunk; the trail map is set on it by Footprints).
const TERRAIN_MATERIAL_PATH := "res://assets/materials/terrain.tres"
## Name of the single vertex-colour material every v2 mesh carries (ASSET_SPEC v2 §2.5). Godot's glTF importer
## strips the legacy `_vcol` suffix, so the imported StandardMaterial3D is called `palette` (white albedo,
## vertex_color_use_as_albedo = true); both names are recognised.
const VCOL_MATERIAL := "palette_vcol"
const VCOL_IMPORTED_NAMES := ["palette_vcol", "palette"]
## Materials kept as separate surfaces (ASSET_SPEC v2 §2.5).
const EXCEPTION_MATERIALS := ["window", "glass", "ember", "ice_clear", "blood", "emissive_lamp"]
## Models that only exist as placeholders (no glb is expected): no warning.
const PLACEHOLDER_ONLY := ["meat", "pelt"]
## Props < 0.5 m and interior furniture do not cast shadows (ASSET_SPEC v2 §14).
const NO_SHADOW_MODELS := ["firewood", "stone", "meat", "pelt", "torch", "stone_axe", "lantern",
	"bed", "desk", "chair", "shelf", "clock", "cabinet", "wood_stove", "storage_box"]

## Palette (ASSET_SPEC v2 §3), sRGB hex.
const PALETTE := {
	"snow": "#F1F5FA", "snow_shadow": "#B9CBE3", "ice": "#BFE3F0",
	"pine_dark": "#2F5D3A", "pine_light": "#4B8A55", "bark": "#5B3F2E",
	"wood": "#8B6543", "wood_light": "#C7A16B", "wood_dark": "#4A3426",
	"stone": "#7C8592", "stone_dark": "#5A616B", "brick": "#8E5A4A", "iron": "#2B2E33",
	"cabin_wall": "#5D7FA6", "cabin_trim": "#DDE6F0", "roof": "#33383F", "window": "#9CC4DD",
	"truck_paint": "#5B6B3F", "bush": "#3E6B45", "berry": "#D9403D", "ember": "#E63B12",
	"jacket": "#B03A2E", "hat": "#2E4A7A", "scarf": "#E8B04B", "skin": "#F1C9A5", "boots": "#2A2320",
	"wolf_fur": "#6E7378", "wolf_belly": "#A9AEB2", "eyes": "#F5D142", "eyes_dark": "#1E1E24",
	"deer_fur": "#8A6A48", "deer_belly": "#C9B79C", "cloth": "#C9B79C", "paper": "#EDE6D6",
	"can_red": "#C23B3B", "can_blue": "#3B6BC2", "fire_orange": "#FF8C2A", "fire_yellow": "#FFD166",
	"glass": "#7FA6C2", "ice_clear": "#A9D8EA", "emissive_lamp": "#FFE2A8", "blood": "#8B1E1E",
	"asphalt": "#3E4248", "concrete": "#9EA3A8", "rust": "#8A4A2B", "tire": "#1F2124",
}

## Test hook: ignore the .glb files and always build placeholders.
var force_placeholders: bool = false

var _cache: Dictionary = {}
var _materials: Dictionary = {}
var _linear_colors: Dictionary = {}
var _prepared: Dictionary = {}  # original Mesh -> Mesh with the shared material (identity when done in place)
var _shared: ShaderMaterial
var _terrain: ShaderMaterial
var _glow: StandardMaterial3D
var _lantern_glow: StandardMaterial3D
var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D
var _missing_warned: Dictionary = {}


func model_path(model_name: String) -> String:
	return MODELS_DIR + model_name + ".glb"


func has_model(model_name: String) -> bool:
	var path := model_path(model_name)
	return ResourceLoader.exists(path, "PackedScene")


func spawn_model(model_name: String) -> Node3D:
	var path := model_path(model_name)
	var root: Node3D = null
	if not force_placeholders and ResourceLoader.exists(path, "PackedScene"):
		var scene: PackedScene = _cache.get(path)
		if scene == null:
			scene = load(path) as PackedScene
			if scene != null:
				_cache[path] = scene
		if scene != null:
			root = scene.instantiate() as Node3D
	if root != null:
		root.set_meta("placeholder", false)
	else:
		root = Placeholders.build(model_name)
		root.set_meta("placeholder", true)
		if not _missing_warned.has(model_name) and not PLACEHOLDER_ONLY.has(model_name) and not force_placeholders:
			_missing_warned[model_name] = true
			push_warning("Model %s missing; using placeholder" % model_name)
	_ensure_anchors(model_name, root)
	_prepare_meshes(model_name, root)
	return root


func is_placeholder(node: Node) -> bool:
	return node != null and node.has_meta("placeholder") and bool(node.get_meta("placeholder"))


func _ensure_anchors(model_name: String, root: Node3D) -> void:
	if not Placeholders.ANCHORS.has(model_name):
		return
	for entry in Placeholders.ANCHORS[model_name]:
		var node_name: String = entry[0]
		if root.find_child(node_name, true, false) != null:
			continue
		var parent: Node = root
		var parent_name: String = entry[1]
		if parent_name != "":
			var p := root.find_child(parent_name, true, false)
			if p != null:
				parent = p
		var n := Node3D.new()
		n.name = node_name
		n.position = entry[2]
		n.rotation_degrees = entry[3]
		parent.add_child(n)
		push_warning("Model %s: anchor %s missing, created" % [model_name, node_name])


# ---------------------------------------------------------------- materials

## The single ShaderMaterial shared by every `palette_vcol` surface (PLAN C2).
func get_shared_material() -> ShaderMaterial:
	if _shared == null:
		_shared = load(SHARED_MATERIAL_PATH) as ShaderMaterial
		if _shared == null:
			push_error("Assets: cannot load %s" % SHARED_MATERIAL_PATH)
			_shared = ShaderMaterial.new()
	return _shared


## The terrain ShaderMaterial (assets/materials/terrain.tres), shared by every terrain chunk.
func get_terrain_material() -> ShaderMaterial:
	if _terrain == null:
		_terrain = load(TERRAIN_MATERIAL_PATH) as ShaderMaterial
		if _terrain == null:
			push_error("Assets: cannot load %s" % TERRAIN_MATERIAL_PATH)
			_terrain = ShaderMaterial.new()
	return _terrain


func is_exception_material(mat_name: String) -> bool:
	return EXCEPTION_MATERIALS.has(mat_name) or mat_name.begins_with("emissive_")


## Palette colour in linear space, as stored in COLOR_0 (ASSET_SPEC v2 §2.5).
func palette_linear(mat_name: String) -> Color:
	if _linear_colors.has(mat_name):
		return _linear_colors[mat_name]
	var c := Color(PALETTE.get(mat_name, "#FF00FF")).srgb_to_linear()
	_linear_colors[mat_name] = c
	return c


## Replaces `palette_vcol` with the shared material, merges legacy per-colour surfaces of v1 models into one
## vertex-coloured surface, and applies the shadow policy. Conversions are cached per mesh resource.
func _prepare_meshes(model_name: String, root: Node3D) -> void:
	var no_shadow := NO_SHADOW_MODELS.has(model_name)
	for mi in _mesh_instances(root):
		if mi.mesh != null:
			mi.mesh = _shared_mesh(mi.mesh)
		if no_shadow:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _shared_mesh(mesh: Mesh) -> Mesh:
	if _prepared.has(mesh):
		return _prepared[mesh]
	var shared := get_shared_material()
	var legacy := 0
	var has_bones := false
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m == shared:
			continue
		var mname := m.resource_name if m != null else ""
		var fmt: int = mesh.surface_get_format(i)
		if fmt & Mesh.ARRAY_FORMAT_BONES:
			has_bones = true
		if _is_vcol_material(m, fmt):
			if mesh is ArrayMesh:
				(mesh as ArrayMesh).surface_set_material(i, shared)
		elif m is StandardMaterial3D and not is_exception_material(mname) and not (fmt & Mesh.ARRAY_FORMAT_COLOR):
			legacy += 1
	var out: Mesh = mesh
	if legacy > 0 and not has_bones:
		out = _merge_legacy(mesh)
	_prepared[mesh] = out
	_prepared[out] = out
	return out


## The imported `palette_vcol` (or any white vertex-colour StandardMaterial3D on a COLOR_0 surface that is not
## a named exception): rendered with the shared ShaderMaterial instead.
func _is_vcol_material(m: Material, fmt: int) -> bool:
	if not (m is StandardMaterial3D) or not (fmt & Mesh.ARRAY_FORMAT_COLOR):
		return false
	var sm := m as StandardMaterial3D
	if is_exception_material(sm.resource_name):
		return false
	if VCOL_IMPORTED_NAMES.has(sm.resource_name):
		return true
	return sm.vertex_color_use_as_albedo and sm.albedo_color.is_equal_approx(Color.WHITE) and not sm.emission_enabled


## v1 model (one StandardMaterial3D per palette colour, no COLOR_0): bake each surface's albedo into vertex
## colours and merge every non-exception surface into a single `palette_vcol` surface.
func _merge_legacy(mesh: Mesh) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var exceptions: Array = []
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		var mname := m.resource_name if m != null else ""
		var arrays := mesh.surface_get_arrays(i)
		if m is StandardMaterial3D and not is_exception_material(mname):
			var c: Color = (m as StandardMaterial3D).albedo_color.srgb_to_linear()
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var n = arrays[Mesh.ARRAY_NORMAL]
			var base := verts.size()
			verts.append_array(v)
			if n is PackedVector3Array and n.size() == v.size():
				normals.append_array(n)
			else:
				for k in v.size():
					normals.append(Vector3.UP)
			for k in v.size():
				colors.append(c)
			var idx = arrays[Mesh.ARRAY_INDEX]
			if idx is PackedInt32Array and idx.size() > 0:
				for k in idx:
					indices.append(k + base)
			else:
				for k in v.size():
					indices.append(base + k)
		else:
			exceptions.append([arrays, m])
	var out := ArrayMesh.new()
	if verts.size() > 0:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, get_shared_material())
		out.surface_set_name(out.get_surface_count() - 1, VCOL_MATERIAL)
	for e in exceptions:
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, e[0])
		out.surface_set_material(out.get_surface_count() - 1, e[1])
	return out


## Flat StandardMaterial3D for the named palette colour (exception surfaces, lake ice). Cached by name.
func material(mat_name: String) -> StandardMaterial3D:
	if _materials.has(mat_name):
		return _materials[mat_name]
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	var hex: String = PALETTE.get(mat_name, "#FF00FF")
	m.albedo_color = Color(hex)
	m.roughness = 0.95
	m.metallic = 0.0
	m.metallic_specular = 0.15
	if mat_name == "ice" or mat_name == "ice_clear" or mat_name == "glass":
		m.roughness = 0.35
		m.metallic_specular = 0.6
	_materials[mat_name] = m
	return m


func get_glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.resource_name = "window_glow"
		_glow.albedo_color = Color("#FFC070")
		_glow.emission_enabled = true
		_glow.emission = Color("#FFC070")
		_glow.emission_energy_multiplier = 3.0  # doc 06 §3.6 (softlight glow reads it at night)
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _glow


## Lantern glass: dimmer than the windows (a 20 cm pane at emission 3.0 blooms into a white blob at night).
func get_lantern_glow_material() -> StandardMaterial3D:
	if _lantern_glow == null:
		_lantern_glow = StandardMaterial3D.new()
		_lantern_glow.resource_name = "lantern_glow"
		_lantern_glow.albedo_color = Color("#FFB454")
		_lantern_glow.emission_enabled = true
		_lantern_glow.emission = Color("#FFB454")
		_lantern_glow.emission_energy_multiplier = 1.4
		_lantern_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _lantern_glow


func get_ember_material() -> StandardMaterial3D:
	if not _materials.has("ember_glow"):
		var m := StandardMaterial3D.new()
		m.resource_name = "ember_glow"
		m.albedo_color = Color("#FF6A2A")
		m.emission_enabled = true
		m.emission = Color("#FF7A2A")
		m.emission_energy_multiplier = 2.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_materials["ember_glow"] = m
	return _materials["ember_glow"]


func get_ghost_material(valid: bool) -> StandardMaterial3D:
	if _ghost_ok == null:
		_ghost_ok = _make_ghost(Color("#6FD08C"))
		_ghost_bad = _make_ghost(Color("#FF5A5A"))
	return _ghost_ok if valid else _ghost_bad


func _make_ghost(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(color.r, color.g, color.b, 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Applies a material override to every MeshInstance3D surface under `root`.
func override_all(root: Node, mat: Material) -> void:
	for mi in _mesh_instances(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, mat)


func clear_overrides(root: Node) -> void:
	for mi in _mesh_instances(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, null)


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_mesh_instances(c))
	return out


## Sets an override on surfaces whose material is named `mat_name` (or all surfaces when the node is a placeholder / no names match).
func override_named(node: Node, mat_name: String, mat: Material) -> void:
	for mi in _mesh_instances(node):
		if mi.mesh == null:
			continue
		var any_named := false
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and m.resource_name == mat_name:
				any_named = true
				mi.set_surface_override_material(i, mat)
		if not any_named and mat != null and mi.get_parent() != null and String(mi.name).begins_with("Windows"):
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, mat)


## Number of surfaces under `root` still using a material called `palette_vcol` (0 after spawn_model).
func count_unshared_vcol(root: Node) -> int:
	var n := 0
	for mi in _mesh_instances(root):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			if m != null and VCOL_IMPORTED_NAMES.has(m.resource_name) and m != _shared:
				n += 1
	return n
