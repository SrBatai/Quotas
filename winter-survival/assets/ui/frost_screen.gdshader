// VENTISCA · HUD v2 «Susurro»: frost vignette on the screen edges ("la interfaz también tiene frío",
// docs/research/10_hud_ux.md §V.4.9; the Godot port of mockups/frost_v2.svg). Intensity = 1 − Calor/40, set by
// the HUD. A cold haze (62 → 100 % of the radius) plus two layers of turbulence ("ice" and "fine") masked by a
// radial band that starts at 66 % of the radius: nothing reaches the centre, no refraction, no screen read, so
// it runs the same in Compatibility (web) and Forward+. Noise is sampled in continuous UV (no per-cell hash:
// no flicker when the resolution changes).
shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
// pixel size of the rect (the turbulence frequencies are per pixel of a 1920 × 1080 reference)
uniform vec2 ref_size = vec2(1920.0, 1080.0);
uniform vec4 ice_color : source_color = vec4(0.90, 0.97, 1.0, 1.0);
uniform vec4 fine_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform vec4 haze_inner : source_color = vec4(0.81, 0.92, 0.96, 1.0);
uniform vec4 haze_outer : source_color = vec4(0.89, 0.96, 0.98, 1.0);
uniform float drift = 0.004;
uniform float ice_gain = 1.9;
uniform float ice_bias = 0.62;
uniform float fine_gain = 1.6;
uniform float fine_bias = 0.55;

vec2 grad(vec2 p) {
	float h = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
	float a = h * 6.2831853;
	return vec2(cos(a), sin(a));
}

// gradient (Perlin-like) noise in [-1, 1]
float pnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(grad(i), f);
	float b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y) * 1.4142;
}

// SVG-style turbulence: Σ |noise| / 2^i
float turbulence(vec2 p, int octaves) {
	float t = 0.0;
	float amp = 1.0;
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		t += abs(pnoise(p)) * amp;
		p = p * 2.0 + vec2(17.3, 9.1);
		amp *= 0.5;
	}
	return t;
}

void fragment() {
	float s = clamp(strength, 0.0, 1.0);
	// radial distance of the SVG gradients (objectBoundingBox, r = 71 % → the corners sit at ≈ 1.0)
	float d = length(UV - vec2(0.5)) / 0.71;
	// haze: 62 % → 100 %, up to 42 %
	float dh = d * 0.71 / 0.72;
	float hz = smoothstep(0.62, 1.0, dh) * 0.42;
	vec3 col = mix(haze_inner.rgb, haze_outer.rgb, smoothstep(0.62, 1.0, dh));
	float a = hz;
	// mask: 0 until 66 %, .55 at 86 %, 1 at the edge
	float m = d < 0.86 ? smoothstep(0.66, 0.86, d) * 0.55 : mix(0.55, 1.0, smoothstep(0.86, 1.0, d));
	vec2 px = UV * ref_size + vec2(TIME * drift * 60.0, 0.0);
	float t1 = turbulence(px * vec2(0.009, 0.013), 5);
	float ice = clamp(ice_gain * t1 - ice_bias, 0.0, 1.0) * 0.85 * m;
	float t2 = turbulence(px * vec2(0.035, 0.05) + vec2(41.0, 7.0), 3);
	float fine = clamp(fine_gain * t2 - fine_bias, 0.0, 1.0) * 0.55 * m;
	// "over" composition: haze, then ice, then fine
	col = mix(col, ice_color.rgb, ice);
	a = a + ice * (1.0 - a);
	col = mix(col, fine_color.rgb, fine * (1.0 - ice * 0.5));
	a = a + fine * (1.0 - a);
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * s);
}
