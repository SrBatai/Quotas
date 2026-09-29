// Footprint stamp for DrawableTexture2D.blit_rect (Godot 4.7 `texture_blit` shader): R = depression, G = rim.
// Additive so repeated steps deepen the trench. The stamp is procedural (the source texture is unused).
shader_type texture_blit;
render_mode blend_add;

uniform sampler2D source_texture0 : hint_blit_source0;
uniform float depth = 1.0;
uniform float rim = 1.0;

void blit() {
	vec2 p = (UV - 0.5) * 2.0;
	float w = 0.62 + 0.10 * p.y;
	float r = length(vec2(p.x / w, p.y / 0.92));
	float inner = 1.0 - smoothstep(0.55, 0.85, r);
	float ring = smoothstep(0.62, 0.85, r) * (1.0 - smoothstep(0.85, 1.0, r));
	COLOR0 = vec4(inner * depth, ring * rim, 0.0, 1.0);
}
