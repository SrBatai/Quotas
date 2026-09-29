# VENTISCA look-dev (rendering research, hito G1)

Proyecto Godot 4.7 independiente (ignorado por el juego: `prototypes/.gdignore`). Recrea la composición de las
referencias con la cámara del juego y prueba tonemapping, luces, AO, nieve, huellas y derrame de ventanas.
Conclusiones y tablas: `docs/research/06_graficos_render.md`.

- `scenes/lookdev.tscn` + `scripts/lookdev.gd`: escena construida por script (terreno, props, luces, cámara, captura).
- `scripts/presets.gd`: presets `day/dusk/night/blizzard` (fuente de verdad de los valores del doc).
- `scripts/terrain_builder.gd`: terreno liso indexado con AO en `COLOR.a`.
- `scripts/trail_map.gd`: mapa de huellas (R hundimiento, G reborde) con back-ends `cpu` y `drawable` (4.7).
- `shaders/`: `snow_terrain.gdshader`, `world_vcol_v2.gdshader` (sustituto de `assets/shaders/world_vcol.gdshader`),
  `stylized_light.gdshaderinc`, `trail_stamp*.gdshader`.
- `assets/models/`: copia de los .glb del juego; `assets/hd/`: héroes HD (salida de Opus, no editar aquí).
- `tools/render.sh [fp|compat] key=value...`: render con lavapipe/llvmpipe (ver cabecera de `lookdev.gd` para los args);
  `tools/contact.py` / `tools/final_sheets.py`: hojas de comparación (Pillow); `tools/inspect.gd`: árbol de los .glb.

Ejemplos:
```
tools/render.sh fp list=day,dusk,night,blizzard frames=10
tools/render.sh compat list=day:filmic:0.28,night:filmic:0.30 sunscale=0.75
tools/render.sh fp costmatrix=1 frames=10
```
