extends RefCounted
## M6a screenshot presets (loaded by tests/screenshot_steps.gd): the test street of Santa María del Puerto (Calle
## Mayor, data/buildings/streets/calle_mayor.json) in the game world, built by KitStreets on its W1 pad.
##   street_day    11:00, the survivor on the road in front of the north 2-storey house (number 5) and the shop
##                 («Ultramarinos»); the south row (between the camera and the player) cut by the corte urbano
##   street_night  22:30, the same place, a campfire on the road
##   street_signs  10:30, the east entrance at the default 24 m zoom: the street name plate and the town entry sign
##                 (S-500, struck through on its back)
##   house_inside  16:00, the survivor inside the north 2-storey house (storey 0, living room): roof and storey 1
##                 hidden shadow-preserving by the CutawayManager, camera-facing facades cut to stubs, front door open
##   RENDER=forward tests/run_screenshots.sh docs/screenshots/m6a street_day street_night street_signs house_inside
## Camera yaw 45°: screen right = (+x, −z), toward the camera = (+x, +z). Street frame: x east along the road,
## z south; the north houses face +z.

const STREET := "calle_mayor"
const SPOTS := {
	"street_day": Vector3(2.0, 0.0, 1.0),
	"street_night": Vector3(2.0, 0.0, 1.0),
	"street_signs": Vector3(40.0, 0.0, -1.0),
	"house_inside": Vector3(3.0, 0.3, -12.1),
}
const ZOOMS := {"street_day": 30.0, "street_night": 27.0, "street_signs": 24.0, "house_inside": 24.0}
const HOURS := {"street_day": 11.0, "street_night": 22.5, "street_signs": 10.5, "house_inside": 16.0}

var tree: SceneTree


func setup(p_tree: SceneTree, preset: String, _game: Node, world: World, player: Player, inv: InventoryComponent) -> void:
	tree = p_tree
	WorldState.instance.set_time(1, float(HOURS.get(preset, 11.0)))
	world.get_node("WolfSpawner").enabled = false
	world.get_node("DeerSpawner").enabled = false
	if Director.instance != null:
		Director.instance.enabled = false
	if PopulationManager.instance != null:
		PopulationManager.instance.enabled = false
	if ZombieSystem.instance != null:
		ZombieSystem.instance.clear_all()
	var centre := KitStreets.centre_of(KitStreets.by_id(STREET))
	var base_y := world.get_height(centre.x, centre.z)
	var off: Vector3 = SPOTS.get(preset, SPOTS["street_day"])
	var pos := centre + Vector3(off.x, 0.0, off.z)
	world.streamer.ensure_loaded(pos, 2)
	pos.y = (base_y + off.y) if off.y > 0.0 else world.get_height(pos.x, pos.z) + 0.05
	_place(player, pos)
	# the street is built lot by lot (one per frame) once the chunk of its centre is loaded
	var st: KitStreet = null
	for i in 600:
		st = KitStreets.street(STREET)
		if st != null and st.done:
			break
		await tree.process_frame
	_place(player, pos)
	inv.add(&"hacha", 1)
	if preset == "street_night":
		inv.add(&"antorcha", 1)
		var p := centre + Vector3(-0.5, 0.0, -2.2)
		p.y = world.get_height(p.x, p.z)
		world.spawn_placed("campfire", p, 0.0)
	if preset == "house_inside" and st != null:
		var d := _front_door(st)
		if d != null:
			d.server_interact(player, &"open", 0)
	for i in 30:
		await tree.physics_frame
	var rig := CameraRig.active()
	if rig != null:
		rig.snap_to_player()
		rig.snap_profile()
		var z := float(ZOOMS.get(preset, 30.0))
		rig.dist = z
		rig.camera.position = Vector3(0, 0, z)
	for i in 20:
		await tree.process_frame
	var mgr := CutawayManager.instance
	if mgr != null:
		mgr.update()
	print("m6a shot %s: player %s, street built %s (%d buildings), inside %s floor %d, city buildings %d" % [preset,
		player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), st != null and st.done, st.buildings.size() if st != null else 0,
		mgr.inside if mgr != null else false, mgr.inside_floor if mgr != null else -1, CityCut.buildings().size()])


func _place(player: Player, pos: Vector3) -> void:
	player.position = pos
	player.net_position = pos
	player.velocity = Vector3.ZERO
	player.set("input_enabled", false)


## The front door (S facade) of the north 2-storey house (as tests/net/net_steps_m6a.gd).
func _front_door(st: KitStreet) -> KitDoor:
	for b in st.buildings:
		if b.template_id == "house_two_story_A" and b.style == "wood_blue":
			for d in b.doors:
				if d.exterior and str((d.leaf.get_meta("extras", {}) as Dictionary).get("cut_group", "")) == "Walls0_S":
					return d
	return null
