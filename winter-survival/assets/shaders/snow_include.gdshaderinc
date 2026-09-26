// Snow by world normal (ARQ v2 §14). Included by world_vcol.gdshader (and terrain.gdshader from M3).
// `snow_amount` is a global shader parameter (project.godot [shader_globals]) that the weather raises
// during blizzards: RenderingServer.global_shader_parameter_set("snow_amount", x).
global uniform float snow_amount;
uniform vec4 snow_color : source_color = vec4(0.945, 0.961, 0.98, 1.0);
uniform float snow_start : hint_range(0.0, 1.0) = 0.55;
uniform float snow_end : hint_range(0.0, 1.0) = 0.85;

vec3 apply_snow(vec3 albedo, vec3 world_normal) {
	float mask = smoothstep(snow_start, snow_end, world_normal.y) * clamp(snow_amount, 0.0, 1.0);
	return mix(albedo, snow_color.rgb, mask);
}
