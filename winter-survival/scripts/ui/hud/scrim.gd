class_name Scrim
extends Control
## Soft veil behind a group of HUD text (docs/research/10_hud_ux.md §V.2.3): NOT a box — a radial closest-side
## gradient rgba(4, 8, 14, α) → α/2 at 55 % → 0, whose α adapts to the background luma:
## α = mix(0.18, 0.45, smoothstep(0.35, 0.80, luma)) (`UiTokens.scrim_alpha`). The HUD writes the luma estimate
## into `Scrim.base_alpha` (4 Hz) and redraws the group "hud_scrim". "Fondo del texto: Opaco" raises α to 70 %.
## Scrims are left out of the coverage measure (§V.5), so they live in the group "hud_scrim".
## `linear` = the side veil of the Info mission list (74 % → 0 at 58 % of the width, §V.4.8).

static var base_alpha: float = 0.36
## The coverage measure (§V.5) leaves the scrims out: while true they draw nothing.
static var suppressed: bool = false
static var _radial: GradientTexture2D
static var _linear: GradientTexture2D

@export var strength: float = 1.0
@export var linear: bool = false
## ≥ 0: a fixed α instead of the adaptive one (the zone title's veil is 46 %, §V.4.4).
@export var fixed_alpha: float = -1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("hud_scrim")


func _ready() -> void:
	queue_redraw()


static func radial_texture() -> GradientTexture2D:
	if _radial == null:
		var g := Gradient.new()
		g.set_color(0, Color(UiTokens.SCRIM_RGB, 1.0))
		g.set_color(1, Color(UiTokens.SCRIM_RGB, 0.0))
		g.add_point(0.55, Color(UiTokens.SCRIM_RGB, 0.5))
		_radial = GradientTexture2D.new()
		_radial.gradient = g
		_radial.fill = GradientTexture2D.FILL_RADIAL
		_radial.fill_from = Vector2(0.5, 0.5)
		_radial.fill_to = Vector2(1.0, 0.5)
		_radial.width = 128
		_radial.height = 128
	return _radial


static func linear_texture() -> GradientTexture2D:
	if _linear == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.26, 0.42, 0.58, 1.0])
		g.colors = PackedColorArray([Color(UiTokens.SCRIM_RGB, 0.74), Color(UiTokens.SCRIM_RGB, 0.62),
			Color(UiTokens.SCRIM_RGB, 0.34), Color(UiTokens.SCRIM_RGB, 0.0), Color(UiTokens.SCRIM_RGB, 0.0)])
		_linear = GradientTexture2D.new()
		_linear.gradient = g
		_linear.fill_from = Vector2(0.0, 0.5)
		_linear.fill_to = Vector2(1.0, 0.5)
		_linear.width = 256
		_linear.height = 4
	return _linear


## Current α of a radial scrim (adaptive, or the opaque setting).
static func current_alpha() -> float:
	if UiSettings.get_value("text_bg") == &"opaque":
		return UiTokens.SCRIM_OPAQUE
	return base_alpha


func _draw() -> void:
	if suppressed:
		return
	if linear:
		draw_texture_rect(linear_texture(), Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, clampf(strength, 0.0, 1.0)))
	else:
		var a := clampf((fixed_alpha if fixed_alpha >= 0.0 else current_alpha()) * strength, 0.0, 1.0)
		draw_texture_rect(radial_texture(), Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, a))
