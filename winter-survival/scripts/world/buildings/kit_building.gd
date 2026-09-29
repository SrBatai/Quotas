class_name KitBuilding
extends Node3D
## One building of the modular kit (M6a, ASSET_SPEC v2 §8 + "M6a", ARQ v2 §9.9): the cut-ready
## res://assets/models/buildings/<style>/<template>.glb (blender/kits, templates in data/buildings/templates/) with
## everything that makes it a place, built identically on the server and on every client (deterministic wids; only
## deltas travel):
##   * root metadata of the W0 city-building contract (floor_h 3.0, ground_h 3.3, foundation 0.3, floors, enterable,
##     kind) from the ShadowProxy extras; the ShadowProxy is SHADOWS_ONLY everywhere (it never draws);
##   * on clients with a display: CityBuilding.attach (the «corte urbano» struct / window_city materials, CityCut
##     registration, the ShadowProxy as the only caster, visibility ranges) and its BuildingCutaway put under the
##     CutawayManager (inside detection, roof and upper storeys SHADOWS_ONLY, camera-facing facades -> stubs);
##     headless: the stubs are hidden;
##   * KitDoor on every `Door_<n>` (server-authoritative open / close, replicated through the chunk delta);
##   * window boxes (a broken window is a later milestone: the panes block until then);
##   * loot containers from `Spawn_Container_<n>` / `Spawn_Loot_<n>` (LootSpawns.attach, the building's wid), each
##     moved under the Interior<k> of its storey so the cutaway hides it with its floor;
##   * diegetic signs on `Spawn_Sign_<n>` (house number / shop name; SignText boards, parented to their cut group);
##   * server: a Shelter area over the storeys (Player.in_house while inside, like the clearing cabin).
## Interior furniture is merged into Interior<k> by the art (cut-ready, one surface per storey); Spawn_Bed /
## Spawn_Stove / Spawn_Furniture stay as anchors for later interactions, Spawn_Zombie / Spawn_Light for M9.

const GEN_BUILDING := 0x424C4447     # "BLDG"

## Tests / benches: -1 = render stuff only on a client with a display (the game's rule), 1 = always (headless checks
## of the cutaway and the corte urbano materials), 0 = never.
static var render_override: int = -1
const ROOT_META := ["floors", "floor_h", "ground_h", "foundation", "kind", "enterable"]

var template_id: String = ""
var style: String = ""
var number: int = 0
var shop_name: String = ""
var seed_v: int = 0
var model: Node3D
var city: CityBuilding
var doors: Array[KitDoor] = []
var containers: int = 0
var floors: int = 1
var built: bool = false
## M6b (settlements): {"use", "locked" (exterior doors locked: a non-enterable house), "alarm" (exterior doors may
## ring: KitDoor.alarm_roll), "tables" (loot tables by use: LootSpawns.attach remap)}. Set before entering the tree.
var opts: Dictionary = {}


static func wid_for(p_seed: int, street_id: String, index: int) -> int:
	return WorldConst.hash64(p_seed, GEN_BUILDING, street_id.hash(), index + 1)


static func visual() -> bool:
	if render_override >= 0:
		return render_override == 1
	return Net.has_client and DisplayServer.get_name() != "headless"


static func model_name(p_template: String, p_style: String) -> String:
	return "buildings/%s/%s" % [p_style, p_template]


## Called before the node enters the tree.
func setup(p_template: String, p_style: String, p_wid: int, p_seed: int, p_number: int = 0, p_shop: String = "") -> void:
	template_id = p_template
	style = p_style
	seed_v = p_seed
	number = p_number
	shop_name = p_shop
	set_meta("wid", p_wid)
	name = "Bldg_%s_%x" % [p_template, p_wid & 0xFFFFFF]


func _ready() -> void:
	add_to_group("kit_building")
	build()


func build() -> void:
	if built:
		return
	built = true
	model = Assets.spawn_model(model_name(template_id, style))
	model.name = "Model"
	add_child(model)
	var proxy := model.get_node_or_null("ShadowProxy") as GeometryInstance3D
	if proxy != null:
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var ex: Dictionary = proxy.get_meta("extras", {})
		for k in ROOT_META:
			if ex.has(k):
				model.set_meta(k, ex[k])
		floors = int(ex.get("floors", 1))
	var wid := int(get_meta("wid", 0))
	_doors(wid)
	_windows()
	var display := visual()
	if display:
		city = CityBuilding.attach(model)
		if city.cutaway != null:
			CutawayManager.register(city.cutaway)
	else:
		for c in model.get_children():
			if String(c.name).ends_with("_Stub"):
				(c as Node3D).visible = false
	_loot(wid)
	_signs()
	if Net.is_server:
		_shelter()


func _doors(wid: int) -> void:
	var leaves: Array[Node3D] = []
	for c in model.get_children():
		if String(c.name).begins_with("Door_") and c is Node3D:
			leaves.append(c as Node3D)
	leaves.sort_custom(func(a: Node3D, b: Node3D) -> bool: return int(String(a.name).substr(5)) < int(String(b.name).substr(5)))
	for i in leaves.size():
		var d := KitDoor.new()
		d.setup(leaves[i], KitDoor.wid_for(seed_v, wid, i))
		if d.exterior and bool(opts.get("locked", false)):
			d.locked = true
		if d.exterior and bool(opts.get("alarm", false)):
			d.alarm_armed = KitDoor.alarm_roll(int(d.get_meta("wid", 0)))
		model.add_child(d)
		doors.append(d)


## One static body with a box per pane (Window_<n>, thickened to the wall), layer 1.
func _windows() -> void:
	var body := StaticBody3D.new()
	body.name = "WindowBoxes"
	body.collision_layer = 1
	body.collision_mask = 0
	for c in model.get_children():
		if String(c.name).begins_with("Window_") and c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var bb := (c as MeshInstance3D).transform * (c as MeshInstance3D).get_aabb()
			var cs := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(maxf(bb.size.x, 0.2), bb.size.y, maxf(bb.size.z, 0.2))
			cs.shape = box
			cs.position = bb.get_center()
			body.add_child(cs)
	if body.get_child_count() > 0:
		model.add_child(body)
	else:
		body.free()


## Loot containers of the spawns (LootSpawns: same wids on every peer), each under the Interior<k> of its storey.
func _loot(wid: int) -> void:
	var before := get_child_count()
	containers = LootSpawns.attach(self, model, wid, seed_v, opts.get("tables", {}))
	var made: Array[Node] = []
	for i in range(before, get_child_count()):
		made.append(get_child(i))
	for c in made:
		if not (c is Node3D):
			continue
		var k := clampi(int(floor(((c as Node3D).position.y - 0.3 + 0.5) / 3.0)), 0, floors - 1)
		var interior := model.get_node_or_null("Interior%d" % k)
		if interior != null:
			c.reparent(interior, true)
			# M6b fix: leaving the tree on the reparent dropped its wid from the registry (WorldRegistry.register
			# erases on tree_exited): the server then refused to open it («no_existe»)
			WorldRegistry.register(c)


## Signs of the Spawn_Sign_<n> anchors: house number / shop name boards, parented to their cut group.
func _signs() -> void:
	for c in model.get_children():
		if not String(c.name).begins_with("Spawn_Sign_"):
			continue
		var ex: Dictionary = c.get_meta("extras", {})
		var kind := str(ex.get("sign", "number"))
		var text := ""
		var board := ""
		match kind:
			"number":
				if number <= 0:
					continue
				text = str(number)
				board = "signs/sign_house_number"
			"shop":
				text = shop_name if shop_name != "" else "TIENDA"
				board = "signs/sign_shop"
			_:
				continue
		var group := model.get_node_or_null(str(ex.get("cut_group", ""))) as Node3D
		var parent: Node3D = group if group != null else model
		var xf := parent.global_transform.affine_inverse() * (c as Node3D).global_transform if parent.is_inside_tree() \
			else (c as Node3D).transform
		SignText.place(parent, board, xf, text, "", float(ex.get("cap", 0.0)))


## Server: Player.in_house while a player's body is inside the storeys (the clearing cabin's rule: noise / 2, no
## night flash, wolves give up, HUD climate). Counts overlapping shelters.
func _shelter() -> void:
	var proxy := model.get_node_or_null("ShadowProxy") as MeshInstance3D
	if proxy == null or proxy.mesh == null:
		return
	var bb := proxy.get_aabb()
	var top := 0.3 + 3.0 * float(floors)
	var area := Area3D.new()
	area.name = "Shelter"
	area.collision_layer = 32
	area.collision_mask = 2
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(bb.size.x - 0.3, top - 0.2, bb.size.z - 0.3)
	cs.shape = box
	cs.position = Vector3(bb.get_center().x, 0.2 + (top - 0.2) * 0.5, bb.get_center().z)
	area.add_child(cs)
	model.add_child(area)
	area.body_entered.connect(func(b: Node) -> void: _shelter_count(b, 1))
	area.body_exited.connect(func(b: Node) -> void: _shelter_count(b, -1))


static func _shelter_count(body: Node, d: int) -> void:
	if not (body is Player):
		return
	var n := maxi(0, int(body.get_meta("_kit_shelters", 0)) + d)
	body.set_meta("_kit_shelters", n)
	(body as Player).in_house = n > 0


## Storey of a world point inside this building (-1 outside): the cutaway's rule when there is one, else the box.
func floor_at(p_world: Vector3) -> int:
	if city != null and city.cutaway != null:
		return city.cutaway.floor_at(p_world)
	var proxy := model.get_node_or_null("ShadowProxy") as MeshInstance3D if model != null else null
	if proxy == null:
		return -1
	var p := model.global_transform.affine_inverse() * p_world
	var bb := proxy.get_aabb()
	if p.x < bb.position.x or p.x > bb.end.x or p.z < bb.position.z or p.z > bb.end.z or p.y < -0.3:
		return -1
	var k := int(floor((p.y - 0.3 + 0.6) / 3.0))
	return k if k < floors else -1
