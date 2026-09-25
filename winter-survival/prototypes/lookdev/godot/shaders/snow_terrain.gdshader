// Snow terrain (look-dev G1). Smooth-shaded mesh + vertex-colour AO (COLOR.a) + wrap lighting + rim tint +
// sparkle + texture-less noise + footprint trail map (depression / rim) as displacement + normal + darkening.
// Forward+ and Compatibility (no textures except the trail map, which is a plain RGBA8 texture).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://shaders/stylized_light.gdshaderinc"

// The reference snow is a cool light blue (sRGB ~#C9DAF0), not white: the blue lives in the albedo, the sun stays warm.
uniform vec4 snow_color : source_color = vec4(0.80, 0.87, 0.96, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float specular_value : hint_range(0.0, 1.0) = 0.2;
// Vertex-colour AO (baked around objects by the terrain builder): 1 = open, 0 = fully occluded.
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ao_tint : source_color = vec4(0.62, 0.70, 0.88, 1.0);
// View-dependent rim: silhouettes of drifts / edges facing away get a sky tint (lit by the environment, no glow).
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(0.80, 0.88, 1.0, 1.0);
// Sparkle glints (per world-space cell; only in direct sun).
uniform float sparkle_strength : hint_range(0.0, 3.0) = 0.8;
uniform float sparkle_density : hint_range(0.9, 1.0) = 0.975;
uniform float sparkle_scale = 18.0;
// Low-frequency tone variation without textures (value noise on world XZ).
uniform float noise_strength : hint_range(0.0, 0.2) = 0.022;
uniform float noise_scale = 0.06;
// Footprint trail map: R = depression (0..1), G = rim (0..1). `trail_rect` = (x0, z0, width, depth) in metres.
uniform sampler2D trail_map : hint_default_black, filter_linear, repeat_disable;
uniform vec4 trail_rect = vec4(-32.0, -32.0, 64.0, 64.0);
uniform float trail_depth = 0.10;
uniform float trail_rim_height = 0.05;
uniform float trail_darken : hint_range(0.0, 1.0) = 0.30;
uniform float trail_normal_strength = 3.5;
uniform bool trail_enabled = true;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_ao;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p) {
	vec3 p3 = fract(p * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec2 trail_uv(vec3 wp) {
	return (wp.xz - trail_rect.xy) / trail_rect.zw;
}

bool trail_inside(vec2 uv) {
	return trail_enabled && uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0;
}

float trail_height(vec2 uv) {
	vec2 t = texture(trail_map, uv).rg;
	return -t.r * trail_depth + t.g * trail_rim_height;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_ao = COLOR.a;
	vec2 uv = trail_uv(wp);
	if (trail_inside(uv)) {
		VERTEX.y += trail_height(uv);
	}
	v_world_pos = wp;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 albedo = snow_color.rgb * COLOR.rgb;
	vec3 nw = normalize(v_world_normal);
	vec2 uv = trail_uv(v_world_pos);
	if (trail_inside(uv)) {
		vec2 t = texture(trail_map, uv).rg;
		vec2 texel = 1.0 / vec2(textureSize(trail_map, 0));
		float hl = trail_height(uv - vec2(texel.x, 0.0));
		float hr = trail_height(uv + vec2(texel.x, 0.0));
		float hd = trail_height(uv - vec2(0.0, texel.y));
		float hu = trail_height(uv + vec2(0.0, texel.y));
		float dhdx = (hr - hl) / (2.0 * texel.x * trail_rect.z);
		float dhdz = (hu - hd) / (2.0 * texel.y * trail_rect.w);
		nw = normalize(nw + vec3(-dhdx, 0.0, -dhdz) * trail_normal_strength);
		albedo *= 1.0 - trail_darken * t.r;
		albedo *= 1.0 + 0.15 * t.g;
	}
	// tone variation (two octaves of value noise, no texture)
	float nz = vnoise(v_world_pos.xz * noise_scale) * 0.65 + vnoise(v_world_pos.xz * noise_scale * 3.1) * 0.35;
	albedo *= 1.0 + (nz - 0.5) * 2.0 * noise_strength;
	// baked contact AO: darker and bluer under objects
	float ao = mix(1.0, v_ao, ao_strength);
	albedo = mix(albedo * ao_tint.rgb, albedo, ao);
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	NORMAL = nv;
	float fres = pow(1.0 - clamp(dot(nv, VIEW), 0.0, 1.0), rim_power);
	albedo = mix(albedo, rim_color.rgb, fres * rim_strength);
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.35;
}

void light() {
	float lit;
	stylized_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, DIFFUSE_LIGHT, SPECULAR_LIGHT, lit);
	if (LIGHT_IS_DIRECTIONAL && sparkle_strength > 0.0 && lit > 0.05) {
		vec3 cell = floor(v_world_pos * sparkle_scale);
		float h = hash13(cell);
		if (h > sparkle_density) {
			vec3 jit = vec3(hash13(cell + 1.0), hash13(cell + 2.0), hash13(cell + 3.0)) * 2.0 - 1.0;
			vec3 ns = normalize(NORMAL + jit * 0.7);
			float g = pow(max(dot(reflect(-LIGHT, ns), VIEW), 0.0), 28.0);
			SPECULAR_LIGHT += g * sparkle_strength * ATTENUATION * LIGHT_COLOR;
		}
	}
}
