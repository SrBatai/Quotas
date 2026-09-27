// Fake light pools under street lamps + bulb halos (G2a, doc 08 §3.4.2): additive, unshaded quads in a MultiMesh
// (2 triangles per lamp, one draw call per chunk and kind), so a street of lamps costs no real light. The real
// OmniLight3D budget (Quality "lamp_lights") only goes to the few lamps nearest the camera; the pools read the same
// on the three renderers (Compatibility has 8 lights per mesh, the street is one mesh).
// INSTANCE_CUSTOM (MultiMesh use_custom_data): rgb = tint multiplier, a = intensity (0 = unpowered lamp,
// negative = flickering lamp of intensity |a|). `halo` = billboard sprite at the bulb instead of a ground pool.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec4 city_lights;   // x: night 0..1 (DayNight)

uniform vec4 pool_color : source_color = vec4(1.0, 0.74, 0.46, 1.0);
uniform float energy = 0.55;
uniform float falloff = 2.2;
uniform bool halo = false;

varying vec4 v_custom;

float lp_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	if (halo) {
		// camera-facing sprite at the instance origin
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float fall = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	float k = abs(v_custom.a);
	if (v_custom.a < 0.0) {
		float f = lp_hash(vec2(floor(TIME * 9.0), floor(v_custom.r * 97.0 + v_custom.g * 13.0)));
		k *= mix(0.1, 1.0, step(0.3, f));
	}
	ALBEDO = pool_color.rgb * v_custom.rgb * fall * energy * k * clamp(city_lights.x, 0.0, 1.0);
}
