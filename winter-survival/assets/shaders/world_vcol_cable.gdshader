// Hanging cables and wires (G2b): world_vcol + sag swing (wind_include, WV_WIND_CABLE) + the city props capsule.
// A cable mesh runs along model X centred on its origin; wind_height = its span (m). assets/materials/world_vcol_cable.tres.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

#define WV_WIND_CABLE
#define WV_CUT_CAPSULE
#include "res://assets/shaders/world_vcol_common.gdshaderinc"
