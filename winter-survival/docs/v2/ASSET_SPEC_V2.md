# VENTISCA v2 — Especificación de assets 3D (contrato para los agentes Opus)

> Blender **5.0.1** como módulo Python (`import bpy`), scripts `bpy`/`bmesh` procedurales, **sin texturas, sin descargas** (salvo CC0 documentado en `LICENSES.md`). Salida al proyecto Godot `winter-survival/`. El agente de código trabaja en paralelo desde `ARQUITECTURA_V2.md` y nunca ve tus scripts: **solo lo escrito aquí está garantizado**. Donde este documento da un número o un nombre, es un requisito.
>
> Sustituye a `docs/ASSET_SPEC.md` (slice). Las diferencias importantes con el slice están marcadas con **[CAMBIO]**. Resultados verificados en `prototypes/animpoc/` (rig, skin, retarget, ragdoll, draw calls).

---

## 1. Pipeline y carpetas

```
blender/
  lib/  palette.py   ← [CAMBIO] paleta → color de vértice (COLOR_0) + material único palette_vcol + excepciones
        lowpoly.py   ← MeshBuilder (boxes, lofts, cilindros, icosferas jitter, nieve por normal, pivotes); [CAMBIO] FRONT = −Y
        export.py    ← save + export glTF (§2.8) + reimport; [CAMBIO] opciones de armature/acciones/COLOR_0
        rig.py       ← [NUEVO] esqueleto humanoide/cuadrúpedo, sockets, skin rígido (del PoC build_humanoid.py)
        anim.py      ← [NUEVO] ActionWriter, generador de marcha (IK analítica), poses clave, utilidades de ciclo
        kit.py       ← [NUEVO] piezas del kit modular, ensamblado de plantillas JSON, fusión por grupos de corte
        vehicle.py   ← [NUEVO] carrocerías, ruedas, anclas, variantes de restos
  chars/build_<char>.py        → assets/models/chars/<char>.glb          (malla + esqueleto, SIN animaciones)
  zombies/build_zombie.py      → assets/models/zombies/zombie_<kind>_<variant>.glb
  animals/build_<animal>.py    → assets/models/animals/<animal>.glb
  anims/build_<set>.py         → assets/models/anims/humanoid_<set>.glb  (solo armature + acciones)
  kits/build_kit_<style>.py    → piezas (solo para ensamblar; no se exportan sueltas salvo road/props)
  kits/build_buildings.py      → assets/models/buildings/<style>/<template>.glb  (una por plantilla y estilo)
  roads/build_roads.py         → assets/models/props/road_*.glb
  vehicles/build_<vehicle>.py  → assets/models/vehicles/<vehicle>.glb (+ _wreck_*)
  weapons/build_weapons.py     → assets/models/weapons/<weapon>.glb
  props/build_<family>.py      → assets/models/props/<prop>.glb
  vegetation/build_<family>.py → assets/models/vegetation/<name>.glb
  poi/build_<poi>.py           → assets/models/poi/<poi>.glb
  build_all.py                 ← construye todo y ejecuta los verificadores
  verify_assets.py             ← props/vegetación/POIs (contrato §2, §13–16)
  verify_chars.py              ← personajes, zombis, animales, animaciones (§4–7)
  verify_kits.py               ← edificios y carreteras (§8–10)
  verify_vehicles.py           ← vehículos (§11) · verify_weapons.py (§12)
  sources/<asset>.blend        ← uno por .glb, guardado antes de exportar
```

Cada script arranca de una escena vacía (`bpy.ops.wm.read_factory_settings(use_empty=True)`), construye, guarda el `.blend`, exporta. Ningún objeto residual (cámaras, luces, cubo). Cada `build_*.py` es ejecutable por separado; `build_all.py` ejecuta todo (≈ segundos) y termina con `ALL OK` o `N FAILURES`.

Godot importa con plantillas `.import` en `assets/import_templates/` que el agente de código copia junto a cada `.glb` nuevo (o que tú escribes con `lib/export.py::write_import(path, kind)` — el PoC lo hace así). Tras exportar: `godot --headless --path winter-survival --import` y `godot --headless --path . -s tests/inspect_models.gd`.

---

## 2. Convenciones globales

### 2.1 Unidades y ejes

- 1 unidad Blender = 1 m; Blender Z‑up; Godot Y‑up. Exportación `export_yup=True`: **Blender (x, y, z) → Godot (x, z, −y)**.
- **[CAMBIO] Frente = −Y Blender = +Z Godot = `Vector3.MODEL_FRONT`.** Todo asset con frente (personajes, zombis, animales, vehículos, armas, edificios, muebles, señales) mira a **−Y** en Blender. En la vista *Front* de Blender (numpad 1) ves la **cara** del modelo. El código usa `basis.z` como frente y `look_at(target, UP, true)`.
- **Derecha del personaje = −X Blender** (izquierda = +X), consecuencia del punto anterior (igual que `SkeletonProfileHumanoid`: `LeftUpperLeg` en +X).
- Arriba = +Z Blender; pies/base en z = 0.

### 2.2 Origen (pivote)

- Cosas de pie (personajes, árboles, rocas, edificios, muebles, vehículos, props): centro de la huella a z = 0.
- Armas y herramientas: **centro de la empuñadura principal**; mango a lo largo de **+Z Blender**, extremo útil (filo, boca, punta) hacia **−Y Blender** (§12).
- Cosas colgantes (farol): en el gancho. Cosas de pared (estante, reloj): en el punto de contacto con la pared, centrado; sobresalen hacia **−Y**.
- Piezas animadas rígidas (animales hasta M9b, puertas, ruedas): origen en su eje de giro.

### 2.3 Transformaciones y jerarquía

Todo objeto exportado con rotación (0,0,0) y escala (1,1,1); solo `location` puede ser ≠ 0. Excepciones: empties de socket/ancla pueden llevar rotación cuando se indica. Parentesco con `matrix_parent_inverse = Identity`. Las posiciones de este documento son coordenadas de **mundo Blender**.

### 2.4 Nombres

ASCII `[A-Za-z0-9_]`, exactos y sensibles a mayúsculas; nunca `.001`. Sufijos de importación permitidos: `-convcolonly` (caja convexa) y `-colonly` (trimesh) solo en objetos `Col*`. Prohibidos: `-vehicle`, `-wheel`, `-rigid`, `-navmesh`, `-noimp`, `-col`. Acciones: `Set_Accion[_Variante][-loop]` (§6). Materiales: solo los de §3.

### 2.5 Aspecto: low‑poly, flat shading, sin texturas

- Todo polígono `use_smooth = False`. Sin UV, sin imágenes, sin subdivisión. Siluetas: cajas, cilindros/conos de 6–12 lados, icosferas subdiv 1 con jitter ±8 %.
- **[CAMBIO] El color va en el atributo de color de vértice `Col` (exportado como `COLOR_0`)**, por esquina (`corner`), en **sRGB convertido a lineal**; **un solo material `palette_vcol`** por malla (Principled, Base Color blanco, roughness 0.9, metallic 0, sin emisión; el exportador escribe `KHR_materials` + `COLOR_0`). Para pintar: `palette.paint(faces, "cabin_wall")` escribe el color en las esquinas de esas caras.
- **Excepciones con material propio** (segunda/tercera superficie): `window` (cristales que el código hace brillar), `glass` (cristal de vehículo), `ember` (puerta de estufa), `ice_clear` (hielo del lago), `blood` (opcional para parches separados), `emissive_lamp` (tubos de farola). Nada más.
- **Nieve**: caras con normal z > 0.55 pintadas `snow` en árboles, rocas, tejados, vehículos, vallas, señales, troncos, arbustos (como en el slice) + losas explícitas donde se pide. La nieve dinámica del clima la añade el shader del juego por normal: no hace falta modelarla en props pequeños.
- Ningún asset lleva más de **2 superficies** (`palette_vcol` + 1 excepción) salvo edificios (por grupo de corte) y vehículos (`palette_vcol` + `glass` + `emissive_lamp`).

### 2.6 Poligonaje (§14)

### 2.7 Colisión

- Por defecto: el código crea formas primitivas (con las dimensiones de este documento; tu malla debe encajar ±10 %).
- Edificios, POIs, vehículos y props grandes embeben colisión: cajas convexas `Col<Nombre>-convcolonly` (6–8 vértices) para muros/forjados/rampas; una malla `Col<Grupo>-colonly` (trimesh simplificado) solo para geometría estática irregular (escaleras exteriores, ruinas). Objetos `Col*` de **primer nivel**, nunca hijos de visuales, visibles al exportar, sin material.
- **[CAMBIO] Vehículos**: sus `ColChassis`/`ColCabin` van **sin sufijo** (el código crea las formas en el `RigidBody3D`); ver §11.

### 2.8 Exportación (`lib/export.py`)

```python
bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_yup=True,
    export_apply=(not has_armature),                       # con Armature NO aplicar modificadores
    export_animations=has_actions, export_animation_mode='ACTIONS',
    export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=True,
    export_anim_single_armature=True, export_reset_pose_bones=True, export_rest_position_armature=True,
    export_def_bones=False,                                  # conserva huesos-socket no deformantes
    export_leaf_bone=False, export_skins=has_armature, export_morph=False,
    export_vertex_color='MATERIAL', export_all_vertex_colors=False,   # un solo COLOR_0
    export_materials='EXPORT', export_image_format='NONE', export_texcoords=False, export_normals=True,
    export_cameras=False, export_lights=False, export_extras=True,   # extras: metadatos (surface, group) leídos por el código
    use_selection=False, use_visible=False, use_active_collection=False)
```

Si una clave falla (`TypeError`), quitarla y seguir. Guardar el `.blend` antes de exportar. `export_extras=True` permite adjuntar `obj["surface"] = "asphalt"` o `obj["cut_group"] = "Walls0_N"` como *custom properties* (el importador las expone como metadatos).

### 2.9 Importación (para tu información)

| Tipo | Importador | Opciones clave (plantilla) |
|---|---|---|
| props/vegetación/edificios/vehículos/armas | `scene` | por defecto; `meshes/generate_lods=true` (inocuo); materiales embebidos; `nodes/use_node_type_suffixes=true` |
| `chars/*.glb`, `zombies/*.glb` | `scene` | `animation/import=false`; retarget: `retarget/bone_map=res://assets/rig/humanoid_bonemap.tres`, `bone_renamer/unique_node/make_unique=true`, `skeleton_name="GeneralSkeleton"`, `rest_fixer/apply_node_transforms=true`, `rest_fixer/retarget_method=1` (Overwrite Axis), `rest_fixer/normalize_position_tracks=true`, `remove_tracks/unimportant_positions=true`, **`remove_tracks/except_bone_transform=false`** (bug #123782), `remove_tracks/unmapped_bones=0` |
| `anims/humanoid_*.glb` | `animation_library` | `animation/fps=30`, `remove_immutable_tracks=true`, `import_rest_as_RESET=true`, mismo retarget |

`Assets.spawn_model` sustituye el material `palette_vcol` por el `ShaderMaterial` compartido del juego; las excepciones se mantienen. Nota (verificado en M0): el importador glTF de Godot elimina el sufijo heredado `_vcol`, así que el `StandardMaterial3D` importado se llama `palette` (albedo blanco, `vertex_color_use_as_albedo`); el código y `tests/inspect_models.gd` reconocen ambos nombres. En el `.glb` el material sigue llamándose `palette_vcol`.

---

## 3. Paleta (`lib/palette.py`)

Nombre → sRGB. Usa solo estos nombres (el verificador falla con otros). Los del slice se conservan; los nuevos están marcados con ★.

| Nombre | Hex | Nombre | Hex | Nombre | Hex |
|---|---|---|---|---|---|
| `snow` | `#F1F5FA` | `snow_shadow` | `#B9CBE3` | `ice` | `#BFE3F0` |
| `pine_dark` | `#2F5D3A` | `pine_light` | `#4B8A55` | `bark` | `#5B3F2E` |
| `wood` | `#8B6543` | `wood_light` | `#C7A16B` | `wood_dark` | `#4A3426` |
| `stone` | `#7C8592` | `stone_dark` | `#5A616B` | `brick` | `#8E5A4A` |
| `iron` | `#2B2E33` | `cabin_wall` | `#5D7FA6` | `cabin_trim` | `#DDE6F0` |
| `roof` | `#33383F` | `window` (mat.) | `#9CC4DD` | `truck_paint` | `#5B6B3F` |
| `bush` | `#3E6B45` | `berry` | `#D9403D` | `ember` (mat.) | `#E63B12` |
| `jacket` | `#B03A2E` | `hat` | `#2E4A7A` | `scarf` | `#E8B04B` |
| `skin` | `#F1C9A5` | `boots` | `#2A2320` | `wolf_fur` | `#6E7378` |
| `wolf_belly` | `#A9AEB2` | `eyes` | `#F5D142` | `eyes_dark` | `#1E1E24` |
| `deer_fur` | `#8A6A48` | `deer_belly` | `#C9B79C` | `cloth` | `#C9B79C` |
| `paper` | `#EDE6D6` | `can_red` | `#C23B3B` | `can_blue` | `#3B6BC2` |
| ★ `jacket_blue` | `#2F5C9E` | ★ `jacket_green` | `#3D7A4E` | ★ `jacket_mustard` | `#C9952B` |
| ★ `skin_dark` | `#8D5B3C` | ★ `skin_zombie` | `#9AA48C` | ★ `skin_frozen` | `#C7D9E6` |
| ★ `blood` | `#8B1E1E` | ★ `blood_dry` | `#6B1F1F` | ★ `gore` | `#A33A3A` |
| ★ `cloth_gray` | `#6E7075` | ★ `cloth_dark` | `#3A3C42` | ★ `cloth_white` | `#E9ECEF` |
| ★ `denim` | `#41598A` | ★ `police_blue` | `#243B6B` | ★ `military_green` | `#4F5A3C` |
| ★ `hospital_green` | `#7FB9A6` | ★ `hivis_orange` | `#F28C28` | ★ `rust` | `#8A4A2B` |
| ★ `asphalt` | `#3E4248` | ★ `asphalt_line` | `#D9D2B0` | ★ `concrete` | `#9EA3A8` |
| ★ `concrete_dark` | `#6F747A` | ★ `brick_dark` | `#6E4438` | ★ `plaster` | `#D8CFC0` |
| ★ `metal_sheet` | `#7A8590` | ★ `metal_blue` | `#4D6B8A` | ★ `paint_red` | `#A83A32` |
| ★ `paint_white` | `#E6E9EC` | ★ `paint_yellow` | `#E0B93A` | ★ `paint_black` | `#1C1E22` |
| ★ `tire` | `#1F2124` | ★ `chrome` | `#C4CBD2` | ★ `glass` (mat.) | `#7FA6C2` |
| ★ `ice_clear` (mat.) | `#A9D8EA` | ★ `ice_thin` | `#7FB3CC` | ★ `emissive_lamp` (mat.) | `#FFE2A8` |
| ★ `gun_metal` | `#3A3E45` | ★ `gun_wood` | `#6B4A2E` | ★ `brass` | `#B8963E` |
| ★ `plastic_black` | `#25272B` | ★ `plastic_red` | `#C0392B` | ★ `plastic_blue` | `#2E86C1` |
| ★ `hay` | `#C9B26B` | ★ `dirt` | `#5A4A3A` | ★ `moss` | `#5C7A4A` |

(mat.) = también es un material aparte (excepción). Zombis: paletas desaturadas construidas por `palette.zombify(name)` (mezcla 40 % hacia `cloth_gray`) — se registran automáticamente como `z_<name>`.

---

## 4. Esqueleto humanoide (jugador, zombis, NPC)

### 4.1 Huesos (nombres exactos de `SkeletonProfileHumanoid`; sin espacios)

| Hueso | Padre | Obligatorio en el perfil | Uso |
|---|---|---|---|
| `Root` | — | no | En el suelo, sin claves (in‑place) |
| `Hips` | Root | **sí** | Única pista de posición (bote) |
| `Spine` | Hips | **sí** | |
| `Chest` | Spine | no | Torsión de apuntado (`AimModifier3D`) |
| `Neck` | Chest | no | |
| `Head` | Neck | **sí** | `LookAtModifier3D` |
| `LeftShoulder`, `RightShoulder` | Chest | **sí** | Clavículas |
| `LeftUpperArm`, `LeftLowerArm`, `LeftHand` (y `Right*`) | cadena | **sí** | `TwoBoneIK3D` mano de apoyo |
| `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot` (y `Right*`) | Hips → cadena | **sí** | Generador de marcha |
| `LeftToes`, `RightToes` | Foot | no | Despegue |
| **Sockets** (no deformantes, no mapeados): `RightHandSocket` (hijo de `RightHand`), `LeftHandSocket` (`LeftHand`), `BackSocket` (`Chest`), `HipSocketR` (`Hips`), `HeadSocket` (`Head`) | | — | Armas, linterna, mochila, casco |

Total: **22 huesos deformantes + 5 sockets = 27**. `use_deform = False` en `Root` y sockets. Pose de reposo **T** (brazos horizontales, rodillas y codos rectos), mirando a **−Y**. Roll determinista: `align_roll((0, −1, 0))` en huesos verticales, `align_roll((0, 0, 1))` en horizontales (todos los humanoides comparten orientación de reposo → las rotaciones son intercambiables).

### 4.2 Proporciones (`rig.joints(params)`; jugador de referencia 1.80 m)

| Parámetro | Valor | Parámetro | Valor |
|---|---|---|---|
| altura total (con gorro) | 1.80 | `Hips` (z) | 0.92 |
| `Spine` | 1.02 | `Chest` | 1.22 |
| `Neck` | 1.48 | `Head` | 1.56 (cráneo hasta 1.74) |
| hombros (x) | ±0.20, z 1.44 | `UpperArm` / `LowerArm` / `Hand` | 0.28 / 0.26 / 0.08 |
| caderas (x) | ±0.11 | `UpperLeg` / `LowerLeg` | 0.42 / 0.41 |
| tobillo (z) | 0.09 | `Toes` | +0.12 hacia −Y |
| `RightHandSocket` | centro del puño: eje **Y del hueso = eje del mango** (hacia el pulgar), **Z = a lo largo del antebrazo** (hacia los nudillos) | `BackSocket` | z 1.30, y +0.14 (espalda) |
| `HipSocketR` | x −0.16, z 0.92 | `HeadSocket` | z 1.62 |

Variantes por parámetros: `height`, `width`, `leg_len`, `torso_len`, `arm_len`, `hunch`, `lean`. Zombis y NPC **comparten nombres, jerarquía y orientación de reposo**; solo cambian proporciones (el retarget con *Normalize Position Tracks* absorbe la altura: verificado, tobillo 0.087 m en ambos).

### 4.3 Skinning

- **Rígido por pieza**: cada pieza del `MeshBuilder` se construye "para" un hueso; se fusionan en una malla `Body` y cada vértice va 100 % a su grupo. Juntas ocultas por solapamiento de volúmenes (manga sobre antebrazo, puño de bota, cuello de abrigo).
- Pesos mezclados **solo** en ropa continua larga (abrigo militar, bata): anillos con `smoothstep` calculados por script.
- **Prohibido** `parent_set(type='ARMATURE_AUTO')` (10 % de vértices sin peso en nuestras mallas).
- Piezas de ropa/props que se activan por el código (§5.4) son **mallas hijas separadas** ligadas al mismo armature (`Outfit_<id>`), exportadas en el mismo `.glb` del personaje, todas visibles al exportar; el código las oculta/muestra por nombre.

### 4.4 Estructura exportada de un personaje

```
<char>.glb
├─ Armature (Skeleton3D → renombrado GeneralSkeleton al importar)
│   ├─ Body            malla con skin, 1 superficie palette_vcol (+ excepciones si las hay)
│   ├─ Outfit_<id> …   piezas de ropa opcionales con skin (jugador: coat, parka, military_coat, hoodie, vest; zombis: según atuendo)
│   └─ Head_<id> …     variantes de cabeza/pelo/gorro (opcional)
└─ (sin animaciones)
```

---

## 5. Personajes

### 5.1 `chars/survivor.glb` (jugador) — M1

Figura abrigada: chaqueta acolchada, gorro con pompón, bufanda, manoplas, pantalón, botas. 1.80 m, ≤ 1 500 tris (Body ≈ 800 + outfits). **4 variantes de paleta** exportadas como `survivor_red.glb`, `survivor_blue.glb`, `survivor_green.glb`, `survivor_mustard.glb` (chaqueta `jacket`/`jacket_blue`/`jacket_green`/`jacket_mustard`, gorro en el color complementario). Cabeza sin cara detallada: dos quads de ojos (`eyes_dark`). Outfits: `Outfit_coat`, `Outfit_parka`, `Outfit_military_coat`, `Outfit_hoodie`, `Outfit_vest`, `Outfit_hat_wool`, `Outfit_hat_fur`, `Outfit_helmet`, `Outfit_gloves`, `Outfit_boots_winter`, `Outfit_boots_military`, `Outfit_backpack_s/m/l` (M8; en M1 basta `Body`).

### 5.2 Zombis (`zombies/zombie_<kind>_<v>.glb`) — M2 (caminante), M4 (lote 1), M9b (lote 2)

Receta: `Cuerpo(params) + Ropa(capa) + Paleta(z_*) + Props(sockets) + Daños(flags)`.

| Tipo (`kind`) | Silueta a 20 m | Receta | Variantes | Hito |
|---|---|---|---|---|
| `walker` | humano encorvado | `hunch 25°`, brazos a media altura; 3 cuerpos (delgado/medio/corpulento) × 8 atuendos (abrigo, sudadera, camisa, chaqueta de nieve, policía, bata, mono, cazador) × 2 paletas | 48 (entregar 8 en M2, 24 en M4, 48 en M9a) | M2 |
| `runner` | delgado, inclinado | `width 0.85`, `lean 15°`, ropa deportiva | 6 | M4 |
| `crawler` | bajo, sin piernas | piernas a escala 0 + muñones (`gore`), brazos largos | 4 | M4 |
| `frozen` | rígido, blanco‑azulado | cualquier caminante con paleta `skin_frozen`/`z_*` + 3–5 esquirlas de hielo (`ice`) como piezas + pose rígida | (paleta sobre caminantes) | M4 |
| `bloater` | muy ancho | `width 1.4`, torso inflado (anillos del loft), `hospital_green`/amarillento | 4 | M4 |
| `screamer` | sin brazos, boca abierta | brazos a escala 0 + mandíbula caída, `cloth_white` | 3 | M9b |
| `stalker` | blanco, agazapado | paleta `cloth_white`/`snow_shadow`, `hunch 35°`, `width 0.9` | 3 | M9b |
| `armored` | casco + chaleco | `Outfit_vest` + `Helmet` en `HeadSocket` (pieza separada `Helmet_<id>.glb` para caer como `RigidBody3D`), `police_blue`/`military_green` | 4 | M9b |
| `colossus` | ×1.6 | mismo esqueleto escalado, piezas engrosadas, `military_green` | 2 | M9b |

Heridas gore‑lite: parches `blood`/`blood_dry` en ropa, boca y manos como caras planas; ropa rasgada = caras que faltan dejando piel; muñones como props pequeños. Sin vísceras. Cada variante de color es una **malla horneada distinta** (~30 KB).

### 5.3 Animales (`animals/wolf.glb`, `deer.glb`)

Hasta **M9b** siguen con **piezas rígidas** y los nombres del slice (`Body`, `Head`, `Muzzle`, `Tail`, `LegFL/FR/BL/BR`), regeneradas en M0 con frente **−Y** y color de vértice. En M9b: esqueleto cuadrúpedo (`Root, Hips, Spine, Chest, Neck, Head, Tail1, Tail2, {FL,FR,BL,BR}{Upper,Lower,Foot}` = 20 huesos), skin rígido, ciclos por generador de 4 fases (paso 0/0.25/0.5/0.75, trote diagonal, galope) + IK de 2 huesos por pata. Conejo: fuera de v2.0.

### 5.4 Ropa (M8)

Piezas rígidas ligadas a los huesos del torso/cabeza/manos/pies del mismo armature del jugador (`Outfit_*`), exportadas en `survivor_*.glb`. Cada prenda cambia la silueta (parka = volumen +15 %, capucha). Las prendas **no** se exportan como assets separados: el código activa `Outfit_<id>` por nombre según el equipo (`data/clothing.gd` mapea `item_id → outfit_id`).

---

## 6. Animaciones

### 6.1 Reglas

- Generadas por script: **locomoción por generador cíclico** (trayectoria de pie anclada al suelo: en apoyo retrocede exactamente a `speed`; arco `sin^0.8` en vuelo; IK analítica de 2 huesos; pelvis con dos valles; contrarrotación de torso; brazos opuestos) y **acciones por poses clave** con interpolación Bézier. Métricas obligatorias (`verify_chars.py`): tobillo mínimo ≥ 0.08 m, velocidad de apoyo = velocidad autorada ± 5 %.
- **In‑place, sin root motion**; `Root` sin claves. Velocidades autoradas: jugador andar 3.0 / correr 6.0 / agachado 1.5; caminante 1.2; corredor 5.5 y 3.0; reptador 1.0. El `AnimationTree` escala `TimeScale = v_real / v_autorada`.
- 30 fps; bucles con sufijo **`-loop`** (Godot lo quita y pone `LOOP_LINEAR`); no bucles sin sufijo. Todos los ciclos empiezan con el **pie izquierdo en contacto en t = 0** (sincronía `CYCLIC_MUTABLE`).
- Estilo para cámara alta: **anticipación ≥ 0.25 s, impacto ≤ 0.12 s, poses exageradas 20–30 %**; lo que se lee son hombros, cabeza y brazos.
- Cada `.glb` de animaciones se genera desde **un armature sin malla** (proporciones del jugador). Eventos (sonidos, ventanas de daño, cargador fuera/dentro) **no viajan en glTF**: se entregan en `data/anim_events.json` (`{"Pistol_Reload": {"mag_out": 0.35, "mag_in": 1.10}, "Melee2H_Swing_A": {"hit_start": 0.30, "hit_end": 0.42}}`). Las ventanas de daño las usa el **servidor**.
- Nombres: `Set_Accion[_Variante][-loop]`. Sets: `Loco`, `Crouch`, `Melee1H`, `Melee2H`, `Spear`, `Bow`, `Pistol`, `LongGun`, `Throw`, `Act`, `Hit`, `Down`, `Death`, `Veh`, `Emote`, `Zom`, `Wolf`, `Deer`.

### 6.2 Jugador / NPC humano

| Nombre | Bucle | Duración (s) | Método | Prioridad | Hito |
|---|---|---|---|---|---|
| `Loco_Idle-loop` | sí | 3.0 | G/K | P0 | M1 |
| `Loco_Idle_Cold-loop` (tiritar, brazos cruzados) | sí | 2.0 | K | P0 | M1 (v0), M8 |
| `Loco_Walk-loop` (3.0 m/s) | sí | 1.0 | G | P0 | M1 |
| `Loco_Run-loop` (6.0 m/s) | sí | 0.7 | G | P0 | M1 |
| `Loco_Walk_L/R/B-loop`, `Loco_Run_L/R/B-loop` (8 direcciones para apuntar andando) | sí | 1.0 / 0.7 | G (IK 3D) | P1 | M5 |
| `Crouch_Idle-loop`, `Crouch_Walk-loop` (1.5 m/s, pelvis −0.35) | sí | 3.0 / 1.2 | G | P0 | M1 |
| `Pistol_Aim-loop`, `LongGun_Aim-loop`, `Bow_Aim-loop` (torso) | sí | 2.0 | K | P0 | M5 |
| `Pistol_Shoot`, `LongGun_Shoot`, `LongGun_Shoot_Shotgun` (aditivas, retroceso) | no | 0.2–0.3 | K/A | P0 | M5 |
| `Pistol_Reload`, `Pistol_Reload_Revolver`, `LongGun_Reload_Bolt`, `LongGun_Reload_Shell-loop` (cartucho a cartucho), `LongGun_Reload_Mag` | no/sí | 1.6 / 3.0 / 3.5 / 0.7 / 2.2 | K | P1 | M5 |
| `Bow_Draw`, `Bow_Hold-loop`, `Bow_Release`; `Bow_Crossbow_Reload` | no/sí/no | 1.4 / 2.0 / 0.3 / 2.5 | K | P1 / P2 | M5 / M9a |
| `Melee1H_Light_A`, `Melee1H_Light_B` | no | 0.55 | K | P0 | M4 |
| `Melee2H_Swing_A`, `Melee2H_Swing_B` (= talar) | no | 0.9 | K | P0 | M2 (A), M4 (B) |
| `Melee_Charged` | no | 1.3 | K | P1 | M4 |
| `Spear_Thrust` | no | 0.8 | K | P1 | M8 |
| `Act_Shove`, `Act_Stomp`, `Act_Execute` (cuchillo, 1.5 s), `Act_Unjam` (1.5 s) | no | 0.5 / 1.0 / 1.5 / 1.5 | K | P0 / P0 / P1 / P1 | M4, M5 |
| `Act_Interact` (mano a objetivo), `Act_Pickup` (agacharse), `Act_Search-loop` (registrar contenedor), `Act_Force_Door` (palanca, 3 s), `Act_Open_Door` | no/sí | 0.6 / 0.8 / 1.5 / 3.0 / 0.6 | K | P0 | M2, M6a |
| `Act_Eat`, `Act_Drink`, `Act_Bandage`, `Act_Inject`, `Act_Read` (60 s: bucle 3 s) | no/sí | 1.5 / 1.5 / 2.0 / 1.5 / 3.0 | K | P1 | M8 |
| `Act_Throw`, `Act_Light_Flare` | no | 0.8 / 1.0 | K | P1 | M5 |
| `Act_Warm_Hands-loop`, `Act_Sit_Fire-loop`, `Act_Sleep-loop`, `Act_Fish-loop`, `Act_Butcher-loop` | sí | 3.0 | K | P1 / P2 | M8 |
| `Act_Repair-loop` (arrodillado), `Act_Chains-loop`, `Act_Siphon-loop`, `Act_Jump_Start-loop` | sí | 2.0 | K | P1 | M10 |
| `Act_Fall_Ice`, `Act_Climb_Out` (salir del agua a rastras) | no | 1.0 / 3.0 | K | P1 | M8 |
| `Hit_Front`, `Hit_Back` (aditivas 0.25 s), `Hit_Stagger`, `Hit_Grabbed-loop` (forcejeo) | no/sí | 0.25 / 0.25 / 0.6 / 1.0 | A / K | P0 | M4 |
| `Down_Fall`, `Down_Idle-loop`, `Down_Crawl-loop` (0.8 m/s), `Down_Revived` (levantarse), `Act_Revive-loop` (arrodillado sobre otro) | no/sí | 0.8 / 2.0 / 1.2 / 1.5 / 2.0 | K/G | P0 | M4 |
| `Death_A` (poses cortas, luego ragdoll) | no | 0.5 | K + R | P0 | M4 |
| `Veh_Enter`, `Veh_Exit` (0.8 s), `Veh_Drive-loop` (manos al volante por IK), `Veh_Passenger-loop`, `Veh_Shoot_Window-loop` (torso), `Veh_Snowmobile-loop` | no/sí | 0.8 / 0.8 / 2.0 / 3.0 / 2.0 / 2.0 | K + IK | P1 | M7 |
| `Act_Carry_Heavy-loop` (bidón, batería) | sí | 1.0 | K | P2 | M8 |
| `Emote_Point`, `Emote_Come`, `Emote_Wait`, `Emote_Quiet` | no | 1.2 | K | P1 | M10 |
| Trepar / saltar valla / escalera | — | — | — | fuera de v2.0 | — |

### 6.3 Zombis (mismo esqueleto)

| Nombre | Bucle | Duración | Método | Prio | Hito |
|---|---|---|---|---|---|
| `Zom_Idle_A-loop`, `Zom_Idle_B-loop` (balanceo, mirar alrededor) | sí | 3.0 | G/K | P0 | M2 |
| `Zom_Shamble_A/B/C/D-loop` (1.2 m/s: cojera izq., cojera der., brazos caídos, brazos al frente) | sí | 1.6 | G | P0 | M2 |
| `Zom_Investigate-loop` (andar con cabeza hacia el ruido) | sí | 1.6 | G | P0 | M4 |
| `Zom_Alert` (giro brusco + gruñido) | no | 0.6 | K | P0 | M4 |
| `Zom_Attack_A`, `Zom_Attack_B` (zarpazo/mordisco) | no | 1.0 | K | P0 | M2 |
| `Zom_Grab-loop` (sobre el jugador) | sí | 1.0 | K | P1 | M4 |
| `Zom_Knock_Door-loop` | sí | 1.0 | K | P1 | M4 |
| `Zom_Hit` (aditiva), `Zom_Stagger`, `Zom_Knockdown`, `Zom_GetUp` | no | 0.25 / 0.6 / 0.8 / 1.5 | A / K | P0 / P0 / P1 / P1 | M2, M4 |
| `Zom_Death_A`, `Zom_Death_B` (caer delante/atrás; ragdoll cerca) | no | 0.8 | K + R | P0 | M2 |
| `Zom_Frozen_Idle-loop` (pose rígida), `Zom_Wake` (sacudidas, 1.5 s) | sí / no | 4.0 / 1.5 | K | P0 / P1 | M2 / M4 |
| `Zom_Run-loop` (5.5 m/s), `Zom_Run_Tired-loop` (3.0 m/s) | sí | 0.7 / 1.0 | G | P1 | M4 |
| `Zom_Crawl-loop` (1.0 m/s, brazos tiran), `Zom_Crawl_Grab`, `Zom_Crawl_Death` | sí / no / no | 1.4 / 0.8 / 0.8 | G / K | P1 | M4 |
| `Zom_Walk_Heavy-loop` (hinchado 0.9 m/s), `Zom_Bloat_Pop` | sí / no | 1.8 / 0.5 | G / K | P1 | M4 |
| `Zom_Scream-loop` (canal 3 s), `Zom_Screamer_Retreat-loop` (2.0 m/s) | sí | 3.0 / 1.2 | K / G | P1 | M9b |
| `Zom_Stalk-loop` (agazapado 4.0 m/s), `Zom_Pounce` | sí / no | 0.8 / 0.9 | G / K | P2 | M9b |
| `Zom_Helmet_Off` | no | 0.5 | K | P2 | M9b |
| `Zom_Charge-loop` (7 m/s), `Zom_Smash` (coloso) | sí / no | 0.6 / 1.6 | G / K | P2 | M9b |
| `Zom_Eat-loop` (arrodillado), `Zom_Sleep_Group-loop` (de pie, cabeza caída) | sí | 3.0 / 4.0 | K | P2 | M9b |

### 6.4 Animales (M9b)

Lobo: `Wolf_Idle-loop`, `Wolf_Walk-loop` (2.5), `Wolf_Trot-loop` (4.0), `Wolf_Gallop-loop` (6.0), `Wolf_Stalk-loop`, `Wolf_Bite`, `Wolf_Hit`, `Wolf_Death`, `Wolf_Howl`. Ciervo: `Deer_Graze-loop`, `Deer_Idle-loop`, `Deer_Walk-loop`, `Deer_Trot-loop`, `Deer_Bound-loop` (7.0), `Deer_Alert`, `Deer_Death`.

### 6.5 `AnimationTree` que consumirá el código (referencia)

```
StateMachine "body": Locomotion | Crouch | Vehicle | Downed | Dead
 Locomotion = BlendTree:
   BlendSpace2D "move" (x lateral, y frontal; Idle(0,0), Walk ±3 ×8 dir, Run ±6 ×8 dir; sync CYCLIC_MUTABLE)
   → TimeScale "stride" → Blend2 "upper" (filtro torso: Spine, Chest, Neck, Head, hombros, brazos, manos)
       ← Transition "weapon_class" (Unarmed, Melee1H, Melee2H, Spear, Pistol, LongGun, Bow, Throwable, Carry)
   → OneShot "action" (filtro torso: golpe/disparo/recarga/lanzar/usar)
   → Add2 "hit" (aditiva 0.25 s)
Modificadores bajo GeneralSkeleton (en este orden): LookAtModifier3D(Head) · AimModifier3D(Chest, ±60°) · TwoBoneIK3D(brazo izq. → SupportGrip / volante) · SpringBoneSimulator3D (bufanda, mochila) · PhysicalBoneSimulator3D (ragdoll: 12 huesos)
```

Los 8 direcciones (`_L/_R/_B`) son P1: hasta M5 el `BlendSpace2D` usa solo el eje frontal y el cuerpo gira hacia el cursor.

---

## 7. Verificación de personajes (`verify_chars.py`)

Por cada `chars/*.glb`, `zombies/*.glb`, `anims/*.glb`: (1) reimport; (2) armature con los 22 huesos + sockets, nombres exactos, `Root` sin deform; (3) T‑pose (brazos ±X horizontales, rodillas rectas), frente −Y (la nariz/quads de ojos con y < 0); (4) 0 vértices sin peso, 100 % de vértices con 1 influencia (salvo `Outfit_*` continuos: ≤ 2); (5) 1 superficie `palette_vcol` (+ excepciones) por malla, `COLOR_0` presente; (6) acciones: nombres válidos, `-loop` solo en bucles, duraciones ± 1 frame de la tabla, ≥ 20 pistas de rotación por acción; (7) métricas de pies (tobillo mín. ≥ 0.08, velocidad de apoyo ± 5 %) en todas las `Loco_*`, `Crouch_*`, `Zom_Shamble_*`, `Zom_Run*`, `Wolf_*`, `Deer_*`; (8) tris ≤ presupuesto; (9) `humanoid_bonemap.tres` regenerado si cambian nombres; (10) importación en Godot (`inspect_models.gd`) sin `ERROR` y `GeneralSkeleton` presente; (11) renders `shots/<char>_<anim>.png` (tira de 6 instantes, perfil y 3/4) y `game_view_dist22.png` para revisión.

---

## 8. Kit modular de edificios

### 8.1 Rejilla y medidas (decisión C8)

| Medida | Valor |
|---|---|
| Rejilla horizontal | **2 m** (medio módulo 1 m); chunk 64 m = 32 celdas; calle 8 m = 4 celdas; acera 2 m |
| Altura de planta | **3.0 m** suelo a suelo (muro 2.8 + forjado 0.2) |
| Cimiento | 0.3 m (suelo interior a +0.3); absorbe desniveles |
| Muros | exterior 0.2 m centrado en la línea de rejilla; interior 0.12 m |
| Huecos | puerta 1.0 × 2.2; doble 2.0 × 2.4; garaje 3.0 × 2.6 (módulo 4 m); ventana 1.2 × 1.2 con alféizar a 0.9; escaparate 3.2 × 2.2 (módulo 4 m) |
| Escalera | 17 peldaños de 0.176, huella 0.28, ancho 1.2 → módulo 2 × 6 m; **colisión en rampa** |
| Tejado | a dos aguas 35° con losa de nieve; plano con peto en comercial |
| Rejilla interior de mobiliario | 1 m |

### 8.2 Piezas (por estilo: `wood_blue` (= `cabin_wall`), `brick`, `concrete`, `sheet_metal`)

| Familia | Nombres de pieza | Tris |
|---|---|---|
| Muros | `Wall_2`, `Wall_1`, `Wall_Door_2`, `Wall_DoubleDoor_2`, `Wall_Window_2`, `Wall_Shop_4`, `Wall_Garage_4`, `Wall_Broken_2`, `Wall_Boarded_2` + versión **`_Stub`** (0.6 m) de cada una | 20–120 |
| Esquinas | `Corner_Out`, `Corner_In`, `Post` | 10–40 |
| Suelos | `Floor_2x2`, `Floor_Stair_Opening_2x6`, `Porch_2x2`, `Foundation_Skirt_2` | 2–30 |
| Escaleras | `Stair_2x6`, `Stair_Exterior_2x6`, `Ladder` | 60–200 |
| Tejados | `Roof_Gable_2`, `Roof_Gable_End`, `Roof_Hip_Corner`, `Roof_Flat_2x2`, `Parapet_2`, `Chimney`, `Awning_4`, `Porch_Roof_2` | 20–150 |
| Aberturas | `Door` (hoja con pivote en bisagra), `Door_Double`, `Door_Garage`, `Window` (material `window`), `Shutter`, `Planks` | 12–60 |
| Interior | tabiques `IWall_2`, `IWall_Door_2`, mobiliario (§9) | 40–400 |

Las piezas viven en `kits/build_kit_<style>.py` y **no se exportan sueltas**: `lib/kit.py` las ensambla según la plantilla y fusiona por grupo.

### 8.3 Plantillas (`data/buildings/templates/<id>.json`)

```json
{ "id": "house_small_A", "style": ["wood_blue","brick"], "footprint": [8,10], "floors": 1,
  "rooms": [ {"name":"living","cells":[[0,0],[3,2]]}, {"name":"bedroom","cells":[[0,3],[3,4]]}, ... ],
  "doors": [ {"pos":[2,0],"dir":"S","kind":"door","exterior":true}, {"pos":[2,3],"dir":"N","kind":"door"} ],
  "windows": [ {"pos":[0,1],"dir":"W"}, ... ],
  "stairs": null, "roof": "gable_S", "porch": {"cells":[[1,-1],[3,-1]]}, "chimney": [0,2],
  "furniture": [ {"kind":"bed","pos":[0.5,3.5],"yaw":0}, {"kind":"wardrobe","pos":[3.5,4.0],"yaw":90} ],
  "spawns": [ {"kind":"Container","table":"house_kitchen","pos":[3.5,1.0],"yaw":180},
              {"kind":"Zombie","pos":[1.5,1.5]}, {"kind":"Light","pos":[2,2,2.7]}, {"kind":"Bed","pos":[0.5,3.5]} ] }
```

`kits/build_buildings.py` genera `assets/models/buildings/<style>/<id>.glb` para cada estilo permitido. La plantilla la escribe Opus (con supervisión del GDD para el botín); el código solo lee la `.glb` y sus anclas.

### 8.4 Estructura exportada (una `.glb` por edificio)

```
<Building>                      frente −Y (puerta principal hacia −Y); origen: centro de la huella a z = 0
├─ Floor0                       forjado + cimiento planta 0 (nunca se oculta)      [cut_group="Floor0"]
├─ Walls0_N / Walls0_S / Walls0_E / Walls0_W      fachadas de la planta 0 (una malla por fachada, ventanas incluidas)
├─ Walls0_N_Stub …              versión 0.6 m de cada fachada (visible solo en corte)
├─ Interior0                    tabiques + marcos + mobiliario decorativo fusionado
├─ Floor1, Walls1_*, Walls1_*_Stub, Interior1 …
├─ Roof                         tejado + nieve + chimenea (se oculta al entrar)
├─ Door_<n>                     hoja con pivote en la bisagra (objeto separado, custom prop "kind": door|double|garage, "exterior": bool)
├─ Window_<n>                   cristal (material window) separado por ventana rompible; custom prop "boarded": false
├─ Spawn_<Kind>_<n>             Empties orientados (−Y = frente del objeto): Container (prop "table"), Furniture (prop "kind"), Bed, Stove, Light, Zombie, Loot, Workbench, Radio
├─ Nav_Block_<n>                (opcional) cajas que el navmesh debe respetar sin colisión de jugador
└─ Col<Grupo>-convcolonly / Col<Grupo>-colonly   primer nivel; nunca hijos de visuales
```

Fachadas por dirección: `N` = +Y Blender (fondo), `S` = −Y (frente), `E` = +X, `W` = −X. Con color de vértice, un edificio de 2 plantas ≈ **12–16 superficies**. Custom props (`export_extras`) leídas por el código: `cut_group`, `floor`, `kind`, `table`, `exterior`, `surface`.

### 8.5 Plantillas por hito

| Hito | Plantillas (× estilos) | Notas |
|---|---|---|
| M6a | `house_small_A/B/C` (8×10, 1 planta), `house_two_story_A/B` (8×10, 2), `shop_general` (10×14), `garage` (6×8), `barn` (12×16), `sawmill_shed` (10×12), `gas_station` (marquesina 12×8 + tienda 8×10), `house_hunter` (= la casa del slice, 6×5 + porche, **misma disposición interior**), `a_frame` (6×7) | ≥ 2 estilos por casa |
| M6b | `farmhouse` (10×12), `silo`, `workshop` (8×10 con foso), `bar` (10×12), `cabin_small` (5×5) | |
| M9a | `shop_clothes`, `shop_pharmacy`, `clinic` (14×16), `hospital` (20×30, 3 plantas, sub‑escenas), `police_station` (16×20, 2, celdas, armería), `church` (10×20 + campanario 14 m), `school` (24×16, 2), `municipal_depot` (16×20), `apartment_small` (12×12, 3), `fishing_hut` (4×5), `dam_control` (8×10), `lookout_tower` (4×4 × 12 m), `rest_area_shop` | Presupuesto §14 |
| M9b | `military_checkpoint` (POI: barreras Jersey, sacos, garita 3×3, tienda, contenedores, torre) | POI a mano |
| M10 | `evacuation_bridge` (POI), `radio_station` (POI) | |

### 8.6 Regla de corte

Jugador dentro en la planta *k* → ocultar `Roof` y todo `Floor/Walls/Interior` de plantas > k; en la planta k sustituir por su `_Stub` las fachadas cuya normal mira a cámara (umbral 0.15). Tu responsabilidad: que cada `Walls<k>_<dir>` tenga su `_Stub` con el **mismo contorno en planta**, y que ninguna pieza cruce de una fachada a otra (las esquinas van con la fachada `S`/`N`).

### 8.7 Colisión de edificios

Cajas `Col*-convcolonly` por fachada y planta (muros), forjados (`ColFloor<k>`), escaleras como **rampa** prisma, porches; trimesh `Col<Grupo>-colonly` solo para escaleras exteriores/ruinas. Puertas: sin colisión propia en el `.glb` (el código añade una caja a `Door_n` y la conmuta). Tejados: sin colisión.

---

## 9. Interiores y mobiliario (`props/build_furniture*.py`)

Existentes (regenerar en M0, frente −Y): `bed`, `desk`, `chair`, `shelf`, `clock`, `cabinet`, `wood_stove`. Nuevos: M6a `kitchen_counter`, `fridge` (puerta `Door` separada), `sofa`, `tv`, `table_round`, `wardrobe`, `dresser`, `bookshelf`, `shop_shelf` (×2), `counter`, `cash_register`, `workbench`, `toolbox`, `oil_drum`, `pallet`, `crate`, `locker`; M9a `hospital_bed`, `gurney`, `medical_cabinet`, `desk_office`, `filing_cabinet`, `jail_bars_2`, `jail_bunk`, `church_pew`, `altar`, `school_desk`, `blackboard`, `lockers_row`, `fitting_room`, `clothes_rack`, `bar_counter`, `stool`; M8 `generator`, `radio_base`, `battery_charger`, `oil_stove`, `cot`, `barricade_window`, `barricade_door`, `reloading_bench`. Cada uno: un objeto raíz con el nombre en PascalCase (`Fridge`), partes móviles como hijos (`Door`, `Drawer`), ≤ 400 tris, sin colisión (el código pone cajas), frente −Y, origen en la base centrada (pared: contacto).

---

## 10. Kit de carreteras (`roads/build_roads.py`)

Baldosas de **8 × 8 m** (2 carriles de 3 m + arcenes de 1 m), origen en el centro a z = 0, asfalto `asphalt` casi cubierto (nieve pisada `snow_shadow` con rodadas, `asphalt` asomando en el centro), líneas `asphalt_line` discontinuas, bermas de nieve apartada (`snow`) en los bordes, aceras opcionales de 2 m con bordillo 0.15 (`concrete`). Nombres: `road_straight`, `road_cross`, `road_t`, `road_curve`, `road_end`, `road_crosswalk`, `road_parking`, `sidewalk_2`, `sidewalk_corner`, `road_bridge_8` (M10). 20–150 tris; custom prop `surface = "asphalt"`. Entre asentamientos la carretera es una cinta generada en Godot con el mismo perfil (no es tu asset).

---

## 11. Vehículos (`vehicles/build_<vehicle>.py`)

```
<vehicle>.glb       frente −Y; origen en el suelo, centro entre ejes
├─ Body             carrocería + interior, palette_vcol (+ emissive_lamp en pilotos/faros)
├─ Glass            cristales, material glass (objeto separado para romperlos)
├─ WheelFL/FR/RL/RR pivote = centro de la rueda, eje a lo largo de X, simétricas (giran en X local); material tire + hub
├─ SteeringWheel    pivote en la columna (P2)
├─ DoorFL/FR/RL/RR  pivote en bisagra (P2)
├─ Seat_Driver, Seat_FrontR, Seat_RL, Seat_RR, Seat_BedL, Seat_BedR    Empties orientados como el vehículo
├─ Exit_L, Exit_R, Interact_Driver, Interact_Trunk, Interact_Hood, FuelCap, Bed (furgoneta: cama)   Empties
├─ Headlight_L/R, Taillight_L/R, Exhaust, Smoke_Engine, Plow (quitanieves), Hitch (motonieve)       Empties
└─ ColChassis, ColCabin, ColPlow   cajas convexas SIN sufijo (el código crea las formas)
```

| Vehículo | Tris (sin ruedas) | Ruedas | Asientos | Notas | Hito |
|---|---|---|---|---|---|
| `sedan` (+ `sedan_police` con barra de luces `Lightbar`) | 1.5–2.5 k | 4 × 120–200 | 4 | variantes de restos | M7 |
| `pickup` (migración de `pickup_truck` con anclas v2) | 2–3 k | 4 | 3 + 2 en caja (`Seat_BedL/R`) | `BedAnchor` → `Interact_Trunk` | M7 |
| `van` (+ `ambulance`) | 2–3 k | 4 | 2 + 4 | `Bed` interior | M7 |
| `snowmobile` | 0.8–1.2 k | esquís + oruga: 4 anclas `WheelFL/FR/RL/RR` de raycast igualmente | 2 | `Hitch` | M7 |
| `snowplow` | 3–4.5 k | 6 | 2 | `Plow` con `ColPlow` | M10 |
| `heavy_truck` (militar) | 3–4 k | 6 | 2 + caja | | M10 |
| `bus_wreck`, `car_wreck_A/B/C`, `van_wreck` | 1–3 k | — | — | props estáticos con `Loot`, `FuelCap`; del **mismo generador** con `wreck=True` (vértices hundidos, cristales oscuros, sin ruedas/pinchadas, paleta `rust`/quemada, nieve encima, puertas abiertas) | M6b (wrecks), M9a (bus) |

Verificación (`verify_vehicles.py`): ruedas simétricas ±0.01, pivotes en el centro de rueda, radio de rueda declarado en custom prop `wheel_radius`, `Col*` sin sufijo y cerrados, anclas presentes, frente −Y (`Headlight_L` con y < 0), masa en custom prop `mass`.

---

## 12. Armas (`weapons/build_weapons.py`)

Convención: **origen = centro de la empuñadura principal**, **mango +Z Blender** (+Y Godot), **extremo útil −Y Blender** (+Z Godot), +X = lado derecho del arma. Se engancha con **identidad** en `RightHandSocket`. Escala real ×1.0; **×1.2 en armas pequeñas** (cuchillo, pistola, revólver). Un solo modelo para mano y suelo. Silueta y un color de acento por clase.

| Ancla (Empty) | Qué es | Usado por |
|---|---|---|
| `Grip` | (= origen; opcional, explícito) | |
| `Muzzle` | boca del cañón, −Y hacia fuera | origen visual del rayo, fogonazo, humo |
| `SupportGrip` | guardamanos / segunda mano | `TwoBoneIK3D` mano izquierda (armas largas, hacha a dos manos, arco) |
| `Magazine` | pieza separada (malla `Magazine`) | recarga: pasa a `LeftHandSocket` |
| `EjectPort` | ventana de expulsión | casquillos |
| `Sight` | punto de mira | línea de apuntado |
| `Holster` | punto de enganche al enfundar | `BackSocket` / `HipSocketR` |
| `FlameAnchor` | antorcha / molotov | fuego |

| Arma | Clase | Largo | Tris | Hito |
|---|---|---|---|---|
| `knife`, `machete` | Melee1H | 0.25 / 0.55 | 40–120 | M2 |
| `crowbar` | Melee1H | 0.60 | 40–80 | M2 |
| `bat`, `bat_nails`, `fire_axe`, `stone_axe` (migrada) | Melee2H | 0.85 / 0.85 / 0.80 / 0.55 | 60–200 | M2 |
| `spear` | Spear | 1.8 | 40–100 | M8 |
| `bow`, `arrow`, `crossbow`, `bolt` | Bow | 1.3 / 0.7 / 0.8 / 0.4 | 80–300 | M5 / M9a |
| `pistol_9mm` (+ `Magazine`), `revolver_357` | Pistol | 0.20 / 0.28 (×1.2) | 150–300 | M5 |
| `shotgun_pump`, `shotgun_sawn` | LongGun | 1.0 / 0.65 | 250–500 | M5 |
| `rifle_308` (+ `Scope` como pieza), `carbine_556` (+ `Magazine`) | LongGun | 1.1 / 0.9 | 300–600 | M5 / M9b |
| `molotov`, `flare`, `pipe_bomb`, `can`, `rock` | Throwable | 0.2–0.3 | 30–100 | M5 |
| `torch`, `flashlight`, `lantern` (existentes/nuevo) | Tool1H | — | 40–120 | M0 / M5 |
| Mods: `suppressor`, `scope`, `flashlight_rail` | piezas en `Muzzle`/`Sight`/`SupportGrip` | — | 30–80 | M9b |

---

## 13. Props y vegetación (MultiMesh‑friendly)

Reglas para todo lo que va a `MultiMesh` (árboles, rocas, arbustos, montones de nieve, troncos, vallas, postes, farolas sin luz, restos pequeños): **un solo objeto, una sola superficie `palette_vcol`, sin hijos, sin empties, sin colisión embebida** (el código pone formas por variante). Variación por instancia la aporta el código (`custom_data`: tinte ±6 %, nieve). Origen en la base centrada; `snow` por normal.

| Familia | Assets | Tris | Hito |
|---|---|---|---|
| Pinos | `pine_a/b/c` (existentes), `pine_d` (muy alto 9 m), `pine_e` (doble copa), `pine_young` (2.5 m) | 150–400 | M0 / M3 |
| Otros árboles | `dead_tree` (existente), `dead_tree_b`, `birch` (abedul, `paint_white` + `bark`), `stump` | 80–250 | M3 |
| Arbustos | `berry_bush` (existente; **excepción**: mantiene hijo `Berries` porque es interactivo y va como nodo), `bush_a`, `bush_b` | 100–400 | M3 |
| Rocas | `rock_a/b/c` (existentes), `rock_d` (losa), `rock_e` (afloramiento 3 m), `stone` | 40–200 | M3 |
| Nieve | `snow_pile_a/b/c`, `snow_drift_4` (alargado), `icicles` | 20–80 | M3 |
| Suelo | `fallen_log` (existente), `fallen_log_b`, `firewood`, `branch_pile`, `campsite_remains` (tienda rota + restos) | 20–150 | M3 |
| Urbano (M6b) | `lamp_post` (+ `Light` Empty), `power_pole` (+ `WireA/B`), `traffic_light`, `sign_stop`, `sign_yield`, `sign_town` (+ `Text` Empty para `Label3D`), `bus_stop`, `bench`, `trash_can`, `dumpster` (+ `Loot`), `hydrant`, `mailbox`, `fence_wood_2` (existente `fence`), `fence_wire_2`, `fence_chain_2`, `barricade_wood`, `barricade_jersey`, `barricade_sandbags`, `barricade_wire`, `tire_stack`, `barrel`, `pallet`, `crate`, `shopping_cart`, `fuel_pump`, `gas_sign` (alto), `silo`, `tractor` (prop), `hay_bale`, `sawmill_saw`, `log_pile` | 20–300 | M6a/M6b |
| Cadáveres y sangre | `corpse_covered`, `corpse_animal_deer`, `blood_splat_a/b/c` (quads irregulares), `blood_trail` | 8–150 | M4 |
| Botín (M5) | `can_beans`, `can_soup`, `chocolate`, `bandage`, `medkit`, `ammo_box_9mm`, `ammo_box_shells`, `ammo_box_308`, `backpack_s/m/l`, `jerrycan`, `car_battery`, `snow_chains`, `rope`, `duct_tape`, `gun_oil`, `blueprint` (revista), `walkie`, `radio_portable`, `battery_pack` | 20–150 | M5 / M8 |
| Militar (M9b) | `sandbag_wall_2`, `guard_booth`, `mil_tent`, `container_20ft`, `watchtower`, `heli_wreck` | 100–800 | M9b |
| Evacuación (M10) | `flare_stand`, `barrier_military`, `radio_component`, `plow_part_a/b/c` | 30–200 | M10 |

---

## 14. Presupuestos

| Categoría | Tris | Huesos | Superficies | Referencia |
|---|---|---|---|---|
| Jugador (Body + 1 outfit activo) | 800–1 500 | 27 | 1 (+ excepciones) | PoC 814 |
| Zombi / NPC | 700–1 300 | 27 | 1 | PoC 762 |
| Lobo / ciervo | 500–900 / 600–1 000 | 20 (M9b) | 1 | slice 600 / 800 |
| Arma en mano | 40–600 | — | 1–2 | |
| Vehículo | 1.5–4.5 k + ruedas | — | 2–3 (`palette_vcol`, `glass`, `emissive_lamp`) | |
| Edificio completo | 2–12 k | — | 8–20 (grupos de corte) | cabaña actual 34 → ≤ 12 |
| Mueble / prop | 20–400 | — | 1 | |
| Árbol | 150–400 | — | 1 | |
| Baldosa de carretera | 20–150 | — | 1 | |
| Animación (fuente) | ≈ 21 KB/s a 30 fps | — | — | |
| **Escena** (radio visible + sombras ≈ 45 m) | ≤ 300 k tris (objetivo), ≤ 1.5 M (máx.) | ≤ 64 esqueletos | **≤ 1 500 draw calls Forward+ con sombras / ≤ 1 000 `compat`** (típico 400–800) | medido por `tests/perf/*` |

LOD: **no autorar LODs**. `meshes/generate_lods` queda activo (inocuo). El código pone `visibility_range_end` (60–80 m props, 120 m edificios), `cast_shadow = OFF` en props < 0.5 m y en todo lo interior. Tu obligación: mallas ya en el mínimo útil y **una superficie**.

---

## 15. Colisión (resumen)

| Asset | Colisión |
|---|---|
| Árboles, rocas, arbustos, props pequeños, muebles | ninguna embebida (código) |
| Edificios, POIs | `Col*-convcolonly` por fachada/planta/forjado/rampa; `Col*-colonly` trimesh solo irregular |
| Vehículos | `ColChassis`, `ColCabin`, `ColPlow` sin sufijo |
| Carreteras | ninguna (el terreno lleva la altura) |
| Barricadas/vallas de base | `Col*-convcolonly` (son estructuras con PV) |
| Armas, ropa, botín | ninguna |

---

## 16. Verificación (obligatoria antes de dar por terminado un pase)

1. **Ficheros**: `.blend` y `.glb` por asset; `.glb` > 1 KB y empieza por `glTF`.
2. **Reimport** en escena vacía y comprobaciones en espacio Blender.
3. **Nombres/jerarquía** según la familia (sockets bajo sus huesos; `Col*` de primer nivel; `Door_n`, `Window_n`, `Spawn_*` en edificios; `Wheel*`/`Seat_*` en vehículos).
4. **Frente −Y**: anclas de frente (`Muzzle`, `Headlight_L`, ojos, `DoorAnchor`/`Door_0` exterior, `Spawn_*` orientados) con **y < 0** o `−Y` como dirección. **[CAMBIO respecto al slice: antes era y > 0.]**
5. **Pivotes** ±0.03 m; **transformaciones** identidad salvo anclas con rotación declarada.
6. **Shading**: flat; sin UV; **con** atributo de color `Col` por esquina en toda malla visual; sin imágenes.
7. **Materiales**: solo `palette_vcol` + excepciones de §2.5; colores de vértice pertenecen a la paleta (±1/255 tras conversión).
8. **Superficies**: ≤ 2 por malla (edificios: 1 por grupo + `window`/`glass`).
9. **Presupuestos** de tris por asset (+20 % tolerancia) y por familia.
10. **Colisiones**: cerradas, convexas (6–8 vértices) o trimesh declarado; dentro de ±0.02 m de la tabla de cada edificio (que tú mismo generas desde la plantilla: el verificador compara con la huella).
11. **Personajes/animaciones**: §7.
12. **Edificios**: cada `Walls<k>_<dir>` tiene `_Stub` con el mismo contorno; `Roof` no contiene muros; `Spawn_Container` con prop `table` válida (lista en `data/loot/loot_tables.gd`); puertas con prop `exterior`.
13. **Godot**: `godot --headless --path winter-survival --import` sin `ERROR`; `tests/inspect_models.gd` muestra los nombres requeridos, `Col*` como `StaticBody3D`, `GeneralSkeleton` en personajes, `AnimationLibrary` con las acciones y bucles esperados.
14. **Renders**: `blender/shots/` (o `prototypes/animpoc/godot/render.gd` adaptado) con la cámara del juego a 22 m para cada familia nueva; el informe incluye las rutas.
15. **Informe**: una línea por asset `OK name tris=NNN surfaces=N …` o `FAIL name: reason`; `ALL OK` al final. No se reporta terminado con un P0 en `FAIL`.

---

## 17. Migración de los 33 assets existentes (M0 salvo indicación)

| Asset (slice) | Acción | Detalle |
|---|---|---|
| `player` | **retirar en M2** | Regenerar en M0 (frente −Y, vcol) para que el slice siga funcionando; sustituido por `chars/survivor_*.glb` esquelético en M1/M2; `player.glb` se borra al cerrar M2 |
| `wolf`, `deer` | regenerar | frente −Y, vcol, mismos nombres de piezas; esqueleto en M9b |
| `pine_a/b/c`, `dead_tree`, `stump` | regenerar | vcol, 1 superficie, sin cambios de forma (sin frente) |
| `rock_a/b/c`, `stone`, `firewood`, `fallen_log` | regenerar | vcol, 1 superficie |
| `berry_bush` | regenerar | vcol; conserva hijo `Berries` |
| `campfire` | regenerar | vcol; `Stones`, `Logs`, `FlameAnchor` iguales |
| `stone_axe`, `torch` | regenerar | **nueva convención de armas** (§12): origen en la empuñadura, mango +Z, extremo útil −Y (antes −Y también para el filo, pero el socket cambia); se prueban en `RightHandSocket` |
| `lantern` | regenerar | vcol; `LightAnchor`; material `window` en el cristal |
| `cabin` | regenerar en M0 (vcol, frente −Y, mismos nombres) y **reemplazar en M6a** por la plantilla `house_hunter` del kit (estructura §8.4, misma disposición interior: estufa, armario, cama, escritorio, silla, estantería, reloj) | en M0 la colisión y anclas (`DoorAnchor`, `LanternSocket`) se conservan; `WallFront` pasa a estar en −Y |
| `a_frame_cabin` | regenerar en M0; reemplazar en M6a por `a_frame` del kit | |
| `pickup_truck` | regenerar en M0 (vcol, frente −Y, `BedAnchor`, `Col*-convcolonly` conservado para el resto estático); **nuevo `vehicles/pickup.glb` en M7** con anclas v2 y `Col*` sin sufijo | el resto estático se convierte en `car_wreck_pickup` del generador en M7 |
| `signpost` | regenerar | frente −Y: los tableros apuntan a +X y el texto mira a **−Y**; `TextTop/TextBottom` con rotación (0,0,0) (antes 180°) |
| `fence` | regenerar | vcol; pasa a `fence_wood_2` en M6b (MultiMesh) |
| `bed`, `desk`, `chair`, `shelf`, `clock`, `cabinet`, `wood_stove` | regenerar | frente −Y (el lado de uso mira a −Y; estante/reloj sobresalen hacia −Y), vcol; `Door` de la estufa con material `ember`; `HourHand/MinuteHand` conservan pivotes |
| `tent`, `storage_box` | regenerar | vcol; `tent` con `ColBack-convcolonly`; frente −Y (apertura hacia −Y) |

Verificación de la migración: `verify_assets.py` v2 **ALL OK** + `tests/inspect_models.gd` con todos los anclajes de frente en +Z local + capturas `day/night/interior` del slice sin regresión (la cabaña sigue viéndose desde la cámara por defecto con el porche hacia la cámara: el código cambia su rotación de 180° a 0°).

---

## 18. Entregables por hito (Opus)

| Hito | Entregables |
|---|---|
| M0 | `lib/palette.py` (vcol), `lib/lowpoly.py` (FRONT −Y), `lib/export.py` (§2.8 + `write_import`), `lib/rig.py`, `lib/anim.py`; 33 assets regenerados; `verify_assets.py` v2; renders del claro |
| M1 | `chars/survivor_{red,blue,green,mustard}.glb`; `anims/humanoid_loco.glb` (`Loco_Idle`, `Loco_Idle_Cold`, `Loco_Walk`, `Loco_Run`, `Crouch_Idle`, `Crouch_Walk`); `assets/rig/humanoid_bonemap.tres`; plantillas `.import`; `verify_chars.py` |
| M2 | `zombies/zombie_walker_01..08.glb`; `anims/humanoid_zombie.glb` (lote M2 de §6.3); `anims/humanoid_melee.glb` (`Melee2H_Swing_A`, `Act_Interact`, `Act_Pickup`, `Act_Search`); `weapons/{knife,machete,crowbar,bat,bat_nails,fire_axe,stone_axe}.glb`; `blood_splat_a/b/c` |
| M3 | vegetación/rocas/nieve/suelo de §13; `poi/cabin_small`, `poi/lookout_tower`, `campsite_remains`; **arranque del kit** (piezas `wood_blue` + `brick`) |
| M4 | `zombie_runner_01..06`, `zombie_crawler_01..04`, `zombie_bloater_01..04`, paleta `frozen` + esquirlas; anims lote M4 (§6.2/§6.3); `corpse_*`, muñones, cabeza fragmentada |
| M5 | armas de fuego, arco, arrojadizas (§12); anims `Pistol_*`, `LongGun_*`, `Bow_*`, `Act_Throw`, `Act_Unjam`, `Loco_*_L/R/B`; botín y contenedores (§9, §13); `muzzle_flash` (malla) |
| M6a | kit completo (3 estilos), plantillas M6a (§8.5), carreteras (§10), `verify_kits.py` |
| M6b | props urbanos, restos de coche ×3, gasolinera/aserradero/granja (props), plantillas M6b |
| M7 | `sedan`, `sedan_police`, `pickup`, `van`, `ambulance`, `snowmobile`, wrecks del generador; anims `Veh_*`; `verify_vehicles.py` |
| M8 | outfits de ropa (§5.4), mochilas, props de base, hielo (grietas, agujero), anims `Act_*` de M8 |
| M9a | plantillas y mobiliario M9a, `bus_wreck`, interiores (§9) |
| M9b | `screamer`, `stalker`, `armored` (+ `Helmet_*`), `colossus`; anims lote M9b; **esqueleto cuadrúpedo** + lobo/ciervo esqueléticos + anims §6.4; control militar; `heli_wreck` |
| M10 | `snowplow`, `heavy_truck`, convoy de evacuación, `Emote_*`, `Act_Repair/Chains/Siphon/Jump_Start`, componentes de radio, mods de armas |

Regla de prioridad dentro de un pase: P0 del hito → verificación → renders → P1 → P2. Entregar P0 verificado antes de pulir nada.

---

## M1 — desviaciones (Opus, M1)

- **Velocidades (decisión vinculante de M1, sustituye C19 y §6.2)**: `Loco_Walk-loop` **2.2 m/s, 0.8 s** (24 fr), `Loco_Run-loop` **6.0 m/s, 0.667 s** (20 fr), `Crouch_Walk-loop` **1.3 m/s, 1.0 s** (30 fr); `Loco_Idle-loop` 3.0 s, `Loco_Idle_Cold-loop` 2.0 s (v0), `Crouch_Idle-loop` 3.0 s. `TimeScale = v_real / v_autorada`. Tabla contractual: `blender/anims/build_loco.py::LOCO_TABLE` (la comprueba `verify_chars.py`); cada animación lleva además `extras` glTF informativos (`authored_speed`, `period`, `drop`).
- **Pisada**: el generador (`lib/anim.py`) bloquea al suelo los **puntos de contacto** (`rig.CONTACT_POINTS`: talón en `Foot` y+0.10, bola y punta en `Toes` y−0.10/−0.19, z 0) con balanceo talón‑punta; la velocidad de apoyo y el deslizamiento se miden sobre esos puntos en el `.glb` exportado (andar 2.200, correr 6.000, agachado 1.300 m/s; deslizamiento ≤ 0.6 %). Caída de pelvis resultante: andar 0.067, correr 0.085 (+ bote), agachado 0.35 (§6.2). Las botas del personaje deben tocar el suelo exactamente en esos puntos.
- **BoneMap** en `res://assets/models/rig/humanoid_bonemap.tres` (no `assets/rig/`: el agente de arte solo escribe en `assets/models/**`). Si se mueve, cambiar `lib/export.py::BONEMAP_RES` y los `.import`.
- **Plantillas `.import`**: no hay `assets/import_templates/`; cada `.glb` de `chars/` y `anims/` lleva su `.import` (tipos `char`/`anim` de `lib/export.py::import_file_text`, ya normalizados por Godot 4.7.2 con uid estable). La plantilla `anim` añade `"PATH:AnimationPlayer": {"optimizer/enabled": false}`: el optimizador por defecto de Godot quitaba claves (Loco_Idle 91 → 45 por pista) y los pies plantados derivaban hasta 0.8 mm/frame.
- **Variantes**: gorro `hat` (roja), `hivis_orange` (azul), `jacket` (verde), `hat` (mostaza); la variante mostaza lleva bufanda y manoplas `jacket` para no fundirse con la chaqueta. Pantalón y cremallera `hat` en todas. Altura con pompón 1.838 m (copa del gorro 1.775).
- **Nota para M2 (AnimationTree)**: con la raíz a la velocidad autorada, el deslizamiento medido en Godot a 60 fps es 0.7 % (andar) y 1.6 % (correr); entre puntos del `BlendSpace1D` (p. ej. 1.3 o 4.0 m/s) mezclar dos ciclos desliza (21–75 %): usar el `TimeScale` del ciclo dominante en vez de posiciones intermedias.

## M2 — notas de integración (Fable, M2)

- El código consume los `.glb` de `chars/` y `anims/` tal cual (`character_visual.gd`): `%GeneralSkeleton`, librería `loco`, `RightHandSocket` con transformación identidad para las herramientas de §12 (mango +Y hacia el pulgar, filo +Z hacia los nudillos: correcto para el hachazo). `tests/inspect_models.gd` comprueba ahora `chars/*.glb` (27 huesos, `Hips` a 0.92, `RightHandSocket` a −X, una malla con *skin* `palette_vcol` + `COLOR_0`) y `anims/*.glb` (nombres y duraciones de la tabla LOCO, `LOOP_LINEAR`, ≥ 20 pistas de rotación, pista de posición de `Hips`).
- Métrica de pies medida en Godot con el ciclo escalado a la velocidad real (`tests/run_smoke.sh`, por tick de física, punto de apoyo = el más bajo de talón/bola mientras está plantado, y < 0.038 m): andar tobillo mín. **0.089 m**, deslizamiento **0.7 %**; correr tobillo mín. **0.079 m**, deslizamiento **1.0 %**. El clip `Loco_Run` importado toca fondo a **0.0774 m** en Godot (punta a 0.024, 1.1 cm bajo el suelo; caída de pelvis 0.135 en vez de 0.085 + bote), es decir, el *retarget* deja el pie de la carrera 3 mm por debajo del contrato: **Opus, M2/M4**: subir 1.5 cm la pelvis mínima de `Loco_Run` (o el contacto) y volver a pasar `verify_chars.py` evaluando también el `.glb` importado por Godot (`tests/inspect_models.gd` imprime las alturas).
- Hasta que existan `Melee2H_Swing_A` y `Act_*` (M2/M4 de Opus), el hachazo es `Act_Chop`, generado en código desde la pose de `Loco_Idle` (brazo derecho arriba y abajo, 0.5 s, filtro de torso): se sustituye cambiando el nombre del clip en `character_visual.gd::_build_tree`.

## G1 — mejora gráfica, guía de arte v2.1 en el pipeline principal (Opus, G1)

Fuente de la guía: `docs/research/05_graficos_arte.md` §4 (paleta, chaflanes, nieve, AO, presupuestos); contrato de
render acordado: `docs/research/06_graficos_render.md` §3.7 (`AO = COLOR.a`, nieve `#CDDEF5`). Todo se regenera con
`cd blender && python3 build_all.py` (**ALL OK**: 33 props + 4 personajes + librería `loco`, autotests de `rig`/`anim`).

**Contrato que NO cambia** (verificado con `tests/inspect_models.gd` en un proyecto Godot desechable: 38 assets
ALL OK, importación 0 errores): nombres de fichero, nombres de nodo, jerarquía, pivotes, frentes, anclas
(`DoorAnchor`, `LanternSocket`, `BedAnchor`, `FlameAnchor`, `LightAnchor`, `StoveAnchor`, `PipeTop`, `TextTop/Bottom`,
`HourHand/MinuteHand`, `ToolSocket`, `BreathAnchor`, `Muzzle`…), partes de corte de la cabaña (`Floor`, `WallBack`,
`WallLeft` + `WindowsLeft`, `WallRight`, `WallFront` + `WindowsFront`, `Roof`, `Chimney`, `Porch`), las 14 cajas `Col*`
de la cabaña (+ `ColSteps`), `ColBody`/`ColDeck` del A‑frame, `ColChassis`/`ColCab` del camión, `ColBack` de la tienda,
esqueleto de 27 huesos y pose de reposo (idénticos: las pistas de `anims/humanoid_loco.glb` se aplican sin cambios),
plantillas `.import` de `chars/`/`anims/`, `rig/humanoid_bonemap.tres`. Materiales: `palette_vcol` + excepciones (§2.5).

### G1.1 Exportación v2.1 (sustituye §2.5 "flat shading" y el `COLOR_0` RGB de §2.8)

- **`COLOR_0` = RGBA** (VEC4; Blender 5.0.1 lo escribe como uint16 normalizado con `export_vertex_color='NAME'`,
  `export_vertex_color_name='Col'`). **RGB = color de paleta exacto**: se guarda el **centro del escalón de 8 bits
  lineal** que conserva Godot (`(round(lin·255)+0.5)/255`, ≈ lineal + 0.5/255): mismo resultado en Godot que el sesgo
  anterior, pero inmune a la cuantización de 16 bits (con el sesgo, `eyes_dark` caía un escalón). **A = oclusión
  ambiental horneada** (1 = abierto, 0 = ocluido) en **todos** los assets. Godot 4.7.2 conserva el alfa (medido:
  0.0–1.0) y los RGB de paleta; `StandardMaterial3D` lo ignora (opaco); el shader del juego hace `AO = COLOR.a`.
- **AO** (`blender/lib/hd.py::bake_ao`, llamado por `export.save_and_export(name, ao=…)`): trazado de rayos (BVH,
  48–96 rayos coseno) contra todas las mallas visuales del asset + plano de suelo a z = 0; los `Col*` nunca ocluyen.
  Esquinas de caras **planas** (o endurecidas por chaflán) se muestrean 5 cm (≤ 25 %) hacia el centro de su cara;
  esquinas **suaves** en el vértice (un valor por vértice: sin costuras en nieve/tela). Alcance: 1.2 m edificios y
  pinos, 0.8 m árbol desnudo y camión, 0.25 m personajes, automático (0.3 × tamaño, 0.1–1.2 m) en el resto; sin suelo
  en `torch`, `stone_axe`, `lantern`; `shelf`/`clock` con una pared a y = 0. **Aviso al render**: el horneado Cycles
  por vértice del look‑dev (`prototypes/lookdev/godot/assets/hd/*`) muestreaba justo en las aristas de contacto y
  dejaba las caras planas casi negras (muros de `cabin_hd`: alfa medio 0.03–0.2); los assets G1 tienen caras abiertas
  a 0.8–1.0 y solo oscurecen pliegues, aleros, bajos y contacto con el suelo → revisar `ao_strength`/`ao_tint` si se
  calibraron con los ficheros del look‑dev.
- **Normales**: `use_smooth` permitido y **normales propias exportadas** (chaflanes con `harden_normals`, nieve/tela/
  corteza suaves, pisos de pino y rocas facetados). El shader **no** debe forzar normales por derivadas.
- Nieve apoyada en el suelo puede hundirse hasta **0.25 m** bajo z = 0 (montículos de pino −0.2, rocas −0.03,
  ventisqueros −0.05) para no flotar en pendiente.

### G1.2 Paleta v2.1 (`blender/lib/palette.py`, sustituye valores de §3)

Cambian: `snow #CDDEF5`, `snow_shadow #AFC3E0`, `pine_dark #1F342E`, `pine_light #2F4A3D`, `bark #4A3D35`,
`wood #7A5F4B`, `wood_light #A88E70`, `wood_dark #4A3B31`, `stone #7B8089`, `stone_dark #565B63`, `brick #735F5D`,
`cabin_wall #6C829C`, `cabin_trim #D3CFC6`, `roof #48434A`, `iron #2A2B2E`, `truck_paint #5E6650`.
Nuevos (doc 05 §4.1): `snow_packed #BFD0E8`, `snow_hole #93AACB`, `snow_deep #D6E4F7`, `roof_seam #2C2A2E`,
`bark_grey #4E4843`, `pine_mid #27402F`, `parka_brown #4F4135`, `parka_olive #4C5040`, `parka_navy #3A4457`,
`parka_rust #7A4536`, `pants_dark #35383D`, `beanie #2E3035`, `fur #CEC8BD`, `pack #5D4C3C`, `pack_dark #3D352D`,
`boots_brown #5B412F`, `sock #D9D4CB`, `skin_hd #C29478`, `glove #2F2B28`, `mat_roll #6D7558`, `strap #2B2826`,
`beard #4A3A30`. Nuevos de G1: `parka_green #465A43`, `parka_mustard #8A6B34` (variantes co‑op), `lamp_red #8C3A34`,
`lamp_clear #BFC4C2` (pilotos del camión). El resto de §3 no cambia; `zombify()` sigue igual.

### G1.3 Assets migrados a HD v2.1 y presupuestos (tris antes → después; superficies iguales salvo lo indicado)

| Asset | Tris | Superficies | Qué cambia |
|---|---|---|---|
| `cabin` | 1 510 → **22 418** | 10 (8 `palette_vcol` + 2 `window`) | port de `cabin_hd` (tablilla 0.20, molduras crema, ventanas 2×3 con alféizar nevado, tejado con juntas + losas de nieve gruesas con cornisa, hastial de entrada con cercha, chimenea de piedra/ladrillo, ventisqueros contra los muros en `Floor`) |
| `pine_a` / `pine_b` / `pine_c` | 226 / 178 / 178 → **1 125 / 873 / 747** | 1 | pisos en estrella casi cubiertos de nieve, tronco suave, montículo; alturas 7.6 / 5.8 / 4.2 m |
| `dead_tree` | 178 → **2 086** | 1 | ramificación 9 × 3 × 2, `bark_grey`, nieve en ramas altas, 4.9 m |
| `stump` | 80 → **254** | 1 | corteza suave con raíces, corte con anillos, casquete de nieve |
| `rock_a` / `rock_b` / `rock_c` | 66 / 124 / 66 → **300 / 632 / 111** | 1 | facetadas más densas, casquete de nieve suave (`snow_cap`), ventisquero en `rock_b` |
| `pickup_truck` | 600 → **5 280** | 4 (`Body` 2 + `Wheels` + `Snow`) | carrocería con chaflán 3.5 cm y pasos de rueda, aletines, neumáticos suaves, nieve almohada en capó/techo/caja |
| `a_frame_cabin` | 404 → **9 614** | 4 (`Body`, `Front` + `WindowsFront`, `Deck`) | tejado con juntas + nieve gruesa con cornisa ondulada, ventisqueros, cercha vista, puerta con tejadillo, ventana 2×2, porche con barandilla |
| `chars/survivor_*` (×4) | 954 → **2 650** | 1 → **2** | superviviente HD (proporciones naturales, parka, capucha con piel, mochila) |
| resto (24 assets) | sin cambio | sin cambio | paleta v2.1 + AO horneada (rehechos HD más adelante) |

Presupuestos v2.1 que comprueba `verify_assets.py` (sin holgura en los HD): cabaña 24 k, A‑frame 14 k, camión 9 k,
pino 1.2 k (`pine_c` 1 k), árbol desnudo 2.6 k, roca 700 (`rock_c` 400), tocón 500; personaje ≤ 3 500
(`verify_chars.py`). **Vista típica del claro** (doc 05 §4.5; cabaña, A‑frame, camión, 40 pinos, 10 árboles, rocas,
props, mobiliario, 2 lobos, 2 ciervos, 4 jugadores = 118 k) + reserva de 110 k (30 zombis, 2 casas del kit,
terreno) = **228 k ≤ 270 k**. Superficies por malla ≤ 2 (excepciones con nombre: cabaña 10 en total, camión `Body` 2).

### G1.4 Desviaciones respecto al contrato anterior (nombres exactos)

1. **`chars/survivor_{red,blue,green,mustard}.glb`**: además de `Body`, una malla **`Outfit_backpack_m`** (hija de
   `Armature`, con *skin*, rígida sobre `Chest`, 1 superficie `palette_vcol`) → 2 mallas / 2 superficies por
   personaje (§4.4 ya lo prevé). `Body` tiene vértices con **2 influencias** (faldón de la parka: `Hips` +
   `LeftUpperLeg` o `RightUpperLeg`, suma 1; §4.3 "ropa continua larga"). Altura 1.79 m (antes 1.838 con pompón).
   Colores de variante (mismos nombres de fichero): red = `parka_rust` + gorro `beanie`, blue = `parka_navy` + gorro
   `sock` (crema), green = `parka_green` + gorro `hivis_orange`, mustard = `parka_mustard` + gorro `beanie`.
2. **`anims/humanoid_loco.glb` `Loco_Run`**: caída de pelvis 0.085 → **0.111 m** (`drop_margin 0.03`) y talón más
   lento (`heel_frac 0.30`). Causa del 0.077 de M2: Godot interpola con *slerp* entre las claves de 30 fps y, con la
   pierna casi extendida, el tobillo bajaba 1.2 cm entre dos claves. Tobillo mínimo **importado en Godot 0.0774 →
   0.0824 m** (≥ 0.08), velocidad de apoyo 6.000 m/s, deslizamiento 0.00 %. `verify_chars.py` lo mide ahora entre
   claves (8× por frame) **y** en el clip importado por Godot 4.7.2 (proyecto desechable, 240 muestras por ciclo).
   Resto de clips sin cambios (andar 0.0887, agachado 0.0895 importados).
3. **`cabin`**: sin `WindowsRight` ni `ColPostL/R` del look‑dev (contrato exacto: el código ilumina `WindowsFront` y
   `WindowsLeft`). La hoja de la puerta, abierta hacia dentro, es parte de `WallFront` (solo visual). Dimensiones
   7.73 × 8.72 × 5.58 m (antes 7.1 × 8.2 × 5.3; ventisqueros en `Floor`, sombrerete de la chimenea); huella y
   colisión iguales.
4. **`a_frame_cabin`**: `WindowsFront` sigue siendo **una sola ventana** (WindowSpill coloca la luz en el centro de su
   AABB). Dimensiones 6.58 × 9.26 × 6.19 (ventisqueros y escalón del porche); colisión igual.
5. **Mínimo z** de los assets apoyados: [−0.25, +0.02] m (antes ±0.02) por la nieve hundida.
6. `player.glb` (rígido, se retira en M2) y los 24 assets no migrados solo cambian paleta + AO.

## M3 — mundo por chunks: vegetación MultiMesh, POIs del bosque y arranque del kit (Opus, M3)

Todo se regenera con `cd blender && python3 build_all.py` → **ALL OK** (`verify_assets.py`: 55 assets + vista típica
del claro 233 k y **del bosque 198 k ≤ 270 k**; `verify_kits.py`: `house_small_A` × 2 estilos; `verify_chars.py`). La
salida es determinista (una segunda pasada deja los 62 `.glb` idénticos). Importación en un proyecto Godot 4.7.2
desechable: **0 errores**; `tests/inspect_models.gd` 38 assets ALL OK; comprobación M3 (`inspect_m3.gd`, fuera del
repo) 29 assets ALL OK. Guía de arte v2.1 (sección G1) en todo: AO en `COLOR_0.a`, paleta v2.1, normales propias,
frente −Y Blender = +Z Godot. **Coordenadas de esta sección en Godot** (Y arriba, +Z = frente) salvo que se diga.

### M3.1 Ficheros (`res://assets/models/…`, cada `.glb` con su `.import` ya normalizado con `uid`)

| Carpeta | Assets | Script |
|---|---|---|
| `vegetation/` | `pine_d`, `pine_e`, `pine_f`, `pine_young`, `dead_tree_b`, `dead_tree_c`, `birch`, `bush_a`, `bush_b`, `rock_d`, `rock_e`, `rock_f`, `snow_pile_a`, `snow_pile_b`, `snow_pile_c`, `snow_drift_4`, `fallen_log_b`, `fallen_log_c` + **`manifest.json`** | `blender/vegetation/build_{trees,bushes,rocks,snow,logs}.py` |
| `props/` | `icicles` + `manifest.json` | `blender/props/build_icicles.py` |
| `poi/` | `cabin_small`, `lookout_tower`, `campsite_remains` | `blender/poi/build_<poi>.py` |
| `buildings/<estilo>/` | `wood_blue/house_small_A`, `brick/house_small_A` (casa de prueba del kit) | `blender/kits/build_buildings.py` + `lib/kit.py` |
| raíz (sin cambio de ruta ni de nodos) | `pine_a/b/c`, `dead_tree`, `stump`, `rock_a/b/c`, `stone`, `firewood`, … y los **HD de M3**: `signpost`, `berry_bush`, `fence`, `lantern`, `fallen_log` (§M3.4) | los de siempre |

### M3.2 Contrato MultiMesh (vegetation/*, props/icicles)

- Escena = raíz + **un solo `MeshInstance3D`** (nombre por familia: `Tree` pinos/árboles, `Bush`, `Rock`, `Snow`, `Log`,
  `Icicles`); **una superficie** (`palette`, = `palette_vcol` del `.glb`) con `COLOR` RGBA (A = AO); sin hijos, sin
  empties, sin `Col*`. Origen = pie del tronco / centro de la base en y = 0 (la nieve se hunde hasta 0.25 m: sin
  huecos en pendiente). Sin frente: yaw aleatorio libre; escala por instancia 0.85–1.15 recomendada.
- Para el `MultiMesh`: `var mi := (load(path) as PackedScene).instantiate().get_child(0) as MeshInstance3D` →
  `mi.mesh` (poner el `ShaderMaterial` del mundo como `material_override` del `MultiMeshInstance3D`; el shader lee
  `AO = COLOR.a`). Godot genera LODs al importar (índices medidos: `pine_d` 1143 → 433/183/7, `birch` 2110 → 1044/522/
  195/80/23, rocas 1 nivel, nieve 3 niveles); en `MultiMesh` el LOD se elige por la AABB de todo el `MultiMesh`: usar
  multimeshes por chunk (no por mundo) para que actúe.
- **Proxy de colisión por variante** (el código crea la forma; §15): en los *extras* del `MeshInstance3D`
  (`mi.get_meta("extras")`) y en `vegetation/manifest.json` / `props/manifest.json` (mismas claves + `path`, `node`,
  `tris`). Claves: `family` (`pine|dead_tree|birch|bush|rock|snow|log|ice`), `height` (m, cima), `radius` (m, radio de
  huella para el espaciado Poisson), `col` (`cylinder|sphere|box|none`), `col_center` [x, y, z] (centro de la forma,
  marco Godot local), `col_size` (`cylinder` [radio, alto] vertical; `sphere` [radio]; `box` [x, y, z]; `none` []),
  `choppable` (1 = acción `chop` con hacha como `ChoppableTree`: árboles y troncos).

| Asset | Nodo | Tris | Alto | Radio huella | Proxy (`col`, centro, tamaño) | chop | Qué es |
|---|---|---|---|---|---|---|---|
| `pine_d` | Tree | 1 143 | 8.97 | 2.13 | cylinder (0, 1.5, 0) r 0.33 h 3.0 | 1 | abeto muy alto 9 m, 8 pisos, poca nieve |
| `pine_e` | Tree | 1 191 | 7.07 | 2.14 | cylinder (0, 1.5, 0) r 0.32 h 3.0 | 1 | doble copa (guía bifurcada a 4.2 m) |
| `pine_f` | Tree | 873 | 6.15 | 1.80 | cylinder (0, 1.5, 0) r 0.29 h 3.0 | 1 | cargado de nieve (puntas caídas, capa 14 cm hasta las puntas) |
| `pine_young` | Tree | 621 | 2.58 | 0.84 | cylinder (0, 0.8, 0) r 0.135 h 1.6 | 1 | abeto joven 2.5 m |
| `dead_tree_b` | Tree | 1 026 | 5.57 | 1.10 | cylinder (0, 1.5, 0) r 0.40 h 3.0 | 1 | tocón alto partido (copa astillada, ramas rotas) |
| `dead_tree_c` | Tree | 2 529 | 3.47 | 1.35 | cylinder (0, 1.0, 0) r 0.25 h 2.0 | 1 | árbol seco pequeño de 3 troncos |
| `birch` | Tree | 2 110 | 7.42 | 2.08 | cylinder (0, 1.5, 0) r 0.24 h 3.0 | 1 | abedul desnudo (corteza `paint_white` con bandas) |
| `bush_a` | Bush | 545 | 0.85 | 0.85 | sphere (0, 0.35, 0) r 0.50 | 0 | enebro perenne con nieve |
| `bush_b` | Bush | 567 | 0.89 | 0.67 | sphere (0, 0.38, 0) r 0.45 | 0 | acebo oscuro **con bayas rojas horneadas** (ver M3.3) |
| `rock_d` | Rock | 342 | 0.62 | 1.49 | box (0, 0.25, 0) 2.3 × 0.5 × 1.5 | 0 | losa inclinada 2.4 × 1.6 m |
| `rock_e` | Rock | 652 | 2.40 | 1.97 | box (0, 1.0, 0) 3.0 × 2.0 × 2.3 | 0 | afloramiento 3.4 × 2.7 × 2.3 m (hito) |
| `rock_f` | Rock | 439 | 0.50 | 0.95 | box (0, 0.2, 0) 1.6 × 0.4 × 1.2 | 0 | pedrera de 5 piedras |
| `snow_pile_a/b/c` | Snow | 144 / 198 / 84 | 0.54 / 0.76 / 0.29 | 0.98 / 1.53 / 0.58 | none | 0 | montones redondos (b: 3 lóbulos) |
| `snow_drift_4` | Snow | 476 | 0.46 | 2.02 | none | 0 | ventisquero de 4 m con cornisa (ver nota) |
| `fallen_log_b` | Log | 515 | 0.46 | 1.91 | box (0, 0.22, 0) 3.4 × 0.45 × 0.5 | 1 | tronco 3.4 m (testa serrada −X, astillada +X, musgo) |
| `fallen_log_c` | Log | 598 | 1.65 | 1.96 | box (0.25, 0.45, 0) 3.1 × 0.9 × 1.7 | 1 | árbol caído con **plato de raíces** vertical en −X |
| `icicles` | Icicles | 290 | 0.0 (cuelga) | 1.01 | none | 0 | tira de carámbanos de 2 m |

Notas: `snow_drift_4` es largo en X (±2 m) con la cara de sotavento y la cornisa hacia **−Z Godot** (+Y Blender); el
yaw por instancia la orienta según el viento. `icicles` es un asset **colgante** (§2.2): origen = centro de la línea
del alero **arriba** (y = 0), cuelga hasta y = −0.58; se repite cada 2 m a lo largo de un alero (volteo 180° libre).

### M3.3 Notas de uso para el código

- Talables por índice (`scatter_index`): todo `choppable = 1`. Sugerencia de `Balance`: `pine_young` y `dead_tree_c`
  dan la mitad de leña; `fallen_log_b/c` como `fallen_log` (`LOG_HITS`).
- `bush_b` se ve igual que un arbusto con bayas: si se esparce, que sea interactivo como `berry_bush` (sustituir la
  instancia por `berry_bush.tscn` al acercarse/al interactuar, igual que los árboles) o no mezclarlo cerca de
  `berry_bush`. `berry_bush` (nodo interactivo) sigue con su hijo `Berries`.
- Nieve (`snow_*`) y carámbanos: sin colisión (`none`), decorativos; no ponerlos sobre caminos/puertas.
- Presupuesto de bosque (vista típica a cámara por defecto: 49 pinos, 8 árboles desnudos + 4 abedules, 15 arbustos,
  11 rocas, 12 montones, 4 troncos, 3 tocones, `cabin_small`, 4 jugadores) = 104.5 k + reserva 93 k = **197.5 k**.

### M3.4 Props del claro rehechos en HD (mismos nombres, nodos, pivotes, anclas y tamaños ±10 %)

| Asset | Tris antes → ahora | Qué cambia |
|---|---|---|
| `signpost` | 130 → 522 | poste achaflanado con capuchón y nieve, listón bajo cada tablero, tableros con marco oscuro + cara clara embutida (cara de texto en y = −0.12 Blender), clavos, línea de nieve redondeada arriba de cada tablero, montículo al pie. `TextTop/TextBottom` iguales ((0.28, 0, 0.125) local, sin rotación); `BoardBottom` sigue girando sobre el eje del poste |
| `berry_bush` | 382 → 524 | lóbulos facetados irregulares `bush`/`pine_light`/`pine_mid` + penachos + casquetes de nieve suaves; `Berries` (hijo, pivote en el origen) = 16 bayas en 5 racimos |
| `fence` | 84 → 528 | postes achaflanados con remate piramidal y casquete de nieve, dos largueros algo irregulares con placas de clavos y línea de nieve, montículos al pie; largueros en +Y Blender como antes |
| `lantern` | 114 → 368 | anilla de gancho toroidal (cima en z = 0), tejadillo piramidal con respiradero de latón, postes, dos aros de alambre sobre el cristal, base con banda de latón; `Lantern` = `palette_vcol` + `window`, `LightAnchor` igual |
| `fallen_log` | 80 → 472 | tronco suave con testas serradas (anillos), dos muñones de rama, línea de nieve, pequeño ventisquero; 1.6 × 0.42 m (caja de `tree.gd` igual) |

### M3.5 POIs del bosque (estructura de corte v2, §8.4)

Reglas comunes (también para el kit, §M3.6): grupos de corte **de primer nivel** `Floor<k>`, `Walls<k>_{N,S,E,W}` y su
`Walls<k>_<dir>_Stub` (mismo contorno en planta, corte a 0.6 m del suelo de la planta), `Interior<k>`, `Roof`;
**extras**: todo grupo `cut_group` (= su nombre) y `floor` (int); `Floor<k>` además `floor_z` (altura del suelo
pisable, m). `Door_<n>`: hoja cerrada con el **origen en el eje de bisagra** (abre hacia dentro girando en Y), extras
`kind` (`door`), `exterior` (bool), `cut_group` (fachada a la que pertenece), `floor`, `hinge` (`L` = a la izquierda
vista desde fuera), `width`; **sin colisión** (el código pone la caja). `Window_<n>`: cristal (material `window`, dos
caras), extras `boarded` (false), `cut_group`, `floor`. **El código debe ocultar `Door_n`/`Window_n` junto con su
`cut_group`** cuando sustituye esa fachada por su `_Stub`. `Spawn_<Kind>_<n>`: empties con **solo yaw** (su +Z local
= frente del objeto que se instancia), extras `kind` y `table` (contenedores). `Col*-convcolonly`: cajas convexas de
primer nivel; las escaleras son **rampas** (cuñas de 6 vértices). La AO de los `_Stub` se hornea con los muros
completos y el tejado ocultos; los cristales llevan AO constante 0.98 (el material `window` no la usa).

**`poi/cabin_small.glb`** — cabaña de tronco del trampero, 5 × 5 m (muros exteriores ±2.5), suelo a y = 0.30, frente
+Z con porche de 1.3 m bajo el alero (6.7 × 8.1 × 5.0 m, **11 842 tris**, 15 superficies; visibles 11 sin stubs).
Nodos: `Floor0` (zócalo de piedra, suelo de tablas, porche, postes de tronco, escalón, leñera, ventisqueros),
`Walls0_S/N/E/W` (+ `_Stub`; las testas de las esquinas van con S/N), `Interior0` (mesa, taburete, estante con
tarros, alfombra de piel, leñero), `Roof` (tejado a dos aguas de tablillas, hastiales, chimenea de estufa, nieve con
cornisa, carámbanos), `Door_0` (origen (−0.48, 0.30, 2.39), `cut_group` `Walls0_S`), `Window_0` (E), `Window_1` (N),
`Window_2` (W), `DoorAnchor` (0, 0.30, 3.05) en el porche. Spawns (posición; yaw): `Spawn_Stove_0` (−1.55, 0.30,
−1.45; 90), `Spawn_Bed_0` (1.45, 0.30, −1.20; 0), `Spawn_Container_0` (1.95, 0.30, 1.20; −90; `table`
`cabin_forest`), `Spawn_Light_0` (0, 2.65, 0), `Spawn_Loot_0` (−0.65, 1.07, 0.92), `Spawn_Zombie_0` (0.30, 0.30, −0.30;
−160). Colisión: `ColFloor0`, `ColPorch`, `ColSteps` (rampa), `ColWalls0_S_0/1/2` (hueco de puerta), `ColWalls0_N_0`,
`ColWalls0_E_0`, `ColWalls0_W_0` (ventanas de 0.8 × 0.7: macizas), `ColPostL/R`, `ColWoodpile`.

**`poi/lookout_tower.glb`** — torre de vigilancia de madera (6.9 × 6.9 × 13.9 m con escaleras, **9 231 tris**, 18
superficies). Cuatro patas inclinadas sobre zapatas, arriostrado en X, **4 tramos de escalera exteriores** (13
peldaños 0.177 × 0.37, 0.9 m de ancho; S → W → N → E, rellanos en las esquinas) hasta un rellano en L que entra por el
borde S de la pasarela; plataforma a **y = 9.20** (4.4 × 4.4, barandilla 1.05), caseta acristalada 3.2 × 3.2 (muros
9.2–11.4), tejado a cuatro aguas con pararrayos hasta 13.65. Nodos: `Floor0` (zapatas, patas, arriostrado, escaleras,
rellanos; `floor_z` 0), `Floor1` (plataforma, pasarela, barandilla; `floor_z` 9.2), `Walls1_S/N/E/W` (+ `_Stub`),
`Interior1` (buscador de incendios con mapa, taburete, catre, estante), `Roof`, `Door_0` (fachada E, origen (1.48, 9.20,
0.43), `cut_group` `Walls1_E`), `Window_0` (N), `Window_1`/`Window_2` (E, a los lados de la puerta), `Window_3` (S),
`Window_4` (W); anclas `DoorAnchor` (1.90, 9.20, 0), `StairFoot` (2.90, 0, 2.85) (pie del primer tramo),
`ViewAnchor` (0, 10.90, 0) (altura de ojos en la caseta: acción "otear"/revelar mapa). Spawns: `Spawn_Radio_0` (0,
10.10, −1.24; 180), `Spawn_Loot_0` (0.20, 10.13, 0), `Spawn_Container_0` (−1.0, 9.2, −1.05; 180; `table` `lookout`),
`Spawn_Bed_0` (−0.95, 9.2, 0.40; 90), `Spawn_Light_0` (0, 11.2, 0). Colisión (31): `ColFooting_0..3`, `ColLeg_0..3`
(cajas inclinadas), `ColStair_0..3` (**rampas**), `ColStairRail_0..3` (barandilla exterior de cada tramo),
`ColLanding_0..3`, `ColFloor1`, `ColRail1_N/S/E/W` (la S se corta en el rellano), `ColWalls1_N/S/W`,
`ColWalls1_E_0..2` (hueco de puerta). Navegación: las rampas + rellanos + `ColFloor1` forman un camino continuo del
suelo a la puerta (pendiente 25.6°).

**`poi/campsite_remains.glb`** — restos de acampada (la tarea lo llama *camp_remains*; el nombre de contrato es
`campsite_remains`), 6.7 × 4.7 m, **3 064 tris**: tienda de lona oliva derrumbada con un mástil aún en pie, anillo de
fuego frío (piedras, tizones, ceniza, nieve dentro) con trípode y olla, dos cajas (una cerrada con nieve, otra rota con
la tapa apoyada), banco de tronco, lata. Nodos: **una sola malla `Remains`** (1 superficie: también vale como
instancia de `MultiMesh` si se ignora el resto), `FlameAnchor` (1.05, 0.18, 0.55) (se puede reencender como
`campfire`), `Spawn_Container_0` (2.25, 0, −1.25; 12; `table` `campsite`), `Spawn_Loot_0` (caja rota),
`Spawn_Loot_1` (bajo la lona); colisión `ColCrate_0`, `ColCrate_1`, `ColBench`, `ColTent`.

Tablas de botín nombradas (`cabin_forest`, `lookout`, `campsite`, `house_kitchen`): propuestas de arte; las crea el
código en `data/loot/loot_tables.gd` (M5).

### M3.6 Kit de edificios — arranque (M6a)

- **`blender/lib/kit.py`** (compartido): rejilla 2 m, planta 3.0 m (muro 2.8 + forjado 0.2), cimiento 0.3, muros 0.2
  centrados en la línea de rejilla, tabiques 0.12, puerta 1.0 × 2.2, ventana 1.2 × 1.2 (alféizar 0.9), `_Stub` 0.6,
  tejado a dos aguas 35° con vuelo 0.4. **Módulos** (se escriben en el constructor de su grupo de corte y se fusionan
  al final, nunca se exportan sueltos): `Wall_2`, `Wall_Window_2`, `Wall_Door_2` (+ `_Stub`), `Corner_Out` (con la
  fachada S/N), `Floor_2x2`, `Foundation_Skirt_2`, `Roof_Gable_2`, `Roof_Gable_End`, `Porch_2x2`, `Porch_Roof_2`,
  `Stair_Porch`, `Chimney`, `IWall_2`, `IWall_Door_2`. **Estilos**: `wood_blue` (tablilla solapada `cabin_wall` como
  lámina en diente de sierra, molduras crema, tejado de junta alzada) y `brick` (hiladas, dintel/alféizar/zócalo de
  hormigón, cadenas de esquina, tejado de tejas).
- **Plantilla** (formato ampliado de §8.3): `blender/kits/templates/house_small_A.json` (`footprint` [8, 10],
  `floors`, `doors`/`windows` = muro del lado `dir` de la celda `pos` [i, j] con la celda (0, 0) al SO,
  `partitions` [{`axis`, `at`, `from`, `to`, `doors`}], `roof`, `porch.cells`, `chimney.pos/offset`, `furniture`
  decorativo, `spawns` en metros desde la esquina SO). La copia del código (`data/buildings/templates/`) es del agente
  de código; los `.glb` no dependen de ella en tiempo de ejecución.
- **`buildings/{wood_blue,brick}/house_small_A.glb`** (8 × 10 m, 1 planta, porche, tabique con puerta, chimenea):
  **12 142 / 12 296 tris**, 21 superficies (17 visibles: los `_Stub` están ocultos por defecto). Nodos: `Floor0`,
  `Walls0_S/N/E/W` (+ `_Stub`), `Interior0`, `Roof`, `Door_0` (exterior, S, origen (0.52, 0.30, 4.97)), `Door_1`
  (interior, `cut_group` `Interior0`), `Window_0..7`, `Spawn_Container_0` (`house_kitchen`), `Spawn_Stove_0`,
  `Spawn_Bed_0`, `Spawn_Furniture_0` (`furniture` `wardrobe`), `Spawn_Light_0/1`, `Spawn_Loot_0`, `Spawn_Zombie_0`;
  colisión (36): `ColFloor0`, `ColWalls0_<dir>_<n>` (troceados alrededor de puertas **y ventanas**: las ventanas
  quedan abiertas para entrar por una rota; el código pone la caja de `Window_n` como la de `Door_n`),
  `ColIWalls0_<p>_<n>`, `ColPorch`, `ColSteps` (rampa).
- `verify_kits.py` reconstruye cada plantilla en memoria y compara con el `.glb`: nodos esperados, contorno de los
  `_Stub`, extras, **cajas de colisión exactas (±0.02 m)**, puerta exterior en S, `Roof` sin muros, presupuesto 14 k,
  ≤ 20 superficies visibles.
- **Falta para M6a**: estilos `concrete` y `sheet_metal`; `Wall_1`, `Wall_DoubleDoor_2`, `Wall_Shop_4`,
  `Wall_Garage_4`, `Wall_Broken_2`, `Wall_Boarded_2`, `Corner_In`, `Post`; plantas altas (`Floor_Stair_Opening_2x6`,
  `Stair_2x6`, `Stair_Exterior_2x6`) y el esquema `Walls1_*` en casas de 2 plantas; tejados a cuatro aguas / planos
  (`Roof_Hip_Corner`, `Roof_Flat_2x2`, `Parapet_2`), `Awning_4`, `Shutter`, `Planks`; mobiliario §9 como
  `Spawn_Furniture`; las demás plantillas de §8.5; baldosas de carretera (§10).

### M3.7 Desviaciones y notas

1. Nombres: 3 pinos nuevos = `pine_d`, `pine_e`, `pine_f` + abeto joven `pine_young`; 2 árboles secos =
   `dead_tree_b`, `dead_tree_c` + `birch` (§13); 4 de nieve (`snow_pile_a/b/c`, `snow_drift_4`); troncos
   `fallen_log_b/c` + `fallen_log` rehecho en HD; carámbanos `props/icicles`. `campsite_remains` va en `poi/` (lleva
   colisión y spawns) aunque su malla única cumple la regla MultiMesh.
2. Presupuestos v2.1 comprobados sin holgura: pino 1 200 (joven 800), árbol desnudo 2 600, arbusto/roca 700, nieve 500,
   tronco 700, carámbanos 300, POI 14 000, campamento 4 000, casa del kit 14 000; props HD del claro: `signpost` 700,
   `fence` 600, `lantern` 400, `berry_bush` 700, `fallen_log` 500.
3. `lib/export.py`: los empties `Spawn_*` pueden llevar yaw (única excepción nueva a "rotación 0"); `save_and_export`
   acepta `blend_name` (una `.blend` por plantilla × estilo: `sources/house_small_A__wood_blue.blend`) e
   `import_kind`. Librerías nuevas: `lib/veg.py` (generadores de vegetación compartidos; los G1 salen idénticos),
   `lib/kit.py`; `lib/hd.py` gana `snow_ridge`/`snow_cone_cap` (nieve barata para listones y postes) y
   `bake_ao(exclude=…)`.
4. **Sin caras traseras visibles** (regla nueva de M3, comprobada por `verify_assets.py`/`verify_kits.py`,
   `backface_problems`): rayos ortográficos desde la cámara del juego (pitch 48°, 8 yaws) y a 25° no pueden dar primero
   en una cara trasera (tubos o conos abiertos, caras volteadas o plegadas, superficies coplanarias solapadas). En
   Godot los `.glb` llegan con `palette`/`window` de doble cara (`cull_mode` DISABLED: una cara trasera se vería oscura),
   pero `Assets.spawn_model` los cambia por `world_vcol.gdshader` (`cull_back`: la cara trasera sería un agujero).
   Arreglos de M3 (librería): `hd.pillow_cage` orienta las caras laterales por el borde de la jaula (antes las
   esquinas de almohadas largas —barandillas, pasarelas— salían volteadas), `hd.tube` realinea los anillos (sin
   pajarita donde el tubo pasa por la vertical), `pillow(keep_bottom=…)` cierra la cornisa que vuela sobre el alero,
   la cornisa superior ondulada ya no se pliega, carámbanos con la base cerrada, láminas de tejas/tablillas cerradas en
   los hastiales, escalón superior de la torre fusionado con el rellano. Estos arreglos también tocan (sin cambiar
   contrato, nodos ni tamaños ±1 %) `cabin` (22 418 → 22 406 tris), `a_frame_cabin` (9 614 → 9 616), `dead_tree`,
   `pickup_truck` y `chars/survivor_*` (mismos tris, anillos reindexados). **Pendiente (G1, fuera de M3)**: `cabin` y
   `pickup_truck` aún muestran caras traseras en ángulos bajos (tejado, ruedas/carrocería); no están bajo la regla.
