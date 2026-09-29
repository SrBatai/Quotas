class_name FirearmFx
extends Node3D
## Client presentation of shots and projectiles (M5; GDD v2 §7.5): the shot events of every shooter in reach
## (Events.shot_fired: tracers to each bullet / pellet end, a muzzle flash at the gun, the gunshot sound), the local
## shooter's predicted flash (Events.local_shot, on the click), arrows flying and thrown cans / flares
## (Events.projectile_spawned; a landed flare glows red for FLARE_SECONDS). The noise ring comes from SoundEvents
## through ZombieNet like every other noise. Pooled, no physics, nothing on the dedicated server.

const TRACER_POOL := 48
const TRACER_TIME := 0.09
const FLASH_TIME := 0.06

static var instance: FirearmFx

var tracers_spawned: int = 0
var flashes: int = 0
var _clock: float = 0.0
var projectiles: int = 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_born := PackedFloat32Array()
var _next: int = 0
var _flash: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_until: float = 0.0
var _flying: Array = []          # [node, from, to, t0, flight, arc]
var _flares: Array = []          # [node, until]
var _tracer_mat: StandardMaterial3D
var _flash_mat: StandardMaterial3D


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	name = "FirearmFx"
	top_level = true
	_tracer_mat = StandardMaterial3D.new()
	_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer_mat.albedo_color = Color(1.0, 0.86, 0.55, 0.85)
	_tracer_mat.emission_enabled = true   # reads at the isometric distance (glow)
	_tracer_mat.emission = Color(1.0, 0.75, 0.4)
	_tracer_mat.emission_energy_multiplier = 1.5
	_tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1.0, 0.8, 0.4)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(1.0, 0.7, 0.3)
	_flash_mat.emission_energy_multiplier = 3.0
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.75, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)
	_flash_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 6
	sm.rings = 3
	_flash_mesh.mesh = sm
	_flash_mesh.material_override = _flash_mat
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	add_child(_flash_mesh)
	_tracer_born.resize(TRACER_POOL)
	Events.shot_fired.connect(_on_shot)
	Events.local_shot.connect(_on_local_shot)
	Events.projectile_spawned.connect(_on_projectile)


## Game clock (scaled by Engine.time_scale): a paused / frozen frame keeps its flash and tracers.
func _now() -> float:
	return _clock


func _on_local_shot(weapon: StringName, _spread: float) -> void:
	var lp := GameFlow.local_player() as Player
	if lp == null:
		return
	var at := _muzzle_of(lp)
	_muzzle(at)
	AudioManager.play(StringName(Firearms.of(weapon).get("sfx", &"gun_pistol")), at)


func _on_shot(shooter: int, weapon: StringName, origin: Vector3, ends: PackedVector3Array, _flags: int) -> void:
	var local := shooter == Net.local_peer_id()
	var from := origin
	var sp := _player_of(shooter)
	if sp != null:
		from = _muzzle_of(sp)
	if not Firearms.is_bow(weapon):
		for e in ends:
			tracer(from, e)
	if not local:
		_muzzle(from)
		AudioManager.play(StringName(Firearms.of(weapon).get("sfx", &"gun_pistol")), from)


func _player_of(peer: int) -> Player:
	var w := get_tree().get_first_node_in_group("world")
	return w.get_node_or_null("Players/%d" % peer) as Player if w != null else null


## The gun's `Muzzle` anchor (ASSET_SPEC v2 §12) when the model is in the hand, else in front of the chest.
func _muzzle_of(p: Player) -> Vector3:
	if p.tool_holder != null and p.tool_holder.tool_model != null:
		var m := p.tool_holder.tool_model.find_child("Muzzle", true, false) as Node3D
		if m != null and m.is_inside_tree():
			return m.global_position
	return p.global_position + Vector3(0, Balance.GUN_ORIGIN_HEIGHT, 0) + p.facing() * 0.5


func _muzzle(at: Vector3) -> void:
	flashes += 1
	_flash.global_position = at
	_flash.light_energy = 3.0
	_flash_mesh.global_position = at
	_flash_mesh.visible = true
	_flash_until = _now() + FLASH_TIME


## A thin bright quad from `a` to `b` that fades in TRACER_TIME.
func tracer(a: Vector3, b: Vector3) -> void:
	var mi: MeshInstance3D
	if _tracers.size() < TRACER_POOL:
		mi = MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.045, 0.045, 1.0)
		mi.mesh = bm
		mi.material_override = _tracer_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_tracers.append(mi)
		_next = _tracers.size() - 1
	else:
		_next = (_next + 1) % TRACER_POOL
		mi = _tracers[_next]
	var d := b - a
	if d.length() < 0.05:
		return
	mi.visible = true
	mi.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT), a + d * 0.5)
	mi.scale = Vector3(1.0, 1.0, d.length())
	_tracer_born[_tracers.find(mi)] = _now()
	tracers_spawned += 1


func _on_projectile(kind: int, from: Vector3, to: Vector3, flight: float, _shooter: int) -> void:
	projectiles += 1
	var n: Node3D
	match kind:
		Projectiles.Kind.ARROW:
			n = Assets.spawn_model("arrow")
		Projectiles.Kind.CAN:
			n = Assets.spawn_model(str(Items.DB[&"lata_vacia"].get("model", "can_soup")))
		_:
			n = Assets.spawn_model("flare")
	add_child(n)
	n.global_position = from
	_flying.append([n, from, to, _now(), maxf(flight, 0.05), 0.0 if kind == Projectiles.Kind.ARROW else 2.5, kind])
	if kind == Projectiles.Kind.ARROW:
		AudioManager.play(&"bow_release", from)


func _land(e: Array) -> void:
	var n: Node3D = e[0]
	var kind := int(e[6])
	if kind == Projectiles.Kind.FLARE:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.25, 0.2)
		l.omni_range = 9.0
		l.light_energy = 2.5
		l.position = Vector3(0, 0.3, 0)
		n.add_child(l)
		_flares.append([n, _now() + Balance.FLARE_SECONDS])
		AudioManager.play(&"flare_burn", n.global_position)
	elif kind == Projectiles.Kind.CAN:
		AudioManager.play(&"can_land", n.global_position)
		get_tree().create_timer(6.0).timeout.connect(n.queue_free)
	else:
		get_tree().create_timer(4.0).timeout.connect(n.queue_free)


func _process(delta: float) -> void:
	_clock += delta
	var now := _now()
	if _flash_mesh.visible and now >= _flash_until:
		_flash_mesh.visible = false
		_flash.light_energy = 0.0
	for i in _tracers.size():
		var mi := _tracers[i]
		if mi.visible and now - _tracer_born[i] > TRACER_TIME:
			mi.visible = false
	for k in range(_flying.size() - 1, -1, -1):
		var e: Array = _flying[k]
		var n: Node3D = e[0]
		if not is_instance_valid(n):
			_flying.remove_at(k)
			continue
		var f := clampf((now - float(e[3])) / float(e[4]), 0.0, 1.0)
		var p := (e[1] as Vector3).lerp(e[2], f)
		p.y += float(e[5]) * 4.0 * f * (1.0 - f)
		var dir: Vector3 = (e[2] as Vector3) - (e[1] as Vector3)
		n.global_position = p
		if dir.length() > 0.1:
			n.look_at(p + dir, Vector3.UP, true)
		if f >= 1.0:
			_flying.remove_at(k)
			_land(e)
	for k in range(_flares.size() - 1, -1, -1):
		var fl: Array = _flares[k]
		if now >= float(fl[1]) or not is_instance_valid(fl[0]):
			if is_instance_valid(fl[0]):
				(fl[0] as Node).queue_free()
			_flares.remove_at(k)
