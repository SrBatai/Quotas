// City props, lamps, foliage and cars (W0, doc 09 §3.1 layer B): world_vcol + the camera→player capsule, active
// only while CityCut turns it on (city profile). assets/materials/world_vcol_capsule.tres.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#define WV_CUT_CAPSULE
#include "res://assets/shaders/world_vcol_common.gdshaderinc"
