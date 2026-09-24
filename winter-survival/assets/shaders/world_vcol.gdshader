// Shared world material (PLAN C2 / ARQ v2 §14): albedo = vertex COLOR (palette baked in linear space),
// snow by world normal driven by the global `snow_amount`, optional frost, cutaway tint hook.
// One ShaderMaterial (assets/materials/world_vcol.tres) is shared by every `palette_vcol` surface so the
// renderer can sort by material. Works in Forward+ and Compatibility (OUTPUT_IS_SRGB branch).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://assets/shaders/snow_include.gdshaderinc"

uniform float roughness_value : hint_range(0.0, 1.0) = 0.95;
uniform float specular_value : hint_range(0.0, 1.0) = 0.15;
// Frost: whitish veil that grows on upward faces (freezing objects, M8). 0 = off.
uniform vec4 frost_color : source_color = vec4(0.749, 0.851, 0.902, 1.0);
uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;
// Cutaway tint hook: multiplied into the albedo (CutawayManager may dim the hidden floors, M6a/M10).
uniform vec4 cutaway_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

varying vec3 world_normal;

vec3 linear_to_srgb(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, 12.92 * c, lessThan(c, vec3(0.0031308)));
}

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// COLOR_0 is stored linear (ASSET_SPEC v2 §2.5). The Compatibility renderer shades in sRGB space.
	vec3 base = COLOR.rgb;
	if (OUTPUT_IS_SRGB) {
		base = linear_to_srgb(base);
	}
	vec3 n = normalize(world_normal);
	vec3 albedo = apply_snow(base, n);
	float frost = frost_amount * (0.55 + 0.45 * clamp(n.y, 0.0, 1.0));
	albedo = mix(albedo, frost_color.rgb, frost);
	ALBEDO = albedo * cutaway_tint.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = specular_value;
}
