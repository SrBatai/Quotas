class_name CityBuilding
extends Node
## City building component (W0 + G2a; contract in ARQ v2 §9.7 and README «Corte urbano y gráficos G2»).
## Attach with CityBuilding.attach(root) to the root of a building scene; it:
##   * swaps the structure surfaces to the «corte urbano» materials of the family (world_vcol_struct*, window_city*)
##     and city props to world_vcol_capsule (all shared: nothing per instance);
##   * applies the tower split: `Base` (podium / lower floors), `Shaft` or `Shaft_<n>` (floor groups), `Roof`
##     (crown) and `ShadowProxy` (the only shadow caster, SHADOWS_ONLY) with visibility ranges and fade;
##   * registers with CityCut, which gives the shader the building the local player stands in (own-building rule);
##     while the player is on floor k the roof and the floor groups above k are hidden shadow-preserving
##     (SHADOWS_ONLY, or invisible when a proxy casts for them), never `visible = false` on a caster;
##   * drives the enterable cut groups (`Floor<k>`, `Walls<k>_*`, `Interior<k>`, …) with a BuildingCutaway in
##     shadow mode.
## Root metadata (node meta, or glTF extras in meta "extras"): floor_h (3.0), ground_h (3.3), foundation (0.3),
## floors, generator (bool), enterable (bool), kind. See validate() for the full contract.

const GROUP := &"city_building"
const BASE := "Base"
const SHAFT := "Shaft"
const ROOF := "Roof"
const PROXY := "ShadowProxy"
## Provisional names of the first A1 exports (doc 08 §3.13 wording) mapped to the contract names.
const ALIASES := {"Tower_Base": "Base", "Tower_Top": "Roof", "Tower_Shadow": "ShadowProxy", "Tower_Shaft": "Shaft"}
const HLOD_META := &"city_hlod"
## Visibility ranges (m from the camera): the camera far is 70–95 m in play, so these only matter for miradores.
const RANGE_BASE_END := 180.0
const RANGE_UPPER_END := 150.0
const RANGE_MARGIN := 12.0
const STRUCT_MAT := "res://assets/materials/world_vcol_struct.tres"
const STRUCT_MAT_4M := "res://assets/materials/world_vcol_struct_4m.tres"
const WINDOW_MAT := "res://assets/materials/window_city.tres"
const WINDOW_MAT_4M := "res://assets/materials/window_city_4m.tres"
const CAPSULE_MAT := "res://assets/materials/world_vcol_capsule.tres"
const STRUCT_NAMES := ["palette_vcol", "palette", "world_vcol"]
const GLASS_NAMES := ["window", "glass"]

static var _mats: Dictionary = {}

var root: Node3D
var floor_h: float = 3.0
var ground_h: float = 3.3
var foundation: float = 0.3
var floors: int = 1
var height: float = 3.0
## Local height of the roof slab (top of the last floor): above it the player is ON the building, not in it.
var roof_level: float = 3.0
var generator: bool = false
var enterable: bool = false
## Footprint in the root's local space (xz; y = 0 … height).
var footprint := AABB()
var cutaway: BuildingCutaway
var player_floor: int = -1
var has_proxy: bool = false
var _shafts: Array = []                 # [floor_from, Node3D]
var _roof: Node3D
var _xf := Transform3D()
var _inv := Transform3D()
var _reach: float = 0.0                 # footprint half diagonal (m), for the cheap distance reject


static func attach(p_root: Node3D) -> CityBuilding:
	var b := CityBuilding.new()
	b.name = "CityBuilding"
	p_root.add_child(b)
	b.setup(p_root)
	return b


## Contract name of a piece: the Tower_* aliases (Tower_Shaft_<n> -> Shaft_<n>) map to Base / Shaft / Roof /
## ShadowProxy; any other name is returned unchanged.
static func canonical(n: String) -> String:
	if ALIASES.has(n):
		return ALIASES[n]
	if n.begins_with("Tower_Shaft_"):
		return "Shaft_" + n.substr(12)
	return n


## First-level piece by contract name (or its alias).
static func piece(p_root: Node, contract_name: String) -> Node:
	for c in p_root.get_children():
		if canonical(String(c.name)) == contract_name:
			return c
	return null


static func meta_of(n: Node, key: String, default: Variant) -> Variant:
	if n.has_meta(key):
		return n.get_meta(key)
	var ex: Variant = n.get_meta("extras", {})
	if ex is Dictionary and (ex as Dictionary).has(key):
		return ex[key]
	return default


func setup(p_root: Node3D) -> void:
	root = p_root
	root.add_to_group(GROUP)
	floor_h = float(meta_of(root, "floor_h", 3.0))
	ground_h = float(meta_of(root, "ground_h", 3.3))
	foundation = float(meta_of(root, "foundation", 0.3))
	floors = int(meta_of(root, "floors", 1))
	generator = bool(meta_of(root, "generator", false))
	enterable = bool(meta_of(root, "enterable", false))
	var proxy := piece(root, PROXY) as GeometryInstance3D
	has_proxy = proxy != null
	_roof = piece(root, ROOF) as Node3D
	for c in root.get_children():
		var n := canonical(String(c.name))
		if n == SHAFT or n.begins_with(SHAFT + "_"):
			_shafts.append([int(meta_of(c, "floor_from", 0)), c])
	_measure()
	apply_materials(root, ground_h, floor_h)
	_apply_lod_and_shadows()
	if BuildingCutaway.has_cut_groups(root):
		cutaway = BuildingCutaway.new()
		cutaway.name = "Cutaway"
		cutaway.hide_mode = BuildingCutaway.HideMode.SHADOW
		add_child(cutaway)
		cutaway.setup(root)
	if is_inside_tree():
		CityCut.register(self)


func _enter_tree() -> void:
	if root != null:
		CityCut.register(self)   # (re)entering the tree: the registry grid needs the building's position


func _exit_tree() -> void:
	CityCut.unregister(self)


func _measure() -> void:
	var box := AABB()
	var src: Array[Node] = []
	var proxy := piece(root, PROXY)
	if proxy != null:
		src.append(proxy)
	else:
		for c in root.get_children():
			if c is GeometryInstance3D and not String(c.name).begins_with("Col"):
				src.append(c)
	for n in src:
		for gi in BuildingCutaway._geometries(n):
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
				var bb := _local_xform(gi) * (gi as MeshInstance3D).get_aabb()
				box = bb if box.size == Vector3.ZERO else box.merge(bb)
	footprint = box
	_reach = Vector2(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z))).length()
	height = maxf(box.end.y, ground_h)
	if floors <= 1 and height > ground_h + 1.0:
		floors = 1 + int(round((height - ground_h) / floor_h))
	roof_level = ground_h + float(floors - 1) * floor_h if floors >= 1 else height
	roof_level = minf(roof_level, height)


func _local_xform(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


## Structure → world_vcol_struct (by floor heights), facade glass → window_city, anything else left alone.
## `props_root` surfaces (street furniture, cars) use apply_prop_materials instead.
static func apply_materials(p_root: Node, p_ground_h: float = 3.3, p_floor_h: float = 3.0) -> void:
	var sm := struct_material(p_ground_h, p_floor_h)
	var wm := window_material(p_ground_h, p_floor_h)
	for gi in BuildingCutaway._geometries(p_root):
		var n := canonical(String(gi.name))
		if n == PROXY or n.begins_with("Col") or not (gi is MeshInstance3D):
			continue
		var mi := gi as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var kind := _surface_kind(mi, i)
			if kind == 1:
				mi.set_surface_override_material(i, sm)
			elif kind == 2:
				mi.set_surface_override_material(i, wm)


## City props, cars, lamps: the shared world_vcol surfaces become world_vcol_capsule (cut by the camera capsule).
static func apply_prop_materials(p_root: Node) -> void:
	var cm := capsule_material()
	for gi in BuildingCutaway._geometries(p_root):
		if not (gi is MeshInstance3D) or (gi as MeshInstance3D).mesh == null:
			continue
		var mi := gi as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			if _surface_kind(mi, i) == 1:
				mi.set_surface_override_material(i, cm)


## 1 = vertex-colour structure, 2 = glass, 0 = other (emissive, exceptions).
static func _surface_kind(mi: MeshInstance3D, i: int) -> int:
	var m := mi.get_surface_override_material(i)
	if m == null:
		m = mi.mesh.surface_get_material(i)
	if m == null:
		return 1
	if m == Assets.get_shared_material():
		return 1
	var nm := m.resource_name.to_lower()
	if nm in GLASS_NAMES:
		return 2
	if nm in STRUCT_NAMES or nm.begins_with("world_vcol"):
		return 1
	return 0


static func struct_material(p_ground_h: float = 3.3, p_floor_h: float = 3.0) -> ShaderMaterial:
	return _family(STRUCT_MAT, STRUCT_MAT_4M, "struct", p_ground_h, p_floor_h)


static func window_material(p_ground_h: float = 3.3, p_floor_h: float = 3.0) -> ShaderMaterial:
	return _family(WINDOW_MAT, WINDOW_MAT_4M, "window", p_ground_h, p_floor_h)


static func capsule_material() -> ShaderMaterial:
	if not _mats.has("capsule"):
		_mats["capsule"] = load(CAPSULE_MAT)
	return _mats["capsule"]


## One shared material per (family, ground_h, floor_h): the two standard grids are .tres files; any other grid
## gets one duplicate, cached, so a city still has a handful of materials.
static func _family(path_3m: String, path_4m: String, fam: String, gh: float, fh: float) -> ShaderMaterial:
	var key := "%s_%.2f_%.2f" % [fam, gh, fh]
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial
	if is_equal_approx(fh, 3.0) and is_equal_approx(gh, 3.3):
		m = load(path_3m)
	elif is_equal_approx(fh, 3.0) and is_equal_approx(gh, 4.3):
		m = load(path_4m)
	else:
		m = (load(path_3m) as ShaderMaterial).duplicate()
		m.resource_name = "%s_%s" % [m.resource_name, key]
		m.set_shader_parameter("ground_h", gh)
		m.set_shader_parameter("floor_h", fh)
	_mats[key] = m
	return m


func _apply_lod_and_shadows() -> void:
	var fade := Quality.visibility_fade()
	for c in root.get_children():
		var n := canonical(String(c.name))
		if n.begins_with("Col"):
			continue
		if n == PROXY:
			for gi in BuildingCutaway._geometries(c):
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			continue
		var end := RANGE_BASE_END if n == BASE or not (n == ROOF or n.begins_with(SHAFT)) else RANGE_UPPER_END
		for gi in BuildingCutaway._geometries(c):
			gi.visibility_range_end = end
			gi.visibility_range_end_margin = RANGE_MARGIN
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF if fade else GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if has_proxy:
				gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ------------------------------------------------------------------ own-building queries (CityCut)

## Is the world point inside this building (footprint, below its roof slab)? A player standing ON the roof is not.
func contains(p_world: Vector3) -> bool:
	if not near(p_world, 0.0):
		return false
	var p := _local(p_world)
	return p.x > footprint.position.x + 0.1 and p.x < footprint.end.x - 0.1 \
		and p.z > footprint.position.z + 0.1 and p.z < footprint.end.z - 0.1 \
		and p.y > -0.6 and p.y < roof_level - 0.25


## Is the world point standing on this building's roof (footprint, up to 3 m over the roof slab)?
func on_roof(p_world: Vector3) -> bool:
	if not near(p_world, 0.0):
		return false
	var p := _local(p_world)
	return p.x > footprint.position.x + 0.1 and p.x < footprint.end.x - 0.1 \
		and p.z > footprint.position.z + 0.1 and p.z < footprint.end.z - 0.1 \
		and p.y >= roof_level - 0.25 and p.y < roof_level + 3.0


## Does the camera at `p_world` look into this building from inside or from right against it? (footprint grown by
## `margin`, camera below the roof). CityCut then removes the whole building above the floor cut: otherwise its
## floors, seen through the cut facade, ring the view (doc 09 §3.8, «anillo de losas»).
func hugs_camera(p_world: Vector3, margin: float) -> bool:
	if not near(p_world, margin):
		return false
	var p := _local(p_world)
	return p.x > footprint.position.x - margin and p.x < footprint.end.x + margin \
		and p.z > footprint.position.z - margin and p.z < footprint.end.z + margin \
		and p.y > 0.0 and p.y < height + 2.0


## Radius of the footprint around the building origin, in plan (m).
func reach() -> float:
	return _reach


## Cheap reject before the exact tests: is the point within the footprint's circle (+ margin) in plan?
func near(p_world: Vector3, margin: float) -> bool:
	if root == null or not root.is_inside_tree() or footprint.size == Vector3.ZERO:
		return false
	var o := root.global_position
	var r := _reach + margin
	return (p_world.x - o.x) * (p_world.x - o.x) + (p_world.z - o.z) * (p_world.z - o.z) <= r * r


## World -> building space, with the inverse cached while the building does not move (they never do).
func _local(p_world: Vector3) -> Vector3:
	var xf := root.global_transform
	if xf != _xf:
		_xf = xf
		_inv = xf.affine_inverse()
	return _inv * p_world


func base_y() -> float:
	return root.global_position.y


## Floor index for a world height (0 = ground floor), with the same half-metre tolerance as the shader.
func floor_index(y_world: float) -> int:
	return maxi(0, int(ceil((y_world + 0.5 - base_y() - ground_h) / floor_h)))


## World height of the walkable level of floor k.
func floor_level(k: int) -> float:
	if k <= 0:
		return base_y() + foundation
	return base_y() + ground_h + float(k - 1) * floor_h


## Footprint box for the shader: centre (world xz), half extents, yaw.
func own_box() -> Dictionary:
	var centre_local := footprint.get_center()
	var c := root.global_transform * Vector3(centre_local.x, 0.0, centre_local.z)
	var yaw := root.global_rotation.y
	return {"centre": Vector2(c.x, c.z), "half": Vector2(footprint.size.x * 0.5, footprint.size.z * 0.5), "yaw": yaw}


## CityCut: the local player is now on floor k of this building (-1 = left it). Hides the roof and the floor
## groups above k, shadow-preserving.
func set_player_floor(k: int) -> void:
	if k == player_floor:
		return
	player_floor = k
	if _roof != null:
		_hide_keep_shadow(_roof, k >= 0)
	for s in _shafts:
		_hide_keep_shadow(s[1], k >= 0 and int(s[0]) > k)


func _hide_keep_shadow(n: Node, hidden: bool) -> void:
	for gi in BuildingCutaway._geometries(n):
		if not gi.has_meta(BuildingCutaway.META_CAST):
			gi.set_meta(BuildingCutaway.META_CAST, gi.cast_shadow)
		var orig: int = int(gi.get_meta(BuildingCutaway.META_CAST))
		if not hidden:
			gi.cast_shadow = orig as GeometryInstance3D.ShadowCastingSetting
			gi.visible = true
		elif orig == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			gi.visible = false
		else:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			gi.visible = true


# ------------------------------------------------------------------ contract check (tests, art pipeline)

## Problems with a city building scene (empty = conforms). `strict` also flags the soft rules (proxy on tall
## buildings, floor count metadata).
static func validate(p_root: Node3D, strict: bool = true) -> PackedStringArray:
	var out := PackedStringArray()
	var base := piece(p_root, BASE)
	if base == null:
		out.append("missing %s" % BASE)
	var fh := float(meta_of(p_root, "floor_h", 3.0))
	var gh := float(meta_of(p_root, "ground_h", 3.3))
	if fh < 2.4 or fh > 6.0:
		out.append("floor_h %.2f outside 2.4–6.0" % fh)
	if gh < fh * 0.8 or gh > 8.0:
		out.append("ground_h %.2f outside %.1f–8.0" % [gh, fh * 0.8])
	var top := 0.0
	for c in p_root.get_children():
		if not (c is Node3D):
			continue
		var n := canonical(String(c.name))
		var t := (c as Node3D).transform
		if n.begins_with("Col") or n.begins_with("Spawn_") or n.begins_with("Door_") or n.begins_with("Window_") or n.ends_with("Anchor"):
			continue
		if absf(t.origin.y) > 0.001:
			out.append("%s: local y offset %.3f (pieces keep the building base at y = 0)" % [n, t.origin.y])
		if not t.basis.get_scale().is_equal_approx(Vector3.ONE):
			out.append("%s: scaled %s (no scale on pieces)" % [n, t.basis.get_scale()])
		var up := t.basis.y.normalized()
		if up.dot(Vector3.UP) < 0.999:
			out.append("%s: tilted (rotation about Y only)" % n)
		if n.begins_with(SHAFT + "_") and meta_of(c, "floor_from", null) == null:
			out.append("%s: needs floor_from (int)" % n)
		if not (n in [BASE, SHAFT, ROOF, PROXY] or n.begins_with(SHAFT + "_") or n.begins_with("Floor") \
				or n.begins_with("Walls") or n.begins_with("Interior") or n == "CityBuilding" or n == "Cutaway"):
			out.append("%s: unknown piece name" % n)
		for gi in BuildingCutaway._geometries(c):
			if gi is MeshInstance3D and (gi as MeshInstance3D).mesh != null:
				top = maxf(top, ((c as Node3D).transform * (gi as MeshInstance3D).get_aabb()).end.y)
	if strict and top > 12.0 and piece(p_root, PROXY) == null:
		out.append("taller than 12 m (%.0f m) without %s" % [top, PROXY])
	return out
