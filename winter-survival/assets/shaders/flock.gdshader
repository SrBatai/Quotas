// G2b circling flocks (doc 08 §3.9 «bandadas»: a MultiMesh of 30–60-triangle birds, flapping by vertex): every
// bird's flight is computed here from INSTANCE_CUSTOM and a clock, so a flock costs 1 draw call (+ its shadow pass:
// from the high game camera the birds themselves are often above the frame, their shadows sweep the snow) and no
// CPU per frame. The instance transform is the flock's centre; INSTANCE_CUSTOM = (phase 0..1, orbit radius m,
// height m, speed factor). The bird mesh: body along +Z, wings along ±X, COLOR.r = 1 on the wing tips (flap).
// Crows by default (dark, unshaded so they read against snow; the fog still fades them). Render only: the takeoff
// and the server registry are V1's.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 bird_color : source_color = vec4(0.07, 0.075, 0.09, 1.0);
uniform float clock = 0.0;
uniform float flap_rate = 11.0;
uniform float base_speed = 0.32;   // rad/s at speed factor 1
// a bird that wheels close to the camera (a flock over a tall roof, the camera zoomed in) would be a black shape across
// the screen: it shrinks to nothing between these distances from the camera (whole bird, by its centre)
uniform float near_hide = 8.0;
uniform float near_full = 14.0;

void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float phase = c.x * 6.2831;
	float radius = c.y;
	float speed = base_speed * c.w * (c.x > 0.5 ? 1.0 : -1.0);
	float th = clock * speed + phase;
	// a wobbling orbit: radius breathes, height drifts, so the flock never looks like a carousel
	float rr = radius * (1.0 + 0.18 * sin(clock * 0.37 + phase * 2.0));
	vec3 p = vec3(cos(th) * rr, c.z + 1.4 * sin(clock * 0.53 + phase * 3.0), sin(th) * rr);
	vec3 fwd = normalize(vec3(-sin(th), 0.0, cos(th)) * sign(speed) + vec3(0.0, 0.15 * cos(clock * 0.53 + phase * 3.0), 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 up = cross(fwd, right);
	// flap in bursts, glide between them
	float burst = smoothstep(-0.2, 0.4, sin(clock * 0.9 + phase * 5.0));
	float flap = sin(clock * flap_rate + phase * 17.0) * burst * 0.55;
	vec3 v = VERTEX;
	v.y += COLOR.r * flap * abs(v.x) * 1.4;
	// bank into the turn
	v = v + vec3(0.0, -v.x * 0.35 * sign(speed), 0.0);
	float cam_dist = -(MODELVIEW_MATRIX * vec4(p, 1.0)).z;
	float keep = smoothstep(near_hide, near_full, cam_dist);
	vec3 wp = p + (right * v.x + up * v.y + fwd * v.z) * keep;
	VERTEX = wp;
}

void fragment() {
	ALBEDO = bird_color.rgb;
}
