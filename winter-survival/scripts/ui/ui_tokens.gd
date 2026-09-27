class_name UiTokens
## Design tokens of the HUD v2 «Susurro» (docs/research/10_hud_ux.md §V.2), in pixels of the 1920 × 1080
## reference at UI scale 100 %. Same names as `mockups/hud_v2.css`. The Theme resource
## (`assets/ui/susurro_theme.tres`, built by `UiStyle.build_theme()`) and the shared LabelSettings of `UiStyle`
## are generated from these values; nothing else in the HUD hard-codes a colour, a size or a timing.

# ------------------------------------------------------------------ reference frame and safe area (§V.2.3)
const REF_SIZE := Vector2(1920.0, 1080.0)
const SAFE_X := 64.0
const SAFE_Y := 52.0
## The edge rail sits this far inside the safe area (appendix §6.4.2 used 36 px; v2 draws the marker at 40 px).
const RAIL_INSET := -24.0
const UI_SCALE_MIN := 0.8
const UI_SCALE_MAX := 1.5
const UI_SCALE_DECK := 1.15
## "Margen de pantalla" (appendix §5.7): 0–5 % per side on top of the safe area (TV overscan).
const SCREEN_MARGIN_MAX := 0.05

# ------------------------------------------------------------------ colour (§V.2.2)
const INK_RGB := Color("#F3F8FD")
const INK := Color(0.9529, 0.9725, 0.9922, 0.92)
const INK_70 := Color(0.9529, 0.9725, 0.9922, 0.70)
const INK_50 := Color(0.9529, 0.9725, 0.9922, 0.52)
const INK_30 := Color(0.9529, 0.9725, 0.9922, 0.32)
const HAIR := Color(0.9529, 0.9725, 0.9922, 0.38)
## Strip of the folded hotbar (mockup `.strip i`: 28 % idle, 85 % the slot in hand).
const STRIP := Color(0.9529, 0.9725, 0.9922, 0.28)
const STRIP_ON := Color(0.9529, 0.9725, 0.9922, 0.85)
const ACCENT := Color("#FFB454")
const COLD := Color("#A6DCF5")
const BLOOD := Color("#F07A86")
const WARN := Color("#F2D58A")
## Softer tints of the semantic colours for numbers / names drawn over the world (mockups b, d, e).
const ACCENT_TEXT := Color("#FFE2BD")
const BLOOD_TEXT := Color("#FFC2C8")
const COLD_TEXT := Color("#D4F0FF")
const PLAYERS: Array[Color] = [Color("#7CC8FF"), Color("#C9A6FF"), Color("#9DE07F"), Color("#FF9FC6")]
const PLAYERS_TEXT: Array[Color] = [Color("#BFE3FF"), Color("#E4D3FF"), Color("#CFF0BF"), Color("#FFD0E3")]
## Colour-blind safe alternative for the four player colours (Okabe–Ito: sky blue, orange, bluish green, yellow).
const PLAYERS_CB: Array[Color] = [Color("#56B4E9"), Color("#E69F00"), Color("#009E73"), Color("#F0E442")]

# ------------------------------------------------------------------ shadow, scrim, hairlines (§V.2.3)
## Tight drop shadow (CSS `0 1px 2px rgba(0,0,0,.62)`).
const SHADOW_COLOR := Color(0, 0, 0, 0.55)
const SHADOW_OFFSET := Vector2(0.0, 1.0)
const SHADOW_SIZE := 1
## Godot draws label shadows as hard outlines: the CSS blur (`0 0 10px .42`, `0 0 26px .22`) is approximated by
## stacked outlines of growing size and falling alpha ([outline px, alpha]).
const SHADOW_STACK := [[4, 0.12], [9, 0.07], [16, 0.045], [26, 0.025]]
## Scrim: radial closest-side gradient rgba(4, 8, 14, α) → α/2 at 55 % → 0.
const SCRIM_RGB := Color(4.0 / 255.0, 8.0 / 255.0, 14.0 / 255.0)
const SCRIM_MIN := 0.18
const SCRIM_MAX := 0.45
const SCRIM_LUMA_LO := 0.35
const SCRIM_LUMA_HI := 0.80
## "Fondo del texto: Opaco" (§V.7): the scrim goes to 70 %, still soft-edged.
const SCRIM_OPAQUE := 0.70
## Text gets one weight heavier above this background luma (§V.1 rule 7).
const BRIGHT_LUMA := 0.62
const HAIR_FADE_A := 0.18
const HAIR_FADE_B := 0.82
const LINE_ICON_STROKE := 1.5

# ------------------------------------------------------------------ typography (§V.2.1): [size, weight, tracking em]
const ZONE_TITLE_SIZE := 76
const ZONE_TITLE_EM := 0.42
const ZONE_TITLE_EM_FROM := 0.78
const ZONE_EYEBROW_SIZE := 16
const ZONE_EYEBROW_EM := 0.50
const ZONE_FACTS_SIZE := 19
const ZONE_FACTS_EM := 0.08
const MAIN_SIZE := 22
const LIST_MISSION_SIZE := 26
const LIST_STEP_SIZE := 20
const LIST_DETAIL_SIZE := 18
const TEXT_SIZE := 18
const SMALLCAPS_SIZE := 16
const SMALLCAPS_EM := 0.16
const SMALLCAPS_WIDE_EM := 0.20
const MIN_SIZE := 16
## Deck legibility floor (appendix §8.9): font_size × total scale ≥ 12 px on 1280 × 800.
const DECK_MIN_PX := 12.0
const W_TITLE := 200
const W_DEFAULT := 300
const W_SMALLCAPS := 400

# ------------------------------------------------------------------ shapes (§V.2.3, §V.4)
const DIAMOND := 10.0
const DIAMOND_INLINE := 8.0
const RING := 40.0
const RING_STROKE := 2.0
const RING_DOWNED := 46.0
const STAMINA_RING := 26.0
const EDGE_ARROW := 6.0
const HOTBAR_STROKE := Vector2(22.0, 2.0)
const HOTBAR_STROKE_GAP := 6.0
const HOTBAR_BOTTOM := 40.0
const HOTBAR_ICON := 40.0
const HOTBAR_CELL := 44.0
const HOTBAR_GAP := 14.0
const HOTBAR_LIFT := 6.0
const HOLD_RING := 40.0
const OBJECTIVE_RULE := 300.0
const ZONE_RULE := 520.0
const HAZARD_RULE := 260.0
const INFO_RULE := 300.0
const PLAYER_DOT := 7.0
## Ground ellipse ratio of the camera (sin 48°) for rings drawn on the floor.
const GROUND_RATIO := 0.74

# ------------------------------------------------------------------ timings in seconds (§V.2.4): in, read, out
const T_VITAL := [0.24, 4.0, 0.8]
const T_HOTBAR := [0.18, 3.0, 0.6]
const T_ITEM_NAME := [0.18, 1.5, 0.6]
const T_OBJECTIVE := [0.32, 5.0, 1.0]
const T_OBJECTIVE_RULE := 0.6
const T_PICKUP := [0.2, 2.5, 0.6]
const T_PICKUP_MERGE := 1.0
const T_PICKUP_MAX := 5.0
const T_HAZARD := [0.3, 5.0, 0.8]
const T_ZONE_FIRST := [1.4, 4.0, 1.6]     # read = until t = 4.0 s; 5.6 s in total
const T_ZONE_REENTRY := [0.6, 1.4, 0.5]
const T_EDGE := [0.24, 5.0, 0.6]
const T_INFO := [0.16, 0.0, 0.3]
const T_CLOCK := [0.24, 4.0, 0.8]
const T_TEAM := [0.24, 0.0, 0.6]
const T_CHAT := 6.0
const T_BANNER := [0.22, 3.0, 0.3]
const T_PROMPT := [0.16, 0.0, 0.25]
const T_DAMAGE_FLASH := 0.25
const T_DAMAGE_ARC := 0.6
## Stamina arc fades this long after refilling.
const T_STAMINA_FULL := 1.0
## Reduced motion: every transition becomes a plain fade of this length (§V.2.4).
const T_REDUCED := 0.2
const MOVE_MAX := 6.0
const CURVE_TRANS := Tween.TRANS_SINE
const CURVE_IN := Tween.EASE_OUT
const CURVE_OUT := Tween.EASE_IN_OUT

# ------------------------------------------------------------------ behaviour thresholds (§V.3)
const HEALTH_SHOW_BELOW := 50.0
const HEALTH_DELTA := 2.0
const HEALTH_DELTA_WINDOW := 2.0
const WARMTH_SHOW_BELOW := 40.0
const WARMTH_DROP_RATE := 1.0
const FEELS_DELTA := 5.0
const HUNGER_SHOW_BELOW := 30.0
const LOW_FRACTION := 0.25
const FROST_START := 40.0
const HEAT_ACCENT_BELOW := 30.0
const HEAT_RANGE := 60.0
const TEAM_FAR := 25.0
const TEAM_HURT := 0.25
const MARKER_RANGE := 300.0
const MARKER_NEAR := 6.0
const INTERACT_RANGE := 2.5
const ZONE_INSET := 12.0
const ZONE_DWELL := 1.5
const ZONE_COOLDOWN := 90.0
const ZONE_GAP := 20.0
const COMBAT_WINDOW := 5.0
const HOLD_INFO := 0.22
const NOTIFY_QUEUE := 6
const NOTIFY_PREEMPT_AFTER := 1.2
const NOTIFY_REFRESH_WINDOW := 10.0
const NOTIFY_KEY_COOLDOWN := 8.0
const PICKUP_LINES := 4


## Adaptive scrim alpha from the background luma (§V.2.3): α = mix(0.18, 0.45, smoothstep(0.35, 0.80, luma)).
static func scrim_alpha(luma: float) -> float:
	return lerpf(SCRIM_MIN, SCRIM_MAX, smoothstep(SCRIM_LUMA_LO, SCRIM_LUMA_HI, luma))


## Letter spacing in whole pixels for a size and an em value (FontVariation.spacing_glyph is an int).
static func tracking(size: int, em: float) -> int:
	return int(round(float(size) * em))


## Player colour by outfit / join order (0..3).
static func player_color(i: int, colorblind: bool = false) -> Color:
	var list := PLAYERS_CB if colorblind else PLAYERS
	return list[posmod(i, list.size())]


static func player_text_color(i: int) -> Color:
	return PLAYERS_TEXT[posmod(i, PLAYERS_TEXT.size())]


# ------------------------------------------------------------------ number formats (appendix §6.4.2, Spanish)
## "84 m" below 100 m, "640 m" (tens) below 1 km, "1,4 km" above.
static func distance(m: float) -> String:
	if m < 100.0:
		return "%d m" % int(round(m))
	if m < 999.5:
		return "%d m" % (int(round(m / 10.0)) * 10)
	return ("%.1f km" % (m / 1000.0)).replace(".", ",")


## "−18 °C" with a true minus sign (U+2212).
static func temperature(c: float) -> String:
	var v := int(round(c))
	return ("−%d °C" % absi(v)) if v < 0 else ("%d °C" % v)


## Clock "15:20" from a 0..24 hour.
static func clock(hour: float) -> String:
	var h := int(floor(hour)) % 24
	var m := int(floor((hour - floor(hour)) * 60.0))
	return "%d:%02d" % [h, m]


## Countdown "2:40" (minutes:seconds) from seconds.
static func countdown(seconds: float) -> String:
	var s := maxi(int(ceil(seconds - 0.001)), 0)
	return "%d:%02d" % [s / 60, s % 60]
