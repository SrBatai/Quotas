extends SceneTree
## Art contract check (ASSET_SPEC v2): for every res://assets/models/*.glb prints the node tree and verifies
##   - every visual mesh has ≤ 2 surfaces (≤ 3 for vehicles): one `palette_vcol` with COLOR_0 + at most one
##     named exception (window, glass, ember, ice_clear, blood, emissive_*);
##   - the front anchors sit in local +Z (Vector3.MODEL_FRONT) and rear anchors in -Z;
##   - the required anchors (Placeholders.ANCHORS) exist, Col* are top-level StaticBody3D, no `.001` names;
##   - the player's ToolSocket points a tool's handle (+Y) forward (+Z), blade (+Z) up.
##   - chars/*.glb: GeneralSkeleton with the 27 humanoid bones/sockets (ASSET_SPEC v2 §4), one skinned palette_vcol mesh;
##   - anims/*.glb: AnimationLibrary with the loops of the LOCO table (names, durations, LOOP_LINEAR, hips position track);
##     M4: zombie_anims (ZOMBIE_TABLE) and humanoid_combat (COMBAT_TABLE): names, durations, loop flags, >= 20 rotation
##     tracks on %GeneralSkeleton, Hips position track;
##   - zombies/*.glb (M4): GeneralSkeleton with the 27 bones, Hips rest 0.80-1.00 m (body types), RightHandSocket on the
##     right, skinned meshes Body / Ice / Outfit_* with palette_vcol + COLOR_0, <= 2 500 tris;
##   - weapons/*.glb (M4, §12): Weapon + Grip at the origin, Tip up the handle (+Y) and not behind (+Z >= 0),
##     SupportGrip (two-handed) below the grip, extras weapon_class; gore/*.glb (M4): the generic mesh contract +
##     head_fragments = 6 Frag_n meshes.
## Run: godot --headless --path . -s tests/inspect_models.gd [++ --quiet] [--placeholders]
## --placeholders checks the primitive stand-ins (Placeholders.build) against the same contract instead of the .glb files.
## Ends with "ALL OK" (exit 0) or "N FAILURES" (exit 1).

const VCOL := "palette_vcol"
## Godot's glTF importer strips the legacy `_vcol` suffix: `palette_vcol` in the .glb imports as `palette`.
const VCOL_IMPORTED := ["palette_vcol", "palette"]
## Same list as Assets.EXCEPTION_MATERIALS (autoloads are not available to -s scripts at compile time).
const EXCEPTIONS := ["window", "glass", "ember", "ice_clear", "blood", "emissive_lamp"]
## Anchors that must be in front (+Z, name) or behind ("-Name" -> -Z) in the model's own frame.
const FRONT_ANCHORS := {
	"player": ["BreathAnchor"],
	"wolf": ["Muzzle"],
	"deer": ["Muzzle"],
	"cabin": ["DoorAnchor", "LanternSocket"],
	"wood_stove": ["StoveAnchor"],
	"signpost": ["TextTop", "TextBottom"],
	"pickup_truck": ["-BedAnchor"],
	"a_frame_cabin": [],
}
## Assets whose meshes may carry 3 surfaces (palette_vcol + glass + emissive_lamp).
const THREE_SURFACE_ASSETS := ["pickup_truck"]
## Assets with embedded collision (Col* StaticBody3D at the first level).
const COLLISION_ASSETS := ["cabin", "a_frame_cabin", "pickup_truck", "tent"]
## Humanoid skeleton contract (ASSET_SPEC v2 §4.1): 22 deform bones + 5 sockets.
const HUMANOID_BONES := ["Root", "Hips", "Spine", "Chest", "Neck", "Head", "LeftShoulder", "LeftUpperArm", "LeftLowerArm",
	"LeftHand", "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
	"RightHandSocket", "LeftHandSocket", "BackSocket", "HipSocketR", "HeadSocket"]
## Locomotion library (ASSET_SPEC v2 "M1 deviations"): name -> duration (s).
const LOCO_TABLE := {"Loco_Idle": 3.0, "Loco_Idle_Cold": 2.0, "Loco_Walk": 0.8, "Loco_Run": 0.667, "Crouch_Idle": 3.0, "Crouch_Walk": 1.0}
## M4 libraries (ASSET_SPEC v2 "M4"): clip (Godot name, `-loop` stripped) -> [duration s, looping].
const ZOMBIE_TABLE := {
	"Zom_Idle_A": [3.000, true], "Zom_Idle_B": [3.000, true], "Zom_Shamble_A": [1.200, true],
	"Zom_Shamble_B": [1.200, true], "Zom_Shamble_C": [1.200, true], "Zom_Shamble_D": [1.200, true],
	"Zom_Investigate": [1.200, true], "Zom_Alert": [0.600, false], "Zom_Attack_A": [1.000, false],
	"Zom_Attack_B": [1.000, false], "Zom_Grab": [1.000, true], "Zom_Knock_Door": [1.000, true],
	"Zom_Hit": [0.267, false], "Zom_Stagger": [0.600, false], "Zom_Knockdown": [0.800, false],
	"Zom_GetUp": [1.500, false], "Zom_Death_A": [0.800, false], "Zom_Death_B": [0.800, false],
	"Zom_Frozen_Idle": [4.000, true], "Zom_Wake": [1.500, false], "Zom_Run": [0.700, true],
	"Zom_Run_Tired": [0.800, true], "Zom_Crawl": [1.400, true], "Zom_Crawl_Grab": [0.800, false],
	"Zom_Crawl_Death": [0.800, false], "Zom_Walk_Heavy": [1.400, true], "Zom_Bloat_Pop": [0.500, false]
}
const COMBAT_TABLE := {
	"Melee1H_Light_A": [0.567, false], "Melee1H_Light_B": [0.567, false], "Melee2H_Swing_A": [0.900, false],
	"Melee2H_Swing_B": [0.900, false], "Melee_Charged": [1.300, false], "Act_Shove": [0.500, false],
	"Act_Stomp": [1.000, false], "Act_Execute": [1.500, false], "Act_Revive": [2.000, true],
	"Hit_Front": [0.267, false], "Hit_Back": [0.267, false], "Hit_Stagger": [0.600, false],
	"Hit_Grabbed": [1.000, true], "Down_Fall": [0.800, false], "Down_Idle": [2.000, true],
	"Down_Crawl": [1.200, true], "Down_Revived": [1.500, false], "Death_A": [0.500, false]
}
const ZOMBIE_BUDGET := 2500
const ZOMBIE_MESHES := ["Body", "Ice"]
## gore/*.glb triangle budgets (blender/props/build_gore.py GORE)
const GORE_BUDGET := {"corpse_covered": 800, "blood_splat_a": 150, "blood_splat_b": 150, "blood_splat_c": 150,
	"blood_trail": 200, "limb_arm": 300, "limb_leg": 300, "head_fragments": 400}

var _quiet: bool = false
var _placeholders: bool = false
var _failures: int = 0
var _anchors: Dictionary = {}  # Placeholders.ANCHORS, loaded at runtime (class dependencies need the autoloads)


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--quiet":
			_quiet = true
		elif a == "--placeholders":
			_placeholders = true
	var placeholders: GDScript = load("res://scripts/data/placeholders.gd")
	if placeholders != null:
		_anchors = placeholders.get_script_constant_map().get("ANCHORS", {})
	if _placeholders:
		_check_placeholders(placeholders)
		return
	var dir := DirAccess.open("res://assets/models")
	if dir == null:
		print("no models dir")
		quit(1)
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb"):
			files.append(f)
		f = dir.get_next()
	files.sort()
	var checked := 0
	for name in files:
		var path := "res://assets/models/" + name
		var asset := name.get_basename()
		if not ResourceLoader.exists(path, "PackedScene"):
			_fail(asset, "not imported yet (run godot --headless --import)")
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			_fail(asset, "cannot load")
			continue
		var inst := scene.instantiate()
		if not _quiet:
			print("== ", name)
			_dump(inst, 1)
		_check(asset, inst)
		checked += 1
		inst.free()
	checked += _check_chars()
	checked += _check_anims()
	checked += _check_zombies()
	checked += _check_subfolder("weapons")
	checked += _check_subfolder("gore")
	print("== inspect_models: %d assets, %s" % [checked, "ALL OK" if _failures == 0 else "%d FAILURES" % _failures])
	quit(0 if _failures == 0 else 1)


func _glbs(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".glb"):
			out.append(f)
		f = dir.get_next()
	out.sort()
	return out


## chars/*.glb: skeletal survivors (M1) and zombies (M2+).
func _check_chars() -> int:
	var n := 0
	for name in _glbs("res://assets/models/chars"):
		var asset := "chars/" + name.get_basename()
		var scene := load("res://assets/models/chars/" + name) as PackedScene
		if scene == null:
			_fail(asset, "cannot load")
			continue
		var inst := scene.instantiate()
		if not _quiet:
			print("== chars/", name)
			_dump(inst, 1)
		var problems: Array[String] = []
		var sk := inst.find_child("GeneralSkeleton", true, false) as Skeleton3D
		if sk == null:
			problems.append("no GeneralSkeleton (retarget bone map not applied)")
		else:
			for b in HUMANOID_BONES:
				if sk.find_bone(b) < 0:
					problems.append("bone %s missing" % b)
			if sk.get_bone_count() != HUMANOID_BONES.size():
				problems.append("%d bones, expected %d" % [sk.get_bone_count(), HUMANOID_BONES.size()])
			var socket := sk.find_bone("RightHandSocket")
			if socket >= 0 and sk.get_bone_global_rest(socket).origin.x > -0.5:
				problems.append("RightHandSocket at x=%.2f, expected on the right (-X) in the T-pose" % sk.get_bone_global_rest(socket).origin.x)
			var hips := sk.find_bone("Hips")
			if hips >= 0 and absf(sk.get_bone_global_rest(hips).origin.y - 0.92) > 0.03:
				problems.append("Hips rest at y=%.2f, expected 0.92" % sk.get_bone_global_rest(hips).origin.y)
		var skinned := 0
		var tris := 0
		for node in _all(inst):
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var mi := node as MeshInstance3D
				if mi.skin == null:
					problems.append("%s has no skin" % mi.name)
				skinned += 1
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i)
					var mname := m.resource_name if m != null else ""
					var has_color := bool(mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR)
					if not VCOL_IMPORTED.has(mname) or not has_color:
						problems.append("%s surface %d: expected palette_vcol with COLOR_0 (got '%s')" % [mi.name, i, mname])
					var arrays := mi.mesh.surface_get_arrays(i)
					var idx = arrays[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx is PackedInt32Array and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		if skinned == 0:
			problems.append("no skinned mesh")
		if problems.is_empty():
			print("OK   %-22s bones=%d skinned=%d tris=%d" % [asset, sk.get_bone_count() if sk != null else 0, skinned, tris])
		else:
			for p in problems:
				_fail(asset, p)
		inst.free()
		n += 1
	return n


## anims/*.glb: animation libraries consumed by character_visual.gd.
func _check_anims() -> int:
	var n := 0
	for name in _glbs("res://assets/models/anims"):
		var asset := "anims/" + name.get_basename()
		var lib := load("res://assets/models/anims/" + name) as AnimationLibrary
		if lib == null:
			_fail(asset, "not imported as an AnimationLibrary")
			continue
		var problems: Array[String] = []
		var table := {}
		if name.begins_with("humanoid_loco"):
			for an in LOCO_TABLE:
				table[an] = [LOCO_TABLE[an], true]
		elif name.begins_with("zombie_anims"):
			table = ZOMBIE_TABLE
		elif name.begins_with("humanoid_combat"):
			table = COMBAT_TABLE
		else:
			problems.append("no clip table for %s" % name)
		for an in table:
			if not lib.has_animation(an):
				problems.append("animation %s missing" % an)
				continue
			var a := lib.get_animation(an)
			if absf(a.length - float(table[an][0])) > 0.04:
				problems.append("%s lasts %.3f s, expected %.3f" % [an, a.length, float(table[an][0])])
			if bool(table[an][1]) and a.loop_mode != Animation.LOOP_LINEAR:
				problems.append("%s is not LOOP_LINEAR" % an)
			elif not bool(table[an][1]) and a.loop_mode != Animation.LOOP_NONE:
				problems.append("%s is a one-shot but loops" % an)
			var rot := 0
			var hips_pos := false
			for t in a.get_track_count():
				var path := String(a.track_get_path(t))
				if not path.begins_with("%GeneralSkeleton:"):
					problems.append("%s track %s is not on %%GeneralSkeleton" % [an, path])
				if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					rot += 1
				elif a.track_get_type(t) == Animation.TYPE_POSITION_3D and path.ends_with(":Hips"):
					hips_pos = true
			if rot < 20:
				problems.append("%s has %d rotation tracks (< 20)" % [an, rot])
			if not hips_pos:
				problems.append("%s has no Hips position track" % an)
		if problems.is_empty():
			print("OK   %-22s animations=%d" % [asset, lib.get_animation_list().size()])
		else:
			for p in problems:
				_fail(asset, p)
		n += 1
	return n


## zombies/*.glb (M4): skeletal zombies sharing the humanoid skeleton (body types change the Hips rest height).
func _check_zombies() -> int:
	var n := 0
	for name in _glbs("res://assets/models/zombies"):
		var asset := "zombies/" + name.get_basename()
		var scene := load("res://assets/models/zombies/" + name) as PackedScene
		if scene == null:
			_fail(asset, "cannot load")
			continue
		var inst := scene.instantiate()
		if not _quiet:
			print("== zombies/", name)
			_dump(inst, 1)
		var problems: Array[String] = []
		var sk := inst.find_child("GeneralSkeleton", true, false) as Skeleton3D
		if sk == null:
			problems.append("no GeneralSkeleton (retarget bone map not applied)")
		else:
			for b in HUMANOID_BONES:
				if sk.find_bone(b) < 0:
					problems.append("bone %s missing" % b)
			if sk.get_bone_count() != HUMANOID_BONES.size():
				problems.append("%d bones, expected %d" % [sk.get_bone_count(), HUMANOID_BONES.size()])
			var socket := sk.find_bone("RightHandSocket")
			if socket >= 0 and sk.get_bone_global_rest(socket).origin.x > -0.45:
				problems.append("RightHandSocket at x=%.2f, expected on the right (-X) in the T-pose" % sk.get_bone_global_rest(socket).origin.x)
			var hips := sk.find_bone("Hips")
			if hips >= 0:
				var hy := sk.get_bone_global_rest(hips).origin.y
				if hy < 0.80 or hy > 1.00:
					problems.append("Hips rest at y=%.2f, expected 0.80-1.00" % hy)
		var skinned := 0
		var tris := 0
		for node in _all(inst):
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var mi := node as MeshInstance3D
				if not ZOMBIE_MESHES.has(String(mi.name)) and not String(mi.name).begins_with("Outfit_"):
					problems.append("unexpected mesh %s" % mi.name)
				if mi.skin == null:
					problems.append("%s has no skin" % mi.name)
				skinned += 1
				for i in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(i)
					var mname := m.resource_name if m != null else ""
					var has_color := bool(mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR)
					if not VCOL_IMPORTED.has(mname) or not has_color:
						problems.append("%s surface %d: expected palette_vcol with COLOR_0 (got '%s')" % [mi.name, i, mname])
					var arrays := mi.mesh.surface_get_arrays(i)
					var idx = arrays[Mesh.ARRAY_INDEX]
					tris += (idx.size() if idx is PackedInt32Array and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
		if skinned == 0:
			problems.append("no skinned mesh")
		if tris > ZOMBIE_BUDGET:
			problems.append("%d tris > %d" % [tris, ZOMBIE_BUDGET])
		if problems.is_empty():
			print("OK   %-24s bones=%d skinned=%d tris=%d" % [asset, sk.get_bone_count() if sk != null else 0, skinned, tris])
		else:
			for p in problems:
				_fail(asset, p)
		inst.free()
		n += 1
	return n


## weapons/*.glb and gore/*.glb (M4): the generic mesh contract (_check) + family rules.
func _check_subfolder(folder: String) -> int:
	var n := 0
	for name in _glbs("res://assets/models/" + folder):
		var asset := folder + "/" + name.get_basename()
		var scene := load("res://assets/models/%s/%s" % [folder, name]) as PackedScene
		if scene == null:
			_fail(asset, "cannot load (run godot --headless --import)")
			continue
		var inst := scene.instantiate()
		if not _quiet:
			print("== ", asset)
			_dump(inst, 1)
		_check(asset, inst)
		var problems: Array[String] = []
		if folder == "weapons":
			var grip := inst.find_child("Grip", true, false) as Node3D
			var tip := inst.find_child("Tip", true, false) as Node3D
			var weapon := inst.find_child("Weapon", true, false)
			if grip == null or tip == null or weapon == null:
				problems.append("Weapon / Grip / Tip missing")
			else:
				if _model_pos(grip, inst).length() > 0.005:
					problems.append("Grip not at the origin (%s)" % _model_pos(grip, inst))
				var tp := _model_pos(tip, inst)
				if tp.y < 0.2 or tp.z < -0.02:
					problems.append("Tip at %s: expected up the handle (+Y) and toward the business end (+Z >= 0)" % tp)
				if not weapon.has_meta("extras") or not (weapon.get_meta("extras") as Dictionary).has("weapon_class"):
					problems.append("Weapon lacks the weapon_class extras")
			var support := inst.find_child("SupportGrip", true, false) as Node3D
			if support != null and _model_pos(support, inst).y > -0.03:
				problems.append("SupportGrip at %s: expected below the grip" % _model_pos(support, inst))
		elif folder == "gore":
			var tris := 0
			var meshes := 0
			for node in _all(inst):
				if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
					meshes += 1
					var mi := node as MeshInstance3D
					for i in mi.mesh.get_surface_count():
						var arrays := mi.mesh.surface_get_arrays(i)
						var idx = arrays[Mesh.ARRAY_INDEX]
						tris += (idx.size() if idx is PackedInt32Array and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			var budget := int(GORE_BUDGET.get(name.get_basename(), 400))
			if tris > budget:
				problems.append("%d tris > %d" % [tris, budget])
			if name.begins_with("head_fragments"):
				for k in 6:
					if inst.find_child("Frag_%d" % k, true, false) == null:
						problems.append("Frag_%d missing" % k)
			elif meshes != 1:
				problems.append("%d meshes (expected 1)" % meshes)
		for p in problems:
			_fail(asset, p)
		inst.free()
		n += 1
	return n


## Spawns every asset through Assets.spawn_model with force_placeholders (the real contract: anchors guaranteed).
func _check_placeholders(placeholders: GDScript) -> void:
	var assets: Node = root.get_node_or_null("Assets")  # autoload, resolved at runtime
	var names := _anchors.keys()
	names.sort()
	for asset in names:
		var inst: Node3D
		if assets != null:
			assets.set("force_placeholders", true)
			inst = assets.call("spawn_model", asset)
		else:
			inst = placeholders.call("build", asset)
		if not _quiet:
			print("== placeholder ", asset)
			_dump(inst, 1)
		_check(asset, inst)
		inst.free()
	print("== inspect_models (placeholders): %d assets, %s" % [names.size(), "ALL OK" if _failures == 0 else "%d FAILURES" % _failures])
	quit(0 if _failures == 0 else 1)


func _fail(asset: String, reason: String) -> void:
	_failures += 1
	print("FAIL %s: %s" % [asset, reason])


func _check(asset: String, root: Node) -> void:
	var problems: Array[String] = []
	var meshes := 0
	var surfaces := 0
	var tris := 0
	var max_surfaces := 3 if THREE_SURFACE_ASSETS.has(asset) else 2
	for n in _all(root):
		if "." in String(n.name) and String(n.name).find(".") > 0 and String(n.name).get_extension().is_valid_int():
			problems.append("name '%s' has a numeric suffix" % n.name)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			meshes += 1
			var count := mi.mesh.get_surface_count()
			surfaces += count
			if count > max_surfaces:
				problems.append("%s has %d surfaces (max %d)" % [mi.name, count, max_surfaces])
			var vcol := 0
			for i in count:
				var m := mi.mesh.surface_get_material(i)
				var mname := m.resource_name if m != null else ""
				var arrays := mi.mesh.surface_get_arrays(i)
				var idx = arrays[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx is PackedInt32Array and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
				var has_color := bool(mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR)
				if VCOL_IMPORTED.has(mname) or (m is ShaderMaterial and mname == "world_vcol"):
					vcol += 1
					if not has_color:
						problems.append("%s surface %d is palette_vcol without COLOR_0" % [mi.name, i])
				elif EXCEPTIONS.has(mname) or mname.begins_with("emissive_"):
					pass
				else:
					problems.append("%s surface %d uses v1 material '%s' (expected palette_vcol)" % [mi.name, i, mname])
			if vcol > 1:
				problems.append("%s has %d palette_vcol surfaces" % [mi.name, vcol])
		if String(n.name).begins_with("Col") and n is CollisionObject3D and n.get_parent() != root:
			problems.append("%s is not a first-level node" % n.name)
	# anchors
	if _anchors.has(asset):
		for entry in _anchors[asset]:
			if root.find_child(entry[0], true, false) == null:
				problems.append("anchor %s missing" % entry[0])
	for spec in FRONT_ANCHORS.get(asset, []):
		var behind := String(spec).begins_with("-")
		var aname := String(spec).trim_prefix("-")
		var a := root.find_child(aname, true, false)
		if a == null:
			continue
		var p := _model_pos(a as Node3D, root)
		if behind and p.z >= -0.05:
			problems.append("%s at z=%.2f, expected behind (-Z)" % [aname, p.z])
		elif not behind and p.z <= 0.05:
			problems.append("%s at z=%.2f, expected in front (+Z = MODEL_FRONT)" % [aname, p.z])
	if COLLISION_ASSETS.has(asset):
		var cols := 0
		for c in root.get_children():
			if String(c.name).begins_with("Col") and c is StaticBody3D:
				cols += 1
		if cols == 0:
			problems.append("no Col* StaticBody3D at the first level")
	if asset == "player":
		var socket := root.find_child("ToolSocket", true, false) as Node3D
		if socket != null:
			var xf := _model_xf(socket, root)
			var handle := xf.basis * Vector3(0, 1, 0)
			var blade := xf.basis * Vector3(0, 0, 1)
			if handle.z < 0.7:
				problems.append("ToolSocket local +Y (tool handle) is %s, expected forward (+Z)" % handle)
			if blade.y < 0.7:
				print("WARN player: ToolSocket local +Z (blade) is %s, expected up; ToolHolder rolls the tool" % blade)
	if asset == "signpost":
		var board := root.find_child("BoardTop", true, false) as MeshInstance3D
		if board != null and board.mesh != null and board.get_aabb().end.x < 0.8:
			problems.append("BoardTop tip at x=%.2f, expected pointing to +X" % board.get_aabb().end.x)
	if problems.is_empty():
		print("OK   %-14s meshes=%d surfaces=%d tris=%d" % [asset, meshes, surfaces, tris])
	else:
		for p in problems:
			_fail(asset, p)


func _all(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


static func _model_xf(n: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _model_pos(n: Node3D, root: Node) -> Vector3:
	return _model_xf(n, root).origin


func _dump(n: Node, depth: int) -> void:
	var info := n.name + " (" + n.get_class() + ")"
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var names := []
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			var tag := m.resource_name if m != null else "null"
			if mi.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR:
				tag += "+COLOR_0"
			names.append(tag)
		info += " aabb=" + str(mi.get_aabb()) + " mats=" + str(names)
	elif n is Node3D:
		info += " pos=" + str((n as Node3D).position)
		if (n as Node3D).rotation_degrees != Vector3.ZERO:
			info += " rot=" + str((n as Node3D).rotation_degrees)
	print("  ".repeat(depth), info)
	for c in n.get_children():
		_dump(c, depth + 1)
