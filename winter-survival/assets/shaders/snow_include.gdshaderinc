// Snow by world normal (ARQ v2 §14), v2 for G2a (doc 08 §3.2). Included by the world_vcol family and window_city.
// `snow_amount` is a global shader parameter (project.godot [shader_globals]) that the weather raises during
// blizzards (DayNight: blizzard blend × Quality ceiling; 0 in clear weather). `snow_wind` (xy: unit xz direction the
// wind blows TO, z: strength 0..1) is written by DayNight from WorldState.wind_yaw.
// v2 terms, all in world space (no UVs, no textures), identical in the three renderers:
//   * broken edge: world-space value noise (0.6 m + 2.5 m) added to n.y before the threshold;
//   * shelter: baked AO (COLOR.a, 1 = open sky) keeps snow out of eaves, recesses, interiors and from under cars
//     (`snow_shelter` = how much; 1 on the city structure, whose interior slabs carry AO <= 0.3);
//   * windward: vertical faces facing into the wind catch patchy snow (posts, facades, car sides);
//   * `snow_base`: permanent cover of a material family on top of the weather (0 = legacy assets that bake their
//     snow slabs, which therefore look exactly as before in clear weather; city materials use it).
// apply_snow(albedo, n) keeps the v1 signature for older callers.
global uniform float snow_amount;
global uniform vec4 snow_wind;
uniform vec4 snow_color : source_color = vec4(0.945, 0.961, 0.98, 1.0);
uniform float snow_start : hint_range(0.0, 1.0) = 0.55;
uniform float snow_end : hint_range(0.0, 1.0) = 0.85;
uniform float snow_base : hint_range(0.0, 1.0) = 0.0;
uniform float snow_edge_noise : hint_range(0.0, 0.5) = 0.16;
uniform float snow_shelter : hint_range(0.0, 1.0) = 0.7;
uniform float snow_windward : hint_range(0.0, 1.0) = 0.45;

float sn_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float sn_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = sn_hash(i);
	float b = sn_hash(i + vec2(1.0, 0.0));
	float c = sn_hash(i + vec2(0.0, 1.0));
	float d = sn_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Snow mask 0..1 for a world-space normal n at world position wp with baked AO `ao` (1 = open).
float snow_mask_v2(vec3 n, vec3 wp, float ao) {
	float a = clamp(snow_amount + snow_base, 0.0, 1.0);
	if (a <= 0.001) {
		return 0.0;
	}
	// 0.6 m and 2.5 m cells; the y term keeps vertical faces from showing vertical stripes
	vec2 q = wp.xz + vec2(wp.y * 0.71, wp.y * 1.37);
	float nz = sn_vnoise(q * 1.6) * 0.55 + sn_vnoise(q * 0.4 + 17.0) * 0.45;
	float up = n.y + (nz - 0.5) * 2.0 * snow_edge_noise;
	// more snow creeps further down the slopes
	float lower = mix(snow_start + 0.15, snow_start - 0.15, a);
	float m = smoothstep(lower, lower + (snow_end - snow_start), up);
	float vertical = 1.0 - abs(n.y);
	float wind = max(dot(normalize(n.xz + vec2(1e-5)), -snow_wind.xy), 0.0) * vertical * snow_wind.z * snow_windward;
	m = max(m, wind * smoothstep(0.38, 0.62, nz));
	// sheltered below AO 0.3 (eaves, under cars, interiors), open sky above 0.75
	m *= smoothstep(0.0, 0.35, a) * mix(1.0 - snow_shelter, 1.0, smoothstep(0.3, 0.75, ao));
	return clamp(m, 0.0, 1.0);
}

vec3 apply_snow_v2(vec3 albedo, vec3 world_normal, vec3 wp, float ao) {
	return mix(albedo, snow_color.rgb, snow_mask_v2(world_normal, wp, ao));
}

// v1 signature (no position: no noise, no wind, no shelter).
vec3 apply_snow(vec3 albedo, vec3 world_normal) {
	float mask = smoothstep(snow_start, snow_end, world_normal.y) * clamp(snow_amount + snow_base, 0.0, 1.0);
	return mix(albedo, snow_color.rgb, mask);
}
