class_name Placeholders
## Primitive stand-ins for every asset in ASSET_SPEC v2, with identical node names and anchors.
## Godot coords: Blender (x, y, z) -> (x, z, -y). Front = +Z (Vector3.MODEL_FRONT), character right = -X.
## The part builders below are still written with the slice's -Z front; build() turns every fronted asset
## 180° about Y (meshes through MeshBuilder.yaw180, nodes through _yaw180_nodes) so the result is v2.

## Assets with a front: built in the old frame and turned 180° at the end of build().
const FRONT_FACING := ["player", "wolf", "deer", "cabin", "wood_stove", "cabinet", "bed", "desk", "chair", "shelf",
	"a_frame_cabin", "pickup_truck", "tent"]

## Anchor table (v2 frame): asset -> [ [node, parent ("" = root), position, rotation_degrees], ... ]
const ANCHORS := {
	"player": [
		["Hips", "", Vector3(0, 0.80, 0), Vector3.ZERO],
		["Torso", "Hips", Vector3.ZERO, Vector3.ZERO],
		["Head", "Torso", Vector3(0, 0.56, 0), Vector3.ZERO],
		["BreathAnchor", "Head", Vector3(0, 0.16, 0.20), Vector3.ZERO],
		["ArmL", "Torso", Vector3(0.36, 0.52, 0), Vector3.ZERO],
		["ArmR", "Torso", Vector3(-0.36, 0.52, 0), Vector3.ZERO],
		["ToolSocket", "ArmR", Vector3(0, -0.52, 0.05), Vector3(-90, 180, 0)],
		["LegL", "Hips", Vector3(0.12, 0, 0), Vector3.ZERO],
		["LegR", "Hips", Vector3(-0.12, 0, 0), Vector3.ZERO],
	],
	"wolf": [
		["Body", "", Vector3(0, 0.55, 0), Vector3.ZERO],
		["Head", "Body", Vector3(0, 0.07, 0.45), Vector3.ZERO],
		["Muzzle", "Head", Vector3(0, -0.04, 0.48), Vector3.ZERO],
		["Tail", "Body", Vector3(0, 0.07, -0.45), Vector3.ZERO],
		["LegFL", "Body", Vector3(0.13, -0.13, 0.30), Vector3.ZERO],
		["LegFR", "Body", Vector3(-0.13, -0.13, 0.30), Vector3.ZERO],
		["LegBL", "Body", Vector3(0.13, -0.13, -0.30), Vector3.ZERO],
		["LegBR", "Body", Vector3(-0.13, -0.13, -0.30), Vector3.ZERO],
	],
	"deer": [
		["Body", "", Vector3(0, 0.90, 0), Vector3.ZERO],
		["Head", "Body", Vector3(0, 0.10, 0.60), Vector3.ZERO],
		["Muzzle", "Head", Vector3(0, 0.35, 0.45), Vector3.ZERO],
		["Tail", "Body", Vector3(0, 0.15, -0.55), Vector3.ZERO],
		["LegFL", "Body", Vector3(0.14, -0.20, 0.42), Vector3.ZERO],
		["LegFR", "Body", Vector3(-0.14, -0.20, 0.42), Vector3.ZERO],
		["LegBL", "Body", Vector3(0.14, -0.20, -0.42), Vector3.ZERO],
		["LegBR", "Body", Vector3(-0.14, -0.20, -0.42), Vector3.ZERO],
	],
	"pine_a": [["Tree", "", Vector3.ZERO, Vector3.ZERO]],
	"pine_b": [["Tree", "", Vector3.ZERO, Vector3.ZERO]],
	"pine_c": [["Tree", "", Vector3.ZERO, Vector3.ZERO]],
	"dead_tree": [["Tree", "", Vector3.ZERO, Vector3.ZERO]],
	"stump": [["Stump", "", Vector3.ZERO, Vector3.ZERO]],
	"rock_a": [["Rock", "", Vector3.ZERO, Vector3.ZERO]],
	"rock_b": [["Rock", "", Vector3.ZERO, Vector3.ZERO]],
	"rock_c": [["Rock", "", Vector3.ZERO, Vector3.ZERO]],
	"stone": [["Stone", "", Vector3.ZERO, Vector3.ZERO]],
	"firewood": [["Firewood", "", Vector3.ZERO, Vector3.ZERO]],
	"fallen_log": [["Log", "", Vector3.ZERO, Vector3.ZERO]],
	"berry_bush": [["Bush", "", Vector3.ZERO, Vector3.ZERO], ["Berries", "Bush", Vector3.ZERO, Vector3.ZERO]],
	"campfire": [["Stones", "", Vector3.ZERO, Vector3.ZERO], ["Logs", "", Vector3.ZERO, Vector3.ZERO],
		["FlameAnchor", "", Vector3(0, 0.18, 0), Vector3.ZERO]],
	"stone_axe": [["Handle", "", Vector3.ZERO, Vector3.ZERO], ["Blade", "", Vector3.ZERO, Vector3.ZERO]],
	"torch": [["Handle", "", Vector3.ZERO, Vector3.ZERO], ["Head", "", Vector3.ZERO, Vector3.ZERO],
		["FlameAnchor", "", Vector3(0, 0.54, 0), Vector3.ZERO]],
	"cabin": [
		["Floor", "", Vector3.ZERO, Vector3.ZERO], ["WallFront", "", Vector3.ZERO, Vector3.ZERO],
		["WindowsFront", "WallFront", Vector3.ZERO, Vector3.ZERO], ["WallBack", "", Vector3.ZERO, Vector3.ZERO],
		["WallLeft", "", Vector3.ZERO, Vector3.ZERO], ["WindowsLeft", "WallLeft", Vector3.ZERO, Vector3.ZERO],
		["WallRight", "", Vector3.ZERO, Vector3.ZERO], ["Roof", "", Vector3.ZERO, Vector3.ZERO],
		["Chimney", "", Vector3.ZERO, Vector3.ZERO], ["Porch", "", Vector3.ZERO, Vector3.ZERO],
		["DoorAnchor", "", Vector3(0.9, 0.30, 3.2), Vector3.ZERO],
		["LanternSocket", "", Vector3(1.6, 2.35, 4.3), Vector3.ZERO],
	],
	"wood_stove": [["Body", "", Vector3.ZERO, Vector3.ZERO], ["Door", "", Vector3.ZERO, Vector3.ZERO],
		["Pipe", "", Vector3.ZERO, Vector3.ZERO], ["StoveAnchor", "", Vector3(0, 0.45, 0.35), Vector3.ZERO],
		["PipeTop", "", Vector3(0, 2.70, -0.15), Vector3.ZERO]],
	"cabinet": [["Cabinet", "", Vector3.ZERO, Vector3.ZERO]],
	"bed": [["Bed", "", Vector3.ZERO, Vector3.ZERO]],
	"desk": [["Desk", "", Vector3.ZERO, Vector3.ZERO]],
	"chair": [["Chair", "", Vector3.ZERO, Vector3.ZERO]],
	"shelf": [["Shelf", "", Vector3.ZERO, Vector3.ZERO]],
	"clock": [["Clock", "", Vector3.ZERO, Vector3.ZERO], ["HourHand", "", Vector3(0, 0, 0.07), Vector3.ZERO],
		["MinuteHand", "", Vector3(0, 0, 0.075), Vector3.ZERO]],
	"a_frame_cabin": [["Body", "", Vector3.ZERO, Vector3.ZERO], ["Front", "", Vector3.ZERO, Vector3.ZERO],
		["WindowsFront", "Front", Vector3.ZERO, Vector3.ZERO], ["Deck", "", Vector3.ZERO, Vector3.ZERO]],
	"pickup_truck": [["Body", "", Vector3.ZERO, Vector3.ZERO], ["Wheels", "", Vector3.ZERO, Vector3.ZERO],
		["Snow", "", Vector3.ZERO, Vector3.ZERO], ["BedAnchor", "", Vector3(0, 1.0, -1.35), Vector3.ZERO]],
	"signpost": [["Post", "", Vector3.ZERO, Vector3.ZERO],
		["BoardTop", "", Vector3(0, 1.84, 0), Vector3.ZERO], ["BoardBottom", "", Vector3(0, 1.44, 0), Vector3.ZERO],
		["TextTop", "BoardTop", Vector3(0.28, 0, 0.125), Vector3.ZERO],
		["TextBottom", "BoardBottom", Vector3(0.28, 0, 0.125), Vector3.ZERO]],
	"fence": [["Fence", "", Vector3.ZERO, Vector3.ZERO]],
	"lantern": [["Lantern", "", Vector3.ZERO, Vector3.ZERO], ["LightAnchor", "", Vector3(0, -0.23, 0), Vector3.ZERO]],
	"tent": [["Tent", "", Vector3.ZERO, Vector3.ZERO]],
	"storage_box": [["Box", "", Vector3.ZERO, Vector3.ZERO]],
}

static var _mesh_cache: Dictionary = {}
## True while a FRONT_FACING asset is being built (MeshBuilder.yaw180 for every mesh made meanwhile).
static var _flip: bool = false


static func build(asset_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = asset_name.to_pascal_case()
	_flip = FRONT_FACING.has(asset_name)
	_build_parts(root, asset_name)
	if _flip:
		_yaw180_nodes(root)
	_flip = false
	return root


static func _build_parts(root: Node3D, asset_name: String) -> void:
	match asset_name:
		"player": _build_player(root)
		"wolf": _build_quadruped(root, false)
		"deer": _build_quadruped(root, true)
		"pine_a", "pine_b", "pine_c": _mesh_node(root, "Tree", asset_name)
		"dead_tree": _mesh_node(root, "Tree", asset_name)
		"stump": _mesh_node(root, "Stump", asset_name)
		"rock_a", "rock_b", "rock_c": _mesh_node(root, "Rock", asset_name)
		"stone": _mesh_node(root, "Stone", asset_name)
		"firewood": _mesh_node(root, "Firewood", asset_name)
		"fallen_log": _mesh_node(root, "Log", asset_name)
		"berry_bush":
			var bush := _mesh_node(root, "Bush", asset_name)
			_mesh_node(bush, "Berries", "berries")
		"campfire":
			_mesh_node(root, "Stones", "campfire_stones")
			_mesh_node(root, "Logs", "campfire_logs")
		"stone_axe":
			_mesh_node(root, "Handle", "axe_handle")
			_mesh_node(root, "Blade", "axe_blade")
		"torch":
			_mesh_node(root, "Handle", "torch_handle")
			_mesh_node(root, "Head", "torch_head")
		"cabin": _build_cabin(root)
		"wood_stove":
			_mesh_node(root, "Body", "stove_body")
			_mesh_node(root, "Door", "stove_door")
			_mesh_node(root, "Pipe", "stove_pipe")
		"cabinet": _mesh_node(root, "Cabinet", asset_name)
		"bed": _mesh_node(root, "Bed", asset_name)
		"desk": _mesh_node(root, "Desk", asset_name)
		"chair": _mesh_node(root, "Chair", asset_name)
		"shelf":
			var shelf := _mesh_node(root, "Shelf", asset_name)
			_mesh_node(shelf, "Jars", "jars")
		"clock":
			_mesh_node(root, "Clock", asset_name)
			var hh := _mesh_node(root, "HourHand", "hour_hand")
			hh.position = Vector3(0, 0, 0.07)
			var mh := _mesh_node(root, "MinuteHand", "minute_hand")
			mh.position = Vector3(0, 0, 0.075)
		"a_frame_cabin": _build_aframe(root)
		"pickup_truck": _build_truck(root)
		"signpost": _build_signpost(root)
		"fence": _mesh_node(root, "Fence", asset_name)
		"lantern": _mesh_node(root, "Lantern", asset_name)
		"tent":
			_mesh_node(root, "Tent", asset_name)
			_col_box(root, "ColBack", Vector3(-1.2, 0, 1.2), Vector3(1.2, 1.7, 1.3))
		"storage_box": _mesh_node(root, "Box", asset_name)
		"meat": _mesh_node(root, "Meat", asset_name)
		"pelt": _mesh_node(root, "Pelt", asset_name)
		# M3 scatter (MultiMesh-friendly: one mesh node at the origin) and POIs (ASSET_SPEC v2 §13, M3 notes)
		"pine_d", "pine_e", "pine_young", "dead_tree_b": _mesh_node(root, "Tree", asset_name)
		"fallen_log_b": _mesh_node(root, "Log", asset_name)
		"bush_a", "bush_b": _mesh_node(root, "Bush", asset_name)
		"rock_d", "rock_e": _mesh_node(root, "Rock", asset_name)
		"snow_pile_a", "snow_pile_b", "snow_pile_c", "snow_drift_4": _mesh_node(root, "Snow", asset_name)
		"branch_pile": _mesh_node(root, "Branches", asset_name)
		"icicles": _mesh_node(root, "Icicles", asset_name)
		"campsite_remains":
			_mesh_node(root, "Camp", asset_name)
			_col_box(root, "ColTent", Vector3(-1.4, 0, -1.7), Vector3(0.6, 1.1, 0.2))
		"cabin_small": _build_cabin_small(root)
		"lookout_tower": _build_lookout_tower(root)
		# M4 melee weapons (ASSET_SPEC v2 §12: origin = grip, handle +Y, working end / edge +Z)
		"knife", "crowbar", "bat", "bat_nailed", "machete": _build_weapon(root, asset_name)
		_:
			push_warning("Placeholders: unknown asset '%s'" % asset_name)


## Stand-in melee weapons: a handle along +Y from the grip and the head / blade, edge toward +Z.
static func _build_weapon(root: Node3D, asset_name: String) -> void:
	var specs := {
		"knife": [["Handle", Vector3(0.028, 0.11, 0.03), Vector3(0, 0.0, 0), "wood_dark"], ["Blade", Vector3(0.008, 0.2, 0.035), Vector3(0, 0.155, 0.004), "iron"]],
		"crowbar": [["Bar", Vector3(0.025, 0.62, 0.025), Vector3(0, 0.22, 0), "rust"], ["Claw", Vector3(0.025, 0.03, 0.09), Vector3(0, 0.52, 0.04), "rust"]],
		"bat": [["Handle", Vector3(0.035, 0.3, 0.035), Vector3(0, 0.05, 0), "wood_dark"], ["Barrel", Vector3(0.07, 0.55, 0.07), Vector3(0, 0.47, 0), "wood_light"]],
		"bat_nailed": [["Handle", Vector3(0.035, 0.3, 0.035), Vector3(0, 0.05, 0), "wood_dark"], ["Barrel", Vector3(0.07, 0.55, 0.07), Vector3(0, 0.47, 0), "wood_light"],
			["Nails", Vector3(0.12, 0.3, 0.12), Vector3(0, 0.55, 0), "iron"]],
		"machete": [["Handle", Vector3(0.03, 0.13, 0.035), Vector3(0, 0.0, 0), "wood_dark"], ["Blade", Vector3(0.008, 0.45, 0.06), Vector3(0, 0.29, 0.01), "iron"]],
	}
	for part in specs.get(asset_name, []):
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		var bm := BoxMesh.new()
		bm.size = part[1]
		mi.mesh = bm
		mi.position = part[2]
		mi.material_override = Assets.material(part[3])
		root.add_child(mi)


# ---------------------------------------------------------------- helpers

static func _old(v: Vector3) -> Vector3:
	## v2-frame position -> the old (-Z front) frame the builders are written in (180° about Y is its own inverse).
	return MeshBuilder.flip(v)


## Turns a built asset 180° about Y so its front is +Z. Meshes were already turned by MeshBuilder.yaw180, so
## nodes with geometry/children are conjugated (position turned, basis kept) and leaf anchors that carry a
## rotation (ToolSocket) are composed with the turn, exactly like a regenerated .glb.
static func _yaw180_nodes(node: Node3D) -> void:
	var r := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	for c in node.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		var leaf_anchor := n.get_child_count() == 0 and not (n is MeshInstance3D) and not (n is CollisionObject3D) and not (n is CollisionShape3D)
		if leaf_anchor and not n.basis.is_equal_approx(Basis.IDENTITY):
			n.transform = Transform3D(r, Vector3.ZERO) * n.transform
			continue
		n.transform = Transform3D(r * n.basis * r, r * n.position)
		if n is CollisionShape3D and (n as CollisionShape3D).shape is ConvexPolygonShape3D:
			var shape := (n as CollisionShape3D).shape as ConvexPolygonShape3D
			var pts := PackedVector3Array()
			for p in shape.points:
				pts.append(r * p)
			shape.points = pts
		_yaw180_nodes(n)


static func _mesh_node(parent: Node3D, node_name: String, mesh_key: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _mesh(mesh_key)
	parent.add_child(mi)
	return mi


static func _mesh(key: String) -> ArrayMesh:
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var b := MeshBuilder.new()
	b.yaw180 = _flip
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match key:
		"pine_a": _pine(b, rng, 7.0, 0.25, 0.12, [[1.4, 1.9, 2.0, "pine_dark"], [3.0, 1.5, 1.8, "pine_dark"], [4.4, 1.1, 1.6, "pine_light"], [5.6, 0.7, 1.4, "pine_light"]], 0.55)
		"pine_b": _pine(b, rng, 5.5, 0.22, 0.10, [[1.1, 1.6, 1.7, "pine_dark"], [2.5, 1.2, 1.5, "pine_light"], [3.7, 0.8, 1.8, "pine_light"]], 0.55)
		"pine_c": _pine(b, rng, 4.0, 0.18, 0.08, [[0.8, 1.3, 1.5, "pine_dark"], [1.9, 0.9, 1.3, "pine_light"], [2.8, 0.55, 1.2, "pine_light"]], 0.45)
		"dead_tree": _dead_tree(b, rng)
		"stump":
			b.cone("bark", Vector3.ZERO, 0.30, 0.30, 0.45, 8, {"cap_top": "wood_light"})
			b.box("snow", Vector3(-0.28, 0.45, -0.28), Vector3(0.05, 0.50, 0.28))
		"rock_a": b.blob("stone", Vector3(0, 0.22, 0), Vector3(1.2, 1.0, 1.0), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 8, "rings": 5})
		"rock_b":
			b.blob("stone", Vector3(-0.3, 0.4, 0.1), Vector3(1.9, 1.7, 1.6), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 9, "rings": 5})
			b.blob("stone", Vector3(0.5, 0.3, -0.2), Vector3(1.4, 1.2, 1.3), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 8, "rings": 4})
		"rock_c": b.blob("stone", Vector3(0, 0.1, 0), Vector3(0.6, 0.5, 0.5), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 7, "rings": 4})
		"stone": b.blob("stone", Vector3(0, 0.08, 0), Vector3(0.30, 0.24, 0.25), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.75, "flat_bottom": true, "segments": 6, "rings": 3})
		"firewood":
			for k in 2:
				var yaw := 0.5 if k == 0 else -0.6
				var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.10 + 0.0 * k, 0))
				b.cone("bark", Vector3(-0.25, 0, 0), 0.10, 0.10, 0.50, 6, {"xform": xf, "cap_bottom": "wood_light", "cap_top": "wood_light"})
			b.box("snow", Vector3(-0.2, 0.19, -0.08), Vector3(0.2, 0.23, 0.08))
		"fallen_log":
			var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.20, 0))
			b.cone("bark", Vector3(-0.8, 0, 0), 0.20, 0.20, 1.6, 8, {"xform": xf, "cap_bottom": "wood_light", "cap_top": "wood_light"})
			b.box("snow", Vector3(-0.7, 0.36, -0.12), Vector3(0.7, 0.42, 0.12))
			var stub := Transform3D(Basis(Vector3.FORWARD, -0.6), Vector3(0.3, 0.3, 0))
			b.cone("bark", Vector3.ZERO, 0.06, 0.03, 0.35, 5, {"xform": stub})
		"berry_bush":
			b.blob("bush", Vector3(-0.15, 0.2, 0.1), Vector3(0.7, 0.6, 0.7), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.6, "flat_bottom": true, "segments": 7, "rings": 4})
			b.blob("bush", Vector3(0.2, 0.22, -0.1), Vector3(0.8, 0.66, 0.8), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.6, "flat_bottom": true, "segments": 7, "rings": 4})
			b.blob("bush", Vector3(0.0, 0.18, 0.25), Vector3(0.6, 0.5, 0.6), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.6, "flat_bottom": true, "segments": 6, "rings": 4})
		"berries":
			for i in 10:
				var ang := TAU * float(i) / 10.0 + rng.randf() * 0.4
				var r := 0.18 + rng.randf() * 0.22
				var p := Vector3(cos(ang) * r, 0.42 + rng.randf() * 0.1, sin(ang) * r)
				b.blob("berry", p, Vector3(0.09, 0.09, 0.09), {"segments": 5, "rings": 3, "jitter": 0.0})
		"campfire_stones":
			for i in 8:
				var ang := TAU * float(i) / 8.0
				var r := 0.12 + rng.randf() * 0.04
				b.blob("stone", Vector3(cos(ang) * 0.5, r * 0.8, sin(ang) * 0.5), Vector3(r * 2.2, r * 1.8, r * 2.0), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.7, "segments": 6, "rings": 3})
		"campfire_logs":
			for i in 4:
				var ang := TAU * float(i) / 4.0 + 0.4
				var basis := Basis(Vector3.UP, -ang) * Basis(Vector3.RIGHT, -1.15)
				var xf := Transform3D(basis, Vector3(cos(ang) * 0.28, 0.06, sin(ang) * 0.28))
				b.cone("bark", Vector3.ZERO, 0.07, 0.06, 0.6, 6, {"xform": xf, "cap_bottom": "wood_light", "cap_top": "wood_light"})
		"axe_handle":
			b.cone("wood", Vector3(0, -0.05, 0), 0.025, 0.022, 0.55, 6, {"cap_bottom": "wood", "cap_top": "wood"})
			b.cone("cloth", Vector3(0, 0.0, 0), 0.03, 0.03, 0.10, 6)
		"axe_blade":
			b.hexa("stone_dark",
				[Vector3(-0.03, 0.50, 0.0), Vector3(0.03, 0.50, 0.0), Vector3(0.01, 0.50, 0.20), Vector3(-0.01, 0.50, 0.20)],
				[Vector3(-0.03, 0.37, 0.0), Vector3(0.03, 0.37, 0.0), Vector3(0.01, 0.37, 0.20), Vector3(-0.01, 0.37, 0.20)])
			b.box("cloth", Vector3(-0.04, 0.36, -0.04), Vector3(0.04, 0.46, 0.04))
		"torch_handle": b.cone("wood", Vector3.ZERO, 0.025, 0.025, 0.42, 6, {"cap_bottom": "wood"})
		"torch_head": b.cone("cloth", Vector3(0, 0.38, 0), 0.055, 0.05, 0.14, 8, {"cap_bottom": "cloth", "cap_top": "ember"})
		"stove_body":
			for sx in [-0.25, 0.25]:
				for sz in [-0.25, 0.25]:
					b.box("iron", Vector3(sx - 0.03, 0, sz - 0.03), Vector3(sx + 0.03, 0.16, sz + 0.03))
			b.box("iron", Vector3(-0.30, 0.15, -0.30), Vector3(0.30, 0.85, 0.30))
			b.box("iron", Vector3(-0.33, 0.85, -0.33), Vector3(0.33, 0.89, 0.33))
			b.box("iron", Vector3(-0.15, 0.62, -0.31), Vector3(0.15, 0.64, -0.29))
		"stove_door":
			b.quad("ember", Vector3(-0.15, 0.30, -0.302), Vector3(0.15, 0.30, -0.302), Vector3(0.15, 0.60, -0.302), Vector3(-0.15, 0.60, -0.302), Vector3.FORWARD)
			b.box("iron", Vector3(0.08, 0.43, -0.33), Vector3(0.12, 0.47, -0.30))
		"stove_pipe":
			b.cone("iron", Vector3(0, 0.89, 0.15), 0.08, 0.08, 1.81, 8, {"cap_top": "iron"})
			b.cone("iron", Vector3(0, 0.89, 0.15), 0.10, 0.10, 0.10, 8, {"cap_top": "iron"})
		"cabinet":
			b.box("wood", Vector3(-0.45, 0, -0.25), Vector3(0.45, 1.80, 0.25))
			b.box("wood_dark", Vector3(-0.42, 0.15, -0.26), Vector3(-0.02, 1.65, -0.24))
			b.box("wood_dark", Vector3(0.02, 0.15, -0.26), Vector3(0.42, 1.65, -0.24))
			b.box("iron", Vector3(-0.08, 0.85, -0.29), Vector3(-0.05, 0.95, -0.25))
			b.box("iron", Vector3(0.05, 0.85, -0.29), Vector3(0.08, 0.95, -0.25))
			b.box("cabin_trim", Vector3(-0.48, 1.80, -0.28), Vector3(0.48, 1.85, 0.28))
		"bed":
			b.box("wood", Vector3(-0.5, 0.20, -1.0), Vector3(0.5, 0.35, 1.0))
			for sx in [-0.46, 0.46]:
				for sz in [-0.96, 0.96]:
					b.box("wood", Vector3(sx - 0.04, 0, sz - 0.04), Vector3(sx + 0.04, 0.25, sz + 0.04))
			b.box("cloth", Vector3(-0.48, 0.35, -0.98), Vector3(0.48, 0.50, 0.98))
			b.box("hat", Vector3(-0.49, 0.50, -0.6), Vector3(0.49, 0.56, 0.9))
			b.box("paper", Vector3(-0.25, 0.50, 0.55), Vector3(0.25, 0.62, 0.85))
			b.box("wood", Vector3(-0.5, 0, 0.94), Vector3(0.5, 0.95, 1.0))
		"desk":
			b.box("wood", Vector3(-0.7, 0.70, -0.3), Vector3(0.7, 0.75, 0.3))
			for sx in [-0.65, 0.65]:
				for sz in [-0.25, 0.25]:
					b.box("wood", Vector3(sx - 0.03, 0, sz - 0.03), Vector3(sx + 0.03, 0.70, sz + 0.03))
			b.quad("paper", Vector3(-0.35, 0.752, -0.05), Vector3(-0.05, 0.752, -0.05), Vector3(-0.05, 0.752, -0.25), Vector3(-0.35, 0.752, -0.25), Vector3.UP)
			b.cone("iron", Vector3(0.3, 0.75, -0.05), 0.04, 0.04, 0.09, 8, {"cap_top": "iron"})
		"chair":
			b.box("wood", Vector3(-0.225, 0.41, -0.225), Vector3(0.225, 0.45, 0.225))
			for sx in [-0.19, 0.19]:
				for sz in [-0.19, 0.19]:
					b.box("wood", Vector3(sx - 0.02, 0, sz - 0.02), Vector3(sx + 0.02, 0.41, sz + 0.02))
			b.box("wood", Vector3(-0.225, 0.45, 0.18), Vector3(0.225, 0.90, 0.22))
		"shelf":
			b.box("wood", Vector3(-0.45, 0, -0.25), Vector3(0.45, 0.05, 0))
			b.box("wood_dark", Vector3(-0.38, -0.15, -0.2), Vector3(-0.34, 0, 0))
			b.box("wood_dark", Vector3(0.34, -0.15, -0.2), Vector3(0.38, 0, 0))
		"jars":
			var mats := ["can_red", "can_blue", "paper"]
			for i in 3:
				b.cone(mats[i], Vector3(-0.25 + 0.25 * i, 0.05, -0.12), 0.06, 0.06, 0.14, 8, {"cap_top": "iron"})
		"clock":
			# v2 frame: origin at the wall contact, body protrudes toward +Z, face at z = 0.06 looking to +Z
			b.cone("wood", Vector3(0, 0, 0), 0.18, 0.18, 0.06, 12, {"xform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0)), "cap_bottom": "wood", "cap_top": "wood"})
			b.cone("paper", Vector3(0, 0, 0), 0.15, 0.15, 0.004, 12, {"xform": Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0, 0.06)), "cap_top": "paper", "cap_bottom": "paper"})
		"hour_hand": b.box("iron", Vector3(-0.01, -0.01, -0.005), Vector3(0.01, 0.09, 0.005))
		"minute_hand": b.box("iron", Vector3(-0.0075, -0.01, -0.005), Vector3(0.0075, 0.13, 0.005))
		"fence":
			for sx in [-0.94, 0.94]:
				b.box("wood", Vector3(sx - 0.06, 0, -0.06), Vector3(sx + 0.06, 1.1, 0.06), "snow")
			b.box("wood", Vector3(-1.0, 0.40, -0.03), Vector3(1.0, 0.52, 0.03), "snow")
			b.box("wood", Vector3(-1.0, 0.80, -0.03), Vector3(1.0, 0.92, 0.03), "snow")
		"lantern":
			b.box("iron", Vector3(-0.02, -0.06, -0.02), Vector3(0.02, 0, 0.02))
			b.box("iron", Vector3(-0.10, -0.10, -0.10), Vector3(0.10, -0.06, 0.10))
			b.box("window", Vector3(-0.08, -0.36, -0.08), Vector3(0.08, -0.10, 0.08))
			b.box("iron", Vector3(-0.10, -0.40, -0.10), Vector3(0.10, -0.36, 0.10))
		"tent":
			b.prism("cloth", [Vector3(-1.2, 0, -1.3), Vector3(1.2, 0, -1.3), Vector3(0, 1.7, -1.3)],
				[Vector3(-1.2, 0, 1.3), Vector3(1.2, 0, 1.3), Vector3(0, 1.7, 1.3)], "wood_dark")
		"storage_box":
			b.box("wood", Vector3(-0.4, 0, -0.3), Vector3(0.4, 0.6, 0.3))
			b.box("wood_dark", Vector3(-0.42, 0.55, -0.32), Vector3(0.42, 0.6, 0.32))
		"meat":
			b.blob("jacket", Vector3(0, 0.1, 0), Vector3(0.36, 0.2, 0.26), {"rng": rng, "segments": 7, "rings": 4, "jitter": 0.08})
			b.cone("paper", Vector3(0.12, 0.08, 0), 0.03, 0.03, 0.18, 5, {"xform": Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3.ZERO)})
		"pelt":
			b.blob("wolf_fur", Vector3(0, 0.05, 0), Vector3(0.7, 0.12, 0.55), {"rng": rng, "segments": 8, "rings": 4, "jitter": 0.12, "flat_bottom": true})
		"pine_d": _pine(b, rng, 9.0, 0.30, 0.13, [[1.6, 2.1, 2.3, "pine_dark"], [3.2, 1.8, 2.1, "pine_dark"], [4.8, 1.4, 1.9, "pine_light"], [6.3, 1.0, 1.7, "pine_light"], [7.5, 0.6, 1.4, "pine_light"]], 0.55)
		"pine_e":
			_pine(b, rng, 6.6, 0.26, 0.12, [[1.3, 1.8, 1.9, "pine_dark"], [2.8, 1.4, 1.7, "pine_dark"], [4.2, 1.0, 1.5, "pine_light"]], 0.55)
			var side := Transform3D(Basis(Vector3.FORWARD, 0.18), Vector3(0.35, 2.4, 0.1))
			b.cone("bark", Vector3.ZERO, 0.12, 0.06, 3.6, 6, {"xform": side})
			for t in [[1.1, 1.1, 1.5, "pine_dark"], [2.1, 0.8, 1.3, "pine_light"], [3.0, 0.5, 1.1, "pine_light"]]:
				b.cone(t[3], Vector3(0, t[0], 0), t[1], 0.0, t[2], 7, {"xform": side, "ring_frac": 0.55, "mat_high": "snow", "cap_bottom": t[3], "jitter": 0.06, "rng": rng})
		"pine_young": _pine(b, rng, 2.6, 0.09, 0.04, [[0.35, 0.85, 1.0, "pine_light"], [1.0, 0.65, 0.9, "pine_light"], [1.6, 0.42, 0.85, "pine_light"]], 0.5)
		"dead_tree_b": _dead_tree(b, rng)
		"fallen_log_b":
			var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(0, 0.22, 0))
			b.cone("bark", Vector3(-0.95, 0, 0), 0.23, 0.2, 1.9, 8, {"xform": xf, "cap_bottom": "wood_light", "cap_top": "wood_light"})
			b.box("snow", Vector3(-0.8, 0.40, -0.13), Vector3(0.8, 0.46, 0.13))
		"bush_a", "bush_b":
			var big := key == "bush_b"
			b.blob("bush", Vector3(-0.15, 0.2, 0.1), Vector3(0.8, 0.6, 0.8) * (1.2 if big else 1.0), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.6, "flat_bottom": true, "segments": 7, "rings": 4})
			b.blob("bush", Vector3(0.25, 0.22, -0.1), Vector3(0.7, 0.62, 0.7) * (1.2 if big else 1.0), {"rng": rng, "snow_mat": "snow", "snow_limit": 0.6, "flat_bottom": true, "segments": 7, "rings": 4})
		"rock_d": b.blob("stone", Vector3(0, 0.12, 0), Vector3(1.9, 0.5, 1.4), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 9, "rings": 4})
		"rock_e":
			b.blob("stone", Vector3(0, 0.9, 0), Vector3(3.0, 2.6, 2.6), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 10, "rings": 6})
			b.blob("stone", Vector3(1.1, 0.4, 0.6), Vector3(1.6, 1.3, 1.4), {"rng": rng, "snow_mat": "snow", "dark_mat": "stone_dark", "flat_bottom": true, "segments": 8, "rings": 4})
		"snow_pile_a": b.blob("snow", Vector3(0, 0.05, 0), Vector3(1.3, 0.45, 1.1), {"rng": rng, "flat_bottom": true, "segments": 8, "rings": 4, "jitter": 0.06})
		"snow_pile_b": b.blob("snow", Vector3(0, 0.05, 0), Vector3(1.8, 0.6, 1.4), {"rng": rng, "flat_bottom": true, "segments": 9, "rings": 4, "jitter": 0.06})
		"snow_pile_c": b.blob("snow", Vector3(0, 0.04, 0), Vector3(0.9, 0.35, 0.8), {"rng": rng, "flat_bottom": true, "segments": 7, "rings": 3, "jitter": 0.06})
		"snow_drift_4": b.blob("snow", Vector3(0, 0.02, 0), Vector3(4.0, 0.45, 1.2), {"rng": rng, "flat_bottom": true, "segments": 10, "rings": 3, "jitter": 0.05})
		"branch_pile":
			for i in 5:
				var yaw := rng.randf() * TAU
				var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5 - 0.15), Vector3(rng.randf_range(-0.3, 0.3), 0.06 + 0.05 * i, rng.randf_range(-0.3, 0.3)))
				b.cone("bark", Vector3(-0.6, 0, 0), 0.05, 0.03, 1.2, 5, {"xform": xf})
			b.blob("snow", Vector3(0, 0.2, 0), Vector3(0.8, 0.12, 0.6), {"rng": rng, "segments": 6, "rings": 3})
		"icicles":
			for i in 7:
				b.cone("ice_clear", Vector3(-0.9 + 0.3 * i, 0, 0), 0.05, 0.0, -(0.25 + rng.randf() * 0.35), 5)
		"campsite_remains":
			b.prism("cloth", [Vector3(-1.2, 0, -1.6), Vector3(0.4, 0, -1.6), Vector3(-0.5, 1.0, -1.6)],
				[Vector3(-1.2, 0, 0.0), Vector3(0.4, 0, 0.0), Vector3(-0.3, 0.6, 0.0)], "wood_dark")
			for i in 7:
				var ang := TAU * float(i) / 7.0
				b.blob("stone", Vector3(1.3 + cos(ang) * 0.45, 0.08, 0.6 + sin(ang) * 0.45), Vector3(0.22, 0.16, 0.2), {"rng": rng, "snow_mat": "snow", "segments": 5, "rings": 3})
			var lx := Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.FORWARD, PI * 0.5), Vector3(1.4, 0.15, -0.6))
			b.cone("bark", Vector3(-0.6, 0, 0), 0.14, 0.14, 1.2, 6, {"xform": lx, "cap_bottom": "wood_light", "cap_top": "wood_light"})
		"cabin_small_body":
			b.box("wood", Vector3(-2.5, 0, -2.0), Vector3(2.5, 0.3, 2.0))
			b.box("cabin_wall", Vector3(-2.4, 0.3, -1.9), Vector3(2.4, 2.6, 1.9))
			b.box("wood_dark", Vector3(-0.5, 0.3, 1.9), Vector3(0.5, 2.1, 1.95))
			b.box("window", Vector3(1.1, 1.2, 1.9), Vector3(1.9, 1.9, 1.96))
		"cabin_small_roof":
			b.prism("roof", [Vector3(-2.8, 2.5, -2.3), Vector3(0.0, 4.0, -2.3), Vector3(2.8, 2.5, -2.3)],
				[Vector3(-2.8, 2.5, 2.3), Vector3(0.0, 4.0, 2.3), Vector3(2.8, 2.5, 2.3)], "snow")
		"tower_frame":
			for sx in [-1.6, 1.6]:
				for sz in [-1.6, 1.6]:
					b.box("wood_dark", Vector3(sx - 0.12, 0, sz - 0.12), Vector3(sx + 0.12, 6.0, sz + 0.12))
			b.box("wood", Vector3(-2.0, 5.8, -2.0), Vector3(2.0, 6.0, 2.0), "snow")
			b.box("wood", Vector3(-2.0, 6.0, -2.0), Vector3(2.0, 7.0, -1.9))
			b.box("wood", Vector3(-2.0, 6.0, 1.9), Vector3(2.0, 7.0, 2.0))
			b.box("wood", Vector3(-2.0, 6.0, -2.0), Vector3(-1.9, 7.0, 2.0))
			b.box("wood", Vector3(1.9, 6.0, -2.0), Vector3(2.0, 7.0, 2.0))
			for i in 10:
				b.box("wood_light", Vector3(-0.4, 0.3 + 0.55 * i, 1.75), Vector3(0.4, 0.36 + 0.55 * i, 1.85))
		"tower_roof":
			b.cone("roof", Vector3(0, 8.4, 0), 2.6, 0.0, 1.4, 4, {"cap_bottom": "roof", "mat_high": "snow", "ring_frac": 0.4})
			for sx in [-1.8, 1.8]:
				for sz in [-1.8, 1.8]:
					b.box("wood_dark", Vector3(sx - 0.07, 7.0, sz - 0.07), Vector3(sx + 0.07, 8.4, sz + 0.07))
		_:
			b.box("stone", Vector3(-0.25, 0, -0.25), Vector3(0.25, 0.5, 0.25))
	var mesh := b.commit()
	_mesh_cache[key] = mesh
	return mesh


static func _pine(b: MeshBuilder, rng: RandomNumberGenerator, height: float, r0: float, r1: float, tiers: Array, ring_frac: float) -> void:
	b.cone("bark", Vector3.ZERO, r0, r1, height - 0.6, 6)
	b.cone("snow", Vector3(0, 0, 0), 0.45, 0.42, 0.08, 8, {"cap_top": "snow"})
	for t in tiers:
		b.cone(t[3], Vector3(0, t[0], 0), t[1], 0.0, t[2], 8, {"ring_frac": ring_frac, "mat_high": "snow", "cap_bottom": t[3], "jitter": 0.06, "rng": rng})


static func _build_cabin_small(root: Node3D) -> void:
	# v2 frame (door at +Z = MODEL_FRONT); cut groups as in ASSET_SPEC v2 §8.4 (Floor, Walls, Roof)
	_mesh_node(root, "Walls0", "cabin_small_body")
	_mesh_node(root, "Roof", "cabin_small_roof")
	_col_box(root, "ColFloor", Vector3(-2.5, 0, -2.0), Vector3(2.5, 0.3, 2.0))
	_col_box(root, "ColWallBack", Vector3(-2.4, 0.3, -1.9), Vector3(2.4, 2.6, -1.7))
	_col_box(root, "ColWallLeft", Vector3(2.2, 0.3, -1.9), Vector3(2.4, 2.6, 1.9))
	_col_box(root, "ColWallRight", Vector3(-2.4, 0.3, -1.9), Vector3(-2.2, 2.6, 1.9))
	_col_box(root, "ColWallFrontL", Vector3(0.5, 0.3, 1.7), Vector3(2.4, 2.6, 1.9))
	_col_box(root, "ColWallFrontR", Vector3(-2.4, 0.3, 1.7), Vector3(-0.5, 2.6, 1.9))


static func _build_lookout_tower(root: Node3D) -> void:
	_mesh_node(root, "Frame", "tower_frame")
	_mesh_node(root, "Roof", "tower_roof")
	for sx in [-1.6, 1.6]:
		for sz in [-1.6, 1.6]:
			_col_box(root, "ColLeg_%d_%d" % [int(sx), int(sz)], Vector3(sx - 0.15, 0, sz - 0.15), Vector3(sx + 0.15, 6.0, sz + 0.15))
	_col_box(root, "ColDeck", Vector3(-2.0, 5.8, -2.0), Vector3(2.0, 6.0, 2.0))


static func _dead_tree(b: MeshBuilder, rng: RandomNumberGenerator) -> void:
	b.cone("bark", Vector3.ZERO, 0.20, 0.08, 4.5, 6, {"cap_top": "bark"})
	b.cone("snow", Vector3.ZERO, 0.4, 0.38, 0.06, 8, {"cap_top": "snow"})
	for i in 6:
		var y := 1.8 + rng.randf() * 2.2
		var yaw := TAU * float(i) / 6.0 + rng.randf() * 0.5
		var tilt := deg_to_rad(35.0 + rng.randf() * 25.0)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -tilt) * Basis(Vector3.UP, 0.0)
		var xf := Transform3D(basis, Vector3(0, y, 0))
		var length := 0.9 + rng.randf() * 0.7
		b.cone("bark", Vector3.ZERO, 0.05, 0.02, length, 4, {"xform": xf})
		b.box("snow", xf * Vector3(-0.03, length * 0.5, -0.05) - Vector3(0.02, 0, 0.02), xf * Vector3(0.03, length * 0.5, -0.05) + Vector3(0.02, 0.03, 0.02))


static func _col_box(parent: Node3D, node_name: String, mn: Vector3, mx: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = mx - mn
	cs.shape = shape
	cs.position = (mn + mx) * 0.5
	body.add_child(cs)
	parent.add_child(body)
	return body


static func _col_convex(parent: Node3D, node_name: String, points: PackedVector3Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	return body


static func _part(parent: Node3D, node_name: String, pos: Vector3, build: Callable) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.position = pos
	var b := MeshBuilder.new()
	b.yaw180 = _flip
	build.call(b)
	mi.mesh = b.commit()
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- characters

static func _build_player(root: Node3D) -> void:
	var hips := Node3D.new()
	hips.name = "Hips"
	hips.position = Vector3(0, 0.80, 0)
	root.add_child(hips)
	var torso := _part(hips, "Torso", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.hexa("jacket",
			[Vector3(-0.26, 0.56, -0.16), Vector3(0.26, 0.56, -0.16), Vector3(0.26, 0.56, 0.16), Vector3(-0.26, 0.56, 0.16)],
			[Vector3(-0.28, 0.0, -0.17), Vector3(0.28, 0.0, -0.17), Vector3(0.28, 0.0, 0.17), Vector3(-0.28, 0.0, 0.17)])
		b.box("scarf", Vector3(-0.20, 0.50, -0.18), Vector3(0.20, 0.60, 0.18))
		b.box("scarf", Vector3(-0.06, 0.30, -0.19), Vector3(0.04, 0.52, -0.17)))
	var head := _part(torso, "Head", Vector3(0, 0.56, 0), func(b: MeshBuilder) -> void:
		b.box("skin", Vector3(-0.15, 0.02, -0.14), Vector3(0.15, 0.28, 0.14))
		b.box("hat", Vector3(-0.17, 0.24, -0.16), Vector3(0.17, 0.38, 0.16))
		b.blob("snow", Vector3(0, 0.44, 0), Vector3(0.12, 0.12, 0.12), {"segments": 6, "rings": 3, "jitter": 0.0})
		for ex in [-0.06, 0.06]:
			b.quad("eyes_dark", Vector3(ex - 0.02, 0.18, -0.142), Vector3(ex + 0.02, 0.18, -0.142), Vector3(ex + 0.02, 0.22, -0.142), Vector3(ex - 0.02, 0.22, -0.142), Vector3.FORWARD))
	var breath := Node3D.new()
	breath.name = "BreathAnchor"
	breath.position = Vector3(0, 0.16, -0.20)
	head.add_child(breath)
	var arm_build := func(b: MeshBuilder) -> void:
		b.box("jacket", Vector3(-0.08, -0.44, -0.08), Vector3(0.08, 0.0, 0.08))
		b.box("scarf", Vector3(-0.08, -0.56, -0.08), Vector3(0.08, -0.44, 0.08))
	_part(torso, "ArmL", Vector3(-0.36, 0.52, 0), arm_build)
	var arm_r := _part(torso, "ArmR", Vector3(0.36, 0.52, 0), arm_build)
	var socket := Node3D.new()
	socket.name = "ToolSocket"
	socket.position = Vector3(0, -0.52, -0.05)
	socket.rotation_degrees = Vector3(-90, 0, 0)
	arm_r.add_child(socket)
	var leg_build := func(b: MeshBuilder) -> void:
		b.box("hat", Vector3(-0.10, -0.62, -0.11), Vector3(0.10, 0.0, 0.11))
		b.box("boots", Vector3(-0.10, -0.80, -0.13), Vector3(0.10, -0.62, 0.11))
	_part(hips, "LegL", Vector3(-0.12, 0, 0), leg_build)
	_part(hips, "LegR", Vector3(0.12, 0, 0), leg_build)


static func _build_quadruped(root: Node3D, deer: bool) -> void:
	var fur := "deer_fur" if deer else "wolf_fur"
	var belly := "deer_belly" if deer else "wolf_belly"
	var anchors: Array = ANCHORS["deer" if deer else "wolf"]
	var body_pos: Vector3 = _old(anchors[0][2])
	var body := _part(root, "Body", body_pos, func(b: MeshBuilder) -> void:
		if deer:
			b.box(fur, Vector3(-0.20, -0.20, -0.65), Vector3(0.20, 0.25, 0.55))
			b.box(belly, Vector3(-0.17, -0.24, -0.55), Vector3(0.17, -0.19, 0.45))
		else:
			b.hexa(fur,
				[Vector3(-0.17, 0.19, -0.45), Vector3(0.17, 0.19, -0.45), Vector3(0.15, 0.17, 0.45), Vector3(-0.15, 0.17, 0.45)],
				[Vector3(-0.18, -0.19, -0.45), Vector3(0.18, -0.19, -0.45), Vector3(0.14, -0.15, 0.45), Vector3(-0.14, -0.15, 0.45)])
			b.box(belly, Vector3(-0.14, -0.23, -0.35), Vector3(0.14, -0.18, 0.35)))
	var head_pos: Vector3 = _old(anchors[1][2])
	var head := _part(body, "Head", head_pos, func(b: MeshBuilder) -> void:
		if deer:
			b.box(fur, Vector3(-0.08, -0.05, -0.25), Vector3(0.08, 0.35, 0.0))
			b.box(fur, Vector3(-0.10, 0.25, -0.45), Vector3(0.10, 0.47, -0.15))
			b.box(belly, Vector3(-0.06, 0.25, -0.46), Vector3(0.06, 0.33, -0.44))
			for ex in [-0.06, 0.06]:
				b.box("wood_light", Vector3(ex - 0.015, 0.47, -0.30), Vector3(ex + 0.015, 0.70, -0.27))
				b.box("wood_light", Vector3(ex - 0.015 + ex * 1.5, 0.60, -0.31), Vector3(ex + 0.015 + ex * 1.5, 0.66, -0.20))
				b.box("wood_light", Vector3(ex - 0.015, 0.62, -0.31), Vector3(ex + 0.015 + ex * 2.2, 0.65, -0.28))
			for ex in [-0.05, 0.05]:
				b.quad("eyes", Vector3(ex - 0.02, 0.36, -0.452), Vector3(ex + 0.02, 0.36, -0.452), Vector3(ex + 0.02, 0.40, -0.452), Vector3(ex - 0.02, 0.40, -0.452), Vector3.FORWARD)
		else:
			b.box(fur, Vector3(-0.12, -0.12, -0.30), Vector3(0.12, 0.12, 0.0))
			b.box(fur, Vector3(-0.07, -0.12, -0.48), Vector3(0.07, 0.02, -0.30))
			b.box(belly, Vector3(-0.06, -0.12, -0.49), Vector3(0.06, -0.02, -0.47))
			b.box("eyes_dark", Vector3(-0.03, -0.01, -0.50), Vector3(0.03, 0.03, -0.46))
			for ex in [-0.08, 0.08]:
				b.prism(fur, [Vector3(ex - 0.04, 0.12, -0.14), Vector3(ex + 0.04, 0.12, -0.14), Vector3(ex, 0.20, -0.12)],
					[Vector3(ex - 0.04, 0.12, -0.06), Vector3(ex + 0.04, 0.12, -0.06), Vector3(ex, 0.20, -0.08)])
			for ex in [-0.06, 0.06]:
				b.quad("eyes", Vector3(ex - 0.02, 0.02, -0.302), Vector3(ex + 0.02, 0.02, -0.302), Vector3(ex + 0.02, 0.06, -0.302), Vector3(ex - 0.02, 0.06, -0.302), Vector3.FORWARD))
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = _old(anchors[2][2])
	head.add_child(muzzle)
	_part(body, "Tail", _old(anchors[3][2]), func(b: MeshBuilder) -> void:
		if deer:
			b.box(fur, Vector3(-0.04, -0.02, 0.0), Vector3(0.04, 0.06, 0.12))
		else:
			b.hexa(fur, [Vector3(-0.05, 0.0, 0.0), Vector3(0.05, 0.0, 0.0), Vector3(0.04, -0.12, 0.45), Vector3(-0.04, -0.12, 0.45)],
				[Vector3(-0.05, -0.10, 0.0), Vector3(0.05, -0.10, 0.0), Vector3(0.04, -0.20, 0.45), Vector3(-0.04, -0.20, 0.45)]))
	var leg_len := 0.70 if deer else 0.42
	var lw := 0.045 if deer else 0.05
	var leg_build := func(b: MeshBuilder) -> void:
		b.box(fur, Vector3(-lw, -leg_len, -lw * 1.2), Vector3(lw, 0.0, lw * 1.2))
	for i in range(4, 8):
		_part(body, anchors[i][0], _old(anchors[i][2]), leg_build)


# ---------------------------------------------------------------- architecture

static func _window(b: MeshBuilder, mn: Vector3, mx: Vector3, axis: String) -> void:
	# pane + trim frame; axis = "x" (pane in the YZ plane) or "z" (pane in the XY plane)
	b.box("window", mn, mx)
	var t := 0.08
	var d := 0.04
	if axis == "z":
		var z0 := mn.z - d if mn.z < 0 else mn.z
		var z1 := mx.z if mn.z < 0 else mx.z + d
		b.box("cabin_trim", Vector3(mn.x - t, mn.y - t, z0), Vector3(mx.x + t, mn.y, z1))
		b.box("cabin_trim", Vector3(mn.x - t, mx.y, z0), Vector3(mx.x + t, mx.y + t, z1))
		b.box("cabin_trim", Vector3(mn.x - t, mn.y, z0), Vector3(mn.x, mx.y, z1))
		b.box("cabin_trim", Vector3(mx.x, mn.y, z0), Vector3(mx.x + t, mx.y, z1))
		var cx := (mn.x + mx.x) * 0.5
		var cy := (mn.y + mx.y) * 0.5
		b.box("cabin_trim", Vector3(cx - 0.02, mn.y, z0), Vector3(cx + 0.02, mx.y, z1))
		b.box("cabin_trim", Vector3(mn.x, cy - 0.02, z0), Vector3(mx.x, cy + 0.02, z1))
	else:
		var x0 := mn.x - d if mn.x < 0 else mn.x
		var x1 := mx.x if mn.x < 0 else mx.x + d
		b.box("cabin_trim", Vector3(x0, mn.y - t, mn.z - t), Vector3(x1, mn.y, mx.z + t))
		b.box("cabin_trim", Vector3(x0, mx.y, mn.z - t), Vector3(x1, mx.y + t, mx.z + t))
		b.box("cabin_trim", Vector3(x0, mn.y, mn.z - t), Vector3(x1, mx.y, mn.z))
		b.box("cabin_trim", Vector3(x0, mn.y, mx.z), Vector3(x1, mx.y, mx.z + t))
		var cz := (mn.z + mx.z) * 0.5
		var cy := (mn.y + mx.y) * 0.5
		b.box("cabin_trim", Vector3(x0, mn.y, cz - 0.02), Vector3(x1, mx.y, cz + 0.02))
		b.box("cabin_trim", Vector3(x0, cy - 0.02, mn.z), Vector3(x1, cy + 0.02, mx.z))


static func _build_cabin(root: Node3D) -> void:
	_part(root, "Floor", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("stone", Vector3(-3.0, 0, -2.5), Vector3(3.0, 0.29, 2.5))
		b.box("wood_light", Vector3(-2.82, 0.2, -2.32), Vector3(2.82, 0.30, 2.32)))
	_part(root, "WallBack", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("cabin_wall", Vector3(-3.0, 0.30, 2.32), Vector3(3.0, 3.0, 2.5))
		for i in 4:
			b.box("cabin_trim", Vector3(-3.0, 0.9 + i * 0.6, 2.50), Vector3(3.0, 0.93, 2.52))
		b.box("cabin_trim", Vector3(-3.05, 0.30, 2.45), Vector3(-2.95, 3.0, 2.55))
		b.box("cabin_trim", Vector3(2.95, 0.30, 2.45), Vector3(3.05, 3.0, 2.55)))
	var wall_left := _part(root, "WallLeft", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("cabin_wall", Vector3(-3.0, 0.30, -2.5), Vector3(-2.82, 3.0, 2.5))
		for i in 4:
			b.box("cabin_trim", Vector3(-3.02, 0.9 + i * 0.6, -2.5), Vector3(-3.0, 0.93, 2.5)))
	_part(wall_left, "WindowsLeft", Vector3.ZERO, func(b: MeshBuilder) -> void:
		_window(b, Vector3(-3.02, 1.3, 0.7), Vector3(-3.0, 2.3, 1.9), "x"))
	_part(root, "WallRight", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("cabin_wall", Vector3(2.82, 0.30, -2.5), Vector3(3.0, 3.0, 2.5))
		for i in 4:
			b.box("cabin_trim", Vector3(3.0, 0.9 + i * 0.6, -2.5), Vector3(3.02, 0.93, 2.5)))
	var wall_front := _part(root, "WallFront", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("cabin_wall", Vector3(-3.0, 0.30, -2.5), Vector3(-1.4, 3.0, -2.32))
		b.box("cabin_wall", Vector3(-0.4, 0.30, -2.5), Vector3(3.0, 3.0, -2.32))
		b.box("cabin_wall", Vector3(-1.4, 2.40, -2.5), Vector3(-0.4, 3.0, -2.32))
		b.box("cabin_trim", Vector3(-1.5, 0.30, -2.54), Vector3(-1.4, 2.5, -2.32))
		b.box("cabin_trim", Vector3(-0.4, 0.30, -2.54), Vector3(-0.3, 2.5, -2.32))
		b.box("cabin_trim", Vector3(-1.5, 2.40, -2.54), Vector3(-0.3, 2.5, -2.32))
		b.box("cabin_trim", Vector3(-3.05, 0.30, -2.55), Vector3(-2.95, 3.0, -2.45))
		b.box("cabin_trim", Vector3(2.95, 0.30, -2.55), Vector3(3.05, 3.0, -2.45)))
	_part(wall_front, "WindowsFront", Vector3.ZERO, func(b: MeshBuilder) -> void:
		_window(b, Vector3(0.8, 1.3, -2.52), Vector3(2.0, 2.3, -2.5), "z"))
	_part(root, "Roof", Vector3.ZERO, func(b: MeshBuilder) -> void:
		# two slopes with snow on top
		b.slab("roof", Vector3(-3.4, 3.0, 2.9), Vector3(3.4, 3.0, 2.9), Vector3(3.4, 4.6, 0.0), Vector3(-3.4, 4.6, 0.0), 0.15)
		b.slab("roof", Vector3(3.4, 3.0, -2.9), Vector3(-3.4, 3.0, -2.9), Vector3(-3.4, 4.6, 0.0), Vector3(3.4, 4.6, 0.0), 0.15)
		b.slab("snow", Vector3(-3.4, 3.12, 2.9), Vector3(3.4, 3.12, 2.9), Vector3(3.4, 4.72, 0.0), Vector3(-3.4, 4.72, 0.0), 0.12)
		b.slab("snow", Vector3(3.4, 3.12, -2.9), Vector3(-3.4, 3.12, -2.9), Vector3(-3.4, 4.72, 0.0), Vector3(3.4, 4.72, 0.0), 0.12)
		b.box("snow", Vector3(-3.45, 4.55, -0.25), Vector3(3.45, 4.85, 0.25))
		for sx in [-3.0, 3.0]:
			var x0: float = sx - 0.09
			var x1: float = sx + 0.09
			b.prism("cabin_wall", [Vector3(x0, 3.0, -2.5), Vector3(x0, 3.0, 2.5), Vector3(x0, 4.6, 0)],
				[Vector3(x1, 3.0, -2.5), Vector3(x1, 3.0, 2.5), Vector3(x1, 4.6, 0)]))
	_part(root, "Chimney", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("brick", Vector3(-3.7, 0, -0.95), Vector3(-3.0, 5.1, -0.25))
		b.box("stone_dark", Vector3(-3.75, 5.1, -1.0), Vector3(-2.95, 5.3, -0.2))
		b.box("snow", Vector3(-3.75, 5.3, -1.0), Vector3(-2.95, 5.4, -0.2)))
	_part(root, "Porch", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("stone", Vector3(-3.0, 0, -4.5), Vector3(3.0, 0.2, -2.5))
		b.box("wood", Vector3(-3.0, 0.2, -4.5), Vector3(3.0, 0.30, -2.5))
		for i in 8:
			b.box("wood_dark", Vector3(-3.0, 0.30, -4.5 + i * 0.25), Vector3(3.0, 0.305, -4.49 + i * 0.25))
		b.box("wood", Vector3(-1.5, 0, -4.85), Vector3(-0.3, 0.20, -4.5))
		b.box("wood", Vector3(-1.5, 0, -5.2), Vector3(-0.3, 0.10, -4.85))
		for p in [Vector2(-3.0, -4.5), Vector2(3.0, -4.5), Vector2(-1.5, -4.5), Vector2(-0.3, -4.5), Vector2(-3.0, -2.5), Vector2(3.0, -2.5)]:
			b.box("cabin_trim", Vector3(p.x - 0.05, 0.30, p.y - 0.05), Vector3(p.x + 0.05, 1.3, p.y + 0.05), "snow")
		b.box("cabin_trim", Vector3(-3.0, 1.16, -4.54), Vector3(-1.5, 1.24, -4.46), "snow")
		b.box("cabin_trim", Vector3(-0.3, 1.16, -4.54), Vector3(3.0, 1.24, -4.46), "snow")
		b.box("cabin_trim", Vector3(-3.04, 1.16, -4.5), Vector3(-2.96, 1.24, -2.5), "snow")
		b.box("cabin_trim", Vector3(2.96, 1.16, -4.5), Vector3(3.04, 1.24, -2.5), "snow")
		var x := -2.7
		while x < 3.0:
			if x < -1.6 or x > -0.2:
				b.box("cabin_trim", Vector3(x - 0.02, 0.30, -4.52), Vector3(x + 0.02, 1.16, -4.48))
			x += 0.3
		var z := -4.2
		while z < -2.6:
			b.box("cabin_trim", Vector3(-3.02, 0.30, z - 0.02), Vector3(-2.98, 1.16, z + 0.02))
			b.box("cabin_trim", Vector3(2.98, 0.30, z - 0.02), Vector3(3.02, 1.16, z + 0.02))
			z += 0.3
		b.slab("roof", Vector3(-3.2, 3.0, -2.5), Vector3(3.2, 3.0, -2.5), Vector3(3.2, 2.5, -4.8), Vector3(-3.2, 2.5, -4.8), 0.12)
		b.slab("snow", Vector3(-3.2, 3.1, -2.5), Vector3(3.2, 3.1, -2.5), Vector3(3.2, 2.6, -4.8), Vector3(-3.2, 2.6, -4.8), 0.10)
		for sx in [-2.9, 2.9]:
			b.box("wood", Vector3(sx - 0.06, 0.30, -4.46), Vector3(sx + 0.06, 2.5, -4.34)))
	var door := Node3D.new()
	door.name = "DoorAnchor"
	door.position = Vector3(-0.9, 0.30, -3.2)
	root.add_child(door)
	var lantern := Node3D.new()
	lantern.name = "LanternSocket"
	lantern.position = Vector3(-1.6, 2.35, -4.3)
	root.add_child(lantern)
	# collision (matches ASSET_SPEC §4.15)
	_col_box(root, "ColFoundation", Vector3(-3.0, 0, -2.5), Vector3(3.0, 0.30, 2.5))
	_col_box(root, "ColPorch", Vector3(-3.0, 0, -4.5), Vector3(3.0, 0.30, -2.5))
	_col_convex(root, "ColSteps", PackedVector3Array([
		Vector3(-1.5, 0, -5.3), Vector3(-1.5, 0, -4.5), Vector3(-1.5, 0.30, -4.5),
		Vector3(-0.3, 0, -5.3), Vector3(-0.3, 0, -4.5), Vector3(-0.3, 0.30, -4.5)]))
	_col_box(root, "ColWallBack", Vector3(-3.0, 0.30, 2.32), Vector3(3.0, 3.0, 2.5))
	_col_box(root, "ColWallLeft", Vector3(-3.0, 0.30, -2.5), Vector3(-2.82, 3.0, 2.5))
	_col_box(root, "ColWallRight", Vector3(2.82, 0.30, -2.5), Vector3(3.0, 3.0, 2.5))
	_col_box(root, "ColWallFrontL", Vector3(-3.0, 0.30, -2.5), Vector3(-1.4, 3.0, -2.32))
	_col_box(root, "ColWallFrontR", Vector3(-0.4, 0.30, -2.5), Vector3(3.0, 3.0, -2.32))
	_col_box(root, "ColDoorTop", Vector3(-1.4, 2.40, -2.5), Vector3(-0.4, 3.0, -2.32))
	_col_box(root, "ColChimney", Vector3(-3.7, 0, -0.95), Vector3(-3.0, 3.0, -0.25))
	_col_box(root, "ColRailFrontL", Vector3(-3.0, 0.30, -4.5), Vector3(-1.5, 1.3, -4.42))
	_col_box(root, "ColRailFrontR", Vector3(-0.3, 0.30, -4.5), Vector3(3.0, 1.3, -4.42))
	_col_box(root, "ColRailLeft", Vector3(-3.0, 0.30, -4.5), Vector3(-2.92, 1.3, -2.5))
	_col_box(root, "ColRailRight", Vector3(2.92, 0.30, -4.5), Vector3(3.0, 1.3, -2.5))


static func _build_aframe(root: Node3D) -> void:
	_part(root, "Body", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.slab("roof", Vector3(-3.0, 0, 3.6), Vector3(0, 6.0, 3.6), Vector3(0, 6.0, -3.6), Vector3(-3.0, 0, -3.6), 0.2)
		b.slab("roof", Vector3(0, 6.0, 3.6), Vector3(3.0, 0, 3.6), Vector3(3.0, 0, -3.6), Vector3(0, 6.0, -3.6), 0.2)
		b.slab("snow", Vector3(-3.1, 0.1, 3.6), Vector3(-0.05, 6.15, 3.6), Vector3(-0.05, 6.15, -3.6), Vector3(-3.1, 0.1, -3.6), 0.12)
		b.slab("snow", Vector3(0.05, 6.15, 3.6), Vector3(3.1, 0.1, 3.6), Vector3(3.1, 0.1, -3.6), Vector3(0.05, 6.15, -3.6), 0.12)
		b.prism("wood_dark", [Vector3(-2.8, 0, 3.3), Vector3(2.8, 0, 3.3), Vector3(0, 5.7, 3.3)],
			[Vector3(-2.8, 0, 3.5), Vector3(2.8, 0, 3.5), Vector3(0, 5.7, 3.5)]))
	var front := _part(root, "Front", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.prism("wood", [Vector3(-2.8, 0, -3.5), Vector3(2.8, 0, -3.5), Vector3(0, 5.7, -3.5)],
			[Vector3(-2.8, 0, -3.3), Vector3(2.8, 0, -3.3), Vector3(0, 5.7, -3.3)])
		for i in 6:
			var x := -2.2 + i * 0.8
			var h := 5.7 * (1.0 - absf(x) / 2.9)
			b.box("wood_dark", Vector3(x - 0.03, 0, -3.52), Vector3(x + 0.03, maxf(h - 0.3, 0.3), -3.5))
		b.box("wood_dark", Vector3(0.15, 0.25, -3.53), Vector3(1.05, 2.25, -3.5))
		b.box("cabin_trim", Vector3(0.1, 0.25, -3.54), Vector3(0.15, 2.3, -3.5))
		b.box("cabin_trim", Vector3(1.05, 0.25, -3.54), Vector3(1.1, 2.3, -3.5))
		b.box("cabin_trim", Vector3(0.1, 2.25, -3.54), Vector3(1.1, 2.3, -3.5)))
	_part(front, "WindowsFront", Vector3.ZERO, func(b: MeshBuilder) -> void:
		_window(b, Vector3(-1.2, 2.5, -3.54), Vector3(-0.2, 3.5, -3.5), "z"))
	_part(root, "Deck", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("wood", Vector3(-2.0, 0, -5.0), Vector3(2.0, 0.25, -3.5), "snow")
		for sx in [-1.9, 1.9]:
			b.box("wood", Vector3(sx - 0.06, 0.25, -4.96), Vector3(sx + 0.06, 1.1, -4.84), "snow")
		b.box("wood", Vector3(-1.9, 1.0, -4.95), Vector3(1.9, 1.08, -4.87), "snow"))
	_col_convex(root, "ColBody", PackedVector3Array([
		Vector3(-3.0, 0, -3.5), Vector3(3.0, 0, -3.5), Vector3(0, 6.0, -3.5),
		Vector3(-3.0, 0, 3.5), Vector3(3.0, 0, 3.5), Vector3(0, 6.0, 3.5)]))
	_col_box(root, "ColDeck", Vector3(-2.0, 0, -5.0), Vector3(2.0, 0.25, -3.5))


static func _build_truck(root: Node3D) -> void:
	_part(root, "Body", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("truck_paint", Vector3(-1.0, 0.6, -2.5), Vector3(1.0, 1.3, -1.0))  # hood
		b.box("truck_paint", Vector3(-0.95, 0.6, -1.0), Vector3(0.95, 2.0, 0.2))  # cab
		b.box("window", Vector3(-0.85, 1.35, -1.02), Vector3(0.85, 1.9, -0.98))   # windshield
		b.box("window", Vector3(-0.85, 1.35, 0.18), Vector3(0.85, 1.9, 0.22))     # rear window
		b.box("window", Vector3(-0.97, 1.35, -0.8), Vector3(-0.93, 1.9, 0.0))
		b.box("window", Vector3(0.93, 1.35, -0.8), Vector3(0.97, 1.9, 0.0))
		b.box("truck_paint", Vector3(-1.0, 0.6, 0.2), Vector3(1.0, 0.8, 2.5))     # bed floor
		b.box("truck_paint", Vector3(-1.0, 0.8, 0.2), Vector3(-0.92, 1.3, 2.5))
		b.box("truck_paint", Vector3(0.92, 0.8, 0.2), Vector3(1.0, 1.3, 2.5))
		b.box("truck_paint", Vector3(-1.0, 0.8, 2.42), Vector3(1.0, 1.3, 2.5))
		b.box("truck_paint", Vector3(-1.0, 0.8, 0.2), Vector3(1.0, 1.3, 0.28))
		b.box("iron", Vector3(-1.05, 0.45, -2.6), Vector3(1.05, 0.6, -2.45))
		b.box("iron", Vector3(-1.05, 0.45, 2.45), Vector3(1.05, 0.6, 2.6))
		b.box("eyes", Vector3(-0.9, 0.9, -2.53), Vector3(-0.6, 1.1, -2.5))
		b.box("eyes", Vector3(0.6, 0.9, -2.53), Vector3(0.9, 1.1, -2.5)))
	_part(root, "Wheels", Vector3.ZERO, func(b: MeshBuilder) -> void:
		for sx in [-0.95, 0.95]:
			for sz in [-1.6, 1.6]:
				var xf := Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(sx, 0.42, sz))
				b.cone("iron", Vector3(-0.125, 0, 0), 0.42, 0.42, 0.25, 12, {"xform": xf, "cap_bottom": "stone", "cap_top": "stone"}))
	_part(root, "Snow", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("snow", Vector3(-1.0, 1.3, -2.5), Vector3(1.0, 1.4, -1.05))
		b.box("snow", Vector3(-0.95, 2.0, -1.0), Vector3(0.95, 2.1, 0.2))
		b.box("snow", Vector3(-1.02, 1.3, 0.2), Vector3(-0.9, 1.38, 2.5))
		b.box("snow", Vector3(0.9, 1.3, 0.2), Vector3(1.02, 1.38, 2.5))
		b.box("snow", Vector3(-0.9, 0.8, 0.3), Vector3(0.9, 0.9, 2.4)))
	var anchor := Node3D.new()
	anchor.name = "BedAnchor"
	anchor.position = Vector3(0, 1.0, 1.35)
	root.add_child(anchor)
	_col_box(root, "ColChassis", Vector3(-1.0, 0.3, -2.5), Vector3(1.0, 1.3, 2.5))
	_col_box(root, "ColCab", Vector3(-0.95, 1.3, -1.0), Vector3(0.95, 2.0, 0.2))


## v2 frame (ASSET_SPEC v2 §17): boards point to +X, the text face looks to +Z, Text* anchors with no rotation.
static func _build_signpost(root: Node3D) -> void:
	_part(root, "Post", Vector3.ZERO, func(b: MeshBuilder) -> void:
		b.box("wood", Vector3(-0.06, 0, -0.06), Vector3(0.06, 2.2, 0.06), "snow"))
	var board_build := func(b: MeshBuilder) -> void:
		var pts_front := [Vector3(-0.25, -0.14, 0.12), Vector3(0.65, -0.14, 0.12), Vector3(0.85, 0.0, 0.12), Vector3(0.65, 0.14, 0.12), Vector3(-0.25, 0.14, 0.12)]
		var pts_back := []
		for p in pts_front:
			pts_back.append(p - Vector3(0, 0, 0.06))
		var faces := [pts_front, pts_back]
		var mats := ["wood_light", "wood_light"]
		for i in 5:
			var j := (i + 1) % 5
			faces.append([pts_front[i], pts_front[j], pts_back[j], pts_back[i]])
			mats.append("wood_dark")
		b.solid("wood_dark", faces, mats)
		b.box("snow", Vector3(-0.25, 0.14, 0.05), Vector3(0.65, 0.18, 0.13))
	var top := _part(root, "BoardTop", Vector3(0, 1.84, 0), board_build)
	var bottom := _part(root, "BoardBottom", Vector3(0, 1.44, 0), board_build)
	for pair in [[top, "TextTop"], [bottom, "TextBottom"]]:
		var t := Node3D.new()
		t.name = pair[1]
		t.position = Vector3(0.28, 0, 0.125)
		pair[0].add_child(t)
