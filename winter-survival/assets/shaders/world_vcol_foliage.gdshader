// Scatter trees and bushes (G2b, doc 08 §3.10): world_vcol + per-vertex wind (wind_include, WV_WIND_TREE). Never
// cut, no discard (the forest keeps the G1 cost). assets/materials/world_vcol_foliage.tres; WindSway puts it on the
// tree / bush meshes of the scatter MultiMeshes and on materialized trees.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

#define WV_WIND_TREE
#include "res://assets/shaders/world_vcol_common.gdshaderinc"
