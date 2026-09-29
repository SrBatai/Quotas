// Shared world material (PLAN C2 / ARQ v2 §14): characters, forest, props, POIs. Never cut, no discard (G1 cost).
// Body and the rest of the family: world_vcol_common.gdshaderinc. One ShaderMaterial
// (assets/materials/world_vcol.tres) is shared by every `palette_vcol` surface.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://assets/shaders/world_vcol_common.gdshaderinc"
