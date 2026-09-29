// G2b smouldering embers (SmokeColumn): an additive, flickering orange disc lying on the ground under a plume. No
// light needed to read at night (the Compatibility / Web builds have no ember lights); dim by day.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

global uniform vec4 city_lights;   // x: night 0..1 (DayNight)

uniform vec4 ember_color : source_color = vec4(1.0, 0.42, 0.12, 1.0);
uniform float energy = 1.1;

float eg_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float cell = eg_hash(floor(wp.xz * 7.0));
	float flick = 0.75 + 0.25 * sin(TIME * (5.0 + 6.0 * cell) + cell * 40.0);
	float core = pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	float speck = step(0.82, cell) * (1.0 - smoothstep(0.35, 0.7, r));
	float night = mix(0.25, 1.0, clamp(city_lights.x, 0.0, 1.0));
	ALBEDO = ember_color.rgb * (core * 0.8 + speck * 0.9) * flick * energy * night;
}
