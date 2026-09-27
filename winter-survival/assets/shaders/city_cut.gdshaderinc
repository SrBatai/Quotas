// «Corte urbano» (W0, doc 09 §3): lets the high isometric camera see the local player through city buildings.
// Layers, all opaque (discard with a 4×4 Bayer threshold, no stencil, same in Forward+ / Compatibility / Web):
//   A. floor cut: structure above the next slab over the player's floor is removed when it lies on the camera
//      side of the player AND inside the camera→player corridor or hides the ground within R of the player;
//   B. capsule: anything within Rc of the camera→chest segment (structure and, if enabled, city props);
//   C. caps: the caller paints back faces with `cap_color` and an upward normal, so a cut building reads as a
//      solid block showing the plan of its next slab (closed volumes, one slab per floor: city building contract);
//   E. own building: inside the footprint of the building the local player stands in, everything above the
//      ceiling slab of the player's floor goes, and the camera-side walls of that floor drop to a 0.6 m stub.
// Never applied in the shadow pass: a cut tower keeps its shadow on the street and its interior stays dark.
//
// Everything that changes per frame or per building comes from GLOBAL uniforms written by CityCut
// (scripts/world/city/city_cut.gd) and from MODEL_MATRIX (base of the building = origin of its pieces). There are
// no instance uniforms on purpose: Godot reserves 16 vec4 per instance in the global buffer and Compatibility caps
// that buffer at the UBO size (4 096 vec4 = 256 instances under llvmpipe/WebGL), far below a city block.
// Per-family values (floor heights, cap colour) are material uniforms (world_vcol_struct*.tres, window_city*.tres).
//
// Stage built-ins (CAMERA_POSITION_WORLD, FRAGCOORD, IN_SHADOW_PASS) are passed in by the caller, so the same
// functions work from any stage; CityCut.is_cut() mirrors them in GDScript for the cursor ray and the tests.

global uniform vec4 ws_cut_player;    // xyz: feet of the local player; w: 1 = cut on
global uniform vec4 ws_cut_floor;     // x: player floor level the cut comes from, y: level it goes to, z: blend 0..1, w: stub (m)
global uniform vec4 ws_cut_view;      // xy: unit xz vector player -> camera; z: corridor half-width W (m); w: zone radius R (m)
global uniform vec4 ws_cut_capsule;   // xyz: chest of the local player; w: capsule radius Rc (m), 0 = off
global uniform vec4 ws_cut_aim;       // xyz: aim point; w: 1 = second zone centre (half radius)
global uniform vec4 ws_cut_own;       // own building footprint: xy centre (world x, z), zw half extents (local x, z); z <= 0: none
global uniform vec4 ws_cut_own_ext;   // x: cos(yaw), y: sin(yaw) of that footprint; z: y of the 0.6 m wall stub; w: y above which all goes (1e4 = the player is on its roof)
global uniform vec4 ws_cut_style;     // x: dither strength 0..1 (1 = the core is fully removed); y: capsule on city props (0/1); z: edge width (m); w: unused
global uniform vec4 ws_cut_cam;       // footprint of the building that CONTAINS THE CAMERA: xy centre (x, z), zw half extents; z <= 0: none
global uniform vec4 ws_cut_cam_ext;   // x: cos(yaw), y: sin(yaw) of that footprint

float cc_bayer4(vec2 p) {
	uvec2 q = uvec2(p) & uvec2(3u);
	uint xy = q.x ^ q.y;
	uint v = ((xy & 1u) << 3u) | ((q.y & 1u) << 2u) | (xy & 2u) | ((q.y & 2u) >> 1u);
	return (float(v) + 0.5) / 16.0;
}

// Height of the cut for a building whose slabs sit at base + ground_h + n * floor_h (n >= 0), for a player whose
// floor is at y_ref: the first slab above the player's floor (street level -> the slab over the ground floor).
float cc_slab_above(float y_ref, float base_y, float ground_h, float floor_h) {
	float k = max(0.0, ceil((y_ref + 0.5 - base_y - ground_h) / floor_h));
	return base_y + ground_h + k * floor_h;
}

// Does p hide the ground within r of `centre` as seen from the camera c? 1 = yes (soft edge of ws_cut_style.z).
float cc_zone(vec3 p, vec3 c, vec3 centre, float r) {
	float h = c.y - p.y;
	if (h <= 0.05) {
		return 1.0;
	}
	vec3 g = c + (p - c) * ((c.y - ws_cut_player.y) / h);
	float e = max(ws_cut_style.z, 0.5);
	return 1.0 - smoothstep(r - e, r, length(g.xz - centre.xz));
}

// Capsule around the camera -> chest segment (stops short of the chest so the player itself is never touched).
float cc_capsule(vec3 p, vec3 c) {
	float r = ws_cut_capsule.w;
	if (r <= 0.01) {
		return 0.0;
	}
	vec3 ba = ws_cut_capsule.xyz - c;
	float t = clamp(dot(p - c, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
	return (1.0 - smoothstep(r * 0.55, r, length(p - (c + ba * t)))) * step(t, 0.96);
}

bool cc_in_box(vec3 p, vec4 box, vec4 ext) {
	if (box.z <= 0.0) {
		return false;
	}
	vec2 d = p.xz - box.xy;
	vec2 l = vec2(d.x * ext.x - d.y * ext.y, d.x * ext.y + d.y * ext.x);
	return abs(l.x) <= box.z && abs(l.y) <= box.w;
}

// Is p inside the footprint of the local player's own building?
bool cc_in_own(vec3 p) {
	return cc_in_box(p, ws_cut_own, ws_cut_own_ext);
}

// Height of the floor cut for this building (blended between the two player floor levels) + stub.
float cc_y_cut(float base_y, float ground_h, float floor_h) {
	return mix(cc_slab_above(ws_cut_floor.x, base_y, ground_h, floor_h),
			cc_slab_above(ws_cut_floor.y, base_y, ground_h, floor_h), ws_cut_floor.z) + ws_cut_floor.w;
}

// Fade (0 keep … 1 remove) of a building-structure fragment. base_y = MODEL_MATRIX[3].y of the piece.
float city_cut_struct_fade(vec3 p, vec3 c, float base_y, float ground_h, float floor_h) {
	vec3 pl = ws_cut_player.xyz;
	float d_side = dot(p.xz - pl.xz, ws_cut_view.xy);
	float side = smoothstep(-3.0, 1.0, d_side);
	float fade = 0.0;
	if (cc_in_own(p)) {
		if (p.y > ws_cut_own_ext.w) {
			fade = 1.0;
		} else if (p.y > ws_cut_own_ext.z) {
			// walls of the player's own floor: a tight ramp (only what is on the camera side of the player drops to the
			// stub); on a roof the parapet and roof plant use the wide one (see the street below over it)
			fade = ws_cut_own_ext.w > 5000.0 ? side : smoothstep(-1.5, 0.5, d_side);
		}
	} else if (side > 0.0) {
		float y_cut = cc_y_cut(base_y, ground_h, floor_h);
		if (p.y > y_cut && cc_in_box(p, ws_cut_cam, ws_cut_cam_ext)) {
			// the building that contains the camera goes entirely above the cut (its floors would ring the view)
			fade = side;
		} else if (p.y > y_cut) {
			vec2 ab = pl.xz - c.xz;
			float u = clamp(dot(p.xz - c.xz, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
			float e = max(ws_cut_style.z, 0.5);
			float corridor = 1.0 - smoothstep(ws_cut_view.z - e, ws_cut_view.z, length(p.xz - (c.xz + ab * u)));
			float zone = cc_zone(p, c, pl, ws_cut_view.w);
			if (ws_cut_aim.w > 0.5) {
				zone = max(zone, cc_zone(p, c, ws_cut_aim.xyz, ws_cut_view.w * 0.5));
			}
			fade = side * max(corridor, zone);
		}
	}
	return max(fade, cc_capsule(p, c));
}

// Structure (walls, slabs, facades, windows): floor cut + own building + capsule.
bool city_cut_struct_discard(vec3 p, vec3 c, float base_y, float ground_h, float floor_h, vec2 fragcoord, bool shadow_pass) {
	if (shadow_pass || ws_cut_player.w < 0.5) {
		return false;
	}
	return city_cut_struct_fade(p, c, base_y, ground_h, floor_h) * ws_cut_style.x > cc_bayer4(fragcoord);
}

// Section plan (layer C): 1 when p is an upward face under a removed column of its building (the slab of the next
// floor seen through the cut, or the player's own floor), so the caller can draw it as a lit plan even inside the
// shadow the (uncut) upper floors still cast.
float city_cut_plan(vec3 p, vec3 n, vec3 c, float base_y, float ground_h, float floor_h) {
	if (ws_cut_player.w < 0.5 || n.y < 0.7) {
		return 0.0;
	}
	bool own = cc_in_own(p);
	if (own && ws_cut_own_ext.w > 5000.0) {
		return 0.0;   // standing on this roof: open sky, not a section
	}
	float top = own ? ws_cut_own_ext.w : cc_y_cut(base_y, ground_h, floor_h);
	if (p.y >= top) {
		return 0.0;
	}
	float above = city_cut_struct_fade(vec3(p.x, top + 0.05, p.z), c, base_y, ground_h, floor_h);
	return smoothstep(0.4, 0.9, above);
}

// City props, foliage, lamps, overpasses: capsule only, and only while the city profile turns it on.
bool city_cut_capsule_discard(vec3 p, vec3 c, vec2 fragcoord, bool shadow_pass) {
	if (shadow_pass || ws_cut_player.w < 0.5 || ws_cut_style.y < 0.5) {
		return false;
	}
	return cc_capsule(p, c) * ws_cut_style.x > cc_bayer4(fragcoord);
}
