class_name UiIcons
## Icon loader: rendered item icons (assets/icons/items/<name>.png, built by blender/icons/build_icons.py) first,
## then the flat SVG pictogram, then a lettered fallback.

static var _cache: Dictionary = {}


## `rendered` = prefer the 3D-rendered item icon (items, recipes); UI glyphs (categories, HUD) stay flat SVG.
static func tex(icon_name: String, rendered: bool = false) -> Texture2D:
	if icon_name == "":
		return null
	var key := ("r:" if rendered else "s:") + icon_name
	if _cache.has(key):
		return _cache[key]
	var t: Texture2D = null
	var paths: Array[String] = ["res://assets/icons/%s.svg" % icon_name]
	if rendered:
		paths.push_front("res://assets/icons/items/%s.png" % icon_name)
	for path: String in paths:
		if ResourceLoader.exists(path, "Texture2D"):
			t = load(path) as Texture2D
			break
	_cache[key] = t
	return t


## TextureRect (or a lettered fallback panel) of the given size.
static func make(icon_name: String, size: float, tint: Color = Color.WHITE, fallback_letter: String = "", rendered: bool = false) -> Control:
	var t := tex(icon_name, rendered)
	if t != null:
		var tr := TextureRect.new()
		tr.texture = t
		tr.custom_minimum_size = Vector2(size, size)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		tr.modulate = tint
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(size, size)
	p.add_theme_stylebox_override("panel", UiTheme.flat_box(Color(tint.r, tint.g, tint.b, 0.85), Color.TRANSPARENT, 0, int(size * 0.2), 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(fallback_letter if fallback_letter != "" else icon_name.substr(0, 1).to_upper(), int(size * 0.5), Color("#101826"), true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


static func item_icon(id: StringName, size: float) -> Control:
	var n := Items.icon_name(id)
	return make(n, size, Items.tint(id) if tex(n, true) == null else Color.WHITE, Items.display_name(id).substr(0, 1), true)
