// G2b per-vertex wind (PLAN v3.8.2 G2b, doc 08 §3.10 «viento por vértice»): trees and bushes (bend growing with
// height + sway + gust fronts that travel downwind), cloth (tarps, tents, laundry: flutter inside a height band)
// and cables (sag swing along the span). World-space maths from the `snow_wind` global (xy: where the wind blows to,
// z: strength — 0.3 calm, ~0.65 overcast, 1 blizzard —, w: gustiness 0..1), no textures, identical in Forward+,
// Compatibility and the Web; it also runs in the shadow pass, so the shadows sway with the trees. Instances whose
// up axis leans away from world up (a felled tree, a tent on its side) do not sway. Include AFTER snow_include
// (which declares `snow_wind`); world_vcol_common does it for the WV_WIND_* variants.
//
//   WV_WIND_TREE   bend ∝ (h / wind_height)², h = model-space height (pines 5–9 m: wind_height 8)
//   WV_WIND_CLOTH  flutter weighted by a band: 0 at the model base and at wind_height, full in between
//   WV_WIND_CABLE  a cable along model X from −wind_height/2 to +wind_height/2: swing ∝ 1 − (2x / span)²

uniform float wind_amount : hint_range(0.0, 3.0) = 1.0;
uniform float wind_height = 8.0;

float wind_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Gust envelope 0..1 at a world point: broad fronts moving downwind at ~8 m/s, stronger with snow_wind.w.
float wind_gust(vec2 p, float t) {
	vec2 wd = snow_wind.xy;
	float along = dot(p, wd);
	float across = dot(p, vec2(-wd.y, wd.x));
	float front = along * 0.045 - t * 0.36 + sin(across * 0.021) * 1.3;
	float g = 0.5 + 0.5 * sin(front * 6.2831) * sin(front * 2.3 + 1.7);
	return clamp(mix(0.35, 1.0, g) * (0.6 + 0.4 * snow_wind.w), 0.0, 1.0);
}

// Model-space offset for a vertex `v` of an instance with transform `m` at time `t`.
vec3 wind_model_offset(vec3 v, mat4 m, float t) {
	float s2 = max(dot(m[0].xyz, m[0].xyz), 1e-6);
	float up = clamp(m[1].y / sqrt(max(dot(m[1].xyz, m[1].xyz), 1e-6)), 0.0, 1.0);
	up = smoothstep(0.8, 0.98, up);
	vec3 origin = m[3].xyz;
	vec2 wd = snow_wind.xy;
	float strength = clamp(snow_wind.z, 0.0, 1.5) * wind_amount;
	float phase = wind_hash(floor(origin.xz * 3.0)) * 6.2831;
	float gust = wind_gust(origin.xz, t);
	vec3 off = vec3(0.0);
#if defined(WV_WIND_TREE)
	float h = max(v.y, 0.0) / max(wind_height, 0.1);
	float k = h * h;
	// steady lean into the gusts + a slow sway + a faster shiver of the crown
	float lean = strength * (0.10 + 0.38 * gust);
	float sway = sin(t * 1.25 + phase) * 0.55 + sin(t * 2.7 + phase * 1.9) * 0.2;
	float shiver = sin(t * 7.3 + phase * 3.1 + v.y * 1.7 + v.x * 2.3) * 0.05 * h;
	vec2 d = wd * (lean + sway * strength * (0.12 + 0.2 * gust)) * k * wind_height * 0.12;
	vec2 side = vec2(-wd.y, wd.x) * sin(t * 1.9 + phase * 1.3) * strength * gust * 0.03 * k * wind_height;
	off = vec3(d.x + side.x, -0.25 * lean * k, d.y + side.y);
	off += vec3(wd.x, 0.0, wd.y) * shiver * strength;
#elif defined(WV_WIND_CLOTH)
	float y = clamp(v.y / max(wind_height, 0.1), 0.0, 1.0);
	float band = smoothstep(0.0, 0.35, y) * (1.0 - smoothstep(0.75, 1.0, y));
	vec2 wp = (m * vec4(v, 1.0)).xz;
	float wave = sin(t * 8.5 + dot(wp, wd) * 2.4 + v.y * 3.1 + phase) * 0.6 + sin(t * 13.1 + dot(wp, vec2(-wd.y, wd.x)) * 3.7) * 0.4;
	float a = strength * (0.35 + 0.65 * gust) * band;
	off = vec3(wd.x, 0.0, wd.y) * (0.05 + 0.06 * wave) * a + vec3(0.0, 0.04 * wave * a, 0.0);
#elif defined(WV_WIND_CABLE)
	float span = max(wind_height, 0.5);
	float x = clamp(v.x / (span * 0.5), -1.0, 1.0);
	float sag = 1.0 - x * x;
	float swing = sin(t * 1.4 + phase) * 0.7 + sin(t * 3.3 + phase * 2.0) * 0.3;
	vec2 across = vec2(-wd.y, wd.x);
	float a = strength * (0.3 + 0.7 * gust) * sag * span * 0.012;
	off = vec3(wd.x, 0.0, wd.y) * a * (0.6 + 0.4 * swing) + vec3(across.x, 0.0, across.y) * a * swing * 0.25 + vec3(0.0, -0.2 * a * abs(swing), 0.0);
#endif
	// world offset -> model space (uniform scale): R^T · off / s = M^T · off / s²
	return (transpose(mat3(m)) * off) / s2 * up;
}
