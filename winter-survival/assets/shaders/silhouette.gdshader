// Character silhouette through walls (W0, doc 09 §3.1 layer D / §3.5). Set as `material_overlay` on the character's
// meshes (per instance: the shared world_vcol material is untouched) by Silhouettes (scripts/world/city/
// silhouettes.gd): players always, in the colour of their jacket; zombies only while perceived, in amber.
// depth_test_inverted: only the parts hidden behind something are drawn. Each vertex is pulled `self_gap` metres
// toward the camera ALONG ITS VIEW RAY (same pixels, smaller depth), so the character never tints itself (from the
// high camera the shoulders hide the feet ~1.3 m deeper: the gap covers a standing body), while a wall, a car or a
// building further in front still does. No depth texture, no stencil: Forward+, Compatibility and Web alike.
shader_type spatial;
render_mode unshaded, depth_test_inverted, depth_draw_never, cull_back, shadows_disabled, fog_disabled, blend_mix;

uniform vec4 tint : source_color = vec4(0.25, 0.9, 1.0, 0.6);
uniform float self_gap = 1.8;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(v.xyz);
	v.xyz *= max(d - self_gap, 0.05) / max(d, 1e-4);
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
