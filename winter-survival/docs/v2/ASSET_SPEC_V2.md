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

`Assets.spawn_model` sustituye el material `palette_vcol` por el `ShaderMaterial` compartido del juego; las excepciones se mantienen.

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
