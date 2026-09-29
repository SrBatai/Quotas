// Copy of the game's snow_include.gdshaderinc (ARQ v2 §14) so the look-dev shaders stay drop-in compatible.
global uniform float snow_amount;
uniform vec4 snow_color : source_color = vec4(0.945, 0.961, 0.98, 1.0);
uniform float snow_start : hint_range(0.0, 1.0) = 0.55;
uniform float snow_end : hint_range(0.0, 1.0) = 0.85;

vec3 apply_snow(vec3 albedo, vec3 world_normal) {
	float mask = smoothstep(snow_start, snow_end, world_normal.y) * clamp(snow_amount, 0.0, 1.0);
	return mix(albedo, snow_color.rgb, mask);
}
