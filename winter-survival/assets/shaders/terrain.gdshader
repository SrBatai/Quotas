// Snow terrain (G1, doc 06 §3.7–3.9). Smooth-shaded chunk meshes + baked vertex AO (COLOR.a, from the scatter
// occluders) + wrap lighting + rim tint + sparkle + texture-less tone noise + footprint trail map (R = depression,
// G = rim) read as displacement + normal + darkening. One ShaderMaterial (assets/materials/terrain.tres) shared
// by every terrain chunk. Forward+ and Compatibility (no textures except the trail map, a plain RGBA8 texture).
// M3: CUSTOM0 = surface mask of the streamed chunks (r asphalt road bed, g lake ice, b packed track; 0 = snow,
// which is all of the hunter's clearing, so the G1 look there is untouched).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://assets/shaders/stylized_light.gdshaderinc"

// The reference snow is a cool light blue (palette v2.1 `snow` #CDDEF5), never white: the blue lives in the
// albedo and in the ambient light, the sun stays a weak warm white.
uniform vec4 snow_color : source_color = vec4(0.80, 0.87, 0.96, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;
uniform float specular_value : hint_range(0.0, 1.0) = 0.2;
// Vertex-colour AO (baked around objects by Terrain.bake_ao): 1 = open, 0 = fully occluded.
uniform float ao_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ao_tint : source_color = vec4(0.62, 0.70, 0.88, 1.0);
// View-dependent rim: silhouettes of drifts / edges facing away get a sky tint (mixed into the albedo, no glow).
uniform float rim_strength : hint_range(0.0, 1.0) = 0.12;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(0.80, 0.88, 1.0, 1.0);
// Sparkle glints (per world-space cell; only in direct sun). DayNight sets the strength per hour (0 at night).
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
uniform bool trail_enabled = false;
// Surface mask (M3): packed snow over the road beds (asphalt under it), wind-polished lake ice.
uniform vec4 road_tint : source_color = vec4(0.80, 0.84, 0.91, 1.0);
uniform vec4 track_tint : source_color = vec4(0.88, 0.91, 0.96, 1.0);
uniform vec4 ice_color : source_color = vec4(0.62, 0.76, 0.88, 1.0);
uniform float ice_roughness : hint_range(0.0, 1.0) = 0.32;
uniform float ice_specular : hint_range(0.0, 1.0) = 0.45;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying float v_ao;
varying vec3 v_tint;
varying vec4 v_surface;

vec3 linear_to_srgb(vec3 c) {
	return mix(1.055 * pow(max(c, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, 12.92 * c, lessThan(c, vec3(0.0031308)));
}

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
	v_surface = CUSTOM0;
	// COLOR.rgb is a linear multiplier (slope / lake tint) written by Terrain; Compatibility shades in sRGB.
	v_tint = COLOR.rgb;
	if (OUTPUT_IS_SRGB) {
		v_tint = linear_to_srgb(v_tint);
	}
	vec2 uv = trail_uv(wp);
	if (trail_inside(uv)) {
		VERTEX.y += trail_height(uv);
	}
	v_world_pos = wp;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 albedo = snow_color.rgb * v_tint;
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
	// M3 surface mask: road beds (packed, greyer, dirtier), tracks, lake ice (bluer, glossy, faint streaks)
	float road = v_surface.r;
	float track = v_surface.b;
	float ice = v_surface.g;
	if (road + track + ice > 0.001) {
		float grime = vnoise(v_world_pos.xz * 0.9) * 0.5 + vnoise(v_world_pos.xz * 0.23) * 0.5;
		albedo *= mix(vec3(1.0), road_tint.rgb * (0.94 + 0.12 * grime), road);
		albedo *= mix(vec3(1.0), track_tint.rgb, track);
		float streak = vnoise(vec2(v_world_pos.x * 0.08 + v_world_pos.z * 0.05, v_world_pos.z * 0.9));
		vec3 ice_c = ice_color.rgb * (0.9 + 0.2 * streak);
		albedo = mix(albedo, ice_c, ice * 0.85);
	}
	// baked contact AO: darker and bluer under objects
	float ao = mix(1.0, v_ao, ao_strength);
	albedo = mix(albedo * ao_tint.rgb, albedo, ao);
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	NORMAL = nv;
	float fres = pow(1.0 - clamp(dot(nv, VIEW), 0.0, 1.0), rim_power);
	albedo = mix(albedo, rim_color.rgb, fres * rim_strength);
	ALBEDO = albedo;
	ROUGHNESS = mix(roughness_value, ice_roughness, v_surface.g);
	SPECULAR = mix(specular_value, ice_specular, v_surface.g);
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
