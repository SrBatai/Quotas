class_name CityWorld
extends Node3D
## World-level part of the city (C0): what is not streamed per chunk. Added by World.configure once CityLots loads.
##   * camera zones of the lot file (client): the `city` profile over the block, `rooftop` on its roofs;
##   * the provisional miradores (client with a display);
##   * the power of the city v0 (CityLights): grid off, the generator lots and the military control powered;
##   * the district silhouettes v0 (visual clients and the menu), built off the main thread, shown only by a
##     mirador (set_skyline) and by the main-menu backdrop;
##   * the main-menu backdrop (decorative world): the night skyline of Altavega seen from the east end of the
##     Puente de Hierro, a mirador of v2.0 (PLAN v3.4 item 4).

## Main menu: the decorative world streams around this point and the camera looks at the skyline from here.
const MENU_FOCUS := Vector3(2585.0, 0.0, -405.0)
const MENU_CAMERA := Vector3(2338.0, 21.0, -330.0)
const MENU_TARGET := Vector3(2700.0, 58.0, -470.0)
const MENU_HOUR := 21.6
const MENU_FOV := 44.0
const MENU_FOG := 0.08
## Menu: a few districts still on generators (the skyline reads by its lit windows); a dark night fog.
const MENU_GRID := 0.22
const NIGHT_FOG := Color("#162033")
## Metres around a generator lot whose street lamps it powers.
const GENERATOR_REACH := 14.0

static var instance: CityWorld
## C1: miradores used by the local player (id -> {"pos": Vector3, "radius": m, "name"}): the map reveal H5 reads.
static var revealed: Dictionary = {}

signal mirador_used(id: int, pos: Vector3, reveal_radius: float)

var world: World
var hf: HeightFunction
var silhouettes: CitySilhouettes
var miradores: Array[Mirador] = []
var zones: Array[CameraZone] = []
var menu_camera: Camera3D
var skyline_on: bool = false


## C1: detached subtrees waiting to be freed a little per frame (a hero tower's ~900 nodes in one teardown step
## are 5–10 ms; `defer_free` takes them out of the tree at once and frees them for ≤ FREE_USEC per frame).
const FREE_USEC := 700
var _graveyard: Array[Node] = []


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	for n in _graveyard:
		if is_instance_valid(n):
			n.free()
	_graveyard.clear()


## Frees `n` (already out of the tree) over the next frames: its children first, a few per frame. Without a
## CityWorld it is freed now.
static func defer_free(n: Node) -> void:
	if instance == null or not is_instance_valid(instance):
		n.free()
		return
	instance._graveyard.append(n)
	instance.set_process(true)


func _process(_delta: float) -> void:
	if _graveyard.is_empty():
		set_process(false)
		return
	var t0 := Time.get_ticks_usec()
	while not _graveyard.is_empty() and Time.get_ticks_usec() - t0 < FREE_USEC:
		var n: Node = _graveyard[_graveyard.size() - 1]
		if not is_instance_valid(n):
			_graveyard.pop_back()
			continue
		var k := n.get_child_count()
		if k > 0:
			var c := n.get_child(k - 1)
			n.remove_child(c)
			if c.get_child_count() > 8:
				_graveyard.append(c)   # a big child (a collider body with its shapes): its own children first
			else:
				c.free()
			continue
		_graveyard.pop_back()
		n.free()


## `visual`: the client renders (silhouettes, lights); `display`: a real window (miradores, camera zones);
## `menu`: the decorative world of the main menu.
func setup(p_world: World, p_hf: HeightFunction, visual: bool, display: bool, menu: bool) -> void:
	world = p_world
	hf = p_hf
	name = "CityWorld"
	if display and not menu:
		for z in CityLots.camera_zones():
			var r := CityLots.rect_of(z["rect"])
			var cz := CityCameraZone.new()
			cz.hf = hf
			cz.name = "CityZone_%d" % int(z["id"])
			cz.profile = StringName(str(z.get("profile", "city")))
			cz.size = Vector3(r.size.x, 800.0, r.size.y)
			cz.priority = int(z.get("priority", 0))
			cz.rooftop_height = CityLots.cm(z.get("rooftop_h", 700))
			add_child(cz)
			var c := r.get_center()
			cz.global_position = Vector3(c.x, hf.height_at(c.x, c.y), c.y)
			zones.append(cz)
		for m in CityLots.miradores():
			var mir := Mirador.new()
			mir.setup(m)
			add_child(mir)
			mir.global_position = mirador_point(hf, m)
			mir.used.connect(_on_mirador_used)
			miradores.append(mir)
		# C1: the arrival cinematic, the first time the local player crosses the Puente de Hierro
		var cine := ArrivalCinematic.new()
		cine.name = "ArrivalCinematic"
		add_child(cine)
		cine.setup(self)
	if Net.is_server and not menu:
		# C1: the floors of the hero towers — lazy navigation tiles + stair links, and their population
		var cn := CityNav.new()
		add_child(cn)
		cn.setup(world)
		var cp := CityPopulation.new()
		add_child(cp)
		cp.setup(world)
	if visual and not menu and Net.has_client:
		# C1: frozen statues (MultiMesh) and the zombies trapped in the jam cars
		var fs := FrozenStatues.new()
		add_child(fs)
	if visual:
		apply_power()
		silhouettes = CitySilhouettes.new()
		silhouettes.name = "DistrictSilhouettes"
		add_child(silhouettes)
		if menu:
			silhouettes.build_now(hf)
		elif WorldStreamer.threads_ok():
			silhouettes.build_async(hf)
		# without worker threads (Web) the silhouettes are built when a mirador first asks for them (set_skyline)
		silhouettes.visible = false


## World point of a mirador record: on a podium roof (`on`, C0), a hero tower's roof (`hero`), the bridge deck
## (`at` deck), a valley POI's platform (`poi`: `h` m over the ground) or the ground (`at` ground).
static func mirador_point(p_hf: HeightFunction, m: Dictionary) -> Vector3:
	var p := CityLots.v2(m["pos"])
	if m.has("on"):
		var pod := CityLots.podium(int(m["on"]))
		return Vector3(p.x, CityLots.podium_base(p_hf, int(m["on"])) + CityLots.podium_roof(pod), p.y)
	if m.has("hero"):
		var h := CityLots.hero(int(m["hero"]))
		var y := CityLots.hero_base(p_hf, int(m["hero"])) + HeroTower.level(int(h["floors"]), CityLots.cm(h.get("ground_h", 430)), CityLots.cm(h.get("floor_h", 380)))
		return Vector3(p.x, y, p.y)
	match str(m.get("at", "ground")):
		"deck":
			var d := CityLots.bridge_deck(p_hf, p.x, p.y)
			return Vector3(p.x, (d if not is_nan(d) else p_hf.height_at(p.x, p.y)), p.y)
		"poi":
			return Vector3(p.x, p_hf.height_at(p.x, p.y) + CityLots.cm(m.get("h", 0)), p.y)
	return Vector3(p.x, p_hf.height_at(p.x, p.y), p.y)


func _on_mirador_used(m: Mirador) -> void:
	var id := int(m.rec.get("id", 0))
	var r := CityLots.cm(m.rec.get("reveal", 60000))
	revealed[id] = {"pos": m.global_position, "radius": r, "name": str(m.rec.get("name", ""))}
	mirador_used.emit(id, m.global_position, r)


## City power (CityLights): the grid level of the lot file (0 = blackout) everywhere, 1 on the generator lots
## (their windows light up at night; C1: the generated lots flagged `generator` too) and in the listed rects (the
## military controls' generators).
func apply_power() -> void:
	var pw := CityLots.power()
	CityLights.set_grid_power(float(pw.get("grid", 0.0)))
	if not pw.has("map"):
		return
	var r := CityLots.rect_of(pw["map"])
	CityLights.create_power_map(r.position.x, r.position.y, r.size.x, r.size.y, CityLots.cm(pw.get("cell", 400)), float(pw.get("grid", 0.0)))
	var gens := {}
	for g in pw.get("generators", []):
		gens[int(g)] = true  # JSON numbers parse as floats
	for id in gens:
		var b := CityLots.building(int(id))
		if not b.is_empty():
			_paint_lot(b["pos"], (b["size"] as Vector2) + Vector2(4, 4), float(b["yaw"]))
	for p in CityLots.podiums():
		if gens.has(int(p["id"])):
			# the lot's generator also feeds the street lamps along its podium (GENERATOR_REACH m around it)
			_paint_lot(CityLots.v2(p["pos"]), CityLots.v2(p["size"]) + Vector2(GENERATOR_REACH, GENERATOR_REACH) * 2.0, float(p.get("yaw", 0.0)))
	for t in CityLots.towers():
		if gens.has(int(t["id"])):
			var fam: Dictionary = CityLots.families()[str(t["family"])]
			_paint_lot(CityLots.v2(t["pos"]), CityLots.v2(fam["base"]) + Vector2(2, 2), float(t.get("yaw", 0.0)))
	for rr in pw.get("rects", []):
		var q := CityLots.rect_of(rr)
		CityLights.paint_power(q.position.x, q.position.y, q.end.x, q.end.y, 1.0)


func _paint_lot(c: Vector2, size: Vector2, yaw_deg: float) -> void:
	var b := CityLots._obb_bounds(c, size, yaw_deg)
	CityLights.paint_power(b.position.x, b.position.y, b.end.x, b.end.y, 1.0)


## The skyline layer (district silhouettes + far terrain) on / off: miradores and the menu.
func set_skyline(on: bool) -> void:
	skyline_on = on
	if silhouettes != null:
		if on and not silhouettes.is_built and silhouettes.hf == null:
			silhouettes.build_now(hf)
		silhouettes.visible = on


# ------------------------------------------------------------------ main menu backdrop
## Decorative world: night, thin fog, the skyline layer on and a fixed camera on the Puente de Hierro looking
## east-north-east over the jam at Las Torres (the C0 block streamed around MENU_FOCUS, the rest silhouettes).
func setup_menu() -> void:
	set_skyline(true)
	var dn := world.get_node_or_null("DayNight") as DayNight
	if dn != null:
		dn.menu_hour = MENU_HOUR
		dn.fog_density_scale = MENU_FOG
		dn.fog_color_override = NIGHT_FOG
		dn.apply(MENU_HOUR)
	CityLights.set_grid_power(MENU_GRID)
	menu_camera = Camera3D.new()
	menu_camera.name = "SkylineCamera"
	menu_camera.fov = MENU_FOV
	menu_camera.near = 0.5
	menu_camera.far = 2200.0
	world.add_child(menu_camera)
	var cam := MENU_CAMERA
	cam.y = maxf(cam.y, hf.height_at(cam.x, cam.z) + 12.0)
	menu_camera.global_position = cam
	menu_camera.look_at(MENU_TARGET, Vector3.UP)
	menu_camera.current = true
