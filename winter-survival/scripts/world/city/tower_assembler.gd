class_name TowerAssembler
extends RefCounted
## Tower assembler (C0, PLAN C26 amendment to C8; doc 09 §4.5 step 3): a city tower is stacked from pieces that are
## already merged — never assembled from modules at run time:
##   Podium  (contract `Base`: the model's lower floors 0–3, lobby and shop fronts)
##   N × FloorGroup (contract `Shaft_<n>`: groups of 4 floors, their own MeshInstance3D so the frustum drops the high
##           ones; the extra groups repeat the model's last full group, its vertices moved up by 4 floors per copy)
##   Crown   (contract `Roof`: the model's partial top group + roof floor + crown, moved up by the extra groups)
##   ShadowProxy (the model's proxy with its upper vertices raised to the new roof: the only shadow caster)
## Pieces keep their node at y = 0 (city contract, ARQ v2 §9.7: the shader reads the building base from the model
## matrix), so the stacked copies are vertex-shifted meshes, cached per (family, groups): a lot file with 5 towers
## builds 5 variants once. The A1 families come from assets/models/city/towers/tower_<a…e>.glb (Base / Shaft_<n> /
## Roof / ShadowProxy). Without that art (the Web build excludes the city models) the tower is a procedural
## cut-ready building of the family's size and floors (CityProcedural.building). Main thread only (prepare / build);
## the results are shared, read-only meshes.

const PIECE_BASE := "Base"
const PIECE_ROOF := "Roof"
const PIECE_PROXY := "ShadowProxy"

## (family|groups) -> {"pieces": [[name, Mesh, floor_from, floor_to], …], "floors", "height", "roof_z", "ground_h",
## "floor_h", "art": bool}
static var _cache: Dictionary = {}
static var _models: Dictionary = {}   # model id -> PackedScene (or null when missing)
static var stats: Dictionary = {"variants": 0, "usec": 0, "fallback": 0}


static func art_path(model: String) -> String:
	return "res://assets/models/city/%s.glb" % model


static func has_art(model: String) -> bool:
	if Assets.force_placeholders:
		return false
	return ResourceLoader.exists(art_path(model), "PackedScene")


## Assembled pieces of a tower lot (cached). `t` = a CityLots TOWER item (family, groups, floors, shift).
static func assembly(family: String, groups: int) -> Dictionary:
	var key := "%s|%d" % [family, groups]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var fam: Dictionary = CityLots.families().get(family, {})
	var res: Dictionary
	if not fam.is_empty() and has_art(str(fam["model"])):
		res = _from_art(fam, groups)
	else:
		res = _fallback(family, fam, groups)
		stats["fallback"] = int(stats["fallback"]) + 1
	_cache[key] = res
	stats["variants"] = int(stats["variants"]) + 1
	stats["usec"] = int(stats["usec"]) + Time.get_ticks_usec() - t0
	return res


static func _scene(model: String) -> PackedScene:
	if not _models.has(model):
		_models[model] = load(art_path(model)) as PackedScene if has_art(model) else null
	return _models[model]


static func _from_art(fam: Dictionary, groups: int) -> Dictionary:
	var root := _scene(str(fam["model"])).instantiate() as Node3D
	var full := int(fam["full_groups"])
	var top := int(fam["top_floors"])
	var fh := CityLots.cm(fam["floor_h"])
	var group_h := 4.0 * fh
	var extra := groups - full
	var shift := float(extra) * group_h
	var base_top := CityLots.cm(fam["base_top"])
	var pieces: Array = []
	var shafts := {}
	for c in root.get_children():
		if c is MeshInstance3D:
			var n := CityBuilding.canonical(String(c.name))
			if n.begins_with("Shaft_"):
				shafts[int(n.substr(6))] = (c as MeshInstance3D).mesh
	var base := root.get_node_or_null(PIECE_BASE) as MeshInstance3D
	var roof := root.get_node_or_null(PIECE_ROOF) as MeshInstance3D
	var proxy := root.get_node_or_null(PIECE_PROXY) as MeshInstance3D
	pieces.append([PIECE_BASE, base.mesh, 0, 3])
	var n_out := 0
	# the model's full groups, then the extra copies of its last full group (4 floors higher each)
	for i in full:
		pieces.append(["Shaft_%d" % n_out, shafts[i], 4 + 4 * i, 7 + 4 * i])
		n_out += 1
	for j in extra:
		var m: Mesh = shifted(shafts[full - 1], group_h * float(j + 1))
		pieces.append(["Shaft_%d" % n_out, m, 4 + 4 * (full + j), 7 + 4 * (full + j)])
		n_out += 1
	# the partial top group and the crown, moved up by the extra groups
	var f := 4 + 4 * groups
	if top > 0 and shafts.has(full):
		pieces.append(["Shaft_%d" % n_out, shifted(shafts[full], shift), f, f + top - 1])
		n_out += 1
	pieces.append([PIECE_ROOF, shifted(roof.mesh, shift), f + top, f + top])
	pieces.append([PIECE_PROXY, stretched(proxy.mesh, base_top, shift), -1, -1])
	var floors := f + top + 1
	var res := {"pieces": pieces, "floors": floors, "height": CityLots.cm(fam["height"]) + shift,
		"roof_z": CityLots.cm(fam["roof_z"]) + shift, "ground_h": float(root.get_meta("ground_h", CityLots.cm(fam["ground_h"]))),
		"floor_h": fh, "art": true, "window_cell": root.get_meta("window_cell", [2.4, fh])}
	root.free()
	return res


static func _fallback(family: String, fam: Dictionary, groups: int) -> Dictionary:
	var proxy: Array = fam.get("proxy", [1500, 1500])
	var gh := CityLots.cm(fam.get("ground_h", 430))
	var fh := CityLots.cm(fam.get("floor_h", 380))
	var floors := 4 + 4 * groups + int(fam.get("top_floors", 1)) + 1
	var b := CityProcedural.building(CityLots.cm(proxy[0]), CityLots.cm(proxy[1]), floors, gh, fh, str(fam.get("style", "glass")),
		family.hash() & 0xFFFF, 4)
	var pieces: Array = [[PIECE_BASE, b["Base"], 0, 3]]
	var i := 0
	for s in b["Shafts"]:
		pieces.append(["Shaft_%d" % i, s[2], int(s[0]), int(s[1])])
		i += 1
	pieces.append([PIECE_ROOF, b["Roof"], floors, floors])
	pieces.append([PIECE_PROXY, b["ShadowProxy"], -1, -1])
	return {"pieces": pieces, "floors": floors, "height": float(b["top"]), "roof_z": float(b["roof_level"]),
		"ground_h": gh, "floor_h": fh, "art": false, "window_cell": [2.4, fh]}


## A copy of `mesh` with every vertex moved up by dy (same surfaces and materials; LODs dropped). dy = 0: the mesh.
static func shifted(mesh: Mesh, dy: float) -> Mesh:
	if is_zero_approx(dy):
		return mesh
	return _remap(mesh, func(v: Vector3) -> Vector3: return v + Vector3(0, dy, 0))


## The shadow proxy stretched to the new roof: vertices above `split` rise by dy (the stacked prism keeps its shape).
static func stretched(mesh: Mesh, split: float, dy: float) -> Mesh:
	if is_zero_approx(dy):
		return mesh
	return _remap(mesh, func(v: Vector3) -> Vector3: return v + Vector3(0, dy, 0) if v.y > split + 0.01 else v)


static func _remap(mesh: Mesh, f: Callable) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for k in verts.size():
			verts[k] = f.call(verts[k])
		arr[Mesh.ARRAY_VERTEX] = verts
		# tangents / normals are unchanged by a vertical translation; keep only what the surface had
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(i))
		if mesh is ArrayMesh:
			out.surface_set_name(out.get_surface_count() - 1, (mesh as ArrayMesh).surface_get_name(i))
	return out


## A tower's scene root (not in the tree yet): the contract pieces + root metadata. `item` = CityLots TOWER item.
static func build(item: Dictionary) -> Node3D:
	var a := assembly(str(item["family"]), int(item["groups"]))
	var root := Node3D.new()
	root.name = "tower_%d" % int(item["id"])
	root.set_meta("floor_h", a["floor_h"])
	root.set_meta("ground_h", a["ground_h"])
	root.set_meta("foundation", 0.0)
	root.set_meta("floors", int(a["floors"]))
	root.set_meta("generator", bool(item.get("generator", false)))
	root.set_meta("enterable", false)
	root.set_meta("kind", "tower")
	root.set_meta("family", str(item["family"]))
	root.set_meta("wid", int(item["wid"]))
	for p in a["pieces"]:
		var mi := MeshInstance3D.new()
		mi.name = str(p[0])
		mi.mesh = p[1]
		if int(p[2]) >= 0 and str(p[0]).begins_with("Shaft_"):
			mi.set_meta("floor_from", int(p[2]))
			mi.set_meta("floor_to", int(p[3]))
		root.add_child(mi)
	return root


## Collider boxes of a tower (local space of its root): [[centre, size], …] — the lobby box (Base footprint up to
## the base's top) and the shaft box (proxy footprint up to the roof), from the lot file (the server has no art).
static func collider_boxes(item: Dictionary) -> Array:
	var fam: Dictionary = CityLots.families()[str(item["family"])]
	var base_sz := CityLots.v2(fam["base"])
	var proxy_sz := CityLots.v2(fam["proxy"])
	var base_top := CityLots.cm(fam["base_top"])
	var roof := CityLots.cm(fam["roof_z"]) + float(item["shift"])
	return [[Vector3(0, base_top * 0.5, 0), Vector3(base_sz.x, base_top, base_sz.y)],
		[Vector3(0, base_top + (roof - base_top) * 0.5, 0), Vector3(proxy_sz.x, roof - base_top, proxy_sz.y)]]


static func clear_cache() -> void:
	_cache.clear()
	_models.clear()
