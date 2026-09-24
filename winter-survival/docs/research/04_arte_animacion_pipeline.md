# 04 — Arte 3D, personajes, animación y kits modulares (pipeline)

> Proyecto: VENTISCA → juego de mundo abierto, invierno post‑apocalíptico con zombis, co‑op 1–4 (PvP opcional).
> Motor **Godot 4.7.2**; arte 100 % procedural con **Blender 5.0.1 como módulo Python** (`import bpy`, sin GUI).
> Fecha: 2026‑09‑24. Estado: **recomendación cerrada + prueba de concepto (PoC) ejecutada y verificada** (§13).
> Decisiones de usuario ya fijadas: cámara alta tipo isométrica (~50° de inclinación, 15–30 m) → sin modelos de
> 1.ª persona, legibilidad de silueta antes que detalle facial/dedos; multijugador co‑op 1–4 con PvP opcional.
> Coherente con `01_mundo_abierto_tecnologia.md` (chunks de 64 m, Forward+ con respaldo Compatibility, vehículos
> `RigidBody3D` + suspensión por raycast), `02_jugabilidad_zombies_armas.md` (tipos de zombi, armas, vehículos) y
> `03_multijugador_servidores.md` (servidor autoritativo, snapshots de zombis con `state` de 1 byte).

---

## 0. Resumen ejecutivo — la pipeline que recomiendo

| Tema | Decisión | Evidencia |
|---|---|---|
| Animación de personajes | **Esqueleto real (Skeleton3D + skin)** para jugador, NPC y zombis. Las piezas rígidas animadas por código se quedan solo en lo que ya existe hasta migrarlo (lobo/ciervo en fase 2). | PoC: humanoide + 5 acciones generado en 1.2 s, importado y renderizado en Godot 4.7.2 sin errores. |
| Esqueleto | **22 huesos con los nombres exactos de `SkeletonProfileHumanoid`** (`Root, Hips, Spine, Chest, Neck, Head`, `Left/Right Shoulder, UpperArm, LowerArm, Hand`, `Left/Right UpperLeg, LowerLeg, Foot, Toes`) + huesos‑socket no deformantes (`RightHandSocket`, …). Pose de reposo en **T**. Sin dedos ni cara. | Los 17 huesos obligatorios del perfil presentes; BoneMap identidad aceptado por el importador (0 errores). |
| Orientación | **Frente = −Y en Blender = +Z glTF = +Z Godot = `Vector3.MODEL_FRONT`** para personajes, vehículos y armas nuevos (el slice usaba +Y). | glTF 2.0: "the front of a glTF asset faces +Z"; `SkeletonProfileHumanoid` mira a +Z; `VehicleBody3D` usa `MODEL_FRONT`. |
| Skinning | **Rígido por pieza** (cada vértice 100 % a un hueso), piezas solapadas en las articulaciones (mangas abullonadas, puños). Pesos mezclados solo en ropa continua (abrigos), calculados por script. **No** `ARMATURE_AUTO`. | `ARMATURE_AUTO` funciona en modo background pero en nuestras mallas por piezas deja **10 % de vértices sin peso** y solo **63 %** asigna el hueso correcto. |
| Autoría de animación | **Generador cíclico por script** (trayectoria de pies anclada al suelo + IK analítica de 2 huesos) para toda la locomoción; **poses clave + interpolación Bézier** para acciones; **Quaternius UAL 1/2 (CC0)** retargeteado para lo difícil (trepar, arrastrarse, conducir, muertes elaboradas). Mixamo no. | PoC: pie de apoyo a 0.087 m (reposo 0.09) y velocidad de apoyo **1.61 m/s** para una Walk autorada a 1.6 m/s → cero deslizamiento. |
| Exportación | Una `.glb` por **personaje** (malla + esqueleto, sin animaciones) y una `.glb` por **set de animaciones** (solo armature + acciones), `export_animation_mode='ACTIONS'`, 30 fps, bucles con sufijo **`-loop`**. | `Idle-loop` → `Idle` con `LOOP_LINEAR`; `Attack` → `LOOP_NONE`; duraciones exactas (3.0/1.0/0.7/1.6/0.9 s). |
| Importación | Sets como **`AnimationLibrary`** con `BoneMap` identidad (`humanoid_bonemap.tres` generado por script) + *Overwrite Axis* + *Normalize Position Tracks* + *Unique node `GeneralSkeleton`*. **Nunca activar "Except Bone Transform"** (bug #123782, reproducido: borra todas las pistas de rotación). | Zombi con piernas 6 % más largas: sin retarget los pies se hunden 5 cm (tobillo a 0.039 m); con retarget 0.087 m. |
| Runtime | `AnimationTree`: StateMachine (Locomoción/Agachado/Conducir/Caído/Muerto) → BlendSpace2D con **sync `CYCLIC_MUTABLE`** + capa de torso filtrada (Blend2/OneShot con filtros) + Add2 para golpes; IK de 4.6+ (`TwoBoneIK3D`, `LookAtModifier3D`); ragdoll con `PhysicalBoneSimulator3D`; armas con `BoneAttachment3D` sobre hueso‑socket. | PoC: piernas caminando + hachazo solo en el torso; ragdoll cae de 0.90 a 0.20 m; hacha correctamente agarrada. |
| Movimiento | **In‑place, sin root motion.** La cápsula la mueve el código (servidor autoritativo); velocidad de reproducción = v_real / v_autorada (calibrada por personaje). | La animación es cosmética: nada que desincronizar en red. |
| Materiales | **1 material por malla con color de vértice** (paleta horneada en `COLOR_0`); materiales aparte solo para casos especiales (`window` emisivo, cristal, `ember`). | PoC: 40 personajes = **960 draw calls** con 8 materiales vs **120** con color de vértice (×8). |
| Kit de edificios | **Rejilla 2 m, planta 3 m, muro 0.2 m.** Modular *en el generador*, **fusionado al exportar** por grupos de corte (planta × fachada). | La cabaña actual tiene **34 superficies** (≈ 100 draw calls por instancia con sombras, a 3 por superficie como se midió); un pueblo así no escala. |
| LOD | **No autorar LODs.** Auto‑LOD por defecto (inocuo), `visibility_range_end` para clutter y para el anillo de precarga; sombras desactivadas en props pequeños. | La cámara nunca ve más de ~45 m; el auto‑LOD apenas reduce mallas low‑poly planas (medido). |
| Vehículos | Frente −Y, ruedas separadas con pivote en el eje, anclas de asientos/luces/salidas; **física ensamblada en código** (doc 01: `RigidBody3D` + raycast), sin sufijos `-vehicle/-wheel`. | Probado: `-wheel` crea `VehicleWheel3D` con radio 0.5 por defecto y `-convcolonly` crea un `StaticBody3D` *dentro* del vehículo (incorrecto). |
| Armas | Origen en la empuñadura; **mango = +Z Blender**, **extremo útil (filo/boca) = −Y Blender** (= dirección del antebrazo); anclas `Muzzle`, `SupportGrip`, `Magazine`, `EjectPort`, `Holster`. Un único modelo (mano + suelo), sin 1.ª persona; armas pequeñas ×1.2 de escala. | PoC: `stone_axe.glb` del slice encaja con identidad en `RightHandSocket`. |

---

## 1. Contexto y restricciones que mandan

1. **Cámara** (decisión de usuario, alineada con `ARCHITECTURE.md`: pitch −52°, FOV 35°, 14–30 m). A 22 m un humano de
   1.8 m ocupa ≈ 90 px de alto en 1080p (≈ 75 px en la captura de 860 px `godot/shots/game_view_dist22.png` del
   PoC); a 14 m ≈ 140 px. Consecuencias:
   - Se leen **silueta, postura y ritmo**; no se leen dedos, caras ni *lip‑sync*. → Sin huesos de dedos/cara.
   - Las poses deben **exagerarse** (anticipación del golpe, brazos del zombi, encorvamiento) y los objetos en mano
     necesitan tamaño y contraste (§11).
   - Vista cenital: los **hombros, cabeza y brazos** son lo más visible; las piernas se ven en escorzo.
   - Nunca se ve más allá de ~45 m desde la cámara: el LOD geométrico apenas aporta; lo caro son **draw calls**.
2. **Co‑op 1–4 + PvP opcional, servidor autoritativo** (doc 03): la animación es 100 % cosmética en cliente, derivada
   de estado replicado (velocidad, yaw, apuntado, `state` u8 de zombis, eventos). Los golpes/impactos se resuelven con
   cápsulas y ventanas de tiempo en el servidor, nunca con la malla animada (§5.7).
3. **Estilo** (capturas de referencia): low‑poly facetado, colores planos saturados sobre nieve azulada, siluetas
   "de juguete" gruesas, interiores con corte (cutaway). El PoC reutiliza `lib/lowpoly.MeshBuilder` y la paleta para
   que los personajes nuevos casen con los 33 assets existentes.
4. **Todo por script, reproducible y verificable**: nada de pintar pesos a mano, nada de GUI. Cada familia de assets
   tiene generador + verificador (como hoy `verify_assets.py`).

---

## 2. Pipeline recomendada (vista general)

```
blender/
  lib/  palette.py  lowpoly.py  export.py         (existentes; se amplían: vcol, armature, actions)
  lib/  rig.py        ← esqueleto humanoide/cuadrúpedo, sockets, skin rígido      (nuevo, base: PoC build_humanoid.py)
  lib/  anim.py       ← ActionWriter (Blender 5.0), generador de marcha, poses clave, IK analítica   (nuevo)
  chars/build_<char>.py   → assets/chars/<char>.glb         malla + esqueleto (SIN animaciones)
  anims/build_<set>.py    → assets/anims/humanoid_<set>.glb solo armature + acciones  (locomotion, melee, firearms, zombie…)
  kits/build_<kit>.py     → assets/buildings/<edificio>.glb  fusionado por grupos de corte + Col*
  vehicles/, weapons/, props/ ...
  verify_*.py             re-import + contratos (nombres, huesos, bucles, duraciones, pies en el suelo, presupuestos)

Godot 4.7.2
  assets/rig/humanoid_bonemap.tres     ← generado por script (identidad perfil → nuestros nombres)
  *.glb de personaje   → import "Scene"  + retarget (BoneMap, GeneralSkeleton)          → Modelo
  *.glb de animaciones → import "AnimationLibrary" + retarget (mismas opciones)          → .res compartidas
  character_visual.tscn = Modelo + AnimationPlayer(libs: loco, melee, guns, zombie…) + AnimationTree
                          + modificadores (IK, LookAt, SpringBone) + BoneAttachment3D(sockets) + PhysicalBoneSimulator3D
```

Tiempo medido del PoC (4 CPU): generar 3 modelos + 5 acciones y exportar: **1.2 s**; importar en Godot: **3.4 s**;
suite completa (build + import + verificaciones + 18 renders): **≈ 25 s** (`run_poc.sh`).

---

## 3. Convenciones nuevas (enmienda propuesta a `ASSET_SPEC.md` para el mundo abierto)

| Convención | Slice actual | Mundo abierto (propuesta) | Motivo |
|---|---|---|---|
| Frente | +Y Blender (= −Z Godot) | **−Y Blender (= +Z glTF/Godot, `MODEL_FRONT`)** para todo lo nuevo; migrar lo existente con una rotación de 180° en `to_object` y en el código usar `look_at(target, UP, true)` / `-MODEL_FRONT` | glTF, perfil humanoide, retarget de librerías externas y `VehicleBody3D` asumen +Z. Mezclar convenciones en personajes rompe el *Rest Fixer*. |
| Derecha del personaje | +X | **−X** (izquierda = +X), consecuencia del punto anterior | Igual que el perfil (`LeftUpperLeg` en +X). |
| Color | 1 material por color de paleta (multi‑surface) | **`COLOR_0` por esquina (paleta horneada) + 1 material** `palette_vcol`; excepciones con nombre: `window`, `glass`, `ember`, `ice_clear` | ×8 menos draw calls (medido). Godot activa *albedo from vertex color* solo si la primitiva trae `COLOR_0` (verificado en `gltf_document.cpp`). |
| UV / texturas | prohibidas | Siguen prohibidas en v1 (la paleta vive en el color de vértice). | Mantener el estilo y la sencillez; sin mipmaps ni atlas. |
| Esqueletos | prohibidos | Humanoide 22 huesos + sockets; cuadrúpedo propio (fase 2) | §4. |
| Animación | procedural en código | Acciones de Blender exportadas, 30 fps, in‑place | §4–5. |
| Nombres | ASCII `[A-Za-z0-9]` | Igual; **acciones** `Set_Accion[_Variante][-loop]` (p. ej. `Loco_Walk-loop`, `Melee2H_Swing_A`, `Zombie_Shamble_B-loop`) | El sufijo `-loop`/`_loop` activa `LOOP_LINEAR` y se elimina del nombre (verificado). |
| Sockets de mano | Empty `ToolSocket` con rotación | **Hueso no deformante** `RightHandSocket`/`LeftHandSocket`/`BackSocket`/`HipSocket`/`HeadSocket` | `BoneAttachment3D` con identidad; sobrevive al retarget (hueso no mapeado se conserva). |
| Colisión de edificios | cajas `Col*-convcolonly` sueltas | Igual para muros; **una malla `Col<Grupo>-colonly` (trimesh) por edificio** para geometría estática compleja | Menos cuerpos estáticos por edificio; Jolt maneja bien trimesh estático (doc 01). |

---

## 4. Personajes esqueléticos generados con bpy

### 4.1 Esqueleto humanoide

| Hueso | Padre | ¿Obligatorio en el perfil? | Uso |
|---|---|---|---|
| `Root` | — | no (es el `root_bone` del perfil) | En el suelo, estático (in‑place). Reservado para root motion futuro. |
| `Hips` | Root | **sí** (`scale_base_bone` → `motion_scale`) | Pelvis; única pista de **posición** (bote de la marcha). |
| `Spine`, `Chest` | Hips / Spine | Spine **sí**, Chest no | Torsión de apuntado (modificadores), respiración. |
| `Neck`, `Head` | Chest / Neck | Head **sí** | `LookAtModifier3D`. |
| `Left/RightShoulder` | Chest | **sí** | Clavícula (encoger hombros). |
| `Left/RightUpperArm`, `LowerArm`, `Hand` | cadena | **sí** | `TwoBoneIK3D` para la mano de apoyo / volante. |
| `Left/RightUpperLeg`, `LowerLeg`, `Foot` | Hips → cadena | **sí** | Generador de marcha. |
| `Left/RightToes` | Foot | no | Despegue de punta. |
| `RightHandSocket` (+ `LeftHandSocket`, `BackSocket`, `HipSocketR`, `HeadSocket`) | Hand/Chest/Hips/Head | — (no deformante, no mapeado) | Armas, linterna, casco, mochila. |

Total PoC: 23 huesos (22 + socket). `SkeletonProfileHumanoid` tiene 56 huesos, 17 obligatorios (consultado en
`ClassDB` de 4.7.2: `Hips, Spine, Head`, hombros, brazos, manos, piernas y pies); los 34 restantes (dedos, ojos,
mandíbula, `UpperChest`) se omiten a propósito. Pose de reposo **T** ("the humanoid is T‑pose… facing +Z"), rodillas y
codos rectos. Roll determinista: eje Z de cada hueso vertical hacia delante (−Y), de los horizontales hacia arriba;
así todos nuestros personajes tienen reposos idénticos en orientación y las pistas de rotación son compartibles
incluso sin retarget (solo cambia la posición de `Hips`, ver §5.2).

### 4.2 Construcción por script (Blender 5.0.1, modo background)

```python
arm = bpy.data.armatures.new("Armature"); obj = bpy.data.objects.new("Armature", arm)
bpy.context.scene.collection.objects.link(obj); bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode='EDIT')                      # funciona en background con objeto activo
for name, parent, head, tail in BONES:                    # posiciones de articulación en T-pose (parametrizadas)
    b = arm.edit_bones.new(name); b.head, b.tail = head, tail
    b.align_roll(Vector((0, -1, 0)) if vertical(b) else Vector((0, 0, 1)))
    b.parent = arm.edit_bones.get(parent); b.use_connect = False; b.use_deform = name != "Root"
bpy.ops.object.mode_set(mode='OBJECT')
```
Las posiciones salen de una función `joints(params)` (altura, largo de pierna/torso/brazo, anchura), de modo que
**todos los humanoides (jugador, NPC, 8 tipos de zombi) comparten nombres, jerarquía y orientación de reposo** y solo
cambian proporciones. Código completo: `animpoc/build_humanoid.py` (`joints`, `build_armature`).

### 4.3 Skinning: opciones y datos

| Opción | Cómo | Resultado medido / valoración | Veredicto |
|---|---|---|---|
| **Rígido por pieza** | Cada pieza del `MeshBuilder` se construye "para" un hueso; se fusionan en una malla `Body` y cada vértice va 100 % a su grupo (`vertex_groups[b].add([i], 1.0, 'REPLACE')`). | Deformación perfecta en todos los renders; cero artefactos de "caramelo"; determinista; 0 trabajo manual. Las juntas se esconden solapando volúmenes (manga sobre antebrazo, puño de bota). | **Por defecto.** Encaja con el estilo facetado. |
| Híbrido por anillos | Rígido + anillos de vértices cerca de la articulación con pesos 50/50 (o `smoothstep` a lo largo del eje), calculados por script. | No probado en el PoC; trivial de implementar sobre el anterior. | Para ropa continua (abrigos largos, faldones, bata de hospital, colas de bufanda). |
| `parent_set(type='ARMATURE_AUTO')` (bone heat) | Selección + armature activo + operador. | **Funciona en bpy background** (`{'FINISHED'}`, 0.01 s), pero en la malla por piezas: **48/476 vértices (10 %) sin peso**, 232 con varias influencias y solo **63 %** con el hueso dominante correcto. No imprime avisos en modo módulo. | **No usar** salvo mallas orgánicas continuas, y siempre con verificación automática (0 vértices sin peso). |

Desmembramiento "gore‑lite" gratis con skin rígido: escalar un hueso a 0 colapsa exactamente su pieza (§8.3).

### 4.4 Acciones por script en Blender 5.0 (API de *slotted actions*)

Blender 5.0 eliminó la API heredada `action.fcurves/groups/id_root` (release notes 5.0); las curvas viven en
`action.layers[].strips[].channelbag(slot)`. Lo más robusto es **insertar claves a través de los pose bones**: Blender
crea la capa, la tira, el *slot* y el channelbag solo.

```python
act = bpy.data.actions.new("Loco_Walk-loop"); act.use_fake_user = True
obj.animation_data_create(); obj.animation_data.action = act
pb = obj.pose.bones["LeftUpperLeg"]; pb.rotation_mode = 'QUATERNION'
r = obj.data.bones["LeftUpperLeg"].matrix_local.to_quaternion()
q = r.inverted() @ q_en_espacio_de_armature @ r           # autorar en ejes del mundo (T-pose), convertir a local
q.make_compatible(q_anterior)                              # evita saltos de hemisferio en la interpolación
pb.rotation_quaternion = q; pb.keyframe_insert("rotation_quaternion", frame=f, group=pb.name)
...
act.use_frame_range = True; act.frame_start, act.frame_end = 0, n
cb = bpy_extras.anim_utils.action_get_channelbag_for_slot(act, act.slots[0])   # sustituto de act.fcurves
for fc in cb.fcurves: [setattr(k, "interpolation", 'LINEAR') for k in fc.keyframe_points]
```
Convención de autoría del PoC: **rotaciones expresadas en los ejes del mundo de la T‑pose** y convertidas al espacio
local (`r⁻¹·q·r`); componen como FK normal y permiten razonar "pierna adelante = −X", "flexión de rodilla = +X",
"inclinar torso = +X", "bajar brazo izq. = +Y". Clase `ActionWriter` en `animpoc/build_humanoid.py`.

### 4.5 Generador de locomoción (lo que hace viable autorar ~40 ciclos sin animador)

Parámetros: `speed` (m/s), `period` (s), `duty` (fracción de apoyo), `lift` (altura de paso), `bob`, `drop` (pelvis),
`lean`, `arm_swing`, `elbow`, `limp` (cojera 0–1), `arms_forward`, `hunch`, `head_tilt`, `sway`.
Algoritmo por fotograma: (1) trayectoria del tobillo de cada pie — **en apoyo retrocede exactamente a `speed`**, en
vuelo describe un arco `sin^0.8`; pies desfasados 0.5; (2) pelvis con dos valles por ciclo; (3) **IK analítica de 2
huesos en el plano sagital** (ley de cosenos) → muslo y rodilla; (4) pie compensado para mantener su inclinación global
(talón → planta → punta); (5) torso: contra‑rotación, balanceo de brazos opuesto a la pierna, cabeza estabilizada.

| Ciclo del PoC | speed | period | duty | Medido en Godot (60 muestras) |
|---|---|---|---|---|
| `Walk-loop` | 1.6 m/s | 1.00 s | 0.62 | tobillo mín. 0.087 m (reposo 0.09), apoyo **1.61 m/s** |
| `Run_loop` | 4.0 m/s | 0.70 s | 0.38 (fase aérea) | tobillo mín. 0.081 m, apoyo **4.06 m/s** |
| `ZombieShamble-loop` | 0.8 m/s | 1.60 s | 0.70, cojera 0.8, brazos al frente | apoyo 0.84 m/s (zombi con piernas +6 %) |
| `Idle-loop` | — | 3.00 s | respiración + trasvase de peso, piernas por IK | — |

Velocidades de producción (doc 02): jugador andar 3.0 / correr 6.0 / agachado 1.5 m/s; caminante 1.2, corredor 5.5,
reptador 1.0. Se autoran **a esas velocidades** y el `AnimationTree` escala `TimeScale = v_real / v_autorada`.
Evolución prevista (no probada): para pasos laterales/atrás, IK 3D con polo, o bien *constraints* IK de Blender sobre
controladores animados por script y `bpy_extras.anim_utils.bake_action` (API Python, sin UI).

### 4.6 Acciones por poses clave

`Attack` del PoC = 5 claves (0 / 0.30 / 0.42 / 0.55 / 0.90 s): reposo → **anticipación** (hacha detrás de la cabeza,
torso girado atrás, muñeca en desviación cubital) → **impacto** (brazo al frente a la altura de la cintura, paso al
frente con piernas por IK) → seguimiento → recuperación, con la interpolación Bézier por defecto de Blender (el
exportador muestrea a 30 fps). Resultado legible también a 22 m (`closeup_iso.png`, `game_view_dist22.png`).
Regla de estilo para la cámara alta: **anticipación ≥ 0.25 s, impacto ≤ 0.12 s, pose de impacto exagerada un 20–30 %**.

### 4.7 Exportación glTF (opciones verificadas en el exportador de Blender 5.0.1, `io_scene_gltf2` 5.0.21)

```python
bpy.ops.export_scene.gltf(filepath=..., export_format='GLB', export_yup=True,
    export_apply=False,                       # con Armature no aplicar modificadores
    export_animations=True, export_animation_mode='ACTIONS',   # cada acción → una animación glTF
    export_force_sampling=True, export_frame_step=1, export_optimize_animation_size=True,
    export_anim_single_armature=True, export_reset_pose_bones=True, export_rest_position_armature=True,
    export_def_bones=False,                   # False: conserva los huesos-socket no deformantes
    export_leaf_bone=False, export_skins=True, export_morph=False,
    export_vertex_color='MATERIAL', export_all_vertex_colors=False,   # un solo COLOR_0
    export_materials='EXPORT', export_image_format='NONE', export_texcoords=False, export_normals=True)
```
- `export_animation_mode` admite `ACTIONS | ACTIVE_ACTIONS | BROADCAST | NLA_TRACKS | SCENE`; con `ACTIONS` no hace
  falta tocar la NLA (a diferencia de lo que sugiere la doc de Godot para el sufijo `loop`).
- Cada animación sale con traslación/rotación/escala de los 23 huesos (medido: ≈ 21 KB por segundo de animación a
  30 fps); Godot elimina las pistas inmutables al importar (quedan 1 posición + ~20 rotaciones). 120 acciones de
  ~1.2 s ≈ 3 MB de `.glb` fuente.
- Con `export_all_vertex_colors=True` (defecto) salen `COLOR_0` y `COLOR_1` duplicados: desactivarlo.

### 4.8 Organización de librerías

- `humanoid_locomotion.glb`: Idle, Walk, Jog/Run, Sprint, Crouch*, Strafe*, Back*, (8 direcciones × 2 velocidades).
- `humanoid_melee.glb`, `humanoid_firearms.glb`, `humanoid_actions.glb` (interactuar, comer, curar, vehículo, lanzar).
- `humanoid_zombie.glb` (se reproduce sobre los mismos humanoides).
- Cada `.glb` de animación se genera desde **un armature sin malla** (proporciones del jugador) → archivos pequeños.
- Eventos (sonido de pasos, "sale el cargador", ventana de daño del melee) **no viajan en glTF**: tabla de datos
  `anim_events.json` (`{"Rifle_Reload": {"mag_out": 0.35, "mag_in": 1.10}}`) aplicada como pistas de método por un
  `EditorScenePostImport` o leída por código. Las ventanas de daño de melee las usa **el servidor** (no la animación).

### 4.9 Root motion vs in‑place → **in‑place**

- La `CharacterBody3D` la mueve el código (predicción + reconciliación en cliente, autoridad del servidor; doc 03).
  Con root motion la posición dependería de la animación evaluada en cada máquina.
- Deslizamiento de pies evitado por construcción (generador) + `TimeScale` calibrado por personaje:
  `v_autorada_personaje = v_autorada × motion_scale_personaje / motion_scale_origen` (o medido al cargar, como hace
  `metrics.gd`: zombi 1.70 m/s en la Walk de 1.6 m/s del jugador).
- Estocadas, embestidas y tambaleos: desplazamiento por código con curva (p. ej. 1.5 m en 0.3 s), animación in‑place.
- `Root` se mantiene en el esqueleto (perfil + futuro), sin claves.

---

## 5. Lado Godot 4.7.2

### 5.1 Ajustes de importación

| Archivo | Importador | Opciones clave |
|---|---|---|
| `chars/<char>.glb` | `scene` | `nodes/use_node_type_suffixes=false` (personajes no llevan sufijos), `animation/import=false`, `meshes/generate_lods=true` (defecto), retarget igual que abajo (para que el esqueleto se llame `GeneralSkeleton` y tenga `motion_scale`). |
| `anims/humanoid_<set>.glb` | **`animation_library`** | `animation/fps=30`, `animation/remove_immutable_tracks=true`, `animation/import_rest_as_RESET=true` (pose RESET para el AnimationTree), retarget ↓. |
| retarget (ambos) | `_subresources.nodes."PATH:Armature/Skeleton3D"` | `retarget/bone_map=Resource("res://assets/rig/humanoid_bonemap.tres")`, `bone_renamer/unique_node/make_unique=true`, `skeleton_name="GeneralSkeleton"`, `rest_fixer/apply_node_transforms=true`, **`rest_fixer/retarget_method=1` (Overwrite Axis)**, `rest_fixer/normalize_position_tracks=true`, `remove_tracks/unimportant_positions=true`, **`remove_tracks/except_bone_transform=false`**, `remove_tracks/unmapped_bones=0`. |

El `.import` se puede escribir por script antes de la primera importación (el PoC lo hace) y el `BoneMap` se genera
con 10 líneas de GDScript (`make_bonemap.gd`: `BoneMap.new()`, `profile = SkeletonProfileHumanoid.new()`,
`set_skeleton_bone_name(n, n)`). El auto‑mapeo por regex del editor (`BoneMapper`) solo corre en la UI; con nombres
idénticos al perfil no hace falta.

**Bug confirmado en 4.7.2** (issue #123782): con *Except Bone Transform* activo el organizador de pistas mete en la
lista de borrado también las pistas de hueso mapeadas (y las de posición dos veces → errores `remove_track` fuera de
rango). En el PoC las animaciones quedaron con **1 pista** (solo `Hips` posición). Mantenerlo en `false`.

### 5.2 Compartir animaciones entre jugador, NPC y zombis (verificado)

| Caso | `motion_scale` | Tobillo mín. (Walk) | Resultado |
|---|---|---|---|
| `survivor.glb` con sus propias animaciones | 1.000 | 0.087 m | Referencia |
| `survivor_rt.glb` (retarget, Overwrite Axis) | 0.950 | 0.087 m | Idéntico al original: el *Rest Fixer* no rompe nuestro esqueleto ni el skin; el socket (hueso no mapeado) sigue en su sitio. |
| `zombie.glb` (+6 % piernas, −12 % anchura) con las animaciones del jugador **sin** retarget | 1.000 | **0.039 m** | Rotaciones correctas (mismos reposos), pero la pista absoluta de `Hips` deja los pies 5 cm bajo el suelo. |
| `zombie_rt.glb` + `survivor_lib.glb` (AnimationLibrary) **con** retarget | 1.000 | **0.087 m** | Correcto: posiciones normalizadas por altura de cadera y re‑escaladas por `motion_scale`. |

Rutas de pista resultantes: `%GeneralSkeleton:Hips` → cualquier escena con un `Skeleton3D` único llamado
`GeneralSkeleton` reproduce las librerías. Para librerías externas (Quaternius/KayKit) el flujo es el mismo con un
`BoneMap` propio de su esqueleto (auto‑mapeo en el editor, una vez) y *Overwrite Axis*; el método 2 ("Use Retarget
Modifier", `RetargetModifier3D`) queda como alternativa si un rig externo pierde calidad con *Overwrite Axis*.

### 5.3 AnimationTree de un humanoide

```
AnimationTree (root: AnimationNodeBlendTree)
└─ StateMachine "body"                               (travel por código desde el estado replicado)
   ├─ Locomotion  = BlendTree
   │    ├─ BlendSpace2D "move" (x = velocidad lateral local, y = frontal; puntos Idle(0,0), Walk ±3 m/s ×8 dir,
   │    │                        Run ±6 m/s ×8 dir; sync_mode = SYNC_MODE_CYCLIC_MUTABLE)
   │    ├─ TimeScale "stride"   (v_real / v_autorada)
   │    ├─ Blend2 "upper"       (filtro: Spine, Chest, Neck, Head, hombros, brazos, manos) ← pose de arma/apuntado
   │    │     └─ Transition "weapon_class" (Unarmed, Melee1H, Melee2H, Pistol, LongGun, Bow, Throwable, Carry)
   │    ├─ OneShot "action"     (filtro de torso: golpe, disparo, recarga, lanzar, beber…)
   │    └─ Add2 "hit"           (reacción aditiva corta, 0.25 s)
   ├─ Crouch (igual con BlendSpace de agachado)   ├─ Vehicle (Drive / Passenger / Shoot-from-vehicle)
   ├─ Downed (arrastrarse + revivir, co-op)       └─ Dead (dispara ragdoll; el árbol se desactiva)
```
- **Ocho direcciones con cámara cenital**: el cuerpo mira al cursor cuando se apunta (twin‑stick, doc 02 §4.1) y la
  velocidad se proyecta en ejes locales → BlendSpace2D; sin apuntar, mira hacia donde anda y basta el eje frontal.
- `sync_mode=CYCLIC_MUTABLE` (nuevo en 4.x: `NONE / INDEPENDENT / CYCLIC_MUTABLE / CYCLIC_CONSTANT`) alinea fases
  de Walk (1.0 s) y Run (0.7 s); nuestro generador empieza todos los ciclos con el pie izquierdo en contacto en t=0.
- Capas por **filtros** de nodo (`filter_enabled` + `set_filter_path("%GeneralSkeleton:Spine", true)`), probado en el
  PoC (`tree.gd`): BlendSpace1D Idle/Walk/Run + OneShot `Attack` filtrado al torso → las piernas siguen caminando
  mientras el torso da el hachazo (`shots/tree_walk_plus_attack_upperbody.png`).
- Por encima del árbol, en este orden como hijos del `Skeleton3D`: `LookAtModifier3D` (cabeza, con límites),
  `AimModifier3D`/`LookAtModifier3D` en `Chest` (torsión hacia el cursor ±60°), `TwoBoneIK3D` (mano de apoyo al
  `SupportGrip`, manos al volante), `SpringBoneSimulator3D` (cola de bufanda, mochila), `PhysicalBoneSimulator3D`.

### 5.4 Familia `SkeletonModifier3D` en 4.7.2 (lista real de `ClassDB`, no de memoria)

| Clase | Uso previsto | Prioridad |
|---|---|---|
| `TwoBoneIK3D` (IK nuevo desde 4.6, determinista, con polo) | Mano izquierda al guardamanos del rifle/escopeta; manos al volante/manillar; pies en pendiente (opcional) | P0 (armas largas) |
| `LookAtModifier3D` (límites de ángulo, suavizado `duration/transition`) | Cabeza hacia objetivo/cursor; zombis mirando a su presa | P0 |
| `AimModifier3D` (sobre `BoneConstraint3D`, simple, sin Euler) | Torsión de pecho hacia el apuntado | P1 |
| `CopyTransformModifier3D`, `ConvertTransformModifier3D` | Copiar giro de muñeca a un socket; mapear rotaciones | P2 |
| `LimitAngularVelocityModifier3D` | Suavizar torsiones bruscas del apuntado en red | P1 |
| `SpringBoneSimulator3D` (+ `SpringBoneCollision3D`) | Bufanda, colgantes, correas, mandíbula colgante de zombi | P2 |
| `PhysicalBoneSimulator3D` + `PhysicalBone3D` | Ragdoll de muerte, golpes fuertes (`influence` parcial) | P0 |
| `RetargetModifier3D` | Retarget en tiempo real (alternativa al *Overwrite Axis*) | Reserva |
| `ModifierBoneTarget3D` | Objetivo de IK = otro hueso | P2 |
| `CCDIK3D`, `FABRIK3D`, `JacobianIK3D`, `SplineIK3D`, `ChainIK3D`, `IterateIK3D`, `BoneTwistDisperser3D` | Colas, tentáculos, espina del reptador; `BoneTwistDisperser3D` no hace falta con skin rígido | P2 |
| `SkeletonIK3D` | Heredado (pre‑4.6); no usar | — |
| `XRBodyModifier3D`, `XRHandModifier3D` | XR, no aplica | — |

### 5.5 Ragdoll (verificado)

`PhysicalBoneSimulator3D` hijo del `Skeleton3D` y 12 `PhysicalBone3D` (cápsula por hueso, articulaciones cono en
hombros/caderas/cabeza/columna y bisagra en codos/rodillas), creados por código con la misma receta que el botón
"Create Physical Skeleton" del editor. `physical_bones_start_simulation()` desde la pose de Walk: la pelvis cae de
0.90 a 0.20 m en 2.5 s y la malla la sigue (`shots/ragdoll_after_2_5s.png`). Nota práctica: durante la simulación
`Skeleton3D.get_bone_global_pose()` fuera del ciclo de modificadores sigue devolviendo la pose animada; leer los
`PhysicalBone3D` directamente. Con 30+ zombis muriendo a la vez: ragdoll solo a < 25 m de un jugador y congelar
(dormir) tras 3 s; más lejos, animación de muerte por poses clave.

### 5.6 Armas en la mano

`BoneAttachment3D(bone_name="RightHandSocket")` + la escena del arma con transformación identidad. El socket se
construye en el script con: cabeza en el centro del puño, **eje Y del hueso = eje del mango** (hacia el pulgar),
**eje Z = a lo largo del antebrazo** (hacia los nudillos). Con la convención de armas de §11 (mango +Z Blender = +Y
Godot, extremo útil −Y Blender = +Z Godot) el filo del hacha y la boca del cañón miran en la dirección del antebrazo,
que es como se empuña de verdad (validado visualmente con `stone_axe.glb` del slice en `survivor_Attack.png`).
Armas largas: el `SupportGrip` del arma es el objetivo de `TwoBoneIK3D` del brazo izquierdo. Enfundar = reparentar
el arma a `BackSocket`/`HipSocketR`.

### 5.7 Red (co‑op 1–4 + PvP opcional) — lo que afecta al arte

- **No se replican poses.** Jugadores: posición, velocidad, yaw, yaw/pitch de apuntado, postura, clase de arma
  equipada y eventos (inicio de ataque con id y tick, recarga, golpe recibido, muerte con impulso). Zombis (doc 03):
  el byte `state` + velocidad derivada de snapshots + eventos. El cliente reconstruye el `AnimationTree`.
- Todas las animaciones son deterministas (generadas), así que dos clientes ven lo mismo con el mismo estado.
- **PvP/fuego amigo**: impactos con cápsula de cuerpo + esfera de cabeza en el servidor (con rebobinado de posiciones,
  no de poses); melee con ventanas activas de `anim_events.json` evaluadas por el servidor. El ragdoll es local y
  puramente visual (cada cliente puede ver un cadáver distinto; aceptable).

### 5.8 Rendimiento de personajes (medido + reglas)

| Escena (Compatibility, xvfb, 1 luz direccional con sombra) | Draw calls | Objetos |
|---|---|---|
| 1 superviviente, 8 materiales | 24 | 24 |
| 1 superviviente, **1 material + color de vértice** | **3** | 3 |
| 40 supervivientes, 8 materiales | 960 | 960 |
| 40 supervivientes, color de vértice | **120** | 120 |

Reglas: (1) color de vértice obligatorio en personajes; (2) *animation LOD*: `AnimationTree` a ritmo completo en
pantalla y < 30 m; `callback_mode_process = MANUAL` a 10–15 Hz fuera de pantalla o > 30 m; desactivado > 60 m de
todo jugador (la IA sigue en el servidor); `VisibleOnScreenNotifier3D` para pausar; (3) presupuesto 20–35 zombis
visibles (doc 02) + 4 jugadores + animales → ≤ 60 esqueletos activos; (4) hordas masivas (L1/L2 del doc 02 "una
MultiMesh por tipo"): una `MultiMesh` **no** admite esqueleto → **Vertex Animation Textures** horneadas por script en
Blender (≈ 500 vértices × 30 fps × 4 ciclos → textura de ~512 × 120 RGBA16F) con desfase por instancia en
`INSTANCE_CUSTOM`. No probado en el PoC: fase 2.

---

## 6. Fuentes externas de animación

| Fuente | Licencia (según la página oficial/búsqueda) | ¿Automatizable aquí? | Encaje de estilo | Veredicto |
|---|---|---|---|---|
| **Quaternius Universal Animation Library 1 y 2** | **CC0**; UAL1 120+ y UAL2 130+ animaciones sobre un rig humanoide universal "compatible con Unreal, Godot y Unity, listo para retarget"; versión *Standard* gratuita (~70 % del contenido en UAL2), *Source* (.blend) de pago; UAL2 incluye combos melee/armados, parkour, granja, pesca y **locomoción zombi** | Descarga manual (quaternius.com / itch.io / Godot Asset Store; bloqueados desde este contenedor). Luego todo por script/import. | Movimiento de "mocap estilizado": más realista que el nuestro, pero lee bien a 22 m; proporciones humanas estándar. | **Complemento recomendado** para lo difícil (trepar, saltar valla, arrastrarse, conducir, muertes, emotes). Se puede subir al repo (CC0). |
| KayKit Character Animations (Kay Lousberg) | **CC0**, `.fbx/.gltf`, rigs `Rig_Medium/Rig_Large`; general, locomoción (andar, correr, agacharse, esquivar, arrastrarse) y melee (1M, 2M, desarmado, doble, bloqueo) | Descarga manual | Personajes chibi/cabezones: proporciones distintas; retarget posible | Segunda fuente para melee estilizado. |
| Kenney (Animated Characters, Mini Characters…) | **CC0** | Descarga manual | Personajes con textura y pocas animaciones | Solo referencia. |
| Mixamo (Adobe) | Uso *royalty‑free* en proyectos personales/comerciales incluidos videojuegos; **no se puede redistribuir** el personaje/animación como asset suelto | **No**: requiere cuenta Adobe y descarga web manual; sin API | Mocap realista; rig `mixamorig:*` (retarget en Godot bien conocido) | **Evitar**: si el repo es público, subir los FBX sería redistribución; y no se puede regenerar en CI. |
| Synty (POLYGON) | Licencia comercial por asientos (cada licencia = 5 asientos del equipo), sin reventa/redistribución de assets | No (compra + descarga) | Low‑poly con atlas de textura; rig propio | **No**: rompe la regla "todo generado/CC0 en el repo" y la coherencia visual. |

**Híbrido recomendado**: ~80 % de las animaciones generadas por nuestro script (toda la locomoción de jugador, NPC,
zombis y animales; acciones de brazo; golpes; poses de arma) + ~20 % de UAL 1/2 (CC0), retargeteadas una vez en el
editor y guardadas como `AnimationLibrary` `.res` en `assets/anims/external/` con un `LICENSES.md`. Las externas se
reproducen sobre nuestros humanoides por el mismo `GeneralSkeleton`. Riesgo de mezcla de estilos: aplicar a las
externas un post‑proceso por script (exagerar poses clave, recortar a 30 fps, igualar velocidad de apoyo).

---

## 7. Lista completa de animaciones

Método: **G** = generador cíclico (§4.5); **K** = poses clave + Bézier (§4.6); **R** = ragdoll; **A** = aditiva;
**E** = externa CC0 (UAL). Viabilidad con calidad buena a esta cámara: ✔ alta, ◐ media, ✖ baja (mejor E).

### 7.1 Jugador / NPC humano

| Animación | Bucle | Prioridad | Método | Viab. | Notas |
|---|---|---|---|---|---|
| Idle (+ variante "frío": tiritar aditivo) | sí | P0 | G/K | ✔ | Probado (`Idle-loop`). |
| Walk (3.0 m/s) ×8 direcciones | sí | P0 (frontal) / P1 (resto) | G | ✔ / ◐ | Laterales requieren IK 3D (evolución del generador). |
| Run (6.0 m/s) ×8 | sí | P0 / P1 | G | ✔ / ◐ | Probado frontal (`Run_loop`). |
| Sprint | sí | P1 | G | ✔ | |
| Crouch idle / crouch walk (1.5 m/s) | sí | P1 | G | ✔ | Pelvis −35 cm. |
| Aim pistol / aim long gun (torso) | sí | P0 | K | ✔ | Pose estática + respiración; `LookAt/Aim` en pecho. |
| Shoot pistol / rifle / shotgun (retroceso) | no | P0 | K/A | ✔ | 0.15–0.3 s, aditiva sobre Aim. |
| Reload pistol / revólver / rifle (cerrojo) / escopeta (cartucho a cartucho, bucle) / carabina | no | P1 | K | ◐ | Cargador como objeto que cambia de socket; eventos en `anim_events.json`. |
| Melee 1M (cuchillo, palanca, machete): ligero ×2 | no | P0 | K | ✔ | |
| Melee 2M (hacha, bate): swing ×2 | no | P0 | K | ✔ | Probado (`Attack`). |
| Lanza: estocada | no | P1 | K | ✔ | |
| Empujón (co‑op, separar zombi) | no | P0 | K | ✔ | |
| Talar (= 2M swing) / picar hielo | no | P0 | K | ✔ | |
| Interactuar / coger del suelo / registrar contenedor (bucle) | no/sí | P0 | K | ✔ | Mano a objetivo con `TwoBoneIK3D` opcional. |
| Comer / beber / vendarse / inyectar | no | P1 | K | ✔ | |
| Lanzar (molotov, bengala, bomba, lata) | no | P1 | K | ✔ | |
| Arco: tensar / sostener / soltar; ballesta: apuntar / recargar | no | P2 | K | ✔ | |
| Golpe recibido (frontal/trasero) | no | P0 | A | ✔ | Add2 0.25 s. |
| Tambaleo / derribo | no | P1 | K | ✔ | |
| Muerte | — | P0 | R (+K corto) | ✔ | Probado ragdoll. |
| Caído (co‑op): arrastrarse + revivir a otro (bucle arrodillado) | sí | P1 | G/K | ◐ | Arrastre = generador con brazos. |
| Entrar / salir de vehículo | no | P1 | K (0.8 s, doc 02) | ◐ | A 22 m basta "paso + agacharse" + fundido. |
| Conducir (volante con IK) / pasajero / disparar desde vehículo (torso) | sí | P1 / P2 | K + IK | ✔ | Anclas `Seat*`/`Steering`. |
| Motonieve (inclinarse) | sí | P2 | K | ✔ | |
| Cargar objeto pesado (torso) / arrastrar trineo | sí | P2 | K/G | ✔ | |
| Saltar valla / trepar muro bajo / escalera | no | P2 | E | ✖ | Movimiento por código + animación externa. |
| Emotes (saludar, señalar, "ven", ping) | no | P1 | K | ✔ | Comunicación co‑op. |
| Dormir / sentarse junto al fuego / calentarse manos | sí | P1 | K | ✔ | Sabor invernal. |

### 7.2 Zombis (mismo esqueleto humanoide; tipos del doc 02)

| Animación | Bucle | Prioridad | Método | Viab. | Notas |
|---|---|---|---|---|---|
| Idle balanceo (3 variantes de fase/amplitud) | sí | P0 | G/K | ✔ | |
| Shamble (caminante 1.2 m/s): A cojera izq., B cojera der., C brazos caídos, D brazos al frente | sí | P0 | G | ✔ | Probado (`ZombieShamble-loop`). |
| Correr (corredor 5.5 m/s) y "fatigado" 3.0 m/s | sí | P1 | G | ✔ | |
| Reptar (reptador 1.0 m/s, brazos tiran) | sí | P1 | G (variante) / E | ◐ | UAL2 trae locomoción zombi. |
| Ataque zarpazo ×2 / embestida | no | P0 | K | ✔ | Probado reutilizando `Attack` en zombi. |
| Agarre (bucle sobre el jugador) | sí | P1 | K | ✔ | |
| Golpear puerta/barricada (bucle) | sí | P1 | K | ✔ | |
| Comer cadáver (arrodillado) | sí | P2 | K | ✔ | |
| Golpe recibido (aditivo) / tambaleo / derribo y levantarse | no | P0 / P0 / P1 | A / K / K | ✔ | |
| Muerte: 2 caídas por poses + ragdoll cercano | no | P0 | K + R | ✔ | |
| Congelado: pose rígida (idle helado) + **despertar** (sacudidas, romper hielo, 1.5 s) | sí / no | P1 | K | ✔ | + shader de escarcha + partículas (§8.4). |
| Gritón: canal de grito 3 s | sí | P1 | K | ✔ | |
| Hinchado: andar pesado (anchura ×1.4) | sí | P1 | G | ✔ | |
| Acechador de ventisca: andar agazapado sigiloso | sí | P2 | G | ✔ | |
| Coloso: embestida / golpe a dos manos | no | P2 | K | ◐ | Esqueleto humanoide escalado ×1.6 (motion_scale lo absorbe). |
| Trepar valla | no | P2 | E | ✖ | |

### 7.3 Animales (esqueleto cuadrúpedo propio, fase 2; hoy piezas rígidas con `quadruped_animator.gd`)

| Animal | Animaciones | Método |
|---|---|---|
| Lobo | idle, andar, trote, galope, acecho agazapado, mordisco/embestida, golpe, muerte (R), aullido (P2) | Generador cuadrúpedo: mismo algoritmo de pie anclado con 4 fases (paso 0/0.25/0.5/0.75, trote diagonales, galope rotatorio) + IK de 2 huesos por pata. ✔ |
| Ciervo | pastar (bucle), andar, trotar, huir a saltos (bound), alerta (cabeza arriba), muerte | Igual. ✔ |

Recuento: ~45 animaciones de jugador/NPC, ~25 de zombi, ~14 de animales. Con el generador + poses clave, **≈ 85 %
son viables por script con calidad buena** a esta cámara; el resto (trepar, saltar vallas, reptar fino, algunas
muertes) se cubre con UAL CC0.

---

## 8. Variedad de zombis

### 8.1 Receta

`Zombi = Cuerpo(params) + Ropa(capa) + Paleta(variante) + Props(sockets) + Daños(flags)`, todo en el generador:

- **Cuerpos** (parámetros de `joints()`): delgado, medio, corpulento, alto, mujer, anciano, niño‑adolescente no (tono).
  Mismo esqueleto y nombres → mismas librerías; `motion_scale` absorbe la altura (verificado §5.2).
- **Ropa como piezas rígidas** del mismo `MeshBuilder` ligadas a los mismos huesos: abrigo, sudadera, camisa, chaqueta
  de nieve, uniforme de policía (chaleco), bata de hospital, mono de trabajo, uniforme militar, ropa de caza.
- **Paletas**: 6–8 filas por tipo (colores desaturados, piel verdosa/grisácea, sangre seca `#6B1F1F`). Al usar color de
  vértice, cada variante de color es una **malla horneada distinta** (~30 KB): se elige al hacer spawn
  (`MeshInstance3D.mesh = variante`). Sin shaders especiales ni texturas.
- **Props en sockets** (`BoneAttachment3D`): gorro, casco (se cae como `RigidBody3D` en el Acorazado), mochila, gafas,
  herramienta clavada; baratos y muy visibles desde arriba.
- Selección curada: **48 variantes de caminante** (3 cuerpos × 8 atuendos × 2 paletas) + 6–10 por tipo especial.

### 8.2 Tipos del doc 02 → parámetros de generador (silueta única a 20 m)

| Tipo | Silueta | Receta |
|---|---|---|
| Caminante | humano encorvado | cuerpo estándar, `hunch 20–30°`, brazos a media altura |
| Corredor | delgado, inclinado | `width 0.85`, `lean 15°`, ropa deportiva |
| Reptador | bajo, sin piernas | ocultar piernas (hueso a escala 0) + muñón; locomoción de arrastre |
| Congelado | rígido, blanco‑azulado | paleta helada + cristales de hielo (props) + pose rígida |
| Hinchado | muy ancho | `width 1.4`, torso inflado (anillos del loft), piel amarillenta |
| Gritón | sin brazos, boca abierta | brazos a escala 0 (desmembrado) + mandíbula caída |
| Acechador de ventisca | blanco, agazapado | paleta blanca/gris (camuflaje), `hunch 35°` |
| Acorazado | casco + chaleco | props en `HeadSocket` + pieza de chaleco en `Chest` |
| Coloso (v2) | ×1.6 | mismo esqueleto escalado, piezas engrosadas |

### 8.3 Heridas y "gore‑lite" coherente con low‑poly

- Sangre = **caras planas** del color `blood` (parches en ropa, boca, manos) y **quads/polígonos irregulares sobre la
  nieve** (sin *decals*, doc 01/02), que se oscurecen con el tiempo.
- Ropa rasgada = caras que faltan dejando ver piel (variante de pieza).
- Desmembramiento opcional (machete 20 % en el doc 02): **escala 0 del hueso** (`LowerArm`/`Hand`) colapsa la pieza con
  skin rígido; se muestra un "muñón" (prop pequeño en socket) y se lanza la pieza como `RigidBody3D` con la malla de
  la pieza (extraída por el generador como asset aparte). Sin vísceras ni texturas.

### 8.4 Variante congelada

Paleta helada + escarcha por normal en el shader común de personajes (`mix(albedo, ice, frost * max(0, NORMAL_mundo.y))`
con `instance uniform float frost`, 0 → 1 al congelarse, 1 → 0 al despertar) + 3–5 esquirlas de hielo como props +
partículas al romperse. El shader común es opcional (1 `ShaderMaterial` para todos los personajes, lee `COLOR`).

---

## 9. Kit modular de pueblos y aldeas

### 9.1 Rejilla y medidas (decisión)

| Medida | Valor | Porqué |
|---|---|---|
| Rejilla horizontal | **2 m** (medio módulo 1 m) | Puerta 1.0 m + jambas 0.5 m en un módulo; habitaciones 4×4/4×6; aceras 2 m; calles de 8 m = 4 celdas; **chunk de 64 m = 32 celdas** (doc 01). |
| Altura de planta | **3.0 m** suelo a suelo (muro 2.8 + forjado 0.2) | Igual que la cabaña actual (muro 2.7 sobre cimiento 0.3). |
| Cimiento | 0.3 m (suelo interior a +0.3) | Absorbe desniveles del terreno; ya usado en `cabin`. |
| Muros | exterior 0.2 m centrado en la línea de rejilla; interior 0.12 m | Colisiones simples. |
| Huecos | puerta 1.0×2.2; doble 2.0×2.4; garaje 3.0×2.6 (módulo de 4 m); ventana 1.2×1.2 con alféizar a 0.9; escaparate 3.2×2.2 (módulo 4 m) | Cápsula del personaje r = 0.35: la puerta de 1 m es un cuello de botella deliberado (doc 02). |
| Escalera | 17 peldaños de 0.176 m, huella 0.28, ancho 1.2 → módulo 2×6 m; **colisión en rampa** | Como `ColSteps` de la cabaña. |
| Tejado | a dos aguas 35° con losa de nieve; plano con peto en comercial | Estilo de la referencia. |

### 9.2 Piezas (por estilo: madera‑azul `cabin_wall`, ladrillo, hormigón, chapa)

| Familia | Piezas | Tris/pieza |
|---|---|---|
| Muros | `Wall_2`, `Wall_1`, `Wall_Door_2`, `Wall_Window_2`, `Wall_Shop_4`, `Wall_Garage_4`, `Wall_Broken_2` (agujero), `Wall_Boarded_2` (tablones, post‑apo) + **versión `Stub`** (0.6 m) de cada una | 20–120 |
| Esquinas | exterior, interior, poste | 10–40 |
| Suelos | `Floor_2x2`, `Floor_Stair_Opening`, `Porch_2x2`, `Foundation_Skirt` | 2–30 |
| Escaleras | `Stair_2x6`, `Stair_Exterior`, `Ladder` | 60–200 |
| Tejados | `Roof_Gable_2` (+nieve), `Roof_Gable_End`, `Roof_Hip_Corner`, `Roof_Flat_2x2`, `Parapet_2`, `Chimney`, `Awning_4` | 20–150 |
| Aberturas | `Door` (hoja con pivote en bisagra, interactiva), `Window` (`window` emisivo), `Shutter`, `Planks` | 12–60 |
| Interior | mobiliario existente (cama, mesa, silla, estantería, armario, estufa, reloj) + cocina, nevera, sofá, TV, estantes de tienda, mostrador, cama de hospital, camilla, taquillas, celdas, bancos de iglesia, altar, pacas, herramientas de granja | 40–400 |

### 9.3 Estructura exportada (una `.glb` por edificio, generada desde un *layout* por script)

```
<Building>                       frente −Y; origen en el centro de la huella a cota 0
├─ Floor0            forjado + cimiento de la planta baja             (nunca se oculta)
├─ Walls0_N / _S / _E / _W       fachadas de la planta 0 (una malla por fachada)
├─ Walls0_N_Stub …   versión baja (0.6 m) de cada fachada              (visible solo en corte)
├─ Interior0         tabiques + marcos + mobiliario decorativo fusionado
├─ Floor1, Walls1_*, Walls1_*_Stub, Interior1 …                        (plantas superiores)
├─ Roof              tejado + nieve + chimenea                          (se oculta al entrar)
├─ Door_<n>          hoja de puerta con pivote en la bisagra (interactiva)
├─ Spawn_<tipo>_<n>  Empties: contenedores de loot, estufa, cama, luces, zombis dormidos
└─ Col*-colonly / Col*-convcolonly   colisiones de nivel superior (nunca hijas de visuales)
```
Regla de corte (generaliza `cutaway.gd`): jugador dentro en la planta *k* → ocultar `Roof` y todo `Floor/Walls/
Interior` de plantas > *k*; en la planta *k* sustituir por su `Stub` las fachadas cuya normal mira a la cámara (umbral
0.15 como hoy). El *stub* mantiene legible el contorno desde arriba (mejor que ocultar del todo). Con color de vértice,
un edificio de 2 plantas ≈ **12–16 superficies** (vs 34 de la cabaña actual de una planta).

### 9.4 Edificios del pueblo

| Edificio | Huella (m) | Plantas | Tris objetivo | Piezas / rasgos |
|---|---|---|---|---|
| Casa pequeña (3 layouts × 3 estilos) | 8×10 | 1–2 | 2–4 k | porche, chimenea, garaje opcional |
| Tienda / ultramarinos | 10×14 | 1 (+ vivienda) | 3–5 k | escaparate 4 m, toldo, estanterías |
| Gasolinera | marquesina 12×8 + tienda 8×10 | 1 | 4–6 k | surtidores (props), cartel alto, depósito |
| Comisaría | 16×20 | 2 | 6–9 k | garaje, celdas, armería (loot doc 02) |
| Hospital / clínica | 20×30 | 2–3 | 8–12 k | ambulancias (props), camillas |
| Iglesia (hito) | 10×20 + torre | 1 + torre 14 m | 5–8 k | campanario visible a distancia |
| Granja | casa 8×10 + granero 12×16 + silo | 1–2 | 6–10 k (conjunto) | vallas, heno, tractor (prop) |
| Control militar | 30×30 | — | 5–8 k | sacos terreros, barreras Jersey, garita, tienda, contenedor, torre |
| Aserradero / cabaña de pescador | 10×12 | 1 | 2–4 k | anclas de cebos para el doc 02 |

### 9.5 Carreteras

Sección de 8 m (2 carriles de 3 m + arcenes de 1 m), baldosas de 8×8 m en el pueblo: recta, cruce X, T, curva 90°,
fin, paso de cebra, aparcamiento; aceras de 2 m con bordillo de 0.15 m; bermas de nieve apartada en los bordes,
rodadas en color `snow_shadow`, asfalto casi cubierto (`stone_dark` asomando). Pueblos sobre meseta aplanada y
alineados a la rejilla; entre pueblos carretera por *spline* generada en Godot con el mismo perfil de sección (lado del
doc 01). 20–150 tris por baldosa.

### 9.6 Props urbanos

| Prop | Tris | Anclas | Prop | Tris | Anclas |
|---|---|---|---|---|---|
| Farola | 60–120 | `Light` | Poste eléctrico + cables | 80–150 | `WireA/B` |
| Semáforo / señal de stop / señales | 40–120 | `Text*` (Label3D) | Parada de autobús | 150–300 | — |
| Banco, papelera, contenedor | 40–200 | `Loot` | Hidrante, buzón | 30–80 | — |
| Vallas: madera, alambre, tela metálica (módulo 2 m) | 20–80 | — | Barricadas: madera, Jersey, sacos, alambre de espino | 30–200 | — |
| Coches abandonados (del generador de vehículos, §10) | 1–2.5 k | `Loot`, `FuelCap` | Neumáticos, bidones, palés, cajas, carrito | 20–150 | — |
| Montones de nieve, carámbanos | 20–80 | — | Cadáver tapado (gore‑lite) | 60–150 | `Loot` |

### 9.7 Nieve en tejados y superficies

Geometría: losa de nieve con grosor en tejados, porches, coches y copas (silueta, como hoy). Además, para todo lo
demás, **nieve por normal en el shader común** (`global uniform float snow_amount` del clima × `max(0, N.y)`): los
props se cubren/descubren con el tiempo sin nuevos assets. Los techos de edificios no se cubren por shader (ya llevan
losa).

### 9.8 Colisiones

- Muros: cajas `Col*-convcolonly` por fachada/planta (convención existente), nunca hijas de visuales (el corte no toca
  la física).
- Geometría estática irregular (escaleras exteriores, ruinas): una malla `Col<Grupo>-colonly` (trimesh) simplificada.
- Props pequeños: formas primitivas en código (como hoy); props apilados/pequeños sin colisión de personaje.
- Navegación: horneada por chunk desde colisiones (doc 01) → las puertas abiertas/cerradas se modelan como obstáculos.

### 9.9 LOD, visibilidad y sombras

- `meshes/generate_lods=true` se queda por defecto pero **no se cuenta con él**: en el PoC la cabaña solo obtuvo LOD en
  5 de 34 superficies y el pino en 2 de 4 (reducciones de 118→48 tris); nuestras mallas ya están en el mínimo útil.
- **`visibility_range_end`** 60–80 m en props y 120 m en edificios: el anillo 2 de precarga (doc 01) queda instanciado
  pero no se dibuja.
- `cast_shadow = OFF` en props < 0.5 m y en todo lo interior; sombras solo en edificios, árboles, vehículos y personajes.
- `MultiMeshInstance3D` para lo repetido y estático (árboles, vallas, postes, montones de nieve) por chunk.

### 9.10 Presupuesto de escena (objetivo, no medido en el juego)

Radio visible + sombras ≈ 45 m: **≤ 300 k tris**, **≤ 1 500 draw calls en Forward+ con sombras** (≤ 1 000 en
Compatibility), ≤ 60 esqueletos activos, ≤ 40 luces dinámicas en pueblo de noche (Forward+).

---

## 10. Vehículos

Alineado con el doc 01 (física propia `RigidBody3D` + raycast; no depende de `VehicleBody3D`) y el doc 02 (sedán,
camioneta, furgoneta, motonieve, quitanieves; asientos y maletero compartido).

```
<vehicle>.glb       frente −Y Blender (= +Z Godot = MODEL_FRONT); origen en el suelo, centro entre ejes
├─ Body             carrocería + interior (color de vértice)          ├─ Glass   cristales (material `glass`)
├─ WheelFL/FR/RL/RR  pivote = centro de la rueda, eje a lo largo de X, simétrica (gira en X local)
├─ SteeringWheel    pivote en el eje de la columna (P2)               ├─ DoorFL/FR/RL/RR  pivote en bisagra (P2)
├─ Seat_Driver, Seat_FrontR, Seat_RL, Seat_RR, Seat_BedL, Seat_BedR   Empties orientados como el vehículo (hasta 4–6)
├─ Exit_L, Exit_R, Interact_Driver, Interact_Trunk, Interact_Hood, FuelCap    Empties en el suelo/puntos de uso
├─ Headlight_L/R, Taillight_L/R, Exhaust, Smoke_Engine, Plow (quitanieves)    Empties para luces y partículas
└─ ColChassis, ColCabin   cajas convexas SIN sufijo de import: el código crea las CollisionShape3D en el RigidBody3D
```
Probado con un `.glb` de prueba: con sufijos `-vehicle/-wheel` Godot crea `VehicleBody3D` + `VehicleWheel3D` bien
situadas, pero con `wheel_radius = 0.5` y tracción/dirección desactivadas por defecto, y el `-convcolonly` hijo acaba
como `StaticBody3D` dentro del vehículo. Por eso: **sin sufijos**, y un `vehicle_builder.gd` lee las anclas y construye
el cuerpo (sirve igual para `VehicleWheel3D` si algún día se usa).

| Vehículo | Tris (sin ruedas) | Ruedas | Asientos | Notas |
|---|---|---|---|---|
| Sedán (+ patrulla con barra de luces) | 1.5–2.5 k | 4 × 120–200 | 4 | Variante *wreck* |
| Camioneta (existente, migrar) | 2–3 k | 4 | 3 + 2 en la caja | `Seat_BedL/R` disparo 360° |
| SUV | 2–2.5 k | 4 | 4 | |
| Furgoneta (+ ambulancia) | 2–3 k | 4 | 2 + 4 | Cama interior (ancla `Bed`) |
| Motonieve | 0.8–1.2 k | esquís + oruga (4 anclas de raycast) | 2 | `Hitch` para trineo |
| Quitanieves / camión | 3–4.5 k | 6 | 2 | `Plow` con colisión propia |
| Autobús escolar (solo restos) | 3–4 k | — | — | Prop estático, `Loot` |

Daños (P2): el generador produce `Body_Damaged` (vértices hundidos por ruido cerca de puntos de impacto, cristales
oscuros, parachoques ausente) y variantes de restos: sin ruedas o pinchadas, paleta oxidada/quemada, nieve encima,
puertas abiertas. Todos los restos de coche del mundo salen del **mismo generador** (variedad sin coste de arte).

---

## 11. Armas

Convención (compatible con `stone_axe`/`torch` del slice): **origen = centro de la empuñadura principal**, **mango
+Z Blender** (+Y Godot), **extremo útil −Y Blender** (+Z Godot: filo, boca del cañón, punta), +X = lado derecho del
arma. Se engancha con identidad en `RightHandSocket` (§5.6). Escala real ×1.0, **×1.2 en armas pequeñas** (cuchillo,
pistola, revólver) para que se lean a 22 m. Un único modelo para mano y suelo (sin 1.ª persona). Silueta y un color de
acento por clase (el jugador distingue "tiene escopeta" desde arriba).

| Ancla | Qué es | Usado por |
|---|---|---|
| `Muzzle` | boca del cañón, +Z Godot hacia fuera | origen del rayo en cliente, fogonazo, humo |
| `SupportGrip` | guardamanos / segunda mano | `TwoBoneIK3D` de la mano izquierda (armas largas, hacha a dos manos) |
| `Magazine` | pieza separada (malla aparte) | recarga: pasa a `LeftHandSocket` y vuelve |
| `EjectPort` | ventana de expulsión | partículas de casquillo |
| `Sight` | punto de mira | línea/láser de apuntado (no ADS) |
| `Holster` | punto de enganche al enfundar | `BackSocket`/`HipSocketR` |

| Arma (doc 02) | Clase de sujeción | Largo real | Tris |
|---|---|---|---|
| Cuchillo de caza, machete | Melee1H | 0.25 / 0.55 m | 40–120 |
| Palanca | Melee1H | 0.60 m | 40–80 |
| Bate (con/sin clavos), hacha de leñador | Melee2H | 0.85 / 0.80 m | 60–200 |
| Lanza artesanal | Spear (2M) | 1.8 m | 40–100 |
| Arco / ballesta | Bow | 1.3 / 0.8 m | 80–300 |
| Pistola 9 mm, revólver .357 | Pistol | 0.20 / 0.28 m | 150–300 |
| Escopeta de corredera (y recortada) | LongGun | 1.0 / 0.65 m | 250–500 |
| Rifle de cerrojo .308 (con/sin mira), carabina 5.56 | LongGun | 1.1 / 0.9 m | 300–600 |
| Molotov, bengala, bomba de tubo, lata | Throwable | 0.2–0.3 m | 30–100 |
| Linterna, antorcha, farol (existentes) | Tool1H | — | 40–120 |

---

## 12. Presupuestos por asset (resumen)

| Categoría | Tris | Huesos | Superficies | Referencia medida |
|---|---|---|---|---|
| Jugador | 800–1 500 | 23–28 | 1 (+ props) | PoC 814 tris, 23 huesos |
| Zombi / NPC | 700–1 300 | idem | 1 | PoC zombi 762 tris |
| Lobo / ciervo | 500–900 / 600–1 000 | 18–24 (cuadrúpedo) | 1 | slice: 600 / 800 |
| Arma en mano | 40–600 | — | 1–2 | `stone_axe` ≤ 100 |
| Vehículo | 1.5–4.5 k + ruedas | — | 2–3 | `pickup_truck` actual: 9 superficies |
| Edificio completo | 2–12 k | — | 8–20 (grupos de corte) | `cabin` actual: 34 superficies |
| Mueble / prop | 20–400 | — | 1 | |
| Árbol | 150–400 | — | 1 | slice |
| Baldosa de carretera | 20–150 | — | 1 | |
| Animación (fuente glTF) | ≈ 21 KB por segundo a 30 fps | — | — | `survivor.glb` 223 KB (malla ≈ 72 KB + 7.2 s de acciones) |

---

## 13. Prueba de concepto — resultados

Directorio: `/tmp/claude-0/-home-user-Quotas/3c3b507e-0838-5643-8cd6-6e5a40202a08/scratchpad/animpoc/`
(fuera del repo; reutiliza `blender/lib` del repo **solo en lectura**).

| Archivo | Qué hace |
|---|---|
| `run_poc.sh` | Reproduce todo (build → import → verificación → métricas → renders) y escribe `results.txt`. ≈ 25 s. |
| `build_humanoid.py` | bpy: `joints()`, piezas low‑poly con `MeshBuilder`, armature (22 + socket), skin rígido, `ActionWriter`, generador de marcha con IK, `Attack` por poses, variante de color de vértice, export `.glb`. |
| `test_autoweights.py` | `ARMATURE_AUTO` en modo background y comparación con el skin rígido. |
| `build_vehicle_test.py` | `.glb` mínimo para probar sufijos `-vehicle/-wheel/-convcolonly`. |
| `inspect_glb.py` | Lee el JSON del `.glb` (animaciones, canales, duraciones, atributos). |
| `out/survivor.glb`, `out/zombie.glb`, `out/survivor_vcol.glb` (+ `.blend`) | Salidas. |
| `godot/` | Proyecto desechable 4.7.2: `verify.gd`, `metrics.gd`, `perf.gd`, `render.gd`, `tree.gd`, `ragdoll.gd`, `vtest.gd`, `make_bonemap.gd`, `humanoid_bonemap.tres`, `models/*.glb.import` con retarget. |
| `probe/` | Consultas a `ClassDB` de 4.7.2 (modificadores, perfil humanoide, nodos de AnimationTree). |

Resultados (de `results.txt`):

| Verificación | Resultado |
|---|---|
| Generación bpy (3 modelos, 5 acciones) | 1.2 s; `survivor`: 23 huesos, 814 tris, 5 acciones con 1 slot cada una |
| glb | 1 skin (23 joints), `JOINTS_0/WEIGHTS_0`, 5 animaciones: Attack 0.900 s, Idle‑loop 3.000, Run_loop 0.700, Walk‑loop 1.000, ZombieShamble‑loop 1.600 |
| Import Godot (`--headless --import`) | 0 errores; `Skeleton3D` con los 23 huesos en orden; `AnimationPlayer` con `Attack` (NONE), `Idle`, `Run`, `Walk`, `ZombieShamble` (LINEAR), longitudes exactas; sufijos `-loop` y `_loop` eliminados del nombre |
| Perfil humanoide | 22/56 huesos presentes por nombre exacto, **0 obligatorios ausentes**; BoneMap identidad aceptado; esqueleto renombrado a `GeneralSkeleton` |
| Retarget | *Overwrite Axis* + *Normalize Position Tracks* sin cambiar la deformación; `motion_scale` 0.95 (jugador) / 1.00 (zombi); pies del zombi corregidos de 0.039 a 0.087 m |
| Bug | *Except Bone Transform* = true deja 1 pista por animación (issue #123782) |
| Pies | Walk: tobillo mín. 0.087 m, apoyo 1.61 m/s (autorado 1.6); Run: 4.06 m/s (autorado 4.0) |
| Auto‑pesos | `ARMATURE_AUTO` en background: FINISHED, 10 % vértices sin peso, 63 % hueso correcto |
| AnimationTree | BlendSpace1D (sync cíclico) + OneShot filtrado al torso: correcto |
| Ragdoll | 12 huesos físicos; pelvis 0.90 → 0.20 m; la malla sigue |
| Draw calls | 40 personajes: 960 (8 materiales) vs 120 (color de vértice) |
| Auto‑LOD | pocas superficies obtienen LOD (cabaña 5/34, superviviente 4/8) |
| Sufijos de vehículo | `VehicleBody3D` + 4 `VehicleWheel3D` (radio 0.5 por defecto), colisión mal ubicada |

Capturas (`godot/shots/`, render real de Godot con `xvfb-run -a godot --rendering-driver opengl3`):
`survivor_Idle.png`, `survivor_Walk.png`, `survivor_Run.png`, `survivor_Attack.png`, `survivor_ZombieShamble.png`
(fila superior perfil, inferior 3/4; 6 instantes del ciclo), `survivor_rt_Walk.png`, `survivor_rt_Attack.png`
(tras retarget), `zombie_noretarget_*.png`, `zombie_retarget_{Walk,ZombieShamble,Attack}.png` (animaciones del jugador
en el zombi), `tree_walk_plus_attack_upperbody.png`, `ragdoll_after_2_5s.png`, `closeup_iso.png`,
`game_view_dist22.png` y `game_view_dist14.png` (cámara del juego junto a `cabin`, `pickup_truck` y pinos del slice).

Limitaciones honestas del PoC:
- Solo locomoción frontal; laterales/atrás y agachado no están hechos (el generador actual resuelve IK en 2D).
- El ataque se ajustó a ojo en 3 iteraciones; la calidad de acciones por poses clave depende de un "ojo" de animación
  y de iterar con renders (el bucle build→render de 25 s lo hace viable).
- Renders en Compatibility (OpenGL) bajo xvfb, con iluminación sencilla y algo sobreexpuesta; Forward+ no se probó aquí.
- No se probó el auto‑mapeo del editor (`BoneMapper`, solo UI), ni librerías externas reales (UAL/KayKit no son
  descargables desde este contenedor), ni VAT, ni animación de cuadrúpedos, ni el coste de CPU de 60 esqueletos.
- Licencias de terceros verificadas vía resultados de búsqueda (las páginas oficiales no eran accesibles con WebFetch
  desde este entorno): revisar las páginas enlazadas antes de incorporar assets.

---

## 14. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| Techo de calidad de lo procedural en acciones complejas (trepar, vallas, entrar al coche) | Medio | UAL CC0 para esas ~15 animaciones; a 22 m la tolerancia es alta; validar con capturas en cámara de juego. |
| Mezcla de estilos entre animación propia y externa | Bajo‑medio | Post‑proceso por script de las externas (poses exageradas, 30 fps, velocidad de apoyo). |
| Bug #123782 (*Except Bone Transform*) u otros del importador | Medio | Opción desactivada; `verify` en CI que cuenta pistas por animación y falla si < 10. |
| Cambios de API de Blender (slotted actions en 4.4, `fcurves` eliminado en 5.0) | Medio | Todo a través de `ActionWriter`; fijar Blender 5.0.1 en el entorno; test de humo de exportación. |
| Convención de frente mixta (+Y slice vs −Y nuevo) | Medio | Migrar todo el slice en un solo PR (rotación en `to_object` + `MODEL_FRONT` en código) antes de producir contenido nuevo. |
| Draw calls por materiales múltiples y edificios con muchas superficies | Alto | Color de vértice + fusión por grupos de corte; presupuesto verificado por `verify` (superficies por asset). |
| CPU de animación con muchos zombis | Medio‑alto | *Animation LOD*, pausa fuera de pantalla, tope de 60 esqueletos; VAT + MultiMesh para hordas (fase 2). |
| Deslizamiento de pies al variar velocidad o proporciones | Bajo | Generador anclado + `TimeScale` calibrado con `motion_scale`; métrica automática (tobillo mín., velocidad de apoyo). |
| Retarget de rigs externos con reposos raros | Medio | *Fix Silhouette* para A‑pose, o método "Use Retarget Modifier"; métrica de pies en `verify`. |
| Licencias (Mixamo/Synty en un repo público) | Alto (legal) | Solo CC0 en el repo, con `LICENSES.md` por carpeta. |
| Escala del catálogo (cientos de assets) | Alto | Familias parametrizadas, un verificador por familia, capturas automáticas por familia para revisión. |
| Readability desde arriba (armas pequeñas, zombis que se confunden) | Medio | Escala ×1.2 en armas pequeñas, siluetas únicas por tipo (§8.2), contraste de paleta; revisar siempre en `game_view_dist22`. |

---

## 15. Plan de trabajo recomendado (orden)

1. **Enmienda de `ASSET_SPEC`** (convenciones §3) + migración del slice a frente −Y y color de vértice (`lib/palette` →
   `COLOR_0`, `lib/export` con las opciones de §4.7). Actualizar `verify_assets.py` (superficies, huesos, bucles).
2. `lib/rig.py` + `lib/anim.py` a partir del PoC; `chars/build_player.py` esquelético (sustituye piezas rígidas) y
   `anims/build_locomotion.py` (Idle, Walk/Run/Sprint frontales, Crouch).
3. Lado Godot: `humanoid_bonemap.tres`, plantillas `.import`, `character_visual.tscn` con el `AnimationTree` de §5.3,
   `BoneAttachment3D` y ragdoll. Sustituir `player_animator.gd` procedural.
4. Zombi caminante (4 variantes de shamble, ataque, golpe, muerte) + 48 variantes de malla; luego tipos especiales.
5. Generador 8 direcciones (IK 3D o *constraints* + `bake_action`), armas (poses por clase, recargas), acciones.
6. Kit modular (rejilla 2 m): casas → tienda/gasolinera → comisaría/hospital/iglesia/granja/control; carreteras y props.
7. Vehículos (sedán, SUV, furgoneta, motonieve, quitanieves, restos) con anclas; conversión de `pickup_truck`.
8. Cuadrúpedos esqueléticos (lobo, ciervo); UAL CC0 para lo difícil; VAT para hordas si el perfil de CPU lo exige.

---

## 16. Fuentes

Documentación y código de Godot (4.7.2 salvo indicación; las páginas de docs.godotengine.org no eran accesibles desde
este entorno y se leyeron desde su fuente en GitHub):
- Retargeting 3D Skeletons — https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html (fuente: https://raw.githubusercontent.com/godotengine/godot-docs/master/tutorials/assets_pipeline/retargeting_3d_skeletons.rst)
- Node type customization using name suffixes — https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
- Import configuration (AnimationLibrary, Generate LODs, animation FPS) — https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/import_configuration.html
- Using AnimationTree (filtros, OneShot, BlendSpace sync modes, root motion) — https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html
- Ragdoll system — https://docs.godotengine.org/en/stable/tutorials/physics/ragdoll_system.html
- Mesh level of detail — https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html ; Visibility ranges — https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
- Referencia de clases 4.7.2 (TwoBoneIK3D, LookAtModifier3D, AimModifier3D, RetargetModifier3D, PhysicalBoneSimulator3D, BoneAttachment3D, SkeletonProfileHumanoid, BoneMap, VehicleBody3D, VehicleWheel3D, AnimationNode, AnimationNodeBlend2/BlendSpace2D, SpringBoneSimulator3D, IKModifier3D, ChainIK3D…) — https://github.com/godotengine/godot/tree/4.7.2-stable/doc/classes
- Código fuente 4.7.2: `editor/import/3d/post_import_plugin_skeleton_track_organizer.cpp`, `post_import_plugin_skeleton_rest_fixer.cpp`, `post_import_plugin_skeleton_renamer.cpp`, `editor/import/3d/resource_importer_scene.cpp` (sufijos `loop/cycle`, opciones de animación), `modules/gltf/gltf_document.cpp` (bucles, `COLOR_0` → albedo de vértice), `editor/scene/3d/bone_map_editor_plugin.cpp` (auto‑mapeo) — https://github.com/godotengine/godot/tree/4.7.2-stable
- Issue #123782 "When 'Except Bone Transform' is enabled in Retarget Import, the bone tracks get erased" — https://github.com/godotengine/godot/issues/123782
- Godot 4.6 release (nuevo framework de IK) — https://godotengine.org/releases/4.6/
- Animation Retargeting in Godot 4.0 — https://godotengine.org/article/animation-retargeting-in-godot-4-0/
- Introspección local: `ClassDB` de Godot 4.7.2 (`probe/*.gd`) y propiedades RNA de `bpy.ops.export_scene.gltf` en Blender 5.0.1 (io_scene_gltf2 5.0.21).

Blender / glTF:
- Blender 5.0 Python API release notes (eliminación de `action.fcurves`, channelbags) — https://developer.blender.org/docs/release_notes/5.0/python_api/
- Slotted Actions (4.4) — https://developer.blender.org/docs/release_notes/4.4/upgrading/slotted_actions/
- glTF 2.0 Specification (sistema de coordenadas: +Y arriba, frente +Z) — https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html

Animaciones y licencias externas:
- Mixamo FAQ — https://helpx.adobe.com/creative-cloud/faq/mixamo-faq.html
- Quaternius Universal Animation Library — https://quaternius.com/packs/universalanimationlibrary.html ; https://opengameart.org/content/universal-animation-library ; https://store.godotengine.org/asset/quaternius/universal-animation-library/
- Quaternius Universal Animation Library 2 — https://quaternius.com/packs/universalanimationlibrary2.html ; https://opengameart.org/content/universal-animation-library-2 ; https://80.lv/articles/get-this-animation-asset-library-with-over-130-diverse-items
- KayKit Character Animations — https://kaylousberg.itch.io/kaykit-character-animations ; https://opengameart.org/content/kaykit-character-animations
- Kenney (CC0) — https://kenney.nl/assets/animated-characters-1 ; https://kenney.nl/assets/mini-characters
- Synty licencias — https://syntystore.com/pages/licences-overview ; https://syntystore.com/pages/one-time-purchase-licence

Documentos internos: `docs/ASSET_SPEC.md`, `docs/ARCHITECTURE.md`, `blender/README.md`, `docs/research/01_mundo_abierto_tecnologia.md`,
`docs/research/02_jugabilidad_zombies_armas.md`, `docs/research/03_multijugador_servidores.md`.
