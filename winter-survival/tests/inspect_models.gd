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
##   - T2 (ASSET_SPEC v2 "T2"): firearms / bow (weapon_class Pistol | LongGun | Bow): Grip at the origin, Muzzle in front
##     (+Z), SupportGrip, the moving / loose parts of FIREARM_PARTS, EjectPort on the shooter's right (-X), the documented
##     part motions (Cylinder rotation.z = -swing swings to +X, Bolt rotation.z = -lift raises the handle); arrow (Tip +Z)
##     and muzzle_flash (emissive, +Z); anims/humanoid_firearms (FIREARMS_TABLE); props/loot/*.glb: containers (root
##     mesh, Loot anchor, every hinged part opens with rotate_object_local(hinge_axis, open_deg): lids up, doors toward
##     +Z) and pickups (one mesh Item); world/*.glb (W1): MultiMesh props (one mesh + collision-proxy extras), tunnel
##     portals (Portal, Col* StaticBody3D at the first level, RoadIn in front, Panel + TextPanel), km signs.
##   - buildings/<style>/*.glb (M6a): the cut-ready kit (cut groups per storey, ShadowProxy + root metadata, no Y
##     offset on any piece, Door_n / Window_n / Spawn_* extras, template budget); signs/*.glb (M6a): mesh font + boards.
##   - city/<family>/*.glb (A1, ASSET_SPEC v2 "A1"): the generic mesh contract; root metadata copied by the
##     post-import script (city_import.gd); towers / buildings: Base, Shaft_<n> with floor_from, ShadowProxy above 12 m,
##     floor_h / ground_h / floors on the root and CityBuilding.validate() clean when that script exists; vehicles: Body
##     [+ Glass], root anchors (Loot, FuelCap), headlights in front (+Z) with Headlight_L on +X; props / highway: Prop,
##     LightPool on the ground under its LightAnchor, one TextPanel per Panel; AO alpha preserved; family budgets.
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
## T2 firearm library (blender/anims/build_firearms.py FIREARMS_TABLE).
const FIREARMS_TABLE := {
	"Pistol_Idle": [3.000, true], "Pistol_Aim": [2.000, true], "Pistol_Shoot": [0.200, false],
	"Pistol_Reload": [1.600, false], "Pistol_Reload_Revolver": [3.000, false], "LongGun_Idle": [3.000, true],
	"LongGun_Aim": [2.000, true], "LongGun_Shoot": [0.300, false], "LongGun_Shoot_Shotgun": [0.300, false],
	"LongGun_Pump": [0.600, false], "LongGun_Bolt_Rack": [1.000, false], "LongGun_Reload_Shell": [0.700, true],
	"LongGun_Reload_Bolt": [3.500, false], "LongGun_Reload_Mag": [2.200, false], "Act_Unjam": [1.500, false],
	"Act_Unjam_LongGun": [1.500, false], "Bow_Aim": [2.000, true], "Bow_Draw": [1.400, false],
	"Bow_Hold": [2.000, true], "Bow_Release": [0.300, false]
}
## T2 firearms: required part / anchor nodes per file (blender/lib/gunspec.py).
const FIREARM_PARTS := {
	"pistol": ["Slide", "Magazine", "EjectPort", "Sight"], "revolver": ["Cylinder", "Round", "Sight"],
	"shotgun": ["Pump", "Round", "EjectPort", "LoadPort", "Sight"],
	"rifle_hunting": ["Bolt", "Scope", "Round", "EjectPort", "Sight"],
	"bow": ["String", "StringDrawn", "Arrow", "DrawPoint"]
}
const WEAPON_BUDGET := 900
const LOOT_BUDGET := {"container": 1200, "pickup": 400}
const WORLD_BUDGET := {"rock": 1200, "snow": 500, "pole": 250, "rail": 700, "portal": 14000, "sign": 400}
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
	checked += _check_loot()
	checked += _check_world()
	checked += _check_city()
	checked += _check_kit()
	checked += _check_signs()
	checked += _check_village()
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
		elif name.begins_with("humanoid_firearms"):
			table = FIREARMS_TABLE
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
		var wclass := ""
		if folder == "weapons":
			var wmain := inst.find_child("Weapon", true, false)
			if wmain == null:
				wmain = inst.find_child("Arrow", true, false) if inst.find_child("Flash", true, false) == null else inst.find_child("Flash", true, false)
			if wmain != null and wmain.has_meta("extras"):
				wclass = String((wmain.get_meta("extras") as Dictionary).get("weapon_class", ""))
		if folder == "weapons" and wclass in ["Pistol", "LongGun", "Bow", "Ammo", "Fx"]:
			problems.append_array(_firearm_problems(name.get_basename(), wclass, inst))
		elif folder == "weapons":
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


## T2 firearms / bow / arrow / muzzle flash (ASSET_SPEC v2 "T2", blender/lib/gunspec.py).
func _firearm_problems(base: String, wclass: String, inst: Node) -> Array[String]:
	var problems: Array[String] = []
	var tris := _tris(inst)
	if tris > WEAPON_BUDGET:
		problems.append("%d tris > %d" % [tris, WEAPON_BUDGET])
	if wclass == "Ammo":
		var tip := inst.find_child("Tip", true, false) as Node3D
		var nock := inst.find_child("Nock", true, false) as Node3D
		if tip == null or nock == null or _model_pos(tip, inst).z <= 0.0 or _model_pos(nock, inst).z >= 0.0:
			problems.append("arrow: Tip must be at +Z (front), Nock at -Z")
		return problems
	if wclass == "Fx":
		var flash := inst.find_child("Flash", true, false) as MeshInstance3D
		if flash == null or flash.mesh == null:
			problems.append("Flash mesh missing")
		else:
			var m := flash.mesh.surface_get_material(0)
			if m == null or not String(m.resource_name).begins_with("emissive"):
				problems.append("Flash must use emissive_lamp")
			if flash.get_aabb().position.z < -0.01:
				problems.append("Flash must extend toward +Z from the muzzle")
		return problems
	var grip := inst.find_child("Grip", true, false) as Node3D
	var muzzle := inst.find_child("Muzzle", true, false) as Node3D
	var support := inst.find_child("SupportGrip", true, false) as Node3D
	if grip == null or muzzle == null or support == null:
		problems.append("Grip / Muzzle / SupportGrip missing")
		return problems
	if _model_pos(grip, inst).length() > 0.005:
		problems.append("Grip not at the origin")
	if _model_pos(muzzle, inst).z <= 0.02:
		problems.append("Muzzle at %s: expected in front (+Z)" % _model_pos(muzzle, inst))
	for n in FIREARM_PARTS.get(base, []):
		if inst.find_child(n, true, false) == null:
			problems.append("%s missing" % n)
	var eject := inst.find_child("EjectPort", true, false) as Node3D
	if eject != null and _model_pos(eject, inst).x >= 0.0:
		problems.append("EjectPort at %s: expected on the shooter's right (-X)" % _model_pos(eject, inst))
	var cyl := inst.find_child("Cylinder", true, false) as MeshInstance3D
	if cyl != null:
		var sw := float((cyl.get_meta("extras", {}) as Dictionary).get("swing_deg", 0.0))
		var c0 := (_model_xf(cyl, inst) * cyl.get_aabb().get_center())
		cyl.rotation.z = deg_to_rad(-sw)
		var c1 := (_model_xf(cyl, inst) * cyl.get_aabb().get_center())
		cyl.rotation.z = 0.0
		if sw < 45.0 or c1.x < c0.x + 0.02:
			problems.append("Cylinder rotation.z = -swing_deg does not swing it out to +X (%.3f -> %.3f)" % [c0.x, c1.x])
	var bolt := inst.find_child("Bolt", true, false) as MeshInstance3D
	if bolt != null:
		var lift := float((bolt.get_meta("extras", {}) as Dictionary).get("lift_deg", 0.0))
		var y0 := (_model_xf(bolt, inst) * bolt.get_aabb()).end.y
		bolt.rotation.z = deg_to_rad(-lift)
		var y1 := (_model_xf(bolt, inst) * bolt.get_aabb()).end.y
		bolt.rotation.z = 0.0
		if lift < 30.0 or y1 < y0 + 0.01:
			problems.append("Bolt rotation.z = -lift_deg does not raise the handle (%.3f -> %.3f)" % [y0, y1])
	var draw := inst.find_child("DrawPoint", true, false) as Node3D
	if draw != null and _model_pos(draw, inst).z > _model_pos(support, inst).z - 0.3:
		problems.append("DrawPoint must be >= 0.3 m behind (-Z) the SupportGrip")
	return problems


func _tris(root: Node) -> int:
	var tris := 0
	for node in _all(root):
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(i)
				var idx = arrays[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx is PackedInt32Array and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return tris


func _load_scene(asset: String, path: String) -> Node:
	var scene := load(path) as PackedScene
	if scene == null:
		_fail(asset, "cannot load (run godot --headless --import)")
		return null
	var inst := scene.instantiate()
	if not _quiet:
		print("== ", asset)
		_dump(inst, 1)
	_check(asset, inst)
	return inst


## props/loot/*.glb (T2): containers with hinged parts + Loot anchor, ground pickups (one mesh Item).
func _check_loot() -> int:
	var n := 0
	for name in _glbs("res://assets/models/props/loot"):
		var asset := "props/loot/" + name.get_basename()
		var inst := _load_scene(asset, "res://assets/models/props/loot/" + name)
		if inst == null:
			continue
		var problems: Array[String] = []
		var tris := _tris(inst)
		var item := inst.find_child("Item", true, false)
		if item != null:
			var meshes := 0
			for node in _all(inst):
				if node is MeshInstance3D:
					meshes += 1
			if meshes != 1:
				problems.append("pickup: %d meshes (expected the single Item)" % meshes)
			if not (item.get_meta("extras", {}) as Dictionary).has("col_size"):
				problems.append("Item lacks the col_size extras")
			if tris > int(LOOT_BUDGET["pickup"]):
				problems.append("%d tris > %d" % [tris, LOOT_BUDGET["pickup"]])
		else:
			var loot := inst.find_child("Loot", true, false) as Node3D
			if loot == null:
				problems.append("Loot anchor missing")
			if tris > int(LOOT_BUDGET["container"]):
				problems.append("%d tris > %d" % [tris, LOOT_BUDGET["container"]])
			var parts := 0
			for node in _all(inst):
				if not (node is MeshInstance3D):
					continue
				var ex: Dictionary = node.get_meta("extras", {})
				if not ex.has("hinge_axis"):
					continue
				parts += 1
				var mi := node as MeshInstance3D
				var ax: Array = ex["hinge_axis"]
				var axis := Vector3(float(ax[0]), float(ax[1]), float(ax[2]))
				var c0 := _model_xf(mi, inst) * mi.get_aabb().get_center()
				var keep := mi.transform
				mi.rotate_object_local(axis, deg_to_rad(float(ex.get("open_deg", 0.0))))
				var c1 := _model_xf(mi, inst) * mi.get_aabb().get_center()
				mi.transform = keep
				if absf(axis.y) > 0.9:
					if c1.z < c0.z + 0.05:
						problems.append("%s does not open toward the front (+Z): %.2f -> %.2f" % [mi.name, c0.z, c1.z])
				elif c1.y < c0.y + 0.03:
					problems.append("%s does not open upward: %.2f -> %.2f" % [mi.name, c0.y, c1.y])
			if parts == 0:
				problems.append("no hinged part (Lid / Door / Flap with hinge_axis extras)")
		if problems.is_empty():
			print("OK   %-30s tris=%d" % [asset, tris])
		for p in problems:
			_fail(asset, p)
		inst.free()
		n += 1
	return n


## world/*.glb (T2, W1 props): MultiMesh props, tunnel portals, kilometre signs.
func _check_world() -> int:
	var n := 0
	for name in _glbs("res://assets/models/world"):
		var asset := "world/" + name.get_basename()
		var inst := _load_scene(asset, "res://assets/models/world/" + name)
		if inst == null:
			continue
		var problems: Array[String] = []
		var tris := _tris(inst)
		var budget := 0
		if inst.get_node_or_null("Portal") != null:
			budget = int(WORLD_BUDGET["portal"])
			var cols := 0
			for c in inst.get_children():
				if String(c.name).begins_with("Col") and c is StaticBody3D:
					cols += 1
			if cols < 10:
				problems.append("%d Col* StaticBody3D at the first level (expected >= 10)" % cols)
			var road := inst.find_child("RoadIn", true, false) as Node3D
			if road == null or _model_pos(road, inst).z <= 0.0:
				problems.append("RoadIn missing / not in front of the portal (+Z)")
			for k in ["road_width", "clearance", "depth", "blocked", "carve"]:
				if not (inst.get_node("Portal").get_meta("extras", {}) as Dictionary).has(k):
					problems.append("Portal extras lack %s" % k)
		elif inst.get_node_or_null("Prop") != null:
			budget = int(WORLD_BUDGET["sign"])
			var panel := inst.get_node_or_null("Panel") as MeshInstance3D
			var text := inst.get_node_or_null("TextPanel") as Node3D
			if panel == null or text == null:
				problems.append("Panel / TextPanel missing")
			elif _model_pos(text, inst).z <= (_model_xf(panel, inst) * panel.get_aabb()).end.z - 0.001:
				problems.append("TextPanel not in front (+Z) of the Panel")
		else:
			var meshes: Array[Node] = []
			for c in _all(inst):
				if c is MeshInstance3D:
					meshes.append(c)
			if meshes.size() != 1 or inst.get_child_count() != 1 or meshes[0].get_child_count() != 0:
				problems.append("MultiMesh prop must be exactly one mesh without children")
			else:
				var ex: Dictionary = meshes[0].get_meta("extras", {})
				for k in ["family", "col", "col_center", "col_size", "height", "radius"]:
					if not ex.has(k):
						problems.append("extras lack %s" % k)
				budget = int(WORLD_BUDGET.get(String(ex.get("family", "rock")), 1200))
		if budget > 0 and tris > budget:
			problems.append("%d tris > %d" % [tris, budget])
		if problems.is_empty():
			print("OK   %-30s tris=%d" % [asset, tris])
		for p in problems:
			_fail(asset, p)
		inst.free()
		n += 1
	return n


## city/<family>/*.glb (A1): winterized CC0 city set. Budgets in triangles (all parts).
const CITY_BUDGET := {"towers": 16000, "buildings": 12000, "vehicles": 8000, "props": 1500, "highway": 4000}


func _check_city() -> int:
	var n := 0
	var cb: GDScript = null
	if ResourceLoader.exists("res://scripts/world/city/city_building.gd"):
		cb = load("res://scripts/world/city/city_building.gd")
	for fam in CITY_BUDGET:
		for name in _glbs("res://assets/models/city/" + fam):
			var asset := "city/%s/%s" % [fam, name.get_basename()]
			var scene := load("res://assets/models/city/%s/%s" % [fam, name]) as PackedScene
			if scene == null:
				_fail(asset, "cannot load (run godot --headless --import)")
				continue
			var inst := scene.instantiate() as Node3D
			if not _quiet:
				print("== ", asset)
				_dump(inst, 1)
			_check(asset, inst)
			var problems: Array[String] = []
			var tris := 0
			var ao_min := 1.0
			for node in _all(inst):
				if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
					var mi := node as MeshInstance3D
					for i in mi.mesh.get_surface_count():
						var arrays := mi.mesh.surface_get_arrays(i)
						var idx = arrays[Mesh.ARRAY_INDEX]
						tris += (idx.size() if idx is PackedInt32Array and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
						var cols = arrays[Mesh.ARRAY_COLOR]
						if cols is PackedColorArray:
							for c in cols:
								ao_min = minf(ao_min, c.a)
			if tris > int(CITY_BUDGET[fam]):
				problems.append("%d tris > %d" % [tris, CITY_BUDGET[fam]])
			if ao_min > 0.9:
				problems.append("no baked AO in COLOR.a (min alpha %.2f)" % ao_min)
			if fam == "towers" or fam == "buildings":
				if inst.get_node_or_null("Base") == null:
					problems.append("Base missing")
				for k in ["floor_h", "ground_h", "floors", "kind"]:
					if not inst.has_meta(k):
						problems.append("root meta %s missing (post-import script not applied?)" % k)
				for c in inst.get_children():
					if String(c.name).begins_with("Shaft_") and not (c.get_meta("extras", {}) as Dictionary).has("floor_from"):
						problems.append("%s lacks floor_from" % c.name)
				if fam == "towers" and inst.get_node_or_null("ShadowProxy") == null:
					problems.append("ShadowProxy missing")
				if cb != null:
					for p in cb.call("validate", inst, true):
						problems.append("CityBuilding.validate: %s" % p)
			elif fam == "vehicles":
				if inst.get_node_or_null("Body") == null:
					problems.append("Body missing")
				var anchors: Dictionary = inst.get_meta("anchors", {})
				for k in ["Loot", "FuelCap"]:
					if not anchors.has(k) or inst.find_child(k, true, false) == null:
						problems.append("anchor %s missing" % k)
				var hl := inst.find_child("Headlight_L", true, false) as Node3D
				if hl != null:
					var p := _model_pos(hl, inst)
					if p.z <= 0.0 or p.x <= 0.0:
						problems.append("Headlight_L at %s: expected in front (+Z) on the left (+X)" % p)
			else:
				if inst.get_node_or_null("Prop") == null:
					problems.append("Prop missing")
				var panels := 0
				var texts := 0
				for c in inst.get_children():
					var cn := String(c.name)
					if cn.begins_with("Panel"):
						panels += 1
					elif cn.begins_with("TextPanel"):
						texts += 1
					elif cn.begins_with("LightPool"):
						var la := inst.get_node_or_null(cn.replace("LightPool", "LightAnchor")) as Node3D
						var lp := (c as Node3D).position
						if la == null or absf(lp.y) > 0.05 or Vector2(la.position.x - lp.x, la.position.z - lp.z).length() > 1.5:
							problems.append("%s not on the ground near its LightAnchor" % cn)
				if panels != texts:
					problems.append("%d Panel meshes, %d TextPanel anchors" % [panels, texts])
			if problems.is_empty():
				print("OK   %-34s tris=%d ao_min=%.2f" % [asset, tris, ao_min])
			for p in problems:
				_fail(asset, p)
			inst.free()
			n += 1
	return n


## buildings/<style>/*.glb (M6a, ASSET_SPEC v2 §8.4 + "M6a"): the cut-ready kit buildings. Generic mesh contract +
## the cut groups (Floor<k> with floor_z, Walls<k>_{N,S,E,W} + _Stub, Interior<k>, Roof), ShadowProxy with the root
## metadata (floors, floor_h, ground_h, foundation, kind, enterable), no piece with a Y offset (the corte urbano shader
## takes the building base from each piece's origin: groups, panes AND door leaves), Door_n / Window_n / Spawn_*
## extras, Col* StaticBody3D at the first level, baked AO, the template budget (data/buildings/templates/<id>.json).
func _check_kit() -> int:
	var n := 0
	for style in ["wood_blue", "brick", "concrete", "sheet_metal"]:
		for name in _glbs("res://assets/models/buildings/" + style):
			var asset := "buildings/%s/%s" % [style, name.get_basename()]
			var inst := _load_scene(asset, "res://assets/models/buildings/%s/%s" % [style, name])
			if inst == null:
				continue
			var problems: Array[String] = []
			var tpl_path := "res://data/buildings/templates/%s.json" % name.get_basename()
			var tpl: Dictionary = {}
			if FileAccess.file_exists(tpl_path):
				var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(tpl_path))
				if v is Dictionary:
					tpl = v
			else:
				problems.append("no template %s" % tpl_path)
			var floors := int(tpl.get("floors", 1))
			var proxy := inst.get_node_or_null("ShadowProxy")
			if proxy == null:
				problems.append("ShadowProxy missing")
			else:
				var ex: Dictionary = proxy.get_meta("extras", {})
				for k in ["floors", "floor_h", "ground_h", "foundation", "kind", "enterable"]:
					if not ex.has(k):
						problems.append("ShadowProxy extras lack %s" % k)
				if int(ex.get("floors", -1)) != floors:
					problems.append("ShadowProxy floors %s != template %d" % [ex.get("floors"), floors])
			for k in floors:
				var fl := inst.get_node_or_null("Floor%d" % k)
				if fl == null or inst.get_node_or_null("Interior%d" % k) == null:
					problems.append("Floor%d / Interior%d missing" % [k, k])
				elif absf(float((fl.get_meta("extras", {}) as Dictionary).get("floor_z", -1.0)) - (0.3 + 3.0 * k)) > 0.001:
					problems.append("Floor%d floor_z != %.1f" % [k, 0.3 + 3.0 * k])
				for d in ["N", "S", "E", "W"]:
					if inst.get_node_or_null("Walls%d_%s" % [k, d]) == null or inst.get_node_or_null("Walls%d_%s_Stub" % [k, d]) == null:
						problems.append("Walls%d_%s (+ _Stub) missing" % [k, d])
			if inst.get_node_or_null("Roof") == null:
				problems.append("Roof missing")
			var ao_min := 1.0
			for c in inst.get_children():
				var cn := String(c.name)
				if cn.begins_with("Col"):
					if not (c is StaticBody3D):
						problems.append("%s is not a StaticBody3D" % cn)
					continue
				if not cn.begins_with("Spawn_") and c is Node3D and absf((c as Node3D).position.y) > 0.001:
					problems.append("%s has a Y offset %.3f (pieces keep the building base at y = 0)" % [cn, (c as Node3D).position.y])
				var ex: Dictionary = c.get_meta("extras", {})
				if cn.begins_with("Door_"):
					for k in ["kind", "exterior", "cut_group", "floor", "hinge", "width"]:
						if not ex.has(k):
							problems.append("%s extras lack %s" % [cn, k])
					if inst.get_node_or_null(String(ex.get("cut_group", ""))) == null:
						problems.append("%s cut_group %s is not a node" % [cn, ex.get("cut_group")])
				elif cn.begins_with("Window_"):
					var mi := c as MeshInstance3D
					if mi == null or mi.mesh == null or mi.mesh.get_surface_count() != 1 or mi.mesh.surface_get_material(0) == null \
							or mi.mesh.surface_get_material(0).resource_name != "window":
						problems.append("%s must be one `window` surface" % cn)
					if inst.get_node_or_null(String(ex.get("cut_group", ""))) == null:
						problems.append("%s cut_group is not a node" % cn)
				elif cn.begins_with("Spawn_Container_") and not ex.has("table"):
					problems.append("%s lacks the loot table" % cn)
				elif cn.begins_with("Spawn_Sign_"):
					for k in ["sign", "width", "cap", "cut_group"]:
						if not ex.has(k):
							problems.append("%s extras lack %s" % [cn, k])
				if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and cn != "ShadowProxy" and not cn.begins_with("Window_"):
					var mi2 := c as MeshInstance3D
					for i in mi2.mesh.get_surface_count():
						var cols = mi2.mesh.surface_get_arrays(i)[Mesh.ARRAY_COLOR]
						if cols is PackedColorArray:
							for col in cols:
								ao_min = minf(ao_min, col.a)
			if ao_min > 0.9:
				problems.append("no baked AO in COLOR.a (min alpha %.2f)" % ao_min)
			var tris := _tris(inst)
			var budget := int(tpl.get("budget", 14000))
			if tris > budget + 400:   # + the ShadowProxy (12-400 tris, not drawn)
				problems.append("%d tris > budget %d" % [tris, budget])
			if problems.is_empty():
				print("OK   %-40s tris=%d floors=%d ao_min=%.2f" % [asset, tris, floors, ao_min])
			for p in problems:
				_fail(asset, p)
			inst.free()
			n += 1
	return n


## props/village/*.glb (M6b): the village / POI props — the A1 prop contract, MultiMesh-friendly: one mesh `Prop`
## (one surface, no children), extras family "village", kind, col / col_center / col_size (+ cols, anchors), the
## manifest entry, ≤ 1 800 tris; lamps carry LightAnchor, power poles WireA / WireB, the dumpster Loot.
func _check_village() -> int:
	var n := 0
	var man: Dictionary = {}
	if FileAccess.file_exists("res://assets/models/props/village/manifest.json"):
		man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/props/village/manifest.json"))
	for name in _glbs("res://assets/models/props/village"):
		var asset := "props/village/" + name.get_basename()
		var inst := _load_scene(asset, "res://assets/models/props/village/" + name)
		if inst == null:
			continue
		var problems: Array[String] = []
		var tris := _tris(inst)
		var prop := inst.get_node_or_null("Prop") as MeshInstance3D
		if prop == null or inst.get_child_count() != 1 or prop.get_child_count() != 0 or prop.mesh == null:
			problems.append("must be exactly one mesh Prop without children")
		else:
			if prop.mesh.get_surface_count() != 1:
				problems.append("%d surfaces (1)" % prop.mesh.get_surface_count())
			var ex: Dictionary = prop.get_meta("extras", {})
			for k in ["family", "kind", "col", "col_center", "col_size", "height", "anchors", "cols"]:
				if not ex.has(k):
					problems.append("extras lack %s" % k)
			var need := {"lamp_post": "LightAnchor", "power_pole": "WireA", "dumpster": "Loot"}.get(name.get_basename(), "") as String
			if need != "" and not (ex.get("anchors", {}) as Dictionary).has(need):
				problems.append("anchor %s missing" % need)
			var rec: Dictionary = man.get(name.get_basename(), {})
			if rec.is_empty() or int(rec.get("tris", -1)) != tris or str(rec.get("col", "")) != str(ex.get("col", "?")):
				problems.append("manifest entry missing / differs (tris %d)" % tris)
		if tris > 1800:
			problems.append("%d tris > 1800" % tris)
		if problems.is_empty():
			print("OK   %-30s tris=%d" % [asset, tris])
		for p in problems:
			_fail(asset, p)
		inst.free()
		n += 1
	return n


## signs/*.glb (M6a): the mesh font (G_<codepoint> meshes with extras char / advance, cap height 1) and the boards
## (Prop + Panel + TextPanel_<n>, extras text_w / text_h >= 0.30 m / colours; TextPanel_0 in front of the Panel).
func _check_signs() -> int:
	var n := 0
	for name in _glbs("res://assets/models/signs"):
		var asset := "signs/" + name.get_basename()
		var inst := _load_scene(asset, "res://assets/models/signs/" + name)
		if inst == null:
			continue
		var problems: Array[String] = []
		if name.begins_with("glyphs"):
			var glyphs := 0
			for c in inst.get_children():
				var ex: Dictionary = c.get_meta("extras", {})
				if not String(c.name).begins_with("G_") or not (c is MeshInstance3D) or not ex.has("advance") or not ex.has("char"):
					problems.append("%s: not a glyph mesh with char / advance" % c.name)
				else:
					glyphs += 1
			var h := inst.get_node_or_null("G_72") as MeshInstance3D
			if h == null or absf(h.get_aabb().end.y - 1.0) > 0.01:
				problems.append("cap height: the H glyph must span y 0..1")
			if glyphs < 40:
				problems.append("only %d glyphs" % glyphs)
		else:
			var prop := inst.get_node_or_null("Prop")
			var panel := inst.get_node_or_null("Panel") as MeshInstance3D
			var t0 := inst.get_node_or_null("TextPanel_0") as Node3D
			if prop == null or panel == null or t0 == null:
				problems.append("Prop / Panel / TextPanel_0 missing")
			else:
				var ex: Dictionary = prop.get_meta("extras", {})
				for k in ["text_w", "text_h", "text_color", "plate_color", "double_sided", "mount", "col"]:
					if not ex.has(k):
						problems.append("Prop extras lack %s" % k)
				if float(ex.get("text_h", 0.0)) < 0.3:
					problems.append("text_h < 0.30 m (doc 10 §7.4)")
				if t0.position.z <= (panel.transform * panel.get_aabb()).end.z - 0.001:
					problems.append("TextPanel_0 not in front (+Z) of the Panel")
				if bool(ex.get("double_sided", false)) and inst.get_node_or_null("TextPanel_1") == null:
					problems.append("double-sided without TextPanel_1")
		if problems.is_empty():
			print("OK   %-30s tris=%d" % [asset, _tris(inst)])
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
