// City building structure (W0 «corte urbano», doc 09 §3): world_vcol + floor cut + capsule + section caps.
// cull_disabled so the back faces of the closed volumes paint the caps. Shared by every structure surface of the
// city buildings (assets/materials/world_vcol_struct.tres; *_4m for 4 m commercial ground floors).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_schlick_ggx;

#define WV_CUT_STRUCT
#include "res://assets/shaders/world_vcol_common.gdshaderinc"
