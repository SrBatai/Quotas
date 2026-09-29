// Decay pass for the trail map: multiplies the whole map by (1 - amount). Blitted over the full rect.
shader_type canvas_item;
render_mode blend_mul;

uniform float keep = 0.995;

void fragment() {
	COLOR = vec4(keep, keep, keep, 1.0);
}
