extends Node3D
## M6a street bench (tests only, never exported): the test street of Santa María del Puerto (KitStreet from
## res://data/buildings/streets/calle_mayor.json — the same builder the world uses) on a snowy ground with the game's
## rendering stack: DayNight keys, the «corte urbano» (CityCut + the kit buildings as CityBuildings), Silhouettes,
## the CutawayManager (inside / storeys / stubs, shadow-preserving), CameraRig (default profile, yaw 45°), plus the
## M3 forest POI cabin_small attached through CutawayManager.attach (as world_chunk does). `measure_mode` swaps the
## characters to flat key colours for the visibility gate (like tests/city_bench).
## Street frame: x along the street (east), z across it (south = +z); the centre of the road is the origin; north
## houses face +Z (toward the camera at yaw 45°), south houses face -Z, so the south row stands between the default
## camera and a player in the street.

const KEY_PLAYER := Color(0, 1, 0)
const KEY_ZOMBIE := Color(1, 0, 0)
const SEED := 20260927
## Player positions of the views (street frame); inside views: y = the storey's floor.
const VIEWS := {
	"street": Vector3(2.0, 0.0, 1.0),        # on the road, the south row (2-storey, house A) between camera and player
	"backyard": Vector3(3.0, 0.0, -21.5),    # behind the north 2-storey house
	"gap": Vector3(-18.8, 0.0, -15.0),       # between the north house A and the shop
	"inside0": Vector3(3.0, 0.3, -12.1),     # north 2-storey house, storey 0 (living room, template (3.0, 3.4))
	"inside1": Vector3(2.0, 3.3, -13.7),     # same house, storey 1 (landing, template (2.0, 5.0))
	"apartment2": Vector3(17.0, 6.3, -9.7),  # the apartment block, storey 2 (3rd floor, living room)
	"south_inside": Vector3(-5.0, 0.3, 12.1),# south 2-storey house (yaw 180), storey 0 (living room)
	"cabin": Vector3(60.0, 0.5, -30.0),      # inside the cabin_small POI
}
const CABIN_POS := Vector3(60.0, 0.0, -30.0)
## The probe counts the zombies around the player (the danger zone the corte urbano must keep readable); zombies
## further away behind a building beyond the player are neither cut (the cut is on the camera side) nor perceived
## (no line of sight: no silhouette), like in the W0 city bench.
const ZOMBIE_RADIUS := 14.0

var street: KitStreet
var cabin_host: Node3D
var cabin_model: Node3D
var player: Node3D
var player_visual: Node3D
var zombies: Array[Node3D] = []
var rig: CameraRig
var cut: CityCut
var sil: Silhouettes
var lights: CityLights
var day_night: DayNight
var sun: DirectionalLight3D
var env: WorldEnvironment
var mgr: CutawayManager
var measure_mode: bool = false
var _key_mats: Dictionary = {}


func build(p_measure: bool = false) -> void:
	measure_mode = p_measure
	_environment()
	_ground()
	_street()
	_cabin()
	_characters()
	_camera()


func _environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	add_child(sun)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	add_child(moon)
	env = WorldEnvironment.new()
	env.name = "Env"
	add_child(env)
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.menu_hour = 11.0
	add_child(day_night)
	lights = CityLights.new()
	lights.name = "CityLights"
	add_child(lights)
	cut = CityCut.new()
	cut.name = "CityCut"
	add_child(cut)
	sil = Silhouettes.new()
	sil.name = "Silhouettes"
	add_child(sil)
	mgr = CutawayManager.new()
	mgr.name = "CutawayManager"
	add_child(mgr)


## Flat day look for the visibility gate: no fog, linear tonemap, no glow.
func flat_environment() -> void:
	day_night.set_process(false)
	var e := env.environment
	e.fog_enabled = false
	e.glow_enabled = false
	e.ssao_enabled = false
	e.volumetric_fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.adjustment_enabled = false


func _ground() -> void:
	var size := 320.0
	var step := 4.0
	var n := int(size / step)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
	var h0 := -size * 0.5
	for iz in n:
		for ix in n:
			var x0 := h0 + ix * step
			var z0 := h0 + iz * step
			var q := [Vector3(x0, 0, z0), Vector3(x0 + step, 0, z0), Vector3(x0 + step, 0, z0 + step), Vector3(x0, 0, z0 + step)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_color(Color(1, 1, 1, 1))
				st.set_normal(Vector3.UP)
				st.set_custom(0, Color(0, 0, 0, 0))
				st.add_vertex(q[idx])
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	mi.material_override = Assets.get_terrain_material()
	add_child(mi)


func _street() -> void:
	street = KitStreet.new()
	street.setup(KitStreets.by_id("calle_mayor"), SEED, 0.0)
	street.position = Vector3.ZERO
	add_child(street)
	street.build_all()


func _cabin() -> void:
	cabin_host = Node3D.new()
	cabin_host.name = "poi_cabin_small"
	cabin_host.position = CABIN_POS
	add_child(cabin_host)
	cabin_model = Assets.spawn_model("cabin_small")
	cabin_host.add_child(cabin_model)
	CutawayManager.attach(cabin_host, cabin_model)


func _characters() -> void:
	player = Node3D.new()
	player.name = "BenchPlayer"
	player.set_script(load("res://tests/city_bench/bench_player.gd"))
	add_child(player)
	player.global_position = VIEWS["street"]
	if measure_mode:
		player_visual = _key_capsule(KEY_PLAYER)
		player.add_child(player_visual)
	else:
		var cv := (load("res://scenes/player/character_visual.tscn") as PackedScene).instantiate() as CharacterVisual
		cv.name = "Visual"
		player.add_child(cv)
		cv.setup(0)
		cv.rotation.y = PI * 0.75
		player_visual = cv
	cut.player_override = player
	mgr.player_override = player
	sil.extra.append({"root": player_visual, "kind": "player", "variant": 0})
	# the street, the yards and the gaps between the houses
	var spots := [Vector2(-4.0, 2.2), Vector2(7.5, -1.5), Vector2(-9.0, -2.0), Vector2(12.0, 2.6), Vector2(0.5, -3.0),
		Vector2(-15.0, 1.5), Vector2(16.0, -2.4), Vector2(5.0, 4.2), Vector2(-2.0, -21.0), Vector2(8.5, -23.0),
		Vector2(0.0, -25.5), Vector2(-19.5, -19.0), Vector2(-17.5, -10.5), Vector2(10.5, -17.0)]
	for i in spots.size():
		var z: Node3D
		if measure_mode:
			z = Node3D.new()
			z.add_child(_key_capsule(KEY_ZOMBIE))
		else:
			z = ZombieView.new()
		z.name = "Zombie%d" % i
		add_child(z)
		if z is ZombieView:
			(z as ZombieView).setup(ZombieKinds.Kind.WALKER, i)
			(z as ZombieView).set_motion(ZombieKinds.State.IDLE, 0.0, false)
		var s: Vector2 = spots[i]
		z.position = Vector3(s.x, 0.0, s.y)
		z.rotation.y = float(i) * 1.3
		zombies.append(z)
		sil.extra.append({"root": (z as ZombieView).model if z is ZombieView else z, "kind": "zombie"})


func _key_capsule(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = 1.8
	mi.mesh = cap
	mi.position = Vector3(0, 0.9, 0)
	var key := col.to_html()
	if not _key_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
		m.disable_fog = true
		_key_mats[key] = m
	mi.material_override = _key_mats[key]
	return mi


func _camera() -> void:
	rig = (load("res://tests/city_bench/bench_rig.tscn") as PackedScene).instantiate() as CameraRig
	player.add_child(rig)
	rig.snap_to_player()


## Puts the player at a view, sets zoom / profile, snaps the rig onto its follow target (deterministic camera) and
## re-evaluates the cut and the cutaway.
func set_view(view: String, dist: float, profile: StringName = &"default") -> void:
	player.global_position = VIEWS.get(view, VIEWS["street"])
	rig.profile_override = profile
	rig.snap_profile()
	rig.dist = dist
	rig.camera.position = Vector3(0, 0, dist)
	rig.snap_to_player()
	var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, rig.pivot.rotation.y)
	rig.global_position = player.global_position + fwd * Balance.CAMERA_FORWARD_OFFSET
	rig._process(0.0)
	rig.snap_profile()
	cut.update(1.0)
	mgr.update()
	if measure_mode:
		for z in zombies:
			var d := Vector2(z.global_position.x - player.global_position.x, z.global_position.z - player.global_position.z)
			z.visible = d.length() <= ZOMBIE_RADIUS


func set_hour(h: float) -> void:
	day_night.menu_hour = h
	day_night.apply(h)


## Reference frame for the gate: the street (buildings, signs, road) and the POI hidden.
func set_occluders_visible(v: bool) -> void:
	street.visible = v
	cabin_host.visible = v


func building(template: String, style: String) -> KitBuilding:
	for b in street.buildings:
		if b.template_id == template and b.style == style:
			return b
	return null


const ANIM_STEP := 1.0 / 30.0


func _process(_delta: float) -> void:
	for z in zombies:
		if z is ZombieView:
			(z as ZombieView).advance(ANIM_STEP)
	if player_visual is CharacterVisual:
		(player_visual as CharacterVisual).set_motion(0.0, false, false, false, false)
		(player_visual as CharacterVisual).advance(ANIM_STEP)
