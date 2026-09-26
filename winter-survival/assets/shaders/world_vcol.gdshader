// Shared world material v2 (PLAN C2 / ARQ v2 §14, G1 look doc 06 §3.7): albedo = vertex COLOR (palette baked in
// linear space), snow by world normal driven by the global `snow_amount`, optional frost, cutaway tint hook.
// G1 additions: wrap lighting + weak sheen (stylized_light), baked AO read from COLOR.a (art guide v2.1: 1 = open,
// legacy assets carry alpha 1 = no AO), a cheap ground-contact band for assets without baked AO, sky-tinted rim,
// and `snow_tint` so the legacy pure-white snow (#F1F5FA) matches the terrain's pastel blue (#CDDEF5).
// One ShaderMaterial (assets/materials/world_vcol.tres) is shared by every `palette_vcol` surface so the
// renderer can sort by material. Works in Forward+ and Compatibility (OUTPUT_IS_SRGB branch).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://assets/shaders/snow_include.gdshaderinc"
#include "res://assets/shaders/stylized_light.gdshaderinc"

uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float specular_value : hint_range(0.0, 1.0) = 0.15;
// Frost: whitish veil that grows on upward faces (freezing objects, M8). 0 = off.
uniform vec4 frost_color : source_color = vec4(0.749, 0.851, 0.902, 1.0);
uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;
// Cutaway tint hook: multiplied into the albedo (CutawayManager may dim the hidden floors, M6a/M10).
uniform vec4 cutaway_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Baked AO (COLOR.a): strength of the darkening and its tint (darker AND bluer, like the reference).
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ao_tint : source_color = vec4(0.62, 0.70, 0.88, 1.0);
// Contact AO for assets WITHOUT baked AO (COLOR.a == 1 everywhere): model-space height band [0, ao_height]
// darkens side faces toward ao_floor. Baked AO wins where present (min of both).
uniform float ao_height = 0.6;
uniform float ao_floor : hint_range(0.0, 1.0) = 0.55;
// Rim: sky tint on silhouettes, mixed into the albedo (no emission, so it stays dark at night).
uniform float rim_strength : hint_range(0.0, 1.0) = 0.10;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(0.80, 0.88, 1.0, 1.0);
// Near-white vertex colours (legacy palette snow #F1F5FA, trim) are tinted so roofs / tree caps match the ground.
// Palette v2.1 snow (#CDDEF5) falls below the band and is left untouched.
uniform vec4 snow_tint : source_color = vec4(0.86, 0.91, 0.98, 1.0);
uniform float snow_tint_low : hint_range(0.0, 1.0) = 0.62;
uniform float snow_tint_high : hint_range(0.0, 1.0) = 0.85;

varying vec3 world_normal;
varying float model_y;

vec3 linear_to_srgb(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, 12.92 * c, lessThan(c, vec3(0.0031308)));
}

vec3 tint_whites(vec3 c) {
	float m = smoothstep(snow_tint_low, snow_tint_high, min(c.r, min(c.g, c.b)));
	return mix(c, c * snow_tint.rgb, m);
}

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	model_y = VERTEX.y;
}

void fragment() {
	// COLOR_0 is stored linear (ASSET_SPEC v2 §2.5). The Compatibility renderer shades in sRGB space.
	vec3 base = COLOR.rgb;
	if (OUTPUT_IS_SRGB) {
		base = linear_to_srgb(base);
	}
	vec3 n = normalize(world_normal);
	vec3 albedo = tint_whites(apply_snow(base, n));
	float frost = frost_amount * (0.55 + 0.45 * clamp(n.y, 0.0, 1.0));
	albedo = mix(albedo, frost_color.rgb, frost);
	// AO: baked in COLOR.a by the v2.1 assets (1 = open sky); legacy assets carry alpha 1, so the contact band
	// (vertices near the model base, side faces only) fills in for them.
	float band = 1.0 - smoothstep(0.0, ao_height, model_y);
	float contact = mix(1.0, ao_floor, band * (1.0 - clamp(n.y, 0.0, 1.0)));
	float ao = min(contact, mix(1.0, COLOR.a, ao_strength));
	albedo = mix(albedo * ao_tint.rgb, albedo, ao);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	albedo = mix(albedo, rim_color.rgb, fres * rim_strength);
	ALBEDO = albedo * cutaway_tint.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = specular_value;
	AO = ao;
	AO_LIGHT_AFFECT = 0.3;
}

void light() {
	float lit;
	stylized_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, DIFFUSE_LIGHT, SPECULAR_LIGHT, lit);
}
