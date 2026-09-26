// Shared stylized lighting for VENTISCA (G1, doc 06 §3.7). Included by world_vcol.gdshader and terrain.gdshader.
//
// * Wrap lighting: the diffuse term is (N·L + wrap) / (1 + wrap) instead of max(N·L, 0). Snow and matte
//   low-poly surfaces stop showing a hard terminator and read "soft"; the shadow map still cuts the light,
//   so cast shadows keep their edge (soft through PCSS / shadow_blur).
// * Shadow fill: a fraction of the sun's own colour, tinted blue, is added where the sun is blocked or facing
//   away so shadows never go muddy. Only for directional lights. Off by default (the blue ambient does it).
// * Specular: a broad, weak sheen (snow is not glossy).
// Works in Forward+, Mobile and Compatibility (custom light() is supported by all three).

uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform float shadow_fill : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shadow_fill_color : source_color = vec4(0.55, 0.66, 0.92, 1.0);
uniform float sheen : hint_range(0.0, 1.0) = 0.08;
uniform float sheen_power : hint_range(1.0, 64.0) = 12.0;

float wrap_diffuse(vec3 n, vec3 l, float w) {
	float d = (dot(n, l) + w) / (1.0 + w);
	return clamp(d, 0.0, 1.0);
}

// Adds the diffuse + sheen contribution of one light. `lit` returns the effective light amount (for sparkles).
void stylized_light(vec3 n, vec3 l, vec3 v, vec3 light_color, float attenuation, bool directional,
		inout vec3 diffuse_light, inout vec3 specular_light, out float lit) {
	float d = wrap_diffuse(n, l, wrap);
	lit = d * attenuation;
	diffuse_light += lit * light_color;
	if (directional && shadow_fill > 0.0) {
		diffuse_light += (1.0 - lit) * shadow_fill * shadow_fill_color.rgb * light_color;
	}
	vec3 h = normalize(l + v);
	float s = pow(max(dot(n, h), 0.0), sheen_power) * sheen;
	specular_light += s * attenuation * light_color;
}
