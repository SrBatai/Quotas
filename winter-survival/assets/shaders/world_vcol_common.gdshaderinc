// Body of the shared world material family (PLAN C2 / ARQ v2 §14, G1 look doc 06 §3.7, G2a doc 08 / W0 doc 09):
// albedo = vertex COLOR (palette baked in linear space), snow by world normal v2 (snow_include), optional frost,
// cutaway tint hook, wrap lighting + weak sheen (stylized_light), baked AO read from COLOR.a (art guide v2.1: 1 =
// open, legacy assets carry alpha 1 = no AO), a cheap ground-contact band for assets without baked AO, sky-tinted
// rim, and `snow_tint` so the legacy pure-white snow (#F1F5FA) matches the terrain's pastel blue (#CDDEF5).
// Works in Forward+ and Compatibility (OUTPUT_IS_SRGB branch).
//
// The family (one ShaderMaterial per member, shared by every surface of that kind, so the renderer sorts by
// material; nothing per instance):
//   world_vcol.gdshader          cull_back, never cut: characters, forest, props, POIs (G1 cost, no discard)
//   world_vcol_capsule.gdshader  cull_back + WV_CUT_CAPSULE: city props, lamps, foliage, cars (capsule only)
//   world_vcol_struct.gdshader   cull_disabled + WV_CUT_STRUCT: city building structure (floor cut + caps)
// The defines select the «corte urbano» hooks of city_cut.gdshaderinc.

#include "res://assets/shaders/snow_include.gdshaderinc"
#include "res://assets/shaders/stylized_light.gdshaderinc"
#if defined(WV_CUT_STRUCT) || defined(WV_CUT_CAPSULE)
#include "res://assets/shaders/city_cut.gdshaderinc"
#endif

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

#ifdef WV_CUT_STRUCT
// City building contract (ARQ v2 §9.7): slabs at base + ground_h + n * floor_h, base = the pieces' origin.
uniform float ground_h = 3.3;
uniform float floor_h = 3.0;
// Section caps: what a cut building shows where the camera looks into its (closed) volume (dark «poché»: the
// thickness of the cut walls and partitions, open shafts and cores).
uniform vec4 cap_color : source_color = vec4(0.13, 0.14, 0.17, 1.0);
// Section plan: the floor under a removed column reads as a lit plan (slab colour lifted toward `plan_color`,
// plus a little emission so it reads inside the shadow of the upper floors; weaker at night).
uniform vec4 plan_color : source_color = vec4(0.86, 0.85, 0.82, 1.0);
uniform float plan_mix : hint_range(0.0, 1.0) = 0.55;
uniform float plan_glow : hint_range(0.0, 1.0) = 0.22;
global uniform vec4 city_lights;
varying flat float v_base_y;
#endif

varying vec3 world_normal;
varying vec3 world_pos;
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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	model_y = VERTEX.y;
#ifdef WV_CUT_STRUCT
	v_base_y = MODEL_MATRIX[3].y;
#endif
}

void fragment() {
	bool cap = false;
#ifdef WV_CUT_STRUCT
	if (city_cut_struct_discard(world_pos, CAMERA_POSITION_WORLD, v_base_y, ground_h, floor_h, FRAGCOORD.xy, IN_SHADOW_PASS)) {
		discard;
	}
	cap = !FRONT_FACING;
#endif
#ifdef WV_CUT_CAPSULE
	if (city_cut_capsule_discard(world_pos, CAMERA_POSITION_WORLD, FRAGCOORD.xy, IN_SHADOW_PASS)) {
		discard;
	}
#endif
	if (cap) {
#ifdef WV_CUT_STRUCT
		// inside of a closed volume seen through the cut: a flat, upward-lit section colour
		ALBEDO = cap_color.rgb;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
		SPECULAR = 0.0;
		AO = 1.0;
#endif
	} else {
		// COLOR_0 is stored linear (ASSET_SPEC v2 §2.5). The Compatibility renderer shades in sRGB space.
		vec3 base = COLOR.rgb;
		if (OUTPUT_IS_SRGB) {
			base = linear_to_srgb(base);
		}
		vec3 n = normalize(world_normal);
		vec3 albedo = tint_whites(apply_snow_v2(base, n, world_pos, COLOR.a));
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
#ifdef WV_CUT_STRUCT
		float plan = city_cut_plan(world_pos, n, CAMERA_POSITION_WORLD, v_base_y, ground_h, floor_h);
		if (plan > 0.0) {
			vec3 pc = mix(base, plan_color.rgb, plan_mix);
			ALBEDO = mix(ALBEDO, pc, plan);
			AO = mix(AO, 1.0, plan);
			EMISSION = pc * plan_glow * plan * (1.0 - 0.75 * clamp(city_lights.x, 0.0, 1.0));
		}
#endif
	}
}

void light() {
	float lit;
	stylized_light(NORMAL, LIGHT, VIEW, LIGHT_COLOR, ATTENUATION, LIGHT_IS_DIRECTIONAL, DIFFUSE_LIGHT, SPECULAR_LIGHT, lit);
}
