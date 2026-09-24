class_name UiIcons
## SVG icon loader with a lettered fallback.

static var _cache: Dictionary = {}


static func tex(icon_name: String) -> Texture2D:
	if icon_name == "":
		return null
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := "res://assets/icons/%s.svg" % icon_name
	var t: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		t = load(path) as Texture2D
	_cache[icon_name] = t
	return t


## TextureRect (or a lettered fallback panel) of the given size.
static func make(icon_name: String, size: float, tint: Color = Color.WHITE, fallback_letter: String = "") -> Control:
	var t := tex(icon_name)
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
	return make(Items.icon_name(id), size, Items.tint(id) if tex(Items.icon_name(id)) == null else Color.WHITE, Items.display_name(id).substr(0, 1))
