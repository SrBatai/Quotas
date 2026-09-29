class_name UiStyle
## Fonts, shared LabelSettings and the Theme of the HUD v2 «Susurro» (docs/research/10_hud_ux.md §V.2, §V.8).
## Barlow / Barlow Condensed (OFL, assets/fonts/) with real small caps (`smcp` + `c2sc`) and tabular figures
## (`tnum`) through FontVariation. Every label style is ONE shared LabelSettings per (style, colour): when the
## background turns bright (snow, blizzard) or the player picks "Grosor del texto: Reforzado", `refresh()` swaps
## the weights in place and every label follows (§V.1 rule 7, §V.7).

const FONT_DIR := "res://assets/fonts/"
const FONT_FILES := {
	&"extralight": "barlow/Barlow-ExtraLight.ttf",
	&"light": "barlow/Barlow-Light.ttf",
	&"regular": "barlow/Barlow-Regular.ttf",
	&"medium": "barlow/Barlow-Medium.ttf",
	&"semibold": "barlow/Barlow-SemiBold.ttf",
	&"cond_thin": "barlow_condensed/BarlowCondensed-Thin.ttf",
	&"cond_extralight": "barlow_condensed/BarlowCondensed-ExtraLight.ttf",
	&"cond_light": "barlow_condensed/BarlowCondensed-Light.ttf",
	&"cond_semibold": "barlow_condensed/BarlowCondensed-SemiBold.ttf",
}
## One step heavier ("Reforzado", or a Light style over a bright background).
const HEAVIER := {
	&"extralight": &"light", &"light": &"regular", &"regular": &"medium", &"medium": &"semibold",
	&"cond_thin": &"cond_extralight", &"cond_extralight": &"cond_light", &"cond_light": &"cond_semibold",
}

## Label styles: weight, size, default colour, tracking (em), OpenType features, bright-adaptive.
const STYLES := {
	&"whisper": {"w": &"light", "size": 18, "color": UiTokens.INK, "em": 0.0, "feat": [], "adapt": true},
	&"text_num": {"w": &"light", "size": 18, "color": UiTokens.INK, "em": 0.0, "feat": ["tnum"], "adapt": true},
	&"main": {"w": &"light", "size": 22, "color": UiTokens.INK, "em": 0.0, "feat": [], "adapt": true},
	&"main_num": {"w": &"regular", "size": 22, "color": UiTokens.INK, "em": 0.0, "feat": ["tnum"], "adapt": false},
	&"meta": {"w": &"light", "size": 16, "color": UiTokens.INK_70, "em": 0.0, "feat": ["tnum"], "adapt": true},
	&"smallcaps": {"w": &"regular", "size": 16, "color": UiTokens.INK, "em": 0.16, "feat": ["smcp", "c2sc"], "adapt": false},
	&"smallcaps_wide": {"w": &"regular", "size": 16, "color": UiTokens.INK, "em": 0.20, "feat": ["smcp", "c2sc"], "adapt": false},
	&"item_name": {"w": &"regular", "size": 18, "color": UiTokens.INK, "em": 0.0, "feat": ["tnum"], "adapt": false},
	&"name": {"w": &"regular", "size": 16, "color": UiTokens.INK, "em": 0.0, "feat": ["tnum"], "adapt": false},
	&"name_l": {"w": &"regular", "size": 20, "color": UiTokens.INK, "em": 0.0, "feat": ["tnum"], "adapt": false},
	&"zone_eyebrow": {"w": &"regular", "size": 16, "color": UiTokens.INK_70, "em": 0.50, "feat": ["smcp", "c2sc"], "adapt": false},
	&"zone_facts": {"w": &"light", "size": 19, "color": UiTokens.INK, "em": 0.08, "feat": ["tnum"], "adapt": true},
	&"list_mission": {"w": &"light", "size": 26, "color": UiTokens.INK, "em": 0.0, "feat": [], "adapt": true},
	&"list_step": {"w": &"light", "size": 20, "color": UiTokens.INK, "em": 0.0, "feat": ["tnum"], "adapt": true},
	&"list_detail": {"w": &"light", "size": 18, "color": UiTokens.INK_70, "em": 0.0, "feat": ["tnum"], "adapt": true},
	&"down_title": {"w": &"cond_light", "size": 40, "color": UiTokens.BLOOD_TEXT, "em": 0.16, "feat": ["tnum"], "adapt": false},
}

static var _files: Dictionary = {}
static var _variations: Dictionary = {}
static var _settings: Dictionary = {}          # key -> LabelSettings
static var _settings_spec: Dictionary = {}     # key -> [style, color]
static var bright: bool = false
static var bold: bool = false
static var _theme: Theme


static func font_file(weight: StringName) -> Font:
	if not _files.has(weight):
		var path: String = FONT_DIR + String(FONT_FILES.get(weight, FONT_FILES[&"regular"]))
		var f: Font = load(path) if ResourceLoader.exists(path) else ThemeDB.fallback_font
		_files[weight] = f
	return _files[weight]


## FontVariation of a weight with OpenType features and a letter spacing in px (cached; do not modify).
static func font(weight: StringName, features: Array = [], spacing: int = 0) -> FontVariation:
	var key := "%s|%s|%d" % [weight, ",".join(features), spacing]
	if _variations.has(key):
		return _variations[key]
	var fv := FontVariation.new()
	fv.base_font = font_file(weight)
	fv.spacing_glyph = spacing
	var feats := {}
	var ts := TextServerManager.get_primary_interface()
	for f: String in features:
		feats[ts.name_to_tag(f)] = 1
	fv.opentype_features = feats
	_variations[key] = fv
	return fv


## Effective weight of a style right now (bold setting, bright background).
static func weight_of(style: StringName) -> StringName:
	var spec: Dictionary = STYLES.get(style, STYLES[&"whisper"])
	var w: StringName = spec["w"]
	if bold:
		w = HEAVIER.get(w, w)
	if bright and bool(spec["adapt"]) and (w == &"light" or w == &"extralight"):
		w = HEAVIER.get(w, w)
	return w


static func font_of(style: StringName) -> FontVariation:
	var spec: Dictionary = STYLES.get(style, STYLES[&"whisper"])
	return font(weight_of(style), spec["feat"], UiTokens.tracking(int(spec["size"]), float(spec["em"])))


static func size_of(style: StringName) -> int:
	return int((STYLES.get(style, STYLES[&"whisper"]) as Dictionary)["size"])


## Shared LabelSettings of a style in a colour (default: the style's colour).
static func settings(style: StringName, color: Color = Color(0, 0, 0, 0)) -> LabelSettings:
	var spec: Dictionary = STYLES.get(style, STYLES[&"whisper"])
	var c: Color = spec["color"] if color.a == 0.0 else color
	var key := "%s|%s" % [style, c.to_html()]
	if _settings.has(key):
		return _settings[key]
	var ls := LabelSettings.new()
	ls.font_size = int(spec["size"])
	ls.font_color = c
	apply_shadow(ls)
	ls.font = font_of(style)
	_settings[key] = ls
	_settings_spec[key] = style
	return ls


## Shared LabelSettings of a style for a panel that lives in the 1280 × 720 canvas (outside the HUD's reference
## space): size and shadows × `factor` (2/3 for 720p units).
static func settings_scaled(style: StringName, factor: float, color: Color = Color(0, 0, 0, 0)) -> LabelSettings:
	var base := settings(style, color)
	var key := "%s|%s|x%.3f" % [style, base.font_color.to_html(), factor]
	if _settings.has(key):
		return _settings[key]
	var ls := base.duplicate() as LabelSettings
	ls.font_size = maxi(int(round(float(base.font_size) * factor)), 8)
	for i in ls.stacked_shadow_count:
		ls.set("stacked_shadow_%d/outline_size" % i, maxi(int(round(float(ls.get("stacked_shadow_%d/outline_size" % i)) * factor)), 1))
	_settings[key] = ls
	_settings_spec[key] = style
	return ls


static func apply_shadow(ls: LabelSettings, strength: float = 1.0) -> void:
	ls.shadow_size = UiTokens.SHADOW_SIZE
	ls.shadow_color = Color(UiTokens.SHADOW_COLOR, UiTokens.SHADOW_COLOR.a * strength)
	ls.shadow_offset = UiTokens.SHADOW_OFFSET
	ls.stacked_shadow_count = UiTokens.SHADOW_STACK.size()
	for i in UiTokens.SHADOW_STACK.size():
		var layer: Array = UiTokens.SHADOW_STACK[i]
		ls.set("stacked_shadow_%d/offset" % i, UiTokens.SHADOW_OFFSET)
		ls.set("stacked_shadow_%d/color" % i, Color(0, 0, 0, float(layer[1]) * strength))
		ls.set("stacked_shadow_%d/outline_size" % i, int(layer[0]))


## New Label using a shared style.
static func label(style: StringName, text: String = "", color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.label_settings = settings(style, color)
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Re-applies the weights after `bright` / `bold` changed. Cheap: only the font reference of each cached
## LabelSettings changes, labels redraw on their own.
static func set_flags(p_bright: bool, p_bold: bool) -> void:
	if p_bright == bright and p_bold == bold:
		return
	bright = p_bright
	bold = p_bold
	for key: String in _settings:
		(_settings[key] as LabelSettings).font = font_of(_settings_spec[key])


## Draws text with the whisper shadow (stacked outlines) in a custom `_draw()` (world-anchored labels).
static func draw_text(ci: CanvasItem, style: StringName, pos: Vector2, text: String, color: Color = Color(0, 0, 0, 0),
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, alpha: float = 1.0) -> void:
	var spec: Dictionary = STYLES.get(style, STYLES[&"whisper"])
	var f := font_of(style)
	var size := int(spec["size"])
	var c: Color = spec["color"] if color.a == 0.0 else color
	c.a *= alpha
	for layer: Array in UiTokens.SHADOW_STACK:
		ci.draw_string_outline(f, pos + UiTokens.SHADOW_OFFSET, text, align, width, size, int(layer[0]), Color(0, 0, 0, float(layer[1]) * alpha))
	ci.draw_string_outline(f, pos + UiTokens.SHADOW_OFFSET, text, align, width, size, UiTokens.SHADOW_SIZE, Color(0, 0, 0, UiTokens.SHADOW_COLOR.a * alpha))
	ci.draw_string(f, pos + UiTokens.SHADOW_OFFSET, text, align, width, size, Color(0, 0, 0, UiTokens.SHADOW_COLOR.a * alpha))
	ci.draw_string(f, pos, text, align, width, size, c)


static func text_width(style: StringName, text: String) -> float:
	return font_of(style).get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_of(style)).x


# ------------------------------------------------------------------ Theme resource (tokens of §V.2)
## The HUD Theme: no panel styleboxes (§V.8), Barlow Light 18 by default, type variations per label style and
## every token (colours, constants, timings in ms) under the type "Susurro". Saved to assets/ui/susurro_theme.tres
## by tools/gen_hud_theme.gd; the HUD loads that file and falls back to this builder.
static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font(&"light")
	t.default_font_size = UiTokens.TEXT_SIZE
	t.set_color("font_color", "Label", UiTokens.INK)
	t.set_color("font_shadow_color", "Label", UiTokens.SHADOW_COLOR)
	t.set_constant("shadow_offset_x", "Label", int(UiTokens.SHADOW_OFFSET.x))
	t.set_constant("shadow_offset_y", "Label", int(UiTokens.SHADOW_OFFSET.y))
	t.set_constant("shadow_outline_size", "Label", UiTokens.SHADOW_SIZE)
	var variations := {
		&"LabelWhisper": &"whisper", &"LabelMain": &"main", &"LabelNum": &"main_num", &"LabelMeta": &"meta",
		&"LabelSmallCaps": &"smallcaps", &"LabelZoneTitle": &"", &"LabelZoneEyebrow": &"zone_eyebrow",
		&"LabelZoneFacts": &"zone_facts", &"LabelListMission": &"list_mission", &"LabelListStep": &"list_step",
		&"LabelListDetail": &"list_detail",
	}
	for v: StringName in variations:
		t.set_type_variation(v, "Label")
		var style: StringName = variations[v]
		if style == &"":
			t.set_font("font", v, font(&"cond_extralight", [], UiTokens.tracking(UiTokens.ZONE_TITLE_SIZE, UiTokens.ZONE_TITLE_EM)))
			t.set_font_size("font_size", v, UiTokens.ZONE_TITLE_SIZE)
			t.set_color("font_color", v, Color("#F6FAFE"))
			continue
		var spec: Dictionary = STYLES[style]
		t.set_font("font", v, font(spec["w"], spec["feat"], UiTokens.tracking(int(spec["size"]), float(spec["em"]))))
		t.set_font_size("font_size", v, int(spec["size"]))
		t.set_color("font_color", v, spec["color"])
	var colors := {
		"ink": UiTokens.INK, "ink_70": UiTokens.INK_70, "ink_50": UiTokens.INK_50, "ink_30": UiTokens.INK_30,
		"hair": UiTokens.HAIR, "accent": UiTokens.ACCENT, "cold": UiTokens.COLD, "blood": UiTokens.BLOOD,
		"warn": UiTokens.WARN, "scrim": UiTokens.SCRIM_RGB, "shadow": UiTokens.SHADOW_COLOR,
	}
	for i in UiTokens.PLAYERS.size():
		colors["player_%d" % i] = UiTokens.PLAYERS[i]
	for k: String in colors:
		t.set_color(k, "Susurro", colors[k])
	var consts := {
		"safe_x": int(UiTokens.SAFE_X), "safe_y": int(UiTokens.SAFE_Y),
		"shadow_size": UiTokens.SHADOW_SIZE, "shadow_offset_y": int(UiTokens.SHADOW_OFFSET.y),
		"scrim_min_pct": int(round(UiTokens.SCRIM_MIN * 100.0)), "scrim_max_pct": int(round(UiTokens.SCRIM_MAX * 100.0)),
		"scrim_luma_lo_pct": int(round(UiTokens.SCRIM_LUMA_LO * 100.0)), "scrim_luma_hi_pct": int(round(UiTokens.SCRIM_LUMA_HI * 100.0)),
		"weight_title": UiTokens.W_TITLE, "weight_default": UiTokens.W_DEFAULT, "weight_smallcaps": UiTokens.W_SMALLCAPS,
		"size_min": UiTokens.MIN_SIZE, "size_main": UiTokens.MAIN_SIZE, "size_text": UiTokens.TEXT_SIZE,
		"size_zone_title": UiTokens.ZONE_TITLE_SIZE, "curve_trans": UiTokens.CURVE_TRANS,
		"curve_in": UiTokens.CURVE_IN, "curve_out": UiTokens.CURVE_OUT, "move_max": int(UiTokens.MOVE_MAX),
	}
	var timings := {
		"vital": UiTokens.T_VITAL, "hotbar": UiTokens.T_HOTBAR, "objective": UiTokens.T_OBJECTIVE,
		"pickup": UiTokens.T_PICKUP, "hazard": UiTokens.T_HAZARD, "zone_first": UiTokens.T_ZONE_FIRST,
		"zone_reentry": UiTokens.T_ZONE_REENTRY, "edge": UiTokens.T_EDGE, "info": UiTokens.T_INFO,
	}
	for k: String in timings:
		var tt: Array = timings[k]
		consts[k + "_in_ms"] = int(round(float(tt[0]) * 1000.0))
		consts[k + "_read_ms"] = int(round(float(tt[1]) * 1000.0))
		consts[k + "_out_ms"] = int(round(float(tt[2]) * 1000.0))
	for k: String in consts:
		t.set_constant(k, "Susurro", int(consts[k]))
	return t


## The HUD theme (the saved resource when present, else built from the tokens).
static func theme() -> Theme:
	if _theme == null:
		var path := "res://assets/ui/susurro_theme.tres"
		_theme = load(path) as Theme if ResourceLoader.exists(path) else null
		if _theme == null:
			_theme = build_theme()
	return _theme
