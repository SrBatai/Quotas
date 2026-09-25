extends Node3D
## VENTISCA look-dev scene (rendering research, G1). Builds the reference composition procedurally (clearing with
## cabin + porch + chimney, A-frame, truck, signpost, pines, bare trees, berry bushes, survivor by the porch,
## footprint trail), the game camera (pitch -48, fov 36, 27 m, yaw 45) and the WorldEnvironment presets.
##
## Command line (after `--`), all optional:
##   preset=day|dusk|night|blizzard   list=day,dusk,...  (several captures in one process)
##   out=/abs/dir  frames=N  tonemap=agx|aces|filmic|linear  exposure=1.0  gi=ssao|none|sdfgi|ssil
##   hd=0|1 (use assets/hd/*.glb when present)  trail=cpu|drawable|none  spill=1|0  pcss=1|0  msaa=0|2|4
##   dist=27 yaw=45 pitch=-48 fov=36  target=x,z  tag=suffix

const Presets := preload("res://scripts/presets.gd")
const TerrainBuilder := preload("res://scripts/terrain_builder.gd")
const TrailMap := preload("res://scripts/trail_map.gd")

const OUT_DEFAULT := "/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/lookdev_render"
## game model name -> HD file stem in assets/hd (see hd_manifest.json)
const HD_ALIASES := {
	"pine_a": "pine_hd_a", "pine_b": "pine_hd_b", "pine_c": "pine_hd_b", "dead_tree": "bare_tree_hd",
	"cabin": "cabin_hd", "a_frame_cabin": "a_frame_hd", "pickup_truck": "truck_hd", "signpost": "signpost_hd",
	"berry_bush": "berry_bush_hd", "survivor_blue": "chars/survivor_hd_navy", "survivor_green": "chars/survivor_hd_olive",
}

var args: Dictionary = {}
var compat: bool = false
var terrain: LookdevTerrain
var trail: LookdevTrailMap
var terrain_mat: ShaderMaterial
var world_mat: ShaderMaterial
var window_glass: StandardMaterial3D
var window_glow: StandardMaterial3D
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var cam_pivot: Node3D
var cam_pitch: Node3D
var camera: Camera3D
var window_nodes: Array[MeshInstance3D] = []
var spill_lights: Array[Light3D] = []
var lantern_light: OmniLight3D
var campfire_root: Node3D
var campfire_light: OmniLight3D
var snowfall: CPUParticles3D
var pad_center := Vector2(0.0, 1.5)
var spill_scale: float = 1.0


func _ready() -> void:
	_parse_args()
	compat = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	print("[lookdev] renderer=%s adapter=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	_build_materials()
	_build_terrain_and_props()
	_build_lights_and_env()
	_build_camera()
	if args.get("costmatrix", "0") == "1":
		_cost_matrix.call_deferred()
	elif args.get("capture", "1") == "1":
		_capture_sequence.call_deferred()


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var eq := a.find("=")
		if eq > 0:
			args[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			args[a] = "1"


func _argf(key: String, def: float) -> float:
	return float(args[key]) if args.has(key) else def


# ---------------------------------------------------------------- materials

func _build_materials() -> void:
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/snow_terrain.gdshader")
	world_mat = ShaderMaterial.new()
	world_mat.shader = load("res://shaders/world_vcol_v2.gdshader")
	window_glass = StandardMaterial3D.new()
	window_glass.albedo_color = Color("#1F2A40")
	window_glass.roughness = 0.25
	window_glass.metallic_specular = 0.6
	window_glow = StandardMaterial3D.new()
	window_glow.albedo_color = Color("#FFC070")
	window_glow.emission_enabled = true
	window_glow.emission = Color("#FFC070")
	window_glow.emission_energy_multiplier = 3.0
	window_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _apply_materials(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			var mname := mat.resource_name if mat != null else ""
			if mname == "window":
				m.set_surface_override_material(i, window_glass)
				if not window_nodes.has(m):
					window_nodes.append(m)
			elif mname.begins_with("palette") or mat == null or (mat is StandardMaterial3D and (mat as StandardMaterial3D).vertex_color_use_as_albedo):
				m.set_surface_override_material(i, world_mat)
		if m.get_aabb().size.y < 0.5 and m.get_aabb().size.x < 0.6:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# ---------------------------------------------------------------- scene

func _model_path(model_name: String) -> String:
	if args.get("hd", "1") == "1":
		# Opus's hero assets: assets/hd/<name>_hd.glb (COLOR_0.a = baked AO, custom normals)
		var base := model_name.get_file()
		var candidates := ["res://assets/hd/%s_hd.glb" % base, "res://assets/hd/%s.glb" % base]
		if HD_ALIASES.has(base):
			candidates.push_front("res://assets/hd/%s.glb" % HD_ALIASES[base])
		for hd in candidates:
			if ResourceLoader.exists(hd, "PackedScene"):
				return hd
	return "res://assets/models/%s.glb" % model_name


func _spawn(model_name: String, pos: Vector3, yaw_deg: float = 0.0, scale_f: float = 1.0) -> Node3D:
	var path := _model_path(model_name)
	var ps: PackedScene = load(path)
	if ps == null:
		push_warning("missing model " + path)
		return null
	var inst := ps.instantiate() as Node3D
	inst.position = Vector3(pos.x, terrain.height_at(pos.x, pos.z) + pos.y, pos.z)
	inst.rotation_degrees.y = yaw_deg
	inst.scale = Vector3.ONE * scale_f
	add_child(inst)
	_apply_materials(inst)
	for sb in inst.find_children("Col*", "StaticBody3D", true, false):
		sb.queue_free()  # no physics needed in look-dev
	return inst


func _occ(pos: Vector2, r: float, strength: float) -> void:
	terrain.occluders.append({"pos": pos, "r": r, "strength": strength})


func _build_terrain_and_props() -> void:
	terrain = TerrainBuilder.new()
	terrain.size = 100.0
	terrain.cell = 0.5
	terrain.pads = [
		{"pos": pad_center, "r": 11.0, "h": 0.0},
		{"pos": Vector2(-15.0, -8.0), "r": 8.0, "h": 0.15},
		{"pos": Vector2(-10.0, 1.5), "r": 5.0, "h": 0.05},
	]
	# occluders (baked contact AO in COLOR.a), placed before the mesh is built
	terrain.occluders.append({"rect": Rect2(-3.2, -2.7, 6.4, 8.0), "strength": 0.50, "soft": 2.2})
	terrain.occluders.append({"rect": Rect2(-3.0, 2.4, 6.0, 2.9), "strength": 0.45, "soft": 0.9})
	terrain.occluders.append({"rect": Rect2(-18.4, -11.9, 6.8, 7.6), "strength": 0.45, "soft": 1.8})
	terrain.occluders.append({"rect": Rect2(-11.6, -0.8, 3.2, 4.6), "strength": 0.45, "soft": 1.6})
	# Screen directions at camera yaw 45: up = (-X,-Z), right = (+X,-Z), left = (-X,+Z), down = (+X,+Z).
	var pines := [
		["pine_a", Vector3(10.5, 0, -7.0), 20], ["pine_b", Vector3(13.5, 0, -2.0), 140], ["pine_a", Vector3(15.5, 0, -11.0), 70],
		["pine_a", Vector3(-6.0, 0, -16.0), 0], ["pine_b", Vector3(2.5, 0, -18.0), 90], ["pine_c", Vector3(-11.0, 0, -20.0), 30],
		["pine_a", Vector3(8.0, 0, -20.0), 200], ["pine_b", Vector3(-25.0, 0, -1.0), 0], ["pine_a", Vector3(-27.0, 0, -15.0), 45],
		["pine_a", Vector3(19.0, 0, 9.5), 10], ["pine_b", Vector3(21.0, 0, 3.0), 60], ["pine_c", Vector3(20.5, 0, 15.0), 0],
		["pine_c", Vector3(-19.0, 0, 6.0), 80], ["pine_a", Vector3(-23.0, 0, 13.0), 15], ["pine_b", Vector3(-28.0, 0, 6.0), 120],
		["pine_a", Vector3(22.0, 0, -7.0), 5], ["pine_b", Vector3(-2.0, 0, -23.0), 50], ["pine_a", Vector3(-15.0, 0, -26.0), 90],
		["pine_a", Vector3(25.0, 0, -16.0), 33], ["pine_b", Vector3(9.0, 0, 22.0), 12], ["pine_a", Vector3(-9.0, 0, 24.0), 77],
		["pine_b", Vector3(4.0, 0, -12.5), 0], ["pine_c", Vector3(-1.5, 0, -9.5), 45], ["pine_a", Vector3(-22.0, 0, -22.0), 0],
	]
	for p in pines:
		var r := 1.7 if p[0] == "pine_a" else (1.2 if p[0] == "pine_b" else 1.0)
		_occ(Vector2(p[1].x, p[1].z), r, 0.45)
	var dead := [[Vector3(12.0, 0, 4.5), 0], [Vector3(-14.0, 0, -10.0), 40], [Vector3(17.5, 0, -15.5), 90], [Vector3(-8.5, 0, 18.5), 20], [Vector3(-24.0, 0, -8.0), 70], [Vector3(9.0, 0, -14.0), 15]]
	for d in dead:
		_occ(Vector2(d[0].x, d[0].z), 0.7, 0.4)
	var bushes := [[Vector3(-12.5, 0, 6.5), 0], [Vector3(-9.0, 0, 12.5), 50], [Vector3(-4.5, 0, 13.5), 120], [Vector3(6.5, 0, 13.0), 30], [Vector3(-16.0, 0, 15.0), 0]]
	for b in bushes:
		_occ(Vector2(b[0].x, b[0].z), 0.8, 0.4)
	var rocks := [["rock_b", Vector3(-13.5, 0, 1.5), 30], ["rock_a", Vector3(5.5, 0, -9.5), 0], ["rock_c", Vector3(-1.5, 0, 12.5), 60], ["rock_a", Vector3(13.0, 0, 12.0), 90]]
	for r in rocks:
		_occ(Vector2(r[1].x, r[1].z), 1.3 if r[0] == "rock_b" else 0.8, 0.5)
	var signpost_pos := Vector3(-4.0, 0, 9.5)
	_occ(Vector2(signpost_pos.x, signpost_pos.z), 0.5, 0.4)
	var player_pos := Vector3(0.6, 0, 6.6)
	_occ(Vector2(player_pos.x, player_pos.z), 0.45, 0.35)
	var fire_pos := Vector3(2.5, 0, 11.0)
	_occ(Vector2(fire_pos.x, fire_pos.z), 0.9, 0.3)
	_occ(Vector2(-7.0, 15.0), 1.1, 0.4)  # fallen log
	_occ(Vector2(7.0, -3.0), 0.5, 0.4)   # stump
	terrain.build_heights()
	# hdterrain=1: Opus's sculpted terrain_tile_hd.glb (path, berms, drifts, mesh footprints) sits on top of the
	# procedural terrain over its extent; the procedural mesh is sunk there so only the tile is visible.
	var use_hd_tile: bool = String(args.get("hdterrain", "0")) == "1" and ResourceLoader.exists("res://assets/hd/terrain_tile_hd.glb", "PackedScene")
	if use_hd_tile:
		var ext := Rect2(-20.0, -26.0, 44.0, 44.0)
		var half := terrain.size * 0.5
		for iz in terrain.n:
			for ix in terrain.n:
				var x := float(ix) * terrain.cell - half
				var z := float(iz) * terrain.cell - half
				var inner := ext.grow(-3.0)
				var dx := maxf(maxf(inner.position.x - x, x - inner.end.x), 0.0)
				var dz := maxf(maxf(inner.position.y - z, z - inner.end.y), 0.0)
				var d := Vector2(dx, dz).length()
				var w := 1.0 - smoothstep(0.0, 3.0, d)
				terrain.heights[iz * terrain.n + ix] = lerpf(terrain.heights[iz * terrain.n + ix], -0.35, w)
	var mesh := terrain.build_mesh()
	var tmi := MeshInstance3D.new()
	tmi.name = "Terrain"
	tmi.mesh = mesh
	tmi.material_override = terrain_mat
	tmi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(tmi)
	print("[lookdev] terrain verts=%d tris=%d" % [terrain.n * terrain.n, (terrain.n - 1) * (terrain.n - 1) * 2])
	# trail map
	var trail_mode: String = args.get("trail", "cpu")
	if trail_mode != "none":
		trail = TrailMap.new()
		trail.rect = Rect2(-22.0, -18.0, 40.0, 40.0)
		trail.resolution = 1024
		trail.setup(trail_mode)
		# main trail: from the left edge past the signpost to the porch steps, plus a loop to the truck
		trail.stamp_path(PackedVector2Array([Vector2(-18.0, 16.5), Vector2(-11.5, 13.0), Vector2(-6.5, 11.5), Vector2(-2.5, 8.8), Vector2(0.4, 7.2)]))
		trail.stamp_path(PackedVector2Array([Vector2(-2.5, 8.8), Vector2(-5.0, 5.0), Vector2(-7.5, 3.5)]))
		trail.stamp_path(PackedVector2Array([Vector2(0.4, 7.2), Vector2(3.0, 8.0), Vector2(6.5, 10.5)]))
		# double-stamped "trampled" patch by the steps
		trail.stamp_path(PackedVector2Array([Vector2(-0.5, 6.4), Vector2(1.5, 6.2), Vector2(1.2, 7.6), Vector2(-0.3, 7.4)]), 0.5)
		trail.flush()
		terrain_mat.set_shader_parameter("trail_map", trail.texture)
		terrain_mat.set_shader_parameter("trail_rect", Vector4(trail.rect.position.x, trail.rect.position.y, trail.rect.size.x, trail.rect.size.y))
		terrain_mat.set_shader_parameter("trail_enabled", true)
		print("[lookdev] trail backend=%s" % trail.backend)
	else:
		terrain_mat.set_shader_parameter("trail_enabled", false)
	if use_hd_tile:
		var tile: PackedScene = load("res://assets/hd/terrain_tile_hd.glb")
		var tinst := tile.instantiate() as Node3D
		add_child(tinst)
		for mi in tinst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.name.begins_with("Terrain"):
				m.material_override = terrain_mat
				m.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			else:
				for i in m.mesh.get_surface_count():
					m.set_surface_override_material(i, world_mat)
		print("[lookdev] HD terrain tile in use")
	# props
	_spawn("cabin", Vector3(0, 0, 0), 0.0)
	_spawn("a_frame_cabin", Vector3(-15.0, 0, -8.0), 0.0)
	_spawn("pickup_truck", Vector3(-10.0, 0, 1.5), 55.0)
	_spawn("signpost", signpost_pos, 35.0)
	for p in pines:
		_spawn(p[0], p[1], p[2])
	for d in dead:
		_spawn("dead_tree", d[0], d[1])
	for b in bushes:
		_spawn("berry_bush", b[0], b[1])
	for r in rocks:
		_spawn(r[0], r[1], r[2])
	_spawn("fallen_log", Vector3(-7.0, 0, 15.0), 25.0)
	_spawn("stump", Vector3(7.0, 0, -3.0), 0.0)
	_spawn("firewood", Vector3(2.6, 0, 8.4), 40.0)
	_spawn("firewood", Vector3(-3.2, 0, 4.8), 110.0)
	_spawn("stone", Vector3(4.5, 0, 12.0), 0.0)
	_spawn("stone", Vector3(-11.0, 0, 9.0), 0.0)
	for i in 7:
		_spawn("fence", Vector3(-6.0 + float(i) * 2.0, 0, -24.0), 0.0)
	# survivor by the porch steps, facing the door
	_spawn_survivor(player_pos, 200.0)
	# campfire (lit only in the night preset)
	campfire_root = _spawn("campfire", fire_pos, 0.0)
	campfire_light = OmniLight3D.new()
	campfire_light.light_color = Color("#FF9A3C")
	campfire_light.light_energy = 4.5
	campfire_light.omni_range = 10.0
	campfire_light.omni_attenuation = 1.3
	campfire_light.shadow_enabled = not compat
	campfire_light.position = Vector3(0, 0.55, 0)
	campfire_root.add_child(campfire_light)
	var flame := MeshInstance3D.new()
	var fm := SphereMesh.new()
	fm.radius = 0.22
	fm.height = 0.5
	flame.mesh = fm
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color("#FFB040")
	flame_mat.emission_enabled = true
	flame_mat.emission = Color("#FF9A2A")
	flame_mat.emission_energy_multiplier = 4.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material_override = flame_mat
	flame.position = Vector3(0, 0.38, 0)
	flame.name = "Flame"
	campfire_root.add_child(flame)
	# lantern on the porch
	var lantern := _spawn("lantern", Vector3(1.6, 2.35, 4.3), 0.0)
	lantern_light = OmniLight3D.new()
	lantern_light.light_color = Color("#FFB454")
	lantern_light.light_energy = 3.5
	lantern_light.omni_range = 8.0
	lantern_light.omni_attenuation = 1.2
	lantern_light.shadow_enabled = not compat
	lantern_light.position = Vector3(0, -0.23, 0)
	lantern.add_child(lantern_light)
	# snowfall (blizzard)
	snowfall = CPUParticles3D.new()
	snowfall.amount = 2200
	snowfall.lifetime = 5.0
	snowfall.preprocess = 5.0
	snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snowfall.emission_box_extents = Vector3(24.0, 1.0, 24.0)
	snowfall.position = Vector3(0, 12.0, 4.0)
	snowfall.direction = Vector3(-0.8, -1.0, 0.3)
	snowfall.spread = 12.0
	snowfall.initial_velocity_min = 5.0
	snowfall.initial_velocity_max = 8.0
	snowfall.gravity = Vector3(-1.5, -1.5, 0.5)
	snowfall.scale_amount_min = 0.6
	snowfall.scale_amount_max = 1.2
	snowfall.particle_flag_align_y = true  # streaks along the wind
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.22)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(0.95, 0.97, 1.0, 0.7)
	pm.albedo_texture = _make_soft_disc()
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = pm
	snowfall.mesh = quad
	snowfall.emitting = false
	add_child(snowfall)


func _make_soft_disc() -> ImageTexture:
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2((float(x) + 0.5) / float(s) - 0.5, (float(y) + 0.5) / float(s) - 0.5).length() * 2.0
			var a := 1.0 - smoothstep(0.35, 1.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _spawn_survivor(pos: Vector3, yaw_deg: float) -> void:
	var root := _spawn("chars/survivor_blue", pos, yaw_deg)
	if root == null:
		_spawn("player", pos, yaw_deg)
		return
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = skeletons[0] as Skeleton3D if skeletons.size() > 0 else null
	var anim_scene: PackedScene = load("res://assets/models/anims/humanoid_loco.glb") if ResourceLoader.exists("res://assets/models/anims/humanoid_loco.glb", "PackedScene") else null
	if sk == null or anim_scene == null:
		return
	var ainst := anim_scene.instantiate()
	var ap: AnimationPlayer = ainst.find_child("AnimationPlayer", true, false)
	if ap == null:
		ainst.free()
		return
	var names := ap.get_animation_list()
	var pick := ""
	for cand in ["Loco_Idle_Cold", "Loco_Idle", "idle", "Idle", "idle_loop"]:
		if names.has(cand):
			pick = cand
			break
	if pick == "":
		for nm in names:
			if nm.to_lower().contains("idle"):
				pick = nm
				break
	if pick == "" and names.size() > 0:
		pick = names[0]
	if pick != "":
		var anim := ap.get_animation(pick)
		var t := 0.4
		for i in anim.get_track_count():
			var path := String(anim.track_get_path(i))
			var colon := path.find(":")
			if colon < 0:
				continue
			var bone := sk.find_bone(path.substr(colon + 1))
			if bone < 0:
				continue
			match anim.track_get_type(i):
				Animation.TYPE_POSITION_3D:
					sk.set_bone_pose_position(bone, anim.position_track_interpolate(i, t))
				Animation.TYPE_ROTATION_3D:
					sk.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(i, t))
				Animation.TYPE_SCALE_3D:
					sk.set_bone_pose_scale(bone, anim.scale_track_interpolate(i, t))
		print("[lookdev] survivor posed with '%s'" % pick)
	ainst.free()


# ---------------------------------------------------------------- lights & environment

func _make_projector() -> ImageTexture:
	# 4-pane window cookie: bright panes, dark mullions, soft edge (projected by the spill spot lights)
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var u := (float(x) + 0.5) / float(s)
			var v := (float(y) + 0.5) / float(s)
			var edge := smoothstep(0.0, 0.10, u) * smoothstep(0.0, 0.10, 1.0 - u) * smoothstep(0.0, 0.10, v) * smoothstep(0.0, 0.10, 1.0 - v)
			var mull := 1.0
			if absf(u - 0.5) < 0.035 or absf(v - 0.5) < 0.035:
				mull = 0.25
			var val := edge * mull
			img.set_pixel(x, y, Color(val, val, val, 1.0))
	return ImageTexture.create_from_image(img)


func _add_spill(pos: Vector3, dir: Vector3, energy: float, range_m: float, cookie: Texture2D) -> void:
	var spot := SpotLight3D.new()
	spot.light_color = Color("#FFC070")
	spot.light_energy = energy
	spot.spot_range = range_m
	spot.spot_angle = 48.0
	spot.spot_angle_attenuation = 0.8
	spot.spot_attenuation = 1.2
	spot.shadow_enabled = false
	spot.light_volumetric_fog_energy = 2.0
	if not compat and args.get("cookie", "1") == "1":
		spot.light_projector = cookie
	add_child(spot)
	spot.position = pos
	spot.look_at(pos + dir, Vector3.UP)
	spot.set_meta("base_energy", energy)
	spill_lights.append(spot)
	# soft wall wash just outside the window (the panes light the frame and the snow bank under them)
	var omni := OmniLight3D.new()
	omni.light_color = Color("#FFB868")
	omni.light_energy = energy * 0.25
	omni.omni_range = range_m * 0.45
	omni.omni_attenuation = 1.4
	omni.shadow_enabled = false
	omni.position = pos + dir.normalized() * 0.5
	add_child(omni)
	omni.set_meta("base_energy", energy * 0.25)
	spill_lights.append(omni)


func _build_lights_and_env() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.35
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.8
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 60.0
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 2.0
	add_child(moon)
	env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.15
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_sky_contribution = 0.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_sky_affect = 0.0
	env.environment = e
	add_child(env)
	# window spill lights (cabin +X window, cabin front window under the porch, A-frame front window)
	var cookie := _make_projector()
	if args.get("arealight", "0") == "1" and ClassDB.class_exists("AreaLight3D") and not compat:
		# 4.7 AreaLight3D as the lit window pane itself (experiment: cost on every object while visible)
		var al: Light3D = ClassDB.instantiate("AreaLight3D")
		al.light_color = Color("#FFC070")
		al.light_energy = 6.0
		al.set("area_size", Vector2(1.2, 1.0))
		al.set("area_range", 9.0)
		al.set("area_texture", cookie)
		al.shadow_enabled = true
		add_child(al)
		al.position = Vector3(3.12, 1.85, -1.3)
		al.look_at(Vector3(3.12, 1.85, -1.3) + Vector3(1.0, 0.0, 0.0), Vector3.UP)
		al.set_meta("base_energy", 6.0)
		spill_lights.append(al)
	elif args.get("spill", "1") == "1":
		_add_spill(Vector3(3.15, 1.85, -1.3), Vector3(1.0, -0.95, 0.0), 9.0, 9.0, cookie)
	if args.get("spill", "1") == "1":
		_add_spill(Vector3(-1.4, 1.85, 2.6), Vector3(0.0, -0.9, 1.0), 4.0, 6.0, cookie)
		var af := Vector3(-15.0, 0, -8.0)
		_add_spill(af + Vector3(0.7, 3.0, 3.55), Vector3(0.0, -0.8, 1.0), 5.0, 8.0, cookie)


func _set_windows(on: bool) -> void:
	for m in window_nodes:
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat != null and mat.resource_name == "window":
				m.set_surface_override_material(i, window_glow if on else window_glass)
	for l in spill_lights:
		l.visible = on
		l.light_energy = float(l.get_meta("base_energy", l.light_energy)) * spill_scale


func _apply_preset(name: StringName) -> void:
	var p := Presets.get_preset(name)
	var e := env.environment
	# sun / moon
	for pair in [[sun, p["sun"]], [moon, p["moon"]]]:
		var light: DirectionalLight3D = pair[0]
		var cfg = pair[1]
		if cfg == null:
			light.visible = false
			continue
		light.visible = true
		light.light_color = Color(cfg["color"])
		light.light_energy = float(cfg["energy"]) * _argf("sunscale", 1.0)
		light.light_indirect_energy = cfg.get("indirect", 1.0)
		light.rotation_degrees = cfg["rot"]
		light.light_angular_distance = cfg["angular"] if (args.get("pcss", "1") == "1" and not compat) else 0.0
		light.shadow_blur = cfg["blur"]
	# ambient / sky
	e.ambient_light_color = Color(p["ambient"]["color"])
	e.ambient_light_energy = p["ambient"]["energy"]
	sky_mat.sky_top_color = Color(p["sky"]["top"])
	sky_mat.sky_horizon_color = Color(p["sky"]["horizon"])
	sky_mat.ground_bottom_color = Color(p["sky"]["ground"])
	sky_mat.ground_horizon_color = Color(p["sky"]["horizon"])
	sky_mat.sky_energy_multiplier = p["sky"]["energy"]
	# fog
	var f: Dictionary = p["fog"]
	e.fog_light_color = Color(f["color"])
	e.fog_density = f["density"]
	e.fog_aerial_perspective = f["aerial"]
	e.fog_height = f["height"]
	e.fog_height_density = f["height_density"]
	e.fog_sun_scatter = f["sun_scatter"]
	# tonemap (cmd line overrides the preset for A/B renders)
	var tm: Dictionary = p["tonemap"]
	var mode: String = args.get("tonemap", tm["mode"])
	match mode:
		"aces": e.tonemap_mode = Environment.TONE_MAPPER_ACES
		"filmic": e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		"linear": e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		"reinhard": e.tonemap_mode = Environment.TONE_MAPPER_REINHARDT
		_: e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = _argf("exposure", tm["exposure"])
	e.tonemap_white = _argf("white", tm["white"])
	if "tonemap_agx_contrast" in e:
		e.set("tonemap_agx_contrast", _argf("agx_contrast", tm.get("agx_contrast", 1.25)))
	var adj: Dictionary = p["adjust"]
	e.adjustment_enabled = true
	e.adjustment_brightness = adj["brightness"]
	e.adjustment_contrast = adj["contrast"]
	e.adjustment_saturation = _argf("saturation", adj["saturation"])
	# glow
	var g: Dictionary = p["glow"]
	e.glow_enabled = bool(g["enabled"]) and args.get("glow", "1") == "1"
	if e.glow_enabled:
		e.glow_intensity = g["intensity"]
		e.glow_bloom = g["bloom"]
		e.glow_hdr_threshold = g["threshold"]
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT if g["blend"] == "softlight" else Environment.GLOW_BLEND_MODE_SCREEN
	# gi
	var gi: String = args.get("gi", "ssao")
	var s: Dictionary = p["ssao"]
	e.ssao_enabled = bool(s["enabled"]) and gi != "none" and gi != "sdfgi_only"
	if e.ssao_enabled:
		e.ssao_radius = s["radius"]
		e.ssao_intensity = s["intensity"]
		e.ssao_power = s["power"]
		e.ssao_detail = s["detail"]
		e.ssao_light_affect = s["light_affect"]
	e.ssil_enabled = gi == "ssil" and not compat
	if e.ssil_enabled:
		e.ssil_radius = 4.0
		e.ssil_intensity = 1.2
	e.sdfgi_enabled = gi.begins_with("sdfgi") and not compat
	if e.sdfgi_enabled:
		e.sdfgi_cascades = 4
		e.sdfgi_min_cell_size = 0.4
		e.sdfgi_cascade0_distance = 16.0
		e.sdfgi_max_distance = 120.0
		e.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
		e.sdfgi_read_sky_light = true
		e.sdfgi_bounce_feedback = 0.4
		e.sdfgi_energy = 1.0
		e.sdfgi_use_occlusion = false
	# volumetric fog
	var v: Dictionary = p["volumetric"]
	e.volumetric_fog_enabled = bool(v["enabled"]) and not compat and args.get("volumetric", "1") == "1"
	if e.volumetric_fog_enabled:
		e.volumetric_fog_density = v["density"]
		e.volumetric_fog_albedo = Color(v["albedo"])
		e.volumetric_fog_anisotropy = v["anisotropy"]
		e.volumetric_fog_length = v["length"]
		e.volumetric_fog_ambient_inject = v["ambient_inject"]
		e.volumetric_fog_sky_affect = v["sky_affect"]
		e.volumetric_fog_temporal_reprojection_enabled = false
	# scene state
	spill_scale = float(p.get("spill_scale", 1.0))
	_set_windows(bool(p["windows"]))
	lantern_light.visible = bool(p["lantern"])
	campfire_light.visible = bool(p["campfire"])
	(campfire_root.get_node("Flame") as MeshInstance3D).visible = bool(p["campfire"])
	snowfall.emitting = bool(p["snowfall"])
	snowfall.visible = bool(p["snowfall"])
	RenderingServer.global_shader_parameter_set("snow_amount", float(p["blizzard"]) * 0.7)
	# terrain material tweaks per preset
	terrain_mat.set_shader_parameter("sparkle_strength", 0.8 if name == &"day" else (0.25 if name == &"dusk" else 0.0))
	terrain_mat.set_shader_parameter("rim_strength", 0.12 if name != &"night" else 0.06)
	print("[lookdev] preset %s applied (tonemap=%s ssao=%s glow=%s sdfgi=%s volumetric=%s)" % [name, mode, e.ssao_enabled, e.glow_enabled, e.sdfgi_enabled, e.volumetric_fog_enabled])


# ---------------------------------------------------------------- camera

func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	var tgt := Vector2(-3.0, 2.0)
	if args.has("target"):
		var parts: PackedStringArray = String(args["target"]).split(",")
		tgt = Vector2(float(parts[0]), float(parts[1]))
	cam_pivot.position = Vector3(tgt.x, terrain.height_at(tgt.x, tgt.y), tgt.y)
	cam_pivot.rotation_degrees.y = _argf("yaw", 45.0)
	add_child(cam_pivot)
	cam_pitch = Node3D.new()
	cam_pitch.rotation_degrees.x = _argf("pitch", -48.0)
	cam_pivot.add_child(cam_pitch)
	camera = Camera3D.new()
	camera.fov = _argf("fov", 36.0)
	camera.position = Vector3(0, 0, _argf("dist", 27.0))
	camera.near = 0.3
	camera.far = 90.0
	cam_pitch.add_child(camera)
	camera.current = true
	var vp := get_viewport()
	var msaa := int(_argf("msaa", 2.0))
	vp.msaa_3d = Viewport.MSAA_2X if msaa == 2 else (Viewport.MSAA_4X if msaa == 4 else Viewport.MSAA_DISABLED)
	if not compat:
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED


# ---------------------------------------------------------------- capture

func _capture_sequence() -> void:
	var out_dir: String = args.get("out", OUT_DEFAULT)
	DirAccess.make_dir_recursive_absolute(out_dir)
	# list entries: preset[:tonemap[:exposure[:tag]]]  e.g. day:aces:0.9:_a
	var list: PackedStringArray = String(args.get("list", args.get("preset", "day"))).split(",")
	var frames := int(_argf("frames", 12.0))
	var base_tag: String = args.get("tag", "")
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for entry in list:
		var parts: PackedStringArray = entry.split(":")
		var name := parts[0]
		var tag := base_tag
		args.erase("tonemap")
		args.erase("exposure")
		if parts.size() > 1 and parts[1] != "":
			args["tonemap"] = parts[1]
			tag += "_" + parts[1]
		if parts.size() > 2 and parts[2] != "":
			args["exposure"] = parts[2]
			tag += "_e" + parts[2]
		if parts.size() > 3:
			tag += parts[3]
		_apply_preset(StringName(name))
		var t0 := Time.get_ticks_msec()
		var gpu_sum := 0.0
		var gpu_n := 0
		for i in frames:
			await get_tree().process_frame
			if i >= 3:
				gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(rid)
				gpu_n += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var suffix := "_%s" % (RenderingServer.get_current_rendering_method() if not compat else "compat")
		var path := "%s/%s%s%s.png" % [out_dir, name, tag, suffix]
		img.save_png(path)
		var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
		var gpu := RenderingServer.viewport_get_measured_render_time_gpu(rid)
		print("[lookdev] saved %s (%d frames in %d ms; last frame cpu %.2f ms gpu %.2f ms; mean gpu %.1f ms over %d frames; draw calls %d, prims %d)" % [path, frames, Time.get_ticks_msec() - t0, cpu, gpu, gpu_sum / maxf(float(gpu_n), 1.0), gpu_n,
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)])
	get_tree().quit()


# ---------------------------------------------------------------- cost matrix (same process, same conditions)

func _measure(rid: RID, warmup: int, n: int) -> float:
	for i in warmup:
		await get_tree().process_frame
	var acc := 0.0
	for i in n:
		await get_tree().process_frame
		acc += RenderingServer.viewport_get_measured_render_time_gpu(rid)
	return acc / float(n)


## Toggles one feature at a time on top of a preset and prints the mean "GPU" time (lavapipe: relative only).
func _cost_matrix() -> void:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var e := env.environment
	var vp := get_viewport()
	var configs := [
		["day base (SSAO + PCSS 1.2 + MSAA 2x)", &"day", {}],
		["day sin PCSS", &"day", {"pcss": true}],
		["day sin SSAO", &"day", {"ssao": true}],
		["day sin MSAA", &"day", {"msaa": true}],
		["day + glow", &"day", {"glow": true}],
		["day + volumetrica 64/64", &"day", {"vol": true}],
		["day + SDFGI 4 cascadas", &"day", {"sdfgi": true}],
		["day + SSIL", &"day", {"ssil": true}],
		["noche base (glow, 2 omni con sombra, 3 spill con proyector)", &"night", {}],
		["noche sin sombras omni", &"night", {"omni_shadow": true}],
		["noche sin proyectores", &"night", {"cookie": true}],
		["ventisca base (volumetrica + 2200 particulas)", &"blizzard", {}],
		["ventisca sin volumetrica", &"blizzard", {"novol": true}],
	]
	var n := int(_argf("frames", 10.0))
	print("[cost] config | mean gpu ms (%d frames) | draw calls" % n)
	for c in configs:
		_apply_preset(c[1])
		var o: Dictionary = c[2]
		if o.has("pcss"):
			sun.light_angular_distance = 0.0
		if o.has("ssao"):
			e.ssao_enabled = false
		if o.has("msaa"):
			vp.msaa_3d = Viewport.MSAA_DISABLED
		if o.has("glow"):
			e.glow_enabled = true
			e.glow_intensity = 0.5
		if o.has("vol"):
			e.volumetric_fog_enabled = true
			e.volumetric_fog_density = 0.02
		if o.has("sdfgi"):
			e.sdfgi_enabled = true
			e.sdfgi_cascades = 4
			e.sdfgi_min_cell_size = 0.4
		if o.has("ssil"):
			e.ssil_enabled = true
		if o.has("omni_shadow"):
			lantern_light.shadow_enabled = false
			campfire_light.shadow_enabled = false
		if o.has("cookie"):
			for l in spill_lights:
				if l is SpotLight3D:
					(l as SpotLight3D).light_projector = null
		if o.has("novol"):
			e.volumetric_fog_enabled = false
		var ms: float = await _measure(rid, 6 if not o.has("sdfgi") else 30, n)
		print("[cost] %s | %.1f | %d" % [c[0], ms, RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
		# restore what _apply_preset does not reset
		vp.msaa_3d = Viewport.MSAA_2X
		lantern_light.shadow_enabled = not compat
		campfire_light.shadow_enabled = not compat
		e.sdfgi_enabled = false
		e.ssil_enabled = false
		if o.has("cookie"):
			var cookie := _make_projector()
			for l in spill_lights:
				if l is SpotLight3D:
					(l as SpotLight3D).light_projector = cookie
	get_tree().quit()
