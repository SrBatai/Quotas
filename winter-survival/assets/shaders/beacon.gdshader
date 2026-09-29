// G2b beacons and rotating lights (doc 08 §3.9 «luces intermitentes: emisivos animados, 0 ms»): bulbs as
// camera-facing halos and, for the ground, the light they throw on the snow — both additive quads in a MultiMesh
// (BeaconLights: 2 draw calls for every beacon in view), animated here from one clock, no CPU per frame beyond setting it. Forward+, Compatibility
// and the Web alike (the Compatibility / Web builds have no real beacon lights: the sweep pools do their job).
// INSTANCE_CUSTOM: rgb = colour, a = mode + phase (fract, 0..1):
//   mode 0 blink    amber flasher (barriers, works), 1 Hz
//   mode 1 rotate   rotating beacon (police, ambulance, snow plough): a lobe sweeps round; the bulb flares when it
//                   faces the camera, the pool is a rotating wedge of light on the ground
//   mode 2 pulse    slow red obstruction light (masts, cranes): a short flash every 1.6 s
//   mode 3 amber    traffic light left on amber-flashing, 0.75 Hz, soft
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

global uniform vec4 city_lights;   // x: night 0..1 (DayNight)

uniform bool halo = true;
uniform float energy = 1.0;
uniform float falloff = 2.4;
uniform float rotate_speed = 4.2;   // rad/s
// BeaconLights sets the clock every frame (the real SpotLights turn on the same clock; the engine time rolls over)
uniform float clock = 0.0;

varying vec4 v_custom;
varying vec3 v_origin;

float beacon_level(int mode, float phase, float t, float facing) {
	if (mode == 0) {
		float f = fract(t * 1.0 + phase);
		return smoothstep(0.0, 0.04, f) * (1.0 - smoothstep(0.42, 0.5, f));
	} else if (mode == 1) {
		return facing;
	} else if (mode == 2) {
		float f = fract(t / 1.6 + phase);
		return exp(-f * 9.0);
	}
	float f = fract(t * 0.75 + phase);
	return smoothstep(0.0, 0.15, f) * (1.0 - smoothstep(0.45, 0.62, f));
}

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_origin = MODEL_MATRIX[3].xyz;
	if (halo) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
}

void fragment() {
	int mode = int(floor(v_custom.a));
	float phase = fract(v_custom.a);
	float ang = clock * rotate_speed + phase * 6.2831;
	vec2 d = UV * 2.0 - 1.0;
	float r = length(d);
	float night = mix(0.3, 1.0, clamp(city_lights.x, 0.0, 1.0));
	float level;
	float shape;
	if (halo) {
		// facing: how much the rotating lobe points at the camera
		vec3 to_cam = CAMERA_POSITION_WORLD - v_origin;
		float cam_ang = atan(to_cam.z, to_cam.x);
		float facing = pow(max(cos(ang - cam_ang), 0.0), 6.0);
		level = mode == 1 ? 0.18 + 0.82 * facing : beacon_level(mode, phase, clock, facing);
		shape = pow(clamp(1.0 - r, 0.0, 1.0), falloff) + 0.6 * pow(clamp(1.0 - r * 3.0, 0.0, 1.0), 2.0);
	} else {
		// ground pool: a rotating wedge for mode 1, a round flash otherwise; only really visible at night
		float radial = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		if (mode == 1) {
			vec2 dir = vec2(cos(ang), sin(ang));
			float wedge = pow(max(dot(normalize(d + vec2(1e-4)), dir), 0.0), 5.0);
			shape = radial * (0.15 + 0.85 * wedge) * smoothstep(0.02, 0.2, r);
			level = 1.0;
		} else {
			shape = radial;
			level = beacon_level(mode, phase, clock, 0.0);
		}
		night = clamp(city_lights.x, 0.0, 1.0) * 0.9;
	}
	ALBEDO = v_custom.rgb * shape * level * energy * night;
}
