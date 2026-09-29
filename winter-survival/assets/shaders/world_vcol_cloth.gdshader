// Tarps, tents and laundry (G2b): world_vcol + cloth flutter (wind_include, WV_WIND_CLOTH) + the city props capsule
// (the camera→player cut is off outside the city profile). cull_disabled: cloth is often single-sided.
// assets/materials/world_vcol_cloth.tres (wind_height = the band height of the model, m).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

#define WV_WIND_CLOTH
#define WV_CUT_CAPSULE
#include "res://assets/shaders/world_vcol_common.gdshaderinc"
