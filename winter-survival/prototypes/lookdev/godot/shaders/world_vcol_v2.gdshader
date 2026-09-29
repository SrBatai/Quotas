// world_vcol v2 (look-dev G1): drop-in replacement for assets/shaders/world_vcol.gdshader.
// Keeps the contract (COLOR = linear palette, snow by world normal from `snow_amount`, frost, cutaway tint,
// OUTPUT_IS_SRGB branch for Compatibility) and adds: wrap lighting + blue shadow fill (stylized_light),
// ground-contact AO (vertices near the model base darken, tinted), view-dependent rim tint, weak sheen.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://shaders/snow_include.gdshaderinc"
#include "res://shaders/stylized_light.gdshaderinc"

uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float specular_value : hint_range(0.0, 1.0) = 0.15;
uniform vec4 frost_color : source_color = vec4(0.749, 0.851, 0.902, 1.0);
uniform float frost_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cutaway_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Contact AO: model-space height band [0, ao_height] darkens toward ao_floor (multiplied by ao_tint).
uniform float ao_height = 0.6;
uniform float ao_floor : hint_range(0.0, 1.0) = 0.55;
uniform vec4 ao_tint : source_color = vec4(0.62, 0.70, 0.88, 1.0);
// Rim (sky tint on silhouettes, no emission).
uniform float rim_strength : hint_range(0.0, 1.0) = 0.10;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(0.80, 0.88, 1.0, 1.0);
// Palette snow (#F1F5FA) is whiter than the terrain snow of the reference: near-white vertex colours are tinted
// so roofs / tree caps match the ground. (In the game this is better done in the palette export; kept here as a knob.)
uniform vec4 snow_tint : source_color = vec4(0.86, 0.91, 0.98, 1.0);

vec3 tint_whites(vec3 c) {
	float m = smoothstep(0.62, 0.85, min(c.r, min(c.g, c.b)));
	return mix(c, c * snow_tint.rgb, m);
}

varying vec3 world_normal;
varying float model_y;

vec3 linear_to_srgb(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, 12.92 * c, lessThan(c, vec3(0.0031308)));
}

void vertex() {
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	model_y = VERTEX.y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	if (OUTPUT_IS_SRGB) {
		base = linear_to_srgb(base);
	}
	vec3 n = normalize(world_normal);
	vec3 albedo = tint_whites(apply_snow(base, n));
	float frost = frost_amount * (0.55 + 0.45 * clamp(n.y, 0.0, 1.0));
	albedo = mix(albedo, frost_color.rgb, frost);
	// AO: baked in COLOR.a by the HD assets (1 = open sky); the legacy assets carry alpha 1, so a cheap
	// contact band (vertices near the model base, side faces only) fills in for them.
	float band = 1.0 - smoothstep(0.0, ao_height, model_y);
	float ao = mix(1.0, ao_floor, band * (1.0 - clamp(n.y, 0.0, 1.0)));
	ao = min(ao, COLOR.a);
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
