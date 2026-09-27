// VENTISCA · HUD v2: the paper map (docs/research/10_hud_ux.md appendix §6.11). A canvas shader on the map
// rect: paper #E9E1CD with fibre and fold creases; the land is inked from `land` (R = height 0..1, G = forest,
// B = water, A = settlement, one texel = 8 m) — contour lines every 12 m drawn with screen derivatives (crisp at
// any zoom), stippled forest, washed water, dark blocks for villages — and only where `fog` (8 m cells) says the
// player has been; unexplored paper stays blank with a charcoal smudge on the edge. No screen read: runs in
// Compatibility (web) and Forward+.
shader_type canvas_item;

uniform sampler2D land : filter_linear, repeat_disable;
uniform sampler2D fog : filter_linear, repeat_disable;
// the part of the land texture shown by this rect (uv offset, uv size)
uniform vec4 view = vec4(0.0, 0.0, 1.0, 1.0);
uniform float height_range = 160.0;
uniform float contour_m = 12.0;
uniform vec4 paper : source_color = vec4(0.914, 0.882, 0.804, 1.0);
uniform vec4 ink : source_color = vec4(0.23, 0.20, 0.17, 1.0);
uniform vec4 forest_ink : source_color = vec4(0.36, 0.42, 0.33, 1.0);
uniform vec4 water_ink : source_color = vec4(0.42, 0.55, 0.62, 1.0);
uniform float texel = 384.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 luv = view.xy + UV * view.zw;
	vec4 l = texture(land, luv);
	float f = texture(fog, luv).r;
	vec2 px = UV * vec2(1600.0, 1600.0);
	// paper: fibre + a cross fold
	float fibre = vnoise(px * vec2(0.9, 0.12)) * 0.5 + vnoise(px * 0.35) * 0.5;
	vec3 col = paper.rgb * (0.95 + 0.07 * fibre);
	float fold = min(abs(UV.x - 0.5), abs(UV.y - 0.5));
	col *= 1.0 - 0.06 * (1.0 - smoothstep(0.0, 0.006, fold));
	// fog: blank paper until explored; charcoal on the edge
	float edge_noise = vnoise(luv * texel * 0.9) * 0.35 + vnoise(luv * texel * 3.1) * 0.15;
	float seen = smoothstep(0.30, 0.70, f + edge_noise - 0.25);
	float rim = seen * (1.0 - smoothstep(0.55, 0.95, f + edge_noise * 0.6 - 0.1));
	// land ink
	vec3 land_col = col;
	float h = l.r * height_range;
	float c = h / contour_m;
	float w = fwidth(c) * 1.2;
	float line = 1.0 - smoothstep(0.0, w, abs(fract(c + 0.5) - 0.5));
	float major = 1.0 - step(0.5, mod(floor(c + 0.5), 5.0));
	land_col = mix(land_col, vec3(0.55, 0.40, 0.28), line * (0.35 + 0.25 * major) * (1.0 - l.b));
	// forest: a light wash + tree dots on a jittered 12 px grid (more of them where the forest is dense)
	vec2 cell = floor(px / 12.0);
	vec2 jitter = vec2(hash(cell), hash(cell + 17.0)) * 6.0 + 3.0;
	float tree_d = length(px - cell * 12.0 - jitter);
	float tree = (1.0 - smoothstep(1.4, 2.4, tree_d)) * step(hash(cell + 5.3), l.g * 1.25);
	land_col = mix(land_col, forest_ink.rgb, l.g * 0.18 + tree * 0.75);
	// water: wash + horizontal hatching
	float hatch = step(0.5, fract(px.y * 0.18)) * 0.25;
	land_col = mix(land_col, water_ink.rgb, l.b * (0.45 + hatch));
	// settlements
	land_col = mix(land_col, ink.rgb, l.a * 0.55);
	col = mix(col, land_col, seen);
	col = mix(col, vec3(0.18, 0.17, 0.16), rim * 0.35);
	COLOR = vec4(col, 1.0);
}
