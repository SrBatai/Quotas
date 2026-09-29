class_name AmbientLife
extends Node3D
## G2b «vida» (PLAN v3.8.2 G2b, doc 08 §3.9): the render side of a lived-in winter, client only, deterministic (the
## same things in the same places on every client, 0 B/s) until V1 brings the server-driven layer:
##   * the C0 city block, read from the streamed city chunks' plans (CityChunk.plan, read only): rotating beacons on
##     some police cars and ambulances of the jam, amber flashers on the striped barriers, traffic lights left
##     flashing amber where there is power, smouldering burnt wrecks and the checkpoint braziers (SmokeColumn: a
##     lit plume, embers, a melted ring), the military tent's canvas flapping (world_vcol_cloth) and cables strung
##     across the Gran Vía between facing street lamps;
##   * circling crows (Flock) over the jam and over the clearing's dead trees, by day only, grounded in a blizzard.
## A chunk's things come and go with the chunk (polled every POLL s: the streaming code is not touched).

const POLL := 0.5
const POLICE := Color(0.25, 0.45, 1.0)
const POLICE_RED := Color(1.0, 0.18, 0.12)
const AMBER := Color(1.0, 0.62, 0.12)
## [centre (x, z), birds, radius, height, seed]: over the Gran Vía jam (C0) and the clearing's edge of the forest.
const FLOCKS := [[Vector2(2690.0, -388.0), 16, 18.0, 11.0, 7], [Vector2(-14.0, -12.0), 11, 16.0, 8.0, 3]]

var beacons: BeaconLights
var cables: HangingCables
var flocks: Array[Flock] = []
var smoke: Dictionary = {}          # chunk key -> Array[SmokeColumn]
var _chunks: Dictionary = {}        # chunk key -> true (processed)
var _t: float = 0.0
var _anchors: Dictionary = {}       # model -> {anchor name: Vector3}
static var _cloth_done: Dictionary = {}   # "model|variant" whose cached city mesh already wears the cloth material


func _ready() -> void:
	beacons = BeaconLights.new()
	beacons.name = "Beacons"
	add_child(beacons)
	cables = HangingCables.new()
	cables.name = "Cables"
	add_child(cables)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL
	_poll_chunks()
	_update_flocks()


# ------------------------------------------------------------------ city chunks
func _poll_chunks() -> void:
	var world := World.instance
	if world == null or not world.is_configured or world.streamer == null:
		return
	var alive := {}
	for k in world.streamer.chunks:
		var c: WorldChunk = world.streamer.chunks[k]
		if c == null or c.city == null or not c.city.is_done() or c.state != WorldChunk.State.LOADED:
			continue
		alive[k] = true
		if not _chunks.has(k):
			_chunks[k] = true
			_populate(int(k), c.city.plan, world)
	for k in _chunks.keys():
		if not alive.has(k):
			_chunks.erase(k)
			_release(int(k))


func _populate(key: int, plan: Dictionary, world: World) -> void:
	var lights: Array = []
	var cols: Array[SmokeColumn] = []
	var groups: Dictionary = plan.get("groups", {})
	for gk in plan.get("group_order", []):
		var g: Dictionary = groups.get(gk, {})
		var model := str(g.get("model", ""))
		var variant := str(g.get("variant", ""))
		var rows: PackedFloat32Array = g.get("rows", PackedFloat32Array())
		for i in rows.size() / 12:
			var o := i * 12
			var pos := Vector3(rows[o + 3], rows[o + 7], rows[o + 11])
			var yaw := atan2(rows[o + 2], rows[o])
			var basis := Basis(Vector3.UP, yaw)
			var h := WorldConst.hash64(int(round(pos.x * 10.0)), int(round(pos.z * 10.0)), 0x4C1FE)
			var u := WorldConst.unit(h)
			var burnt := variant.contains("burnt")
			match model:
				"police":
					if not burnt and u < 0.6:
						var b := pos + basis * _anchor(model, variant, "Beacon", Vector3(0, 1.55, -0.5))
						lights.append([b + basis * Vector3(0.28, 0, 0), pos.y, POLICE, BeaconLights.Mode.ROTATE, u])
						lights.append([b + basis * Vector3(-0.28, 0, 0), pos.y, POLICE_RED, BeaconLights.Mode.ROTATE, u + 0.5])
				"ambulance":
					if not burnt and u < 0.5:
						var b := pos + basis * Vector3(0.8, 2.66, 2.4)
						lights.append([b, pos.y, AMBER, BeaconLights.Mode.ROTATE, u])
						lights.append([pos + basis * Vector3(-0.8, 2.66, 2.4), pos.y, POLICE_RED, BeaconLights.Mode.ROTATE, u + 0.33])
				"barrier_striped":
					if u < 0.7:
						lights.append([pos + basis * Vector3(0.62, 1.2, 0.0), pos.y, AMBER, BeaconLights.Mode.BLINK, u])
				"traffic_light_arm":
					if CityLights.power_at(pos) > 0.5:
						for s in 3:
							var a := _anchor(model, variant, "Signal_%d" % s, Vector3.INF)
							if a != Vector3.INF:
								lights.append([pos + basis * a, pos.y, AMBER, BeaconLights.Mode.AMBER, u])
				"barrel":
					if u < 0.75 and cols.size() < 4:
						cols.append(_smoke_at(pos, 0.55, 0.35, 1.2))
				"mil_tent":
					_cloth_tent(variant)
			if burnt and u < 0.55 and cols.size() < 4:
				cols.append(_smoke_at(pos + Vector3(0, 0.6, 0), 1.0, 0.75, 2.4))
	if not lights.is_empty():
		beacons.put_set(key, lights)
	if not cols.is_empty():
		smoke[key] = cols
	var spans := _cable_spans()
	cables.put_set(0, spans)


## The military tent's canvas flutters (world_vcol_cloth): its shared MultiMesh mesh (CityChunk.group_mesh cache) gets
## the cloth material once, in place, so every tent of every chunk moves.
func _cloth_tent(variant: String) -> void:
	var key := "mil_tent|" + variant
	if _cloth_done.has(key):
		return
	_cloth_done[key] = true
	var mesh := CityChunk.group_mesh("mil_tent", variant, "props") as ArrayMesh
	if mesh == null:
		return
	var cloth := WindSway.material("cloth", CityLots.model_size("mil_tent").y)
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m != null and m.resource_name == "world_vcol_capsule":
			mesh.surface_set_material(i, cloth)


func _smoke_at(pos: Vector3, height: float, darkness: float, thaw_radius: float) -> SmokeColumn:
	var s := SmokeColumn.new()
	s.height = height
	s.darkness = darkness
	s.thaw_radius = thaw_radius
	s.name = "Smoke_%d_%d" % [int(pos.x), int(pos.z)]
	add_child(s)
	s.global_position = pos
	return s


func _release(key: int) -> void:
	beacons.remove_set(key)
	for s in smoke.get(key, []):
		if is_instance_valid(s):
			(s as Node).queue_free()
	smoke.erase(key)
	cables.put_set(0, _cable_spans())


## Cables across the street between facing lamps (CityLights' lamp list): a lamp and another 22–40 m away across
## the street (|Δx| or |Δz| < 2 m), every other pair, hung 0.6 m over the bulbs.
func _cable_spans() -> Array:
	var cl := CityLights.instance
	if cl == null:
		return []
	var out: Array = []
	var used := {}
	var lamps := cl.lamps
	for i in lamps.size():
		if used.has(i):
			continue
		var a: Vector3 = lamps[i]["pos"]
		for j in range(i + 1, lamps.size()):
			if used.has(j):
				continue
			var b: Vector3 = lamps[j]["pos"]
			var d := Vector2(b.x - a.x, b.z - a.z)
			var across := (absf(d.x) < 2.0 and absf(d.y) > 22.0 and absf(d.y) < 40.0) or (absf(d.y) < 2.0 and absf(d.x) > 22.0 and absf(d.x) < 40.0)
			if across and absf(a.y - b.y) < 1.5:
				used[i] = true
				used[j] = true
				if WorldConst.unit(WorldConst.hash64(int(a.x), int(a.z), 0xCAB1E)) < 0.5:
					out.append([a + Vector3(0, 0.6, 0), b + Vector3(0, 0.6, 0)])
				break
	return out


## Anchor of a city model (its glTF empties: police "Beacon", traffic light "Signal_n"), cached; fallback if absent.
func _anchor(model: String, variant: String, anchor: String, fallback: Vector3) -> Vector3:
	var key := model + "|" + variant
	if not _anchors.has(key):
		var found := {}
		var dir := "vehicles" if model in ["police", "ambulance"] else "props"
		for id in ["%s/%s_%s" % [dir, model, variant], "%s/%s" % [dir, model]]:
			var path := "res://assets/models/city/%s.glb" % id
			if ResourceLoader.exists(path):
				var root := (load(path) as PackedScene).instantiate()
				for c in root.get_children():
					if c is Node3D and not (c is MeshInstance3D):
						found[String(c.name)] = (c as Node3D).position
				root.free()
				break
		_anchors[key] = found
	return (_anchors[key] as Dictionary).get(anchor, fallback)


# ------------------------------------------------------------------ flocks
func _update_flocks() -> void:
	if flocks.is_empty():
		for f in FLOCKS:
			var fl := Flock.new()
			fl.birds = int(f[1])
			fl.radius = float(f[2])
			fl.height = float(f[3])
			fl.seed_value = int(f[4])
			fl.name = "Flock%d" % flocks.size()
			add_child(fl)
			flocks.append(fl)
	var world := World.instance
	var dn := get_parent().get_parent() as DayNight if get_parent() != null else null
	var blizzard := dn.blizzard_blend if dn != null else 0.0
	var day := DayNight.sun_elevation(WorldState.hour_now()) > -1.0 if WorldState.instance != null else true
	for i in flocks.size():
		var c: Vector2 = FLOCKS[i][0]
		var fl := flocks[i]
		var ground := world.get_height(c.x, c.y) if world != null and world.is_configured else 0.0
		fl.position = Vector3(c.x, ground, c.y)
		fl.visible = day and blizzard < 0.5
