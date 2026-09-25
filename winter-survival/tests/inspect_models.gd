extends SceneTree
## Art contract check (ASSET_SPEC v2): for every res://assets/models/*.glb prints the node tree and verifies
##   - every visual mesh has ≤ 2 surfaces (≤ 3 for vehicles): one `palette_vcol` with COLOR_0 + at most one
##     named exception (window, glass, ember, ice_clear, blood, emissive_*);
##   - the front anchors sit in local +Z (Vector3.MODEL_FRONT) and rear anchors in -Z;
##   - the required anchors (Placeholders.ANCHORS) exist, Col* are top-level StaticBody3D, no `.001` names;
##   - the player's ToolSocket points a tool's handle (+Y) forward (+Z), blade (+Z) up.
##   - chars/*.glb: GeneralSkeleton with the 27 humanoid bones/sockets (ASSET_SPEC v2 §4), one skinned palette_vcol mesh;
##   - anims/*.glb: AnimationLibrary with the loops of the LOCO table (names, durations, LOOP_LINEAR, hips position track).
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
		var table := LOCO_TABLE if name.begins_with("humanoid_loco") else {}
		for an in table:
			if not lib.has_animation(an):
				problems.append("animation %s missing" % an)
				continue
			var a := lib.get_animation(an)
			if absf(a.length - float(table[an])) > 0.04:
				problems.append("%s lasts %.3f s, expected %.3f" % [an, a.length, float(table[an])])
			if a.loop_mode != Animation.LOOP_LINEAR:
				problems.append("%s is not LOOP_LINEAR" % an)
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
