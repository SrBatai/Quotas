shader_type canvas_item;

uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.75, 0.89, 0.94, 1.0);
uniform float inner = 0.55;
uniform float outer = 1.45;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv * vec2(1.0, 1.15));
	float m = smoothstep(inner, outer, d) * strength;
	// subtle crystalline noise on the rim
	float n = fract(sin(dot(floor(UV * 240.0), vec2(12.9898, 78.233))) * 43758.5453);
	m *= 0.85 + 0.15 * n;
	COLOR = vec4(tint.rgb, m * 0.9);
}
