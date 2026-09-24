# VENTISCA — 3D Asset Specification (contract for the Blender agent)

Blender **5.0.1** as a Python module (`python3 -c "import bpy"`), procedural `bpy`/`bmesh` scripts only, **no textures, no downloaded assets**. Output goes into the Godot project at `winter-survival/`. The code agent works in parallel from `ARCHITECTURE.md` and never sees your scripts — **only what is written here is guaranteed to match**. Where this doc gives a number or a name, it is a requirement, not a suggestion.

---

## 1. Pipeline

| What | Path |
|---|---|
| Build scripts (one per asset family) | `winter-survival/blender/build_<family>.py` |
| Shared helpers | `winter-survival/blender/lib/palette.py`, `winter-survival/blender/lib/lowpoly.py`, `winter-survival/blender/lib/export.py` |
| Build everything | `winter-survival/blender/build_all.py` (imports and runs every `build_*.py`, then runs `verify_assets.py`) |
| Verification | `winter-survival/blender/verify_assets.py` (re-imports every `.glb`, prints a report, exits non-zero on contract violations) |
| Blender sources | `winter-survival/blender/sources/<asset>.blend` (one per `.glb`, saved right before export) |
| Godot models | `winter-survival/assets/models/<asset>.glb` |

Run from anywhere: `cd /home/user/Quotas/winter-survival/blender && python3 build_all.py`. Each `build_*.py` must also be runnable on its own. Every script starts from an empty scene (`bpy.ops.wm.read_factory_settings(use_empty=True)`), builds one asset, saves the `.blend`, exports the `.glb`. Never leave stray objects (cameras, lights, default cube) in the scene.

Script → assets mapping:

| Script | Assets produced |
|---|---|
| `build_player.py` | `player` |
| `build_animals.py` | `wolf`, `deer` |
| `build_trees.py` | `pine_a`, `pine_b`, `pine_c`, `dead_tree`, `stump` |
| `build_rocks.py` | `rock_a`, `rock_b`, `rock_c`, `stone` |
| `build_plants.py` | `berry_bush` |
| `build_pickups.py` | `firewood`, `fallen_log` |
| `build_fire.py` | `campfire`, `torch`, `lantern` |
| `build_tools.py` | `stone_axe` |
| `build_cabin.py` | `cabin` |
| `build_furniture.py` | `bed`, `desk`, `chair`, `shelf`, `clock`, `cabinet`, `wood_stove` |
| `build_props.py` | `a_frame_cabin`, `pickup_truck`, `signpost`, `fence` |
| `build_optional.py` | `tent`, `storage_box` (P2, only if time allows) |

Priorities: **P0** first (the game is unplayable-looking without them), then **P1**, then **P2**. Ship P0 before polishing anything.

- P0: player, wolf, pine_a, pine_b, pine_c, dead_tree, stump, rock_a, rock_b, stone, berry_bush, firewood, fallen_log, campfire, stone_axe, torch, cabin, wood_stove, cabinet
- P1: deer, rock_c, pickup_truck, signpost, fence, lantern, bed, desk, chair, shelf, clock, a_frame_cabin
- P2: tent, storage_box

---

## 2. Global conventions (apply to every asset)

### 2.1 Units and axes
- **1 Blender unit = 1 meter.** Scene unit scale 1.0. Godot: 1 unit = 1 m.
- Blender is **Z-up, right-handed**. Godot is **Y-up, right-handed, −Z forward**.
- Export with the glTF exporter's default **`export_yup=True`**. The conversion is exactly:
  `Blender (x, y, z) → Godot (x, z, −y)`, i.e. **Blender +X → Godot +X, Blender +Z → Godot +Y, Blender +Y → Godot −Z.** Handedness is preserved (no mirroring): a part on the character's right in Blender is on its right in Godot.
- **Forward = Blender +Y.** Every asset that has a front (player, wolf, deer, cabin, A-frame, truck, cabinet, stove, bed, chair, desk, clock, shelf, signpost boards) faces **+Y in Blender**, which becomes **−Z in Godot = Godot's forward** (`Vector3.FORWARD`). The code uses `-basis.z` as facing without any correction. Consequence for you: in Blender's *Front* view (numpad 1, looking along +Y) you see the model's **back**; use *Back* view (Ctrl+numpad 1) to see its face. This is intentional — do not "fix" it.
- **Up = Blender +Z**, feet/base on the ground plane z = 0.

### 2.2 Origin (pivot) rules
- Ground-standing things (characters, trees, rocks, bushes, pickups, campfire, buildings, furniture, fence, signpost, truck): origin at the **center of the footprint, at ground level (z = 0)**. Godot places the node at terrain height and the model sits on the snow.
- Hand tools (axe, torch): origin at the **grip point** (where the hand holds), handle extending along **+Z**.
- Lantern: origin at the **hanging hook** (top), body hanging along −Z.
- Wall-mounted things (shelf, clock): origin at the **wall contact point, centered** (back face center); the object protrudes toward **+Y**.
- Animated parts (§2.6): each part's origin is its **joint** (hip, shoulder, neck…).

### 2.3 Transforms and hierarchy
- Every object is exported with **rotation (0,0,0) and scale (1,1,1)**; only `location` may be non-zero (it is the pivot position). Bake any rotation/scale into the mesh data. **Exception:** empties used as sockets may carry a rotation when this doc says so (`ToolSocket`, `TextTop`, `TextBottom`).
- Parenting: `child.parent = parent; child.matrix_parent_inverse = Matrix.Identity(4)`; then set `child.location` **relative to the parent**. Positions in this doc are given in **world (Blender) coordinates**; local = world − parent's world position.
- Objects that are not listed as children are top-level objects in the scene collection. Godot imports the glb as a scene whose root is a `Node3D` and whose children are your top-level objects, in order. **The code never relies on the root's name**; it uses `find_child(name, true, false)` for every named node below.

### 2.4 Naming
- Object names are **exact, case-sensitive**, ASCII letters/digits only (plus the `-convcolonly` suffix in §2.8). No spaces, dots, colons. Never let Blender append `.001` — every script builds in an empty scene and names each object once. Use `verify_assets.py` to prove it.
- Names listed as **required** are looked up by the code. Extra decorative objects are allowed with any ASCII name, as long as they don't collide with required names.
- Material names are exact too (§3): the code looks for the material named `window` to make windows glow, and `ember` for the stove door.

### 2.5 Look: low-poly flat shading, no textures
- **Flat shading everywhere**: every polygon `use_smooth = False` (`mesh.shade_flat()`), so the exporter writes per-face normals. No subdivision surfaces, no smooth-shaded icospheres.
- **No UVs, no textures, no images, no vertex colors.** Color comes only from each material's Principled BSDF **Base Color**. Roughness 0.9, Metallic 0.0, Emission black, Alpha 1.0 (the code handles transparency/emission itself where needed).
- Materials: `mat = bpy.data.materials.new(name); mat.use_nodes = True; bsdf = mat.node_tree.nodes["Principled BSDF"]; bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)` (linear RGB converted from the sRGB hex: `((c/255)**2.2)` per channel is acceptable, or use `mathutils.Color.from_srgb_to_scene_linear()` when available). Also set `mat.diffuse_color` to the same value for the viewport. Create each material **once per file** via `palette.get_material(name)`.
- Meshes may have several material slots (multi-material meshes export as several primitives → several surfaces in Godot). That is the normal way to color parts: e.g. a tree is one mesh with `bark`, `pine_dark`, `pine_light`, `snow` slots.
- **Snow rule**: on trees, rocks, roofs, the truck, the fence, the signpost, fallen logs and bushes, faces whose world normal has **z > 0.55** get the `snow` material (unless the spec says otherwise), so everything looks snowed-on from above. Where a thicker look is wanted (roofs, tree tiers), add explicit snow "slabs" (see per-asset notes).
- Silhouettes: boxes, 6–12-sided cylinders/cones, icospheres subdivision 1 with random jitter (±8 % of radius) for rocks/bushes/stones. Bevel nothing.

### 2.6 Animation approach: procedural in code, separate rigid parts (no armatures)
Skeletal animation is **not used** (no armatures, no actions, `export_animations=False`). Characters (player, wolf, deer) are built as **separate rigid mesh objects parented in a hierarchy**, each with its origin at the joint it rotates around. The Godot code rotates these parts procedurally (walk cycle, chop, bite). The exact part names, parents and pivots are given per asset in §4. If a part is missing, the code still runs (it creates an empty node) but that part won't animate — so get the names right.

### 2.7 Poly budget
Triangle counts (after flat-shaded export, visual meshes only): see each asset. Keep the total under **12 000 triangles** for the whole set. Over-budget models are rejected by `verify_assets.py` (+20 % tolerance).

### 2.8 Collision convention
- **Default: collision shapes are created in Godot code** (primitive shapes with the dimensions in this doc). Your mesh must fit those dimensions within ±10 %.
- **Exception — large static architecture embeds its own collision**: `cabin`, `a_frame_cabin`, `pickup_truck` (and P2 `tent`) include invisible convex collision boxes as separate **top-level** mesh objects named `Col<Name>-convcolonly` (e.g. `ColWallBack-convcolonly`). Godot's importer turns each into a `StaticBody3D` named `Col<Name>` with a `ConvexPolygonShape3D` and removes the mesh. Rules: each is a simple closed convex box/prism (8 or 6 vertices), no material needed, must remain **visible** in the scene at export time (the exporter skips hidden objects only when asked, but don't risk it), must never be parented under a visual object (cutaway hiding must not touch them).
- No other suffixes (`-col`, `-colonly`, `-navmesh`, `-noimp`, `-rigid`…) anywhere.

### 2.9 Export settings (`lib/export.py`)
```python
bpy.ops.export_scene.gltf(
    filepath=str(glb_path), export_format='GLB', export_yup=True, export_apply=True,
    export_animations=False, export_skins=False, export_morph=False,
    export_materials='EXPORT', export_image_format='NONE',
    export_normals=True, export_texcoords=False,
    export_cameras=False, export_lights=False, export_extras=False,
    use_selection=False, use_visible=False, use_active_collection=False)
```
If a keyword is rejected by this Blender version (`TypeError`), drop that keyword and keep going (the defaults are acceptable). If `bpy.ops.export_scene.gltf` is not registered, enable the add-on first: `import addon_utils; addon_utils.enable("io_scene_gltf2")`. Save the `.blend` **before** exporting with `bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))`.

### 2.10 Godot import (for your information)
The code agent imports each `.glb` with Godot's default scene importer (no `.import` overrides): meshes → `MeshInstance3D`, empties → `Node3D`, materials embedded, names preserved (Godot only replaces `. : @ / " %` with `_`, which you never use). `Assets.spawn_model("<name>")` instantiates `res://assets/models/<name>.glb` and guarantees the required anchors exist; if the file is missing, a primitive placeholder with the same node names is used — so a missing or broken file never crashes the game, it just looks worse.

---

## 3. Palette (`lib/palette.py`)

Material name → sRGB hex. Use only these names; the same name must have the same color in every file.

| Name | Hex | Name | Hex |
|---|---|---|---|
| `snow` | `#F1F5FA` | `iron` | `#2B2E33` |
| `snow_shadow` | `#B9CBE3` | `cabin_wall` | `#5D7FA6` |
| `ice` | `#BFE3F0` | `cabin_trim` | `#DDE6F0` |
| `pine_dark` | `#2F5D3A` | `roof` | `#33383F` |
| `pine_light` | `#4B8A55` | `window` | `#9CC4DD` |
| `bark` | `#5B3F2E` | `truck_paint` | `#5B6B3F` |
| `wood` | `#8B6543` | `bush` | `#3E6B45` |
| `wood_light` | `#C7A16B` | `berry` | `#D9403D` |
| `wood_dark` | `#4A3426` | `ember` | `#E63B12` |
| `stone` | `#7C8592` | `jacket` | `#B03A2E` |
| `stone_dark` | `#5A616B` | `hat` | `#2E4A7A` |
| `brick` | `#8E5A4A` | `scarf` | `#E8B04B` |
| `skin` | `#F1C9A5` | `boots` | `#2A2320` |
| `wolf_fur` | `#6E7378` | `wolf_belly` | `#A9AEB2` |
| `eyes` | `#F5D142` | `eyes_dark` | `#1E1E24` |
| `deer_fur` | `#8A6A48` | `deer_belly` | `#C9B79C` |
| `cloth` | `#C9B79C` | `paper` | `#EDE6D6` |
| `can_red` | `#C23B3B` | `can_blue` | `#3B6BC2` |

---

## 4. Asset specifications

Notation: dimensions are **Blender X (width, left–right) × Y (depth, back–front) × Z (height)** in meters. "World" coordinates are Blender scene coordinates (the asset's own file). Godot dimensions are (X, Z, Y) of those, and Godot z = −Blender y. Tri = triangle budget.

### 4.1 `player.glb` — the survivor (P0)
Bundled-up figure: puffy dark-red jacket, navy beanie with a snow-white pompom, mustard scarf and mittens, navy pants, dark boots. Total height **1.80 m** (pompom top), shoulder width 0.72 m (with arms), depth 0.34 m. Faces **+Y**. Tri ≤ 700.

Hierarchy (required names; world pivot positions):

```
Hips            Empty, pivot (0, 0, 0.80)                      ← root of the rig (top-level object)
├── Torso       Mesh, pivot (0, 0, 0.80). Jacket box 0.52×0.32, z 0.80–1.36 (slightly wider at the bottom: 0.56 at z=0.80),
│               material jacket; scarf ring 0.40×0.36, z 1.30–1.40 material scarf (part of Torso).
│   ├── Head    Mesh, pivot (0, 0, 1.36) (neck). Skin box 0.30×0.28, z 1.38–1.64 material skin; hat box 0.34×0.32,
│   │           z 1.60–1.74 material hat; pompom icosphere r 0.06 at z 1.80 material snow; eyes: two 0.04×0.04 quads
│   │           material eyes_dark at (±0.06, +0.141, 1.56) on the front face (+Y).
│   │   └── BreathAnchor   Empty, world (0, 0.20, 1.52)  (local (0, 0.20, 0.16))
│   ├── ArmL    Mesh, pivot (−0.36, 0, 1.32) (shoulder). Box 0.16×0.16 from z 1.32 down to 0.76; z 0.76–0.88 material scarf (mitten), rest jacket.
│   └── ArmR    Mesh, pivot (+0.36, 0, 1.32). Mirror of ArmL.
│       └── ToolSocket     Empty, world (0.36, 0.05, 0.80) (local (0, 0.05, −0.52)), **rotation_euler = (−90°, 0, 0)**
│                          so that its local +Z points along world +Y (forward). Tools are parented here with identity transform.
├── LegL        Mesh, pivot (−0.12, 0, 0.80) (hip). Box 0.20×0.22 from z 0.80 down to 0; z 0–0.18 material boots, rest material hat (pants).
└── LegR        Mesh, pivot (+0.12, 0, 0.80). Mirror.
```
`ArmR`/`LegR` are on **+X** = the character's right (facing +Y, up +Z → right = +X). Code: capsule collider r 0.35, height 1.7.

### 4.2 `wolf.glb` — night predator (P0)
Grey wolf, **1.40 m nose-to-rump** (1.85 m with tail), **0.75 m tall at the back**, 0.36 m wide. Faces **+Y**. Materials `wolf_fur` (body), `wolf_belly` (underside faces with normal z < −0.3, and the snout front), `eyes` (two 0.04 quads), `eyes_dark` (nose 0.05 quad). Tri ≤ 600.

```
Body            Mesh, pivot (0, 0, 0.55). Tapered box 0.36×0.90 (y −0.45…+0.45), z 0.36–0.74; top-level object.
├── Head        Mesh, pivot (0, 0.45, 0.62) (neck). Skull box 0.24×0.30 (y 0.45…0.75), z 0.50–0.74; snout box 0.14×0.18
│               (y 0.75…0.93), z 0.50–0.64; two ear pyramids 0.08 tall on top at x ±0.08, y 0.55.
│   └── Muzzle  Empty, world (0, 0.93, 0.58)
├── Tail        Mesh, pivot (0, −0.45, 0.62). Box 0.10×0.45 (y −0.90…−0.45) drooping to z 0.45 at the tip.
├── LegFL       Mesh, pivot (−0.13, +0.30, 0.42). Box 0.10×0.12 from z 0.42 to 0.
├── LegFR       Mesh, pivot (+0.13, +0.30, 0.42)
├── LegBL       Mesh, pivot (−0.13, −0.30, 0.42)
└── LegBR       Mesh, pivot (+0.13, −0.30, 0.42)
```
Code: capsule r 0.3, height 1.1 lying along Z, centered y 0.45.

### 4.3 `deer.glb` — ambient wildlife (P1)
Same hierarchy and names as the wolf (`Body`, `Head`+`Muzzle`, `Tail`, `LegFL/FR/BL/BR`), scaled up: body box 0.40×1.20 (y −0.55…+0.65), z 0.70–1.15, pivot (0, 0, 0.90); legs 0.09×0.10 from z 0.70 to 0, pivots (±0.14, ±0.42, 0.70); neck box rising from (0, 0.60, 0.95) to (0, 0.85, 1.35) as part of `Head`, pivot (0, 0.60, 1.00); head box 0.20×0.30 (y 0.75…1.05) z 1.25–1.47; `Muzzle` (0, 1.05, 1.35); antlers: two branched boxes (3 segments each) material `wood_light` on top of the head; tail tiny. Materials `deer_fur`, `deer_belly`, `eyes`, `eyes_dark`. Height 1.65 (antler tips). Tri ≤ 800. Code: capsule r 0.35, height 1.4 along Z, centered y 0.7.

### 4.4 `pine_a.glb`, `pine_b.glb`, `pine_c.glb` — snow-capped pines (P0)
Single mesh object named **`Tree`**, origin at trunk base center, trunk axis +Z. Style: **stacked flat tiers** (like snow-capped umbrellas, see reference). Each tier is an **8-sided cone** with an extra vertex ring at **55 % of its height**; faces below the ring get pine green, faces above the ring get `snow`. Trunk: 6-sided cylinder, material `bark`, visible between tiers.

| Variant | Total height | Trunk r (base→top) | Tiers (base z, base radius, height) from bottom | Tri |
|---|---|---|---|---|
| `pine_a` (tall) | 7.0 | 0.25 → 0.12 | (1.4, 1.9, 2.0) `pine_dark`; (3.0, 1.5, 1.8) `pine_dark`; (4.4, 1.1, 1.6) `pine_light`; (5.6, 0.7, 1.4) `pine_light` | ≤ 350 |
| `pine_b` (medium) | 5.5 | 0.22 → 0.10 | (1.1, 1.6, 1.7) `pine_dark`; (2.5, 1.2, 1.5) `pine_light`; (3.7, 0.8, 1.8) `pine_light` | ≤ 300 |
| `pine_c` (small, heavy snow) | 4.0 | 0.18 → 0.08 | (0.8, 1.3, 1.5) `pine_dark`; (1.9, 0.9, 1.3) `pine_light`; (2.8, 0.55, 1.2) `pine_light`; snow ring at 45 % (more snow) | ≤ 300 |

Also add a small snow disc (flattened 8-gon, r = 0.45, 0.08 thick, `snow`) at the trunk base to blend with the ground. Code collider: cylinder r 0.35, height 3 at y 1.5.

### 4.5 `dead_tree.glb` — bare leafless tree (P0)
Object **`Tree`**. Trunk 6-sided cylinder r 0.20→0.08, height 4.5, material `bark`, with 5–7 thin tapered branches (4-sided, r 0.05→0.02, length 0.9–1.6) at z 1.8–4.0 pointing up-and-out at 35–60°, two of them forked once. `snow` on branch top faces (normal rule) and a snow disc at the base. Slight lean of the trunk (bake it into the mesh, rotation stays 0). Tri ≤ 250. Code collider: same as pines.

### 4.6 `stump.glb` (P0)
Object **`Stump`**: 8-sided cylinder r 0.30, height 0.45, `bark` sides, `wood_light` top (the cut) with 2–3 flat "ring" polygons inset optional, plus a snow patch on half of the top. Tri ≤ 80. Code collider: cylinder r 0.3 h 0.5.

### 4.7 `rock_a.glb`, `rock_b.glb`, `rock_c.glb` — snow-dusted boulders (P0/P0/P1)
Object **`Rock`**: icosphere subdivision 1, vertices jittered ±10 %, **flattened to 60 % on Z**, bottom clipped at z = 0 (flat bottom, sits on the ground). Material `stone` on sides, `stone_dark` on faces with normal z < 0.1, `snow` on faces with normal z > 0.55. Sizes (X×Y×Z): `rock_a` 1.2×1.0×0.7, `rock_b` 2.2×1.8×1.2 (built from two overlapping icospheres), `rock_c` 0.6×0.5×0.35. Tri ≤ 160 each. Code colliders: spheres (a: r 0.55 at y 0.4; b: r 0.9 at y 0.6; c: r 0.3 at y 0.2).

### 4.8 `stone.glb` — stone pickup (P0)
Object **`Stone`**: jittered icosphere subdivision 1 scaled to 0.30×0.25×0.20, flat bottom, `stone` with a `snow` top face or two. Tri ≤ 40. Code: Area3D sphere r 0.45 (pickup).

### 4.9 `berry_bush.glb` (P0)
Low round bush **1.0×1.0×0.55**: object **`Bush`** = union of 3 jittered icospheres (r 0.35, 0.40, 0.30, offset ±0.2), bottom clipped at z = 0, material `bush`, `snow` on faces with normal z > 0.6. Child object **`Berries`** (parent `Bush`, pivot (0,0,0)): 10 tiny icospheres (subdiv 0 → 20 faces) r 0.045, material `berry`, scattered on the upper surface. The code hides `Berries` when harvested. Tri ≤ 400 total. Code collider: sphere r 0.5 (placement blocker only).

### 4.10 `firewood.glb` — hand-pickable wood (P0)
Object **`Firewood`**: two split logs (half-cylinders, 6 sides, r 0.10, length 0.50) lying crossed on the ground with `bark` outside, `wood_light` cut faces, a little `snow` on top. Bounding 0.55×0.55×0.22. Tri ≤ 120. Pickup Area3D r 0.45 in code.

### 4.11 `fallen_log.glb` — axe-only wood source (P0)
Object **`Log`**: 8-sided cylinder r 0.20, length **1.6 m along X** (x −0.8…+0.8), lying on the ground (axis at z 0.20), `bark` with `wood_light` end caps, `snow` on the upper faces, one short broken branch stub. Tri ≤ 120. Code collider: box 1.6×0.4×0.4 at y 0.2.

### 4.12 `campfire.glb` — unlit fire pit (P0)
Diameter **1.2 m**, height 0.35. Objects: **`Stones`** (8 jittered icospheres r 0.12–0.16 on a ring of radius 0.50, material `stone`, tops `snow`), **`Logs`** (4 cylinders r 0.07, length 0.6, 6 sides, leaning into a tepee/cross at the center, `bark` + `wood_light` ends), **`FlameAnchor`** Empty at **(0, 0, 0.18)**. The flame, light and smoke are Godot effects placed at `FlameAnchor`. Tri ≤ 400. Code collider: cylinder r 0.55 h 0.35.

### 4.13 `stone_axe.glb` (P0)
Origin at the **grip** (bottom of the handle + 0.05). Objects: **`Handle`** 6-sided cylinder r 0.025, from z −0.05 to +0.50 (material `wood`, a `cloth` wrap band z 0.00–0.10); **`Blade`** wedge 0.06 (X) × 0.20 (Y) × 0.13 (Z) of `stone_dark`, mounted at z 0.37–0.50, extending toward **−Y** (blade edge at y = −0.20, tapering to 0.02 thick at the edge), plus a small `cloth` lashing box around the junction. Total length 0.55. Tri ≤ 100. No collision. When parented to `ToolSocket` with identity transform, the handle points forward from the hand and the blade points up.

### 4.14 `torch.glb` (P0)
Origin at the bottom grip. **`Handle`** 6-sided cylinder r 0.025, z 0…0.42 material `wood`; **`Head`** 8-sided cylinder r 0.055, z 0.38…0.52 material `cloth`; **`FlameAnchor`** Empty at **(0, 0, 0.54)**. Tri ≤ 80. No collision.

### 4.15 `cabin.glb` — the hunter's house (P0)
Blue-grey clapboard house with a dark snowy gable roof, brick chimney, covered porch with railing and steps, open doorway (no door leaf), painted-on windows with trim. **Faces +Y (porch side).** Footprint (walls) **6.0 (X) × 5.0 (Y)**, porch adds 2.0 m in +Y, steps 0.8 more. Eave height 3.0, ridge **4.6**, chimney top 5.3. Origin: ground level at the center of the wall footprint (0,0,0). Tri ≤ 2500 (visual objects, excluding `Col*`).

Layout facts the code depends on: floor top at **z = 0.30** (house on a 0.30 stone foundation); doorway centered at **x = −0.9** on the front wall, 1.0 wide, 2.1 tall (z 0.30–2.40); chimney on the **−X** wall; interior clear area x −2.82…+2.82, y −2.32…+2.32, z 0.30–3.0 (wall thickness 0.18). The interior furniture is **not** part of this file (separate assets placed by code).

Visual objects (all top-level, required names in bold, pivots at (0,0,0) unless noted):

| Object | Content |
|---|---|
| **`Floor`** | Foundation skirt box x ±3.0, y ±2.5, z 0–0.30 material `stone`; interior floor slab x ±2.82, y ±2.32, z 0.20–0.30 material `wood_light` (optionally 6 plank strips with 0.01 gaps). Never hidden. |
| **`WallBack`** | Box x ±3.0, y −2.5…−2.32, z 0.30–3.0, material `cabin_wall`; horizontal clapboard grooves optional (thin `cabin_trim` strips every 0.3 m are cheap: max 6). Corner trims `cabin_trim` 0.1 wide. |
| **`WallLeft`** | Box x −3.0…−2.82, y ±2.5, z 0.30–3.0 `cabin_wall`. Child **`WindowsLeft`** (pivot (0,0,0)): pane quad 1.2 (Y) × 1.0 (Z) at x = −3.01, y −1.9…−0.7, z 1.3–2.3, material **`window`**, with a `cabin_trim` frame (4 thin boxes 0.08 wide, 0.04 proud) and one vertical + one horizontal `cabin_trim` mullion. |
| **`WallRight`** | Box x 2.82…3.0, y ±2.5, z 0.30–3.0 `cabin_wall`. No window. |
| **`WallFront`** | Three boxes at y 2.32…2.5, z 0.30–3.0: x −3.0…−1.4 (left of door), x −0.4…3.0 (right of door), and above the door x −1.4…−0.4, z 2.40–3.0. Door frame `cabin_trim` around the opening (0.1 wide). Child **`WindowsFront`**: pane 1.2 (X) × 1.0 (Z) at y = 2.51, x 0.8…2.0, z 1.3–2.3, material **`window`** + trim + mullions like `WindowsLeft`. |
| **`Roof`** | Gable: two slabs 0.15 thick from the eaves (y = ±2.9, z = 3.0) to the ridge (y = 0, z = 4.6), spanning x −3.4…3.4, material `roof` (underside/edges) with a `snow` slab 0.12 thick on top of each slope (top faces `snow`); two gable triangles closing the roof at x = ±3.0 above z = 3.0 (material `cabin_wall`, with a `cabin_trim` bargeboard). Hidden by code when the player is inside. |
| **`Chimney`** | Brick box x −3.7…−3.0, y 0.25…0.95, z 0–5.3, material `brick`, `snow` cap on top, a `stone_dark` rim at z 5.1–5.3. Hidden with the roof. |
| **`Porch`** | Deck box x ±3.0, y 2.5…4.5, z 0.20–0.30 `wood` with a `stone` skirt below (z 0–0.20); steps in front of the door: x −1.5…−0.3: upper step y 4.5…4.85 top z 0.20, lower step y 4.85…5.2 top z 0.10 (`wood`); railing: posts 0.10×0.10, z 0.30–1.3 at (±3.0, 4.5), (−1.5, 4.5), (−0.3, 4.5), (±3.0, 2.5); top rails 0.08×0.08 at z 1.2 along y = 4.5 (except the gap x −1.5…−0.3) and along x = ±3.0 (y 2.5…4.5); balusters 0.04×0.04 every 0.3 m, z 0.30–1.2 (material `cabin_trim` for all railing parts); porch roof: shed slab 0.12 thick from (y 2.5, z 3.0) to (y 4.8, z 2.5), x −3.2…3.2, `roof` + `snow` top; two support posts 0.12×0.12 at (±2.9, 4.4) from z 0.30 to the roof underside (`wood`). |
| **`DoorAnchor`** | Empty at **(−0.9, 3.2, 0.30)** (on the porch just outside the door, facing +Y like the house). Code spawns the player 2.5 m further along +Y (Godot: along the anchor's −Z). |
| **`LanternSocket`** | Empty at **(−1.6, 4.3, 2.35)** (under the porch roof beside the door). The lantern hangs from here. |

Collision objects (`-convcolonly`, top-level, boxes as x-range / y-range / z-range):

| Name | Box |
|---|---|
| `ColFoundation-convcolonly` | x ±3.0 / y ±2.5 / z 0–0.30 |
| `ColPorch-convcolonly` | x ±3.0 / y 2.5–4.5 / z 0–0.30 |
| `ColSteps-convcolonly` | **ramp prism** x −1.5…−0.3, from (y 5.3, z 0) rising to (y 4.5, z 0.30); bottom at z 0 (6 vertices: (x, 5.3, 0), (x, 4.5, 0), (x, 4.5, 0.30) for x = −1.5 and −0.3). The character walks up this ramp; the visual steps are cosmetic. |
| `ColWallBack-convcolonly` | x ±3.0 / y −2.5…−2.32 / z 0.30–3.0 |
| `ColWallLeft-convcolonly` | x −3.0…−2.82 / y ±2.5 / z 0.30–3.0 |
| `ColWallRight-convcolonly` | x 2.82…3.0 / y ±2.5 / z 0.30–3.0 |
| `ColWallFrontL-convcolonly` | x −3.0…−1.4 / y 2.32–2.5 / z 0.30–3.0 |
| `ColWallFrontR-convcolonly` | x −0.4…3.0 / y 2.32–2.5 / z 0.30–3.0 |
| `ColDoorTop-convcolonly` | x −1.4…−0.4 / y 2.32–2.5 / z 2.40–3.0 |
| `ColChimney-convcolonly` | x −3.7…−3.0 / y 0.25–0.95 / z 0–3.0 |
| `ColRailFrontL-convcolonly` | x −3.0…−1.5 / y 4.42–4.5 / z 0.30–1.3 |
| `ColRailFrontR-convcolonly` | x −0.3…3.0 / y 4.42–4.5 / z 0.30–1.3 |
| `ColRailLeft-convcolonly` | x −3.0…−2.92 / y 2.5–4.5 / z 0.30–1.3 |
| `ColRailRight-convcolonly` | x 2.92…3.0 / y 2.5–4.5 / z 0.30–1.3 |

No roof collision (the player cannot get up there). Windows are painted on the walls — no openings except the doorway.

### 4.16 Furniture set (P0: `wood_stove`, `cabinet`; P1: `bed`, `desk`, `chair`, `shelf`, `clock`)
All face **+Y** (the side a person uses). Origins per §2.2. No embedded collision (code uses boxes with the sizes below).

| File | Object names | Spec | Tri |
|---|---|---|---|
| `wood_stove.glb` | **`Body`**, **`Door`**, **`Pipe`**, **`StoveAnchor`**, `PipeTop` | Cast-iron box stove 0.60×0.60, body z 0.15–0.85 on four 0.06 legs (z 0–0.15), top plate 0.66×0.66×0.04 at z 0.85, all `iron`; **`Door`** = separate quad 0.30×0.30 on the front face (y = 0.301, z 0.30–0.60) material **`ember`** (the code makes it glow when lit) with an `iron` handle box; **`Pipe`** 8-sided cylinder r 0.08 from z 0.89 to 2.70 at (0, −0.15) `iron` with a 0.10 collar at z 0.89; **`StoveAnchor`** Empty at (0, 0.35, 0.45) (light/embers), `PipeTop` Empty at (0, −0.15, 2.70). | ≤ 250 |
| `cabinet.glb` | **`Cabinet`** | Tall storage cabinet 0.90×0.50×1.80, `wood` carcass, two `wood_dark` door panels (0.40×0.02×1.5 each at y = 0.251), `iron` handles, `cabin_trim` top cornice 0.96×0.56×0.05. | ≤ 120 |
| `bed.glb` | **`Bed`** | 1.00 (X) × 2.00 (Y) × 0.50 frame `wood` (legs + rails), mattress `cloth` z 0.35–0.50, blanket `hat` (navy) covering y −0.9…+0.6, pillow `paper` 0.5×0.3×0.12 near the headboard; headboard `wood` at y −1.0…−0.94, z 0–0.95 (headboard is at −Y = the wall side). | ≤ 150 |
| `desk.glb` | **`Desk`** | 1.40 (X) × 0.60 (Y) × 0.75, top slab 0.05 `wood`, four legs, a `paper` sheet quad 0.3×0.2 at z 0.751, a small `iron` mug cylinder r 0.04 h 0.09. Back edge at y = −0.30 (wall side). | ≤ 150 |
| `chair.glb` | **`Chair`** | 0.45 × 0.45, seat at z 0.45 (0.04 thick), four legs, backrest 0.45 wide up to z 0.90 at y = −0.2 (back side −Y), `wood`. | ≤ 120 |
| `shelf.glb` | **`Shelf`**, `Jars` | Wall shelf: origin at the back-bottom center; board x ±0.45, y 0…0.25, z 0…0.05 `wood`, two `wood_dark` brackets; child `Jars`: three 8-sided cylinders r 0.06 h 0.14 on the board at x −0.25, 0, 0.25 with materials `can_red`, `can_blue`, `paper` and `iron` lids. | ≤ 250 |
| `clock.glb` | **`Clock`**, **`HourHand`**, **`MinuteHand`** | Wall clock: origin at the back center; body 12-sided cylinder r 0.18, axis along Y, y 0…0.06, `wood` rim; face disc r 0.15 `paper` at y = 0.061; four small `iron` tick marks. **`HourHand`**: box 0.02 (X) × 0.01 (Y) × 0.09 (Z) extending from the center toward **+Z** (12 o'clock), pivot (0, 0.07, 0), material `iron`; **`MinuteHand`**: 0.015×0.01×0.13, pivot (0, 0.075, 0). The code rotates the hands around the face normal. | ≤ 120 |

### 4.17 `a_frame_cabin.glb` — the fisher's cabin (P1)
Decorative closed A-frame, faces **+Y**. Footprint **6.0 (X) × 7.0 (Y)**, ridge along Y at **z 6.0**, roof slopes from the ground at x = ±3.0 to the ridge. Objects: **`Body`** (two roof slabs 0.2 thick `roof` with `snow` slabs on top; back triangle wall `wood_dark`), **`Front`** (front triangle wall `wood` with `wood_dark` vertical planks, a door quad 0.9×2.0 `wood_dark` at x 0.6, a `cabin_trim` frame; child **`WindowsFront`** = one pane 1.0×1.0 at z 2.5–3.5, x −1.2…−0.2, material **`window`**), **`Deck`** (x ±2.0, y 3.5…5.0, z 0–0.25, `wood`, two `wood` posts and a rail). Collision: `ColBody-convcolonly` triangular prism vertices (±3.0, ±3.5, 0) and (0, ±3.5, 6.0); `ColDeck-convcolonly` x ±2.0 / y 3.5–5.0 / z 0–0.25. Tri ≤ 600.

### 4.18 `pickup_truck.glb` — abandoned truck (P1)
Olive-green pickup, snow on hood/roof/bed rim. Faces **+Y** (hood forward). Size **2.0 (X) × 5.0 (Y) × 1.95 (Z)**, origin at ground under the center. Objects: **`Body`** (hood y 1.0…2.5 z 0.6–1.3; cab y −0.2…1.0 z 0.6–2.0 with `window` quads on the windshield/side/rear (dark-ish, use the `window` material anyway); bed y −2.5…−0.2: floor at z 0.8, side walls 0.08 thick up to z 1.3, open top and closed tailgate; bumpers `iron`; material `truck_paint`), **`Wheels`** (four 12-sided cylinders r 0.42, width 0.25, axis along X at (±0.95, ±1.6, 0.42), `iron` with a `stone` hub), **`Snow`** (slabs 0.10 thick on the hood, cab roof and bed rim, `snow`), **`BedAnchor`** Empty at (0, −1.35, 1.0). Collision: `ColChassis-convcolonly` x ±1.0 / y ±2.5 / z 0.3–1.3; `ColCab-convcolonly` x ±0.95 / y −0.2…1.0 / z 1.3–2.0. Tri ≤ 900.

### 4.19 `signpost.glb` (P1)
Wooden post 0.12×0.12, z 0–2.2, `wood`, snow cap. Two **arrow boards** pointing to **+X** (pointed end at +X, text face toward **+Y**): **`BoardTop`** (pivot (0,0,1.84)): board x −0.25…+0.85 (pointed tip at 0.85, base end at −0.25), y 0.06…0.12, z 1.70–1.98, `wood_light` with a `wood_dark` 0.02 border and `snow` on top; **`BoardBottom`** (pivot (0,0,1.44)): same board at z 1.30–1.58. Empties for the text (the code adds `Label3D` children with identity transforms): **`TextTop`** at world (0.28, 0.125, 1.84), **child of `BoardTop`**, and **`TextBottom`** at world (0.28, 0.125, 1.44), **child of `BoardBottom`** (so the code can yaw each board with its text), both with **rotation_euler = (0, 0, 180°)** so that their local +Z (Godot) faces the board's front (+Y Blender = −Z Godot) and text reads left-to-right. Post object **`Post`** (top-level; the boards are top-level too, not children of the post). Tri ≤ 150. No collision.

### 4.20 `fence.glb` (P1)
One segment **2.0 m along X**, origin at the ground center. Object **`Fence`**: two posts 0.12×0.12×1.1 at x = ±0.94, two rails 2.0×0.06×0.12 at z 0.40–0.52 and 0.80–0.92, material `wood`, `snow` strips 0.03 thick on top of the rails and posts. Tri ≤ 120. Code collider: box 2.0×1.0×0.15.

### 4.21 `lantern.glb` (P1)
Origin at the **hook** (top). Object **`Lantern`**: hook ring/box 0.04 at z −0.06…0; cap 0.20×0.20×0.04 at z −0.10…−0.06 `iron`; glass 0.16×0.16 box z −0.36…−0.10 material **`window`**; base 0.20×0.20×0.04 at z −0.40…−0.36 `iron`; four `iron` corner rods. **`LightAnchor`** Empty at (0, 0, −0.23). Tri ≤ 120. No collision.

### 4.22 P2: `tent.glb`, `storage_box.glb`
`tent`: triangular prism 2.4 (X) × 2.6 (Y) × 1.7 (Z), open at +Y, `cloth` with `snow` on the slopes, `wood` poles; object `Tent`; collision `ColBack-convcolonly` (the back wall only, x ±1.2 / y −1.3…−1.2 / z 0–1.7). `storage_box`: wooden crate 0.8×0.6×0.6, object `Box`, `wood` + `wood_dark` edges, no embedded collision.

---

## 5. Anchor summary (what the code looks up)

| Asset | Required node names (mesh or empty) |
|---|---|
| player | `Hips`, `Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `ToolSocket`, `BreathAnchor` |
| wolf, deer | `Body`, `Head`, `Muzzle`, `Tail`, `LegFL`, `LegFR`, `LegBL`, `LegBR` |
| pine_a/b/c, dead_tree | `Tree` |
| stump / rock_* / stone / firewood / fallen_log | `Stump` / `Rock` / `Stone` / `Firewood` / `Log` |
| berry_bush | `Bush`, `Berries` |
| campfire | `Stones`, `Logs`, `FlameAnchor` |
| stone_axe / torch | `Handle`, `Blade` / `Handle`, `Head`, `FlameAnchor` |
| cabin | `Floor`, `WallFront`, `WindowsFront`, `WallBack`, `WallLeft`, `WindowsLeft`, `WallRight`, `Roof`, `Chimney`, `Porch`, `DoorAnchor`, `LanternSocket`, `Col*` bodies |
| wood_stove | `Body`, `Door`, `Pipe`, `StoveAnchor` |
| cabinet / bed / desk / chair | `Cabinet` / `Bed` / `Desk` / `Chair` |
| shelf / clock | `Shelf` / `Clock`, `HourHand`, `MinuteHand` |
| a_frame_cabin | `Body`, `Front`, `WindowsFront`, `Deck`, `Col*` |
| pickup_truck | `Body`, `Wheels`, `Snow`, `BedAnchor`, `Col*` |
| signpost | `Post`, `BoardTop`, `BoardBottom`, `TextTop`, `TextBottom` |
| fence / lantern | `Fence` / `Lantern`, `LightAnchor` |

Materials the code searches by name: `window` (glow at night), `ember` (stove door glow). Everything else is used as exported.

---

## 6. Verification checklist (mandatory before you finish)

`verify_assets.py` must implement and pass all of these; run it after `build_all.py` and paste its final summary in your report.

1. **Files exist**: every P0 asset has both `blender/sources/<name>.blend` and `assets/models/<name>.glb`; the `.glb` is > 1 KB and starts with the bytes `glTF`.
2. **Re-import round trip**: for each `.glb`, `bpy.ops.wm.read_factory_settings(use_empty=True)` then `bpy.ops.import_scene.gltf(filepath=...)`. (The importer converts back to Z-up, so Blender-space checks below apply directly.)
3. **Names**: the set of object names contains every required name of §5 for that asset; no name contains `.` (no `.001`); `Col*` objects end with `-convcolonly` and nothing else uses a `-` suffix.
4. **Hierarchy**: `ToolSocket.parent.name == "ArmR"`, `BreathAnchor.parent.name == "Head"`, `Head.parent.name == "Torso"`, `ArmL/ArmR.parent.name == "Torso"`, `Torso/LegL/LegR.parent.name == "Hips"`; wolf/deer `Head/Tail/Leg*.parent.name == "Body"`, `Muzzle.parent.name == "Head"`; `Berries.parent.name == "Bush"`; `WindowsFront.parent.name == "WallFront"`, `WindowsLeft.parent.name == "WallLeft"`; `TextTop.parent.name == "BoardTop"`, `TextBottom.parent.name == "BoardBottom"`; `Jars.parent.name == "Shelf"`; `Col*` objects have no parent.
5. **Pivots**: `matrix_world.translation` of each named part is within **±0.03 m** of the world pivot in §4 (e.g. player `Hips` (0,0,0.80), `ArmR` (0.36,0,1.32), `ToolSocket` (0.36,0.05,0.80), wolf `Muzzle` (0,0.93,0.58), campfire `FlameAnchor` (0,0,0.18), cabin `DoorAnchor` (−0.9,3.2,0.30)).
6. **Forward axis**: after re-import, `Muzzle` (wolf, deer) and `BreathAnchor` (player) have **world y > 0**; the cabin's `DoorAnchor` has y > 0; the stove's `StoveAnchor` has y > 0; the signpost's `TextTop` has y > 0 and the tip of `BoardTop` (max x of its vertices) is > 0.8. This proves the +Y-forward convention (→ Godot −Z).
7. **Dimensions**: the combined bounding box of the visual objects (excluding `Col*`) matches the spec within ±10 % (player height 1.80, wolf length 1.85 incl. tail / back height 0.75, pine_a 7.0, cabin ≈ 7.1 (X, chimney to roof overhang) × 8.2 (Y, roof overhang to steps) × 5.3, truck 2.0×5.0×1.95, etc.). Minimum z of every asset is 0 (±0.02) except tools (origin at the grip, min z ≈ −0.05) and the lantern (max z = 0, min z = −0.40).
8. **Transforms**: every object has `rotation_euler == (0,0,0)` and `scale == (1,1,1)` except `ToolSocket` (−90°,0,0) and `TextTop/TextBottom` (0,0,180°).
9. **Shading**: no polygon has `use_smooth == True`; no mesh has UV layers or color attributes; no image datablocks exist.
10. **Materials**: every material name is in the palette table (§3); every visual mesh has at least one material slot and every polygon's `material_index` is valid; `cabin` uses `window` on `WindowsFront`/`WindowsLeft`; `wood_stove.Door` uses `ember`; `Col*` objects may have no material.
11. **Triangle budget**: per asset ≤ budget × 1.2; total ≤ 12 000.
12. **Collision boxes**: each `Col*` mesh is a closed convex box or prism (6 or 8 vertices, 6 or 5 faces) whose bounds match the table in §4.15/4.17/4.18 within ±0.02 m.
13. **Godot import check** (recommended, catches importer surprises): create a throwaway project `/tmp/glbcheck/project.godot` containing just `config_version=5` and `[application]\nconfig/name="glbcheck"`, copy the `.glb` files into `/tmp/glbcheck/models/`, run `godot --headless --path /tmp/glbcheck --import`, then run the script below and check that every required name appears, that `Col*` nodes are `StaticBody3D`, and that no `ERROR` lines are printed:
    ```gdscript
    # /tmp/glbcheck/inspect.gd  —  run: godot --headless --path /tmp/glbcheck -s inspect.gd
    extends SceneTree
    func _initialize() -> void:
        for f in DirAccess.get_files_at("res://models"):
            if not f.ends_with(".glb"): continue
            var scene := load("res://models/" + f) as PackedScene
            if scene == null: print("ERROR cannot load ", f); continue
            var inst := scene.instantiate()
            print("== ", f); _dump(inst, 1); inst.free()
        quit()
    func _dump(n: Node, depth: int) -> void:
        var info := n.name + " (" + n.get_class() + ")"
        if n is MeshInstance3D and n.mesh:
            var names := []
            for i in n.mesh.get_surface_count(): names.append(n.mesh.surface_get_material(i).resource_name if n.mesh.surface_get_material(i) else "null")
            info += " aabb=" + str(n.get_aabb()) + " mats=" + str(names)
        elif n is Node3D: info += " pos=" + str((n as Node3D).position)
        print("  ".repeat(depth), info)
        for c in n.get_children(): _dump(c, depth + 1)
    ```
    (The Godot project of the game may not exist yet when you run this — that is why the throwaway project exists.)
14. **Report**: `verify_assets.py` prints one line per asset: `OK name  tris=NNN  dims=(x,y,z)  objects=[...]` or `FAIL name: reason`, and ends with `ALL OK` or `N FAILURES`. Do not report the job done while any P0 asset fails.

---

## 7. Deliverables checklist

- [ ] `blender/lib/palette.py` (materials), `blender/lib/lowpoly.py` (box/cylinder/cone-with-ring/icosphere-jitter/flat-shade/snow-by-normal/set-pivot/parent helpers), `blender/lib/export.py` (save + export + reimport helpers)
- [ ] `blender/build_*.py` per the table in §1, each runnable standalone
- [ ] `blender/build_all.py` and `blender/verify_assets.py`
- [ ] `blender/sources/*.blend` for every exported asset
- [ ] `assets/models/*.glb`: all **P0**, then P1, then P2
- [ ] `verify_assets.py` output ending in `ALL OK` (paste it in your final report), plus the Godot `inspect.gd` dump for `player`, `wolf`, `cabin`, `campfire`
- [ ] A short `blender/README.md` (how to rebuild, how to verify) — the only documentation file you create
