class_name KitDoor
extends StaticBody3D
## A door of a kit building (M6a, ARQ v2 §9.2 first step): wraps the building model's `Door_<n>` leaf (ASSET_SPEC v2
## §8.4: origin on the hinge axis at the building base, extras kind / exterior / hinge / width / cut_group / floor).
## Built identically on the server and every client with a deterministic wid (hash64 of the seed, GEN_DOOR, the
## building's wid and the door index), so nothing is spawned over the network: only its delta travels.
## Server-authoritative: a click sends NetWorld.request_interact(wid, &"use") (or &"open" / &"close"); the server
## validates it (distance, rate limit), toggles, stores {"open": bool, "swing": ±1} in the chunk delta
## (NetWorld.set_delta: persisted with the chunk, broadcast to the peers that follow it, restored for late joiners
## and after a reload / restart) and makes a 6 m noise (SoundEvents, indoors). Clients animate the leaf and its box
## (0.35 s). Exterior doors always swing into the building; interior doors swing away from whoever opens them.
## The collision box follows the leaf (a closed door blocks, an open one stands against the wall). M6b: `locked`
## (the exterior doors of a non-enterable village house: the server refuses to open them; «Cerrada con llave») and
## the shop alarm (`alarm_armed`: 5 % of the exterior doors of shops / the gas station, GDD §6.3 / §9.2): the first
## time one opens, the server stores {"alarm": true} in the delta (it never rings twice) and emits an ALARM noise of
## 150 m every ALARM_PERIOD s for 60 s; every peer that sees it live plays the alarm. Not yet: forcing / breaking by
## zombies and the NavigationLink3D (ARQ v2 §9.2, M9).

const GEN_DOOR := 0x444F4F52      # "DOOR"
const OPEN_DEG := 100.0
const SWING_SECONDS := 0.35
const NOISE := 6.0
## M6b: shop alarm (GDD §6.3: «alarma de tienda 150 (60 s), 5 % al forzar tienda»).
const ALARM_CHANCE := 0.05
const ALARM_SECONDS := 60.0
const ALARM_RADIUS := 150.0
const ALARM_PERIOD := 2.5
const GEN_ALARM := 0x414C524D     # "ALRM"
## Tests: 1 = every alarm-capable door is armed, 0 = none, -1 = the 5 % roll.
static var force_alarm: int = -1

var leaf: Node3D
var is_open: bool = false
var swing: int = 1
var exterior: bool = true
var outward := Vector3.BACK       # model space: the facade's outward normal (exterior doors)
var width: float = 1.0
var interactable: InteractableComponent
var locked: bool = false
var alarm_armed: bool = false
var alarm_fired: bool = false
## Seconds of alarm still to ring on this peer (server: noise; clients: sound).
var alarm_left: float = 0.0
var _alarm_t: float = 0.0
## Tests / stats.
var toggles: int = 0
var _angle: float = 0.0           # current (animated) angle, radians
var _leaf_xf := Transform3D()
var _centre := Vector3.ZERO       # leaf centre relative to the hinge (model space, closed)


static func wid_for(seed_v: int, building_wid: int, index: int) -> int:
	return WorldConst.hash64(seed_v, GEN_DOOR, building_wid, index + 1)


## True for the alarm-capable doors that are armed (5 % by the door's wid, or the test override).
static func alarm_roll(door_wid: int) -> bool:
	if force_alarm >= 0:
		return force_alarm == 1
	return WorldConst.unit(WorldConst.hash64(door_wid, GEN_ALARM)) < ALARM_CHANCE


## Called before the node enters the tree (child of the building model root, next to the leaf).
func setup(p_leaf: Node3D, p_wid: int) -> void:
	leaf = p_leaf
	name = "KitDoor_%s" % String(p_leaf.name).trim_prefix("Door_")
	set_meta("wid", p_wid)
	_leaf_xf = leaf.transform
	transform = Transform3D(Basis.IDENTITY, leaf.position)
	var ex: Dictionary = leaf.get_meta("extras", {}) if leaf.has_meta("extras") else {}
	exterior = bool(ex.get("exterior", true))
	width = float(ex.get("width", 1.0))
	var g := str(ex.get("cut_group", ""))
	match g.get_slice("_", 1):
		"S":
			outward = Vector3(0, 0, 1)
		"N":
			outward = Vector3(0, 0, -1)
		"E":
			outward = Vector3(1, 0, 0)
		"W":
			outward = Vector3(-1, 0, 0)
	var aabb := AABB()
	if leaf is MeshInstance3D and (leaf as MeshInstance3D).mesh != null:
		aabb = (leaf as MeshInstance3D).get_aabb()
	else:
		aabb = AABB(Vector3(0, 0.3, -0.05), Vector3(width, 2.2, 0.1))
	_centre = aabb.get_center()
	# box of the leaf (thickened to 0.1 m), in the hinge frame
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(aabb.size.x, 0.1), aabb.size.y, maxf(aabb.size.z, 0.1))
	var cs := CollisionShape3D.new()
	cs.name = "Box"
	cs.shape = box
	cs.position = _centre
	add_child(cs)
	collision_layer = 1
	collision_mask = 0
	interactable = InteractableComponent.new()
	interactable.name = "Interactable"
	interactable.position = Vector3(_centre.x, 0.0, _centre.z)
	interactable.interact_range = Balance.INTERACT_RANGE
	interactable.ring_radius = 0.6
	interactable.ring_offset = Vector3(_centre.x, _centre.y - 1.0, _centre.z)
	interactable.default_action = &"use"
	var ib := BoxShape3D.new()
	ib.size = Vector3(maxf(aabb.size.x, 0.3), aabb.size.y, maxf(aabb.size.z, 0.3))
	interactable.set_shape(ib, Vector3(0, _centre.y, 0))
	add_child(interactable)


func _ready() -> void:
	add_to_group("kit_door")
	if NetWorld.instance != null:
		apply_net_delta(NetWorld.instance.delta_of(WorldRegistry.wid_of(self)), false)


func interact_actions() -> Array:
	return [&"use", &"open", &"close"]


func get_interact_label(_player: Node) -> String:
	if locked and not is_open:
		return "Cerrada con llave"
	return "Cerrar puerta" if is_open else "Abrir puerta"


func can_interact(_player: Node) -> bool:
	return true


## Server only (NetWorld validated distance / rate): toggle (use) or set (open / close).
func server_interact(player: Node, action: StringName, _arg: int) -> bool:
	if not Net.is_server or NetWorld.instance == null:
		return false
	var want := not is_open if action == &"use" else action == &"open"
	if want == is_open:
		return true
	if want and locked:
		print("[EVT] door %x locked (peer %d)" % [WorldRegistry.wid_of(self), int((player as Player).peer_id) if player is Player else 0])
		return false
	var s := swing
	if want:
		s = _swing_for(player as Node3D)
	var fields := {"open": want, "swing": s}
	if want and alarm_armed and not alarm_fired:
		fields["alarm"] = true
		print("[EVT] door %x alarm: %d m for %d s" % [WorldRegistry.wid_of(self), int(ALARM_RADIUS), int(ALARM_SECONDS)])
	NetWorld.instance.set_delta(WorldRegistry.wid_of(self), fields)
	apply_net_delta(fields, true)
	var pid := int((player as Player).peer_id) if player is Player else 0
	SoundEvents.emit(global_position, NOISE, 1, SoundEvents.Kind.DOOR, pid, true)
	toggles += 1
	print("[EVT] door %x %s by peer %d" % [WorldRegistry.wid_of(self), "open" if want else "closed", pid])
	return true


## Exterior doors swing inward; interior doors away from the opener (-1 / +1 = the sign of the Y rotation).
func _swing_for(player: Node3D) -> int:
	var model := get_parent() as Node3D
	var away := -outward
	if not exterior and player != null and model != null:
		var local_p := model.global_transform.affine_inverse() * player.global_position
		var hinge := position
		var c := hinge + _centre
		away = Vector3(c.x - local_p.x, 0.0, c.z - local_p.z).normalized()
	var best := 1
	var best_d := -INF
	for s in [1, -1]:
		var rotated := Basis(Vector3.UP, deg_to_rad(OPEN_DEG) * float(s)) * Vector3(_centre.x, 0.0, _centre.z)
		var d := rotated.dot(away)
		if d > best_d:
			best_d = d
			best = s
	return best


## Replicated fields (server delta, snapshot, live event). live = animate, else snap.
func apply_net_delta(f: Dictionary, live: bool = true) -> void:
	if f.has("alarm"):
		var rang := alarm_fired
		alarm_fired = bool(f["alarm"])
		if live and alarm_fired and not rang and is_inside_tree():
			alarm_left = ALARM_SECONDS
			_alarm_t = 0.0
			set_process(true)
	if f.has("swing"):
		swing = int(f["swing"])
	if f.has("open"):
		var was := is_open
		is_open = bool(f["open"])
		set_process((live and is_inside_tree()) or alarm_left > 0.0)
		if live and is_inside_tree() and was != is_open:
			# every peer hears its own copy swing (S1 plugs the streams; silent until then)
			AudioManager.play(&"door_open" if is_open else &"door_close", global_position)
		if not live or not is_inside_tree():
			_angle = _target()
			_pose()


func _target() -> float:
	return deg_to_rad(OPEN_DEG) * float(swing) if is_open else 0.0


func _process(delta: float) -> void:
	var t := _target()
	_angle = move_toward(_angle, t, delta * deg_to_rad(OPEN_DEG) / SWING_SECONDS)
	_pose()
	if alarm_left > 0.0:
		alarm_left -= delta
		_alarm_t -= delta
		if _alarm_t <= 0.0:
			_alarm_t = ALARM_PERIOD
			if Net.is_server:
				SoundEvents.emit(global_position, ALARM_RADIUS, 3, SoundEvents.Kind.ALARM, 0, false)
			if Net.has_client:
				AudioManager.play(&"car_alarm", global_position)
	if is_equal_approx(_angle, t) and alarm_left <= 0.0:
		set_process(false)


func _pose() -> void:
	var b := Basis(Vector3.UP, _angle)
	rotation = Vector3(0.0, _angle, 0.0)
	if leaf != null and is_instance_valid(leaf):
		leaf.transform = Transform3D(b * _leaf_xf.basis, _leaf_xf.origin)
