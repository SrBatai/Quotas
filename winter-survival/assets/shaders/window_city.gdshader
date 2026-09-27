// City windows (G2a, doc 08 §3.4): the facade glass of city buildings, split into world-space cells (one window bay
// of `cell_w` × one floor). At night a hash per cell decides, per powered block, whether the window is lit, and how:
// warm (most), cold (TV / fluorescent) or flickering; unpowered blocks keep a few dim survivor lights (candles,
// stoves). Cells re-roll one by one, staggered, every `reroll_hours` of game time. No lights, no textures (the
// power map is the only one, optional): emission only, the glow picks it up. By day: glass tinted by a fake sky
// reflection (the Environment has reflections off). Same «corte urbano» as the structure (windows are part of the
// facades) and the same section caps. Forward+, Compatibility and Web.
//
// Globals (DayNight / CityLights write them):
//   city_lights     x: night 0..1, y: grid power 0..1 where the power map does not reach, z: game time (h), w: unused
//   city_power_map  R8/RGBA8 map of powered blocks (R: 0 off … 1 on; generator blocks = 1 during a blackout)
//   city_power_rect x0, z0, width, depth of that map in metres; width <= 0: no map, use city_lights.y
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

#include "res://assets/shaders/city_cut.gdshaderinc"

global uniform vec4 city_lights;
global uniform sampler2D city_power_map;
global uniform vec4 city_power_rect;
global uniform float snow_amount;

// city building contract (same values as the structure material of the family)
uniform float ground_h = 3.3;
uniform float floor_h = 3.0;
uniform vec4 cap_color : source_color = vec4(0.20, 0.22, 0.27, 1.0);
// cells
uniform float cell_w = 2.4;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.28;
uniform float cold_share : hint_range(0.0, 1.0) = 0.12;
uniform float flicker_share : hint_range(0.0, 1.0) = 0.03;
uniform float survivor_share : hint_range(0.0, 0.2) = 0.015;
uniform float reroll_hours = 2.0;
uniform float frame_width : hint_range(0.0, 0.4) = 0.10;
// look
uniform vec4 glass_color : source_color = vec4(0.23, 0.29, 0.36, 1.0);
uniform vec4 sky_reflect : source_color = vec4(0.62, 0.72, 0.86, 1.0);
uniform vec4 frame_color : source_color = vec4(0.10, 0.11, 0.13, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.70, 0.40, 1.0);
uniform vec4 cold_color : source_color = vec4(0.62, 0.77, 1.0, 1.0);
uniform vec4 candle_color : source_color = vec4(1.0, 0.52, 0.22, 1.0);
uniform vec4 frost_color : source_color = vec4(0.80, 0.87, 0.95, 1.0);
uniform float energy = 2.4;
uniform float candle_energy = 0.7;

varying vec3 world_pos;
varying vec3 world_normal;
varying flat float v_base_y;

float wc_hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float wc_power(vec2 xz) {
	if (city_power_rect.z <= 0.0) {
		return city_lights.y;
	}
	vec2 uv = (xz - city_power_rect.xy) / city_power_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return city_lights.y;
	}
	ivec2 size = textureSize(city_power_map, 0);
	return texelFetch(city_power_map, ivec2(uv * vec2(size)), 0).r;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_base_y = MODEL_MATRIX[3].y;
}

void fragment() {
	if (city_cut_struct_discard(world_pos, CAMERA_POSITION_WORLD, v_base_y, ground_h, floor_h, FRAGCOORD.xy, IN_SHADOW_PASS)) {
		discard;
	}
	if (!FRONT_FACING) {
		ALBEDO = cap_color.rgb;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
	} else {
		vec3 n = normalize(world_normal);
		vec2 nh = normalize(n.xz + vec2(1e-4));
		vec2 tangent = vec2(-nh.y, nh.x);
		// cell = (bay along the facade, floor, facade plane); nudged into the wall so a face never sits on a border
		vec3 p = world_pos - n * 0.05;
		float s = dot(p.xz, tangent) / cell_w;
		float fl = floor((p.y - v_base_y) / floor_h);
		float plane = floor(dot(p.xz, nh) + 0.5);
		vec3 cell = vec3(floor(s), fl, plane);
		float h = wc_hash(cell);
		float slot = floor(city_lights.z / max(reroll_hours, 0.1) + h * 7.0);
		float roll = wc_hash(cell + vec3(slot * 17.0, 3.1, 0.0));
		float kind = wc_hash(cell * 1.7 + vec3(3.1, slot, 5.3));
		float power = wc_power(p.xz);
		float night = clamp(city_lights.x, 0.0, 1.0);
		float lit = step(roll, lit_fraction * power) * night;
		float candle = (1.0 - step(roll, lit_fraction * power)) * step(wc_hash(cell + 11.0), survivor_share) * night;
		vec3 c = kind < cold_share ? cold_color.rgb : warm_color.rgb;
		float e = energy;
		if (kind > 1.0 - flicker_share) {
			// failing tube / generator hiccups: a hashed square wave, never fully steady
			float f = wc_hash(vec3(floor(TIME * 7.0 + h * 13.0), cell.x, cell.y));
			e *= mix(0.15, 1.0, step(0.35, f));
		}
		// inside of the lit room: brighter under the ceiling, darker at the sill
		float v = fract((p.y - v_base_y) / floor_h);
		float room = mix(0.65, 1.15, smoothstep(0.1, 0.9, v));
		// mullions between bays
		float u = fract(s);
		float frame = 1.0 - smoothstep(frame_width * 0.5, frame_width * 0.5 + 0.02, min(u, 1.0 - u));
		float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		vec3 albedo = mix(glass_color.rgb, sky_reflect.rgb, 0.18 + 0.5 * fres) * (1.0 - 0.85 * max(lit, candle));
		// frost creeping up from the sill while it snows
		float frost = clamp(snow_amount, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.35, v)) * 0.8;
		albedo = mix(albedo, frost_color.rgb, frost);
		albedo = mix(albedo, frame_color.rgb, frame);
		ALBEDO = albedo;
		EMISSION = (c * e * lit + candle_color.rgb * candle_energy * candle) * room * (1.0 - frame);
		ROUGHNESS = mix(0.12, 0.8, max(frame, frost));
		METALLIC = 0.0;
		SPECULAR = 0.6;
	}
}
