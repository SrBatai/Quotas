@tool
extends EditorScenePostImport
## A1 post-import for every assets/models/city/**.glb (set as `import_script/path` in their .import files).
## Godot 4.7's glTF importer keeps node extras (node meta "extras") but drops the glTF *scene* extras, where the
## Blender pipeline writes the city-building root metadata. This copies the extras of the first piece that carries
## them (`Base` for towers / buildings, `Body` for vehicles, `Prop` for props and highway pieces) to the scene root,
## both as meta "extras" and as individual meta keys, so CityBuilding.meta_of(root, "floor_h", …) and the prop /
## vehicle spawners read floor_h, ground_h, floors, kind, anchors, col_* from the root. Per-piece keys (cut_group,
## floor_from / floor_to, z_from / z_to) stay on their piece.

const PIECE_KEYS := ["cut_group", "floor_from", "floor_to", "z_from", "z_to"]


func _post_import(scene: Node) -> Object:
	for piece in ["Base", "Body", "Prop"]:
		var n := scene.get_node_or_null(piece)
		if n == null or not n.has_meta("extras"):
			continue
		var ex: Variant = n.get_meta("extras")
		if not (ex is Dictionary):
			continue
		var root_ex := {}
		for k in (ex as Dictionary):
			if not PIECE_KEYS.has(str(k)):
				root_ex[k] = ex[k]
				scene.set_meta(StringName(str(k)), ex[k])
		scene.set_meta("extras", root_ex)
		break
	return scene
