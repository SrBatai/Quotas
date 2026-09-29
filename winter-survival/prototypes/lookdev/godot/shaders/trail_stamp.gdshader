// Footprint stamp for the trail map (canvas_item). Draws one foot: R = depression, G = raised rim.
// Used by DrawableTexture2D.blit_rect (4.7) and by the SubViewport fallback. Additive so repeated steps deepen.
shader_type canvas_item;
render_mode blend_add;

uniform float depth = 1.0;
uniform float rim = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	// foot outline: ellipse, slightly wider at the toes (+y)
	float w = 0.62 + 0.10 * p.y;
	float r = length(vec2(p.x / w, p.y / 0.92));
	float inner = 1.0 - smoothstep(0.55, 0.85, r);
	float ring = smoothstep(0.62, 0.85, r) * (1.0 - smoothstep(0.85, 1.0, r));
	COLOR = vec4(inner * depth, ring * rim, 0.0, 1.0);
}
