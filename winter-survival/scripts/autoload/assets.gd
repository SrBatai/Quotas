extends Node
## Model loader: uses res://assets/models/<name>.glb when present, primitive placeholders otherwise.
## Always guarantees the anchor nodes from ASSET_SPEC §5 exist.

const MODELS_DIR := "res://assets/models/"
## Models that only exist as placeholders (no glb is expected): no warning.
const PLACEHOLDER_ONLY := ["meat", "pelt"]

## Palette (ASSET_SPEC §3)
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
}

## Test hook: ignore the .glb files and always build placeholders.
var force_placeholders: bool = false

var _cache: Dictionary = {}
var _materials: Dictionary = {}
var _glow: StandardMaterial3D
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


## Flat palette material (cached by name).
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
	if mat_name == "ice":
		m.roughness = 0.35
		m.metallic_specular = 0.6
	_materials[mat_name] = m
	return m


func get_glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.resource_name = "window_glow"
		_glow.albedo_color = Color("#FFB454")
		_glow.emission_enabled = true
		_glow.emission = Color("#FFB454")
		_glow.emission_energy_multiplier = 2.5
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _glow


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
