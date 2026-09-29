class_name SignText
## Diegetic sign text (M6a, docs/research/10_hud_ux.md §7.4: cap height >= 0.30 m ambient, >= 0.45 m for what must
## read at the max zoom): text MESHES composed from the mesh font res://assets/models/signs/glyphs.glb (Barlow
## Condensed SemiBold cut to flat meshes, cap height 1, one `G_<codepoint>` mesh per glyph with extras char / advance;
## blender/props/build_signs.py). No Label3D, no font atlas: the letters are geometry with vertex colour, lit by the
## scene like the board they sit on, identical in Forward+, Compatibility and Web, sharp at any distance. One
## ArrayMesh (one draw call) per text, cached by (text, cap, colour, width); the shared world_vcol material.
## Boards (signs/sign_street, sign_house_number, sign_shop, sign_road): `Prop` (+ extras text_w, text_h, text_color,
## plate_color, double_sided), `Panel`, `TextPanel_0` (front, +Z) and `TextPanel_1` (back, -Z) — place() puts the
## text on them.

const GLYPHS := "res://assets/models/signs/glyphs.glb"
const SPACE := 0.32
const LINE_GAP := 0.42
## Palette colours the boards name (sRGB, blender/lib/palette.py).
const COLORS := {"paint_white": "#E6E9EC", "metal_blue": "#4D6B8A", "cabin_trim": "#D3CFC6", "paint_black": "#1C1E22",
	"paint_red": "#A83A32", "military_green": "#4F5A3C", "paint_yellow": "#E0B93A"}

static var _glyphs: Dictionary = {}     # char -> [Mesh, advance]
static var _loaded: bool = false
static var _cache: Dictionary = {}


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(GLYPHS):
		push_warning("SignText: %s missing (blender/props/build_signs.py)" % GLYPHS)
		return
	var root := (load(GLYPHS) as PackedScene).instantiate()
	for c in root.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var ex: Dictionary = c.get_meta("extras", {})
			if ex.has("char"):
				_glyphs[str(ex["char"])] = [(c as MeshInstance3D).mesh, float(ex.get("advance", 0.5))]
	root.free()


static func has_glyph(ch: String) -> bool:
	_ensure()
	return _glyphs.has(ch)


## Width of one line in cap units.
static func line_width(line: String) -> float:
	_ensure()
	var w := 0.0
	for ch in line:
		w += float((_glyphs[ch] as Array)[1]) if _glyphs.has(ch) else SPACE
	return maxf(w - 0.1, 0.0)


static func color_of(name: String) -> Color:
	return Color(str(COLORS.get(name, "#E6E9EC")))


## Text mesh (uppercase; "\n" separates lines, each centred; lines wider than max_w are condensed to fit), in the
## XY plane facing +Z, centred on the origin. `color` is sRGB (written linear, like the art's COLOR_0).
static func build(text: String, cap: float, color: Color, max_w: float = 0.0) -> ArrayMesh:
	_ensure()
	var key := "%s|%.3f|%s|%.3f" % [text, cap, color.to_html(), max_w]
	if _cache.has(key):
		return _cache[key]
	var lines := text.to_upper().split("\n")
	var n := lines.size()
	var total_h := float(n) * cap + float(n - 1) * cap * LINE_GAP
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for li in n:
		var line: String = lines[li]
		var w := line_width(line)
		var sx := cap
		if max_w > 0.0 and w * cap > max_w:
			sx = max_w / w
		var x := -w * sx * 0.5
		var y := total_h * 0.5 - cap - float(li) * cap * (1.0 + LINE_GAP)
		for ch in line:
			if not _glyphs.has(ch):
				x += SPACE * sx
				continue
			var g: Array = _glyphs[ch]
			var m: Mesh = g[0]
			for s in m.get_surface_count():
				var arr := m.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var ii = arr[Mesh.ARRAY_INDEX]
				var base := verts.size()
				for v in vs:
					verts.append(Vector3(x + v.x * sx, y + v.y * cap, v.z))
					normals.append(Vector3.BACK)
				if ii is PackedInt32Array and (ii as PackedInt32Array).size() > 0:
					for k in ii:
						idx.append(base + k)
				else:
					for k in vs.size():
						idx.append(base + k)
			x += float(g[1]) * sx
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		_cache[key] = mesh
		return mesh
	var lin := color.srgb_to_linear()
	lin.a = 1.0
	var cols := PackedColorArray()
	cols.resize(verts.size())
	cols.fill(lin)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, Assets.get_shared_material())
	_cache[key] = mesh
	return mesh


## Spawns a board (res://assets/models/<board>.glb) at `xf` under `parent` with `front` on TextPanel_0 and `back` on
## TextPanel_1 ("" = none; "strike" = the front text struck through with a red bar, the S-510 end-of-town sign).
## Cap height / width / colour from the board's Prop extras (`cap` > 0 overrides the height). Returns the board.
static func place(parent: Node3D, board: String, xf: Transform3D, front: String, back: String = "", cap: float = 0.0) -> Node3D:
	var root := Assets.spawn_model(board)
	root.name = "Sign_%s" % board.get_file()
	root.transform = xf
	parent.add_child(root)
	var prop := root.get_node_or_null("Prop")
	var ex: Dictionary = prop.get_meta("extras", {}) if prop != null else {}
	var h := cap if cap > 0.0 else float(ex.get("text_h", 0.34))
	var w := float(ex.get("text_w", 2.0))
	var col := color_of(str(ex.get("text_color", "paint_white")))
	for side in [0, 1]:
		var txt := front if side == 0 else back
		if txt == "strike":
			txt = front
		var anchor := root.get_node_or_null("TextPanel_%d" % side) as Node3D
		if txt == "" or anchor == null:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Text_%d" % side
		mi.mesh = build(txt, h, col, w)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = anchor.position
		if side == 1:
			mi.rotation.y = PI
		root.add_child(mi)
		if side == 1 and back == "strike":
			var bar := MeshInstance3D.new()
			bar.name = "Strike"
			var bm := BoxMesh.new()
			bm.size = Vector3(w * 0.95, h * 0.22, 0.004)
			bar.mesh = bm
			bar.material_override = _strike_material()
			bar.position = anchor.position + Vector3(0, 0, -0.003)
			bar.rotation = Vector3(0, PI, deg_to_rad(-12.0))
			bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(bar)
	return root


static var _strike: StandardMaterial3D


static func _strike_material() -> StandardMaterial3D:
	if _strike == null:
		_strike = StandardMaterial3D.new()
		_strike.albedo_color = Color("#A83A32")
		_strike.roughness = 0.9
	return _strike
