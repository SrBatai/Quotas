class_name UiTheme
## Shared theme + style helpers (GDD §17 UI palette).

const PANEL_BG := Color("#1E2A3A", 0.88)
const PANEL_BG_SOLID := Color("#1E2A3A", 0.97)
const SLOT_BG := Color("#101826", 0.7)
const SLOT_HOVER := Color("#2A3A50", 0.9)
const BORDER := Color("#8FA6C0", 0.45)
const ICE := Color("#DCEBFA", 0.7)
const TEXT := Color("#EAF2FF")
const TEXT_2 := Color("#93A6BF")
const ACCENT := Color("#FFB454")
const PRIMARY_BG := Color("#DCEBFA")
const PRIMARY_TEXT := Color("#1E2A3A")
const DANGER := Color("#FF5A5A")
const HUNGER := Color("#E8A33C")
const HEALTH := Color("#E85A6E")
const WARMTH := Color("#4EC7B0")

static var _theme: Theme
static var _title_font: FontVariation
static var _bold_font: FontVariation


static func title_font() -> Font:
	if _title_font == null:
		_title_font = FontVariation.new()
		_title_font.base_font = ThemeDB.fallback_font
		_title_font.variation_embolden = 1.1
		_title_font.spacing_glyph = 2
	return _title_font


static func bold_font() -> Font:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.base_font = ThemeDB.fallback_font
		_bold_font.variation_embolden = 0.7
	return _bold_font


static func flat_box(bg: Color, border: Color = Color.TRANSPARENT, border_w: int = 1, radius: int = 4, margin: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w if border.a > 0.0 else 0)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


static func panel_box(margin: int = 10) -> StyleBoxFlat:
	return flat_box(PANEL_BG, BORDER, 1, 4, margin)


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 13
	t.set_stylebox("panel", "PanelContainer", panel_box(10))
	t.set_stylebox("panel", "Panel", panel_box(0))
	# buttons
	var normal := flat_box(Color("#101826", 0.7), BORDER, 1, 4, 8)
	var hover := flat_box(SLOT_HOVER, ICE, 1, 4, 8)
	var pressed := flat_box(Color("#0B121C", 0.9), ACCENT, 1, 4, 8)
	var disabled := flat_box(Color("#101826", 0.35), Color("#8FA6C0", 0.2), 1, 4, 8)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", Color("#93A6BF", 0.6))
	t.set_font_size("font_size", "Button", 14)
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 13)
	t.set_stylebox("panel", "TooltipPanel", flat_box(Color("#101826", 0.95), BORDER, 1, 3, 6))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 12)
	var pb_bg := flat_box(Color("#101826", 0.8), Color.TRANSPARENT, 0, 2, 0)
	var pb_fill := flat_box(ICE, Color.TRANSPARENT, 0, 2, 0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	_theme = t
	return t


## Convenience label factory.
static func label(text: String, size: int = 13, color: Color = TEXT, bold: bool = false, upper: bool = false, title: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if title:
		l.add_theme_font_override("font", title_font())
	elif bold:
		l.add_theme_font_override("font", bold_font())
	l.uppercase = upper
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", flat_box(PRIMARY_BG, Color.TRANSPARENT, 0, 3, 8))
	b.add_theme_stylebox_override("hover", flat_box(Color.WHITE, Color.TRANSPARENT, 0, 3, 8))
	b.add_theme_stylebox_override("pressed", flat_box(ACCENT, Color.TRANSPARENT, 0, 3, 8))
	b.add_theme_stylebox_override("disabled", flat_box(Color("#DCEBFA", 0.25), Color.TRANSPARENT, 0, 3, 8))
	b.add_theme_color_override("font_color", PRIMARY_TEXT)
	b.add_theme_color_override("font_hover_color", PRIMARY_TEXT)
	b.add_theme_color_override("font_pressed_color", PRIMARY_TEXT)
	b.add_theme_color_override("font_disabled_color", Color("#1E2A3A", 0.5))
	b.add_theme_font_override("font", title_font())
	b.add_theme_font_size_override("font_size", 13)
	return b


static func menu_button(text: String, min_width: float = 220.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 40)
	b.add_theme_font_override("font", bold_font())
	b.add_theme_font_size_override("font_size", 16)
	return b


## 2 px "ice edge" line at the top of a panel.
static func add_ice_edge(panel: Control) -> void:
	var edge := ColorRect.new()
	edge.color = ICE
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.set_anchors_preset(Control.PRESET_TOP_WIDE)
	edge.offset_left = 6
	edge.offset_right = -6
	edge.offset_top = 0
	edge.offset_bottom = 2
	panel.add_child(edge)


static func spacer(h: float = 4.0, v: float = 4.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(h, v)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func hspacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
