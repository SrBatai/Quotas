class_name SnowDrift
extends GPUParticles3D
## Wind-blown snow at ground level (G2a P1, doc 08 §3.10 «serpientes de nieve»): long, faint streaks lying on the
## ground that run with the wind in a 44 m box around the camera focus. Direction and strength come from
## DayNight.current_wind (the `snow_wind` of the snow v2 shader): almost nothing in clear weather, a carpet of moving
## snow in a blizzard. One draw call; amount 900 × the Quality particle ratio (alto 900, medio 540, compat 405).
## The streaks are flat quads built in the vertex shader along the particle velocity (align_y), so they never show
## edge-on. Client only (World adds it next to Snowfall).

const AMOUNT := 900
const SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.93, 0.96, 1.0, 1.0);
uniform float width = 0.45;
uniform float length_m = 2.6;
void vertex() {
	vec3 axis = MODEL_MATRIX[1].xyz;
	axis.y = 0.0;
	axis = length(axis) > 1e-3 ? normalize(axis) : vec3(1.0, 0.0, 0.0);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), axis));
	vec3 wp = MODEL_MATRIX[3].xyz + side * VERTEX.x * width + axis * VERTEX.y * length_m;
	POSITION = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(wp, 1.0));
}
void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float a = (1.0 - d.x * d.x) * (1.0 - smoothstep(0.2, 1.0, abs(d.y)));
	ALBEDO = tint.rgb;
	ALPHA = a * COLOR.a * tint.a;
}
"""

var _t: float = 0.0


func _ready() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.15, 22)
	pm.spread = 8.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 6.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3.ZERO
	pm.particle_flag_align_y = true
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.25, Color(1, 1, 1, 0.22))
	ramp.add_point(0.75, Color(1, 1, 1, 0.16))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	q.material = mat
	draw_pass_1 = q
	amount = AMOUNT
	lifetime = 2.4
	preprocess = 2.4
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(Vector3(-50, -4, -50), Vector3(100, 8, 100))
	_apply_wind()


func _process(delta: float) -> void:
	var rig := CameraRig.active()
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if rig != null:
		global_position = rig.global_position + Vector3(0, 0.12, 0)
	elif cam != null:
		global_position = cam.global_position + (-cam.global_basis.z) * 12.0
	_t -= delta
	if _t <= 0.0:
		_t = 0.5
		_apply_wind()


func _apply_wind() -> void:
	var w := DayNight.current_wind
	var dir := Vector3(w.x, 0.0, w.y)
	if dir.length() < 0.01:
		dir = Vector3.RIGHT
	var pm := process_material as ParticleProcessMaterial
	pm.direction = dir.normalized()
	var strength := clampf(w.z, 0.0, 1.0)
	pm.initial_velocity_min = lerpf(4.0, 8.0, strength)
	pm.initial_velocity_max = lerpf(7.0, 14.0, strength)
	# calm weather (prevailing drift 0.3) shows nothing; blizzards (1.0) the full carpet
	amount_ratio = Quality.particle_ratio() * smoothstep(0.35, 1.0, strength)
	emitting = amount_ratio > 0.01
