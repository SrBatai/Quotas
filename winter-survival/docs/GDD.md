# VENTISCA — Documento de Diseño (GDD)

> Juego de supervivencia invernal, low-poly, en Godot 4.7.2. Versión: vertical slice v1.
> Documentos hermanos: `ARCHITECTURE.md` (técnico, código) y `ASSET_SPEC.md` (contrato de modelos 3D). Los tres son coherentes entre sí: **si algo cambia aquí, cambia allí**.

---

## 1. Ficha

| Campo | Valor |
|---|---|
| Título | **VENTISCA** |
| Subtítulo / lema | *Sobrevive cinco días en el bosque helado* |
| Género | Supervivencia ligera, un jugador, cámara alta en perspectiva (estilo isométrico), controlado con ratón + WASD |
| Sesión objetivo | 35–45 minutos para ganar (5 días de juego, 7 min por día) |
| Referencia visual | Vídeo de @ddemirferhat: casa azul-gris con porche en un claro nevado, pinos low-poly con nieve, camioneta abandonada, señal de madera, cabaña en A al fondo, huellas en la nieve, luces cálidas contra noche azul |
| Idioma del juego | **Todo el texto en español** (los identificadores en código van en inglés) |
| Plataformas | PC (Forward+ en la máquina del usuario; debe verse bien en Compatibility/OpenGL) |

### Pitch
Despiertas en la vieja casa de un cazador, en un claro rodeado de pinos cargados de nieve. La estufa aún está tibia. Cada día es una carrera contra el frío y el hambre: recoger leña, mantener viva la estufa, fabricar un hacha, talar, cocinar… y cuando cae la noche, quedarte cerca de una llama, porque los lobos merodean. Si aguantas cinco amaneceres, has ganado.

---

## 2. Pilares

1. **Frío contra calor.** La tensión central es térmica: el mundo es azul y frío; la estufa, la fogata y la antorcha son naranjas y calientes. Cada decisión gira en torno a *dónde está mi próxima fuente de calor*.
2. **Acogedor pero duro.** Estética low-poly amable (flat shading, paleta suave, nieve que cae siempre), pero las reglas son estrictas: la casa se enfría si la estufa muere, los lobos aparecen cada noche.
3. **Se juega con el ratón.** Pasear con WASD, pero *todo* lo demás es "haz clic en la cosa": clic en un árbol con el hacha, clic en el armario para abrirlo, clic en la fogata para echar leña. El juego te dice siempre qué pasará al hacer clic (etiqueta de contexto sobre la barra de objetos).
4. **Legible desde arriba.** Cámara alta fija; la casa se muestra en **corte** (sin techo ni paredes delanteras) cuando entras, como una casa de muñecas.
5. **Alcance cerrado.** Un claro, una casa, un lago, un bosque; cinco días; ocho recetas. Todo terminado y probado antes que ambicioso.

---

## 3. Bucle principal

```
Explorar el claro ──► Recoger (leña, piedras, bayas) ──► Fabricar (hacha, antorcha, fogata)
       ▲                                                          │
       │                                                          ▼
Amanece (nuevo día, ◄── Sobrevivir la noche ◄── Mantener fuentes de calor (estufa, fogata)
 nuevas misiones)        (lobos, ventiscas)      y comer (latas, bayas, carne)
```

**Minuto a minuto:** mirar los tres anillos (hambre, salud, calor) → decidir si hace falta calor o comida → salir a por recursos → volver antes de que anochezca o llevar una antorcha → alimentar la estufa → dormir de pie (no hay acción de dormir en v1) vigilando la ventana.

**Día a día:** el panel de misiones ("PRIMER DÍA — SOBREVIVE 3/8") guía los primeros minutos; a partir del día 2 las misiones son de mantenimiento; cada noche hay un lobo más.

---

## 4. Cámara y controles

### 4.1 Cámara
- **Perspectiva** (no ortográfica), FOV vertical **35°**, **inclinación −52°** (mira hacia abajo), **guiñada por defecto 35°** (mira hacia el noreste del mundo), distancia **22 m** al jugador (zoom con rueda entre **14 y 30 m**).
- Sigue al jugador con suavizado (lerp 6/s) y ligero adelanto hacia la dirección de movimiento (1.5 m).
- **Q / E** giran la cámara **±45°** con un tween de 0.35 s (la guiñada siempre es múltiplo de 45°).
- El cursor del ratón **siempre visible** (modo `VISIBLE`). No hay cámara al hombro.
- Corte de la casa: al entrar en el interior de la casa desaparecen el **techo, la chimenea y las dos paredes que dan a la cámara**; al salir vuelven. Se recalcula si giras la cámara.

### 4.2 Controles

| Acción | Teclado / ratón | Mando | Notas |
|---|---|---|---|
| Moverse | W A S D / flechas | Stick izquierdo | Relativo a la guiñada de la cámara |
| Correr | Mayús (mantener) | L3 | Velocidad 6.0 m/s; gasta el doble de hambre |
| Interactuar / atacar objetivo bajo el cursor | **Clic izquierdo** (E: interactúa con lo más cercano a ≤ 2.5 m) | X (botón 2) → interactúa con lo más cercano a ≤ 2.5 m | Si el objetivo está lejos, el personaje **camina solo hacia él** y actúa al llegar (cualquier tecla de movimiento lo cancela) |
| Atacar al lobo más cercano | Espacio | RT | Alternativa al clic; alcance 2.0 m |
| Cancelar / cerrar panel | Clic derecho, Esc | B (botón 1) | Cancela colocación de fogata, cierra paneles |
| Pausa | Esc (si no hay panel abierto) | Start | |
| Girar cámara | Q / E | LB / RB | ±45° |
| Zoom | Rueda del ratón | D-pad arriba/abajo | 14–30 m |
| Ranura de la barra 1–9 | Teclas 1–9 | D-pad izq/der + A | Herramienta → equipar en MANO; comida → comer una |
| Abrir/cerrar fabricación | Tab | Y (botón 3) | Abre la última categoría usada (por defecto Herramientas) |
| Equipar/guardar antorcha | T | D-pad abajo (mantener) | Atajo: intercambia antorcha ↔ mano |
| Comer lo mejor disponible | F | — | Prioridad: carne asada > lata > bayas calientes > bayas > carne cruda |

Todo lo que se puede hacer con el ratón también se puede hacer con teclado+mando (interactuar con lo más cercano), pero el ratón es el modo principal.

### 4.3 Etiqueta de contexto (hover)
Al pasar el cursor sobre algo interactivo aparece un **anillo de resalte** en su base y una etiqueta centrada justo encima de la barra de objetos. Textos exactos:

| Objetivo | Etiqueta (sin herramienta necesaria / estado) |
|---|---|
| Pino / árbol seco | `Talar árbol (0/3)` — sin hacha: `Necesitas un hacha` |
| Tronco caído | `Cortar leña (0/2)` — sin hacha: `Necesitas un hacha` |
| Leña suelta | `Recoger leña` |
| Piedra | `Recoger piedra` |
| Arbusto de bayas | `Recoger bayas` — vacío: `Sin bayas (rebrotan)` |
| Fogata | `Añadir leña (7)` (número = madera en inventario) — sin madera: `Sin leña` |
| Estufa | `Alimentar estufa (7)` — apagada: `Estufa apagada · Añadir leña (7)` |
| Armario / camioneta / caja | `Abrir armario` / `Registrar camioneta` / `Abrir caja` — abierto: `Armario abierto` |
| Lobo | `Atacar lobo` (con hacha: `Atacar lobo (hacha)`) |
| Ciervo | `Ciervo` (no interactivo en v1) |
| Objeto demasiado lejos | misma etiqueta + ` · acércate` |

---

## 5. Estadísticas del jugador

Tres anillos en la esquina superior derecha: **Hambre** (muslo de pollo, dorado), **Salud** (corazón, rojo), **Calor** (termómetro, turquesa). No hay barra de energía/estamina.

| Stat | Máx | Inicio | Regla base (por segundo) |
|---|---|---|---|
| **Salud** | 100 | 100 | −4/s si Calor = 0; −2/s si Hambre = 0 (se suman); +0.5/s si Calor > 40 **y** Hambre > 40; mordisco de lobo −15 |
| **Calor** | 100 | 80 | Exterior de día −0.4/s; exterior de noche −1.0/s; ventisca ×2.0; dentro de la casa con estufa encendida **+4/s**; dentro con estufa apagada −0.15/s; a ≤ 4.5 m de una fogata encendida **+5/s** (se suma); con antorcha encendida en mano el drenaje ×0.6; con abrigo de piel el drenaje ×0.6 (acumulable con antorcha) |
| **Hambre** | 100 | 70 | −0.15/s (×2 mientras corres). Al comer: ver §9 |

Umbrales y avisos:
- Calor < 30: viñeta de escarcha en los bordes (intensidad 0→1 entre 30→0), aviso `Tienes frío`. Calor < 15: velocidad ×0.8 y aviso `Te estás congelando`.
- Hambre < 25: aviso `Tienes hambre`; Hambre = 0: aviso `Te mueres de hambre`.
- Salud < 25: latido del anillo de salud (pulso 1.2 Hz) y viñeta roja leve.
- Salud = 0: muerte. Causa registrada por la última fuente de daño: `Frío`, `Hambre` o `Lobos`.

Tiempos de referencia (sin protección): de 100 a 0 de calor en 250 s de día o 100 s de noche; de 100 a 0 de hambre en ~11 min.

---

## 6. Ciclo día / noche

- Un día completo dura **420 s reales** (7 min). Una hora de juego = 17.5 s.
- El juego empieza el **Día 1 a las 08:00**.
- **Noche** = de **20:00 a 06:00** (10 h = 175 s). **Día** = 06:00–20:00 (14 h = 245 s).
- Amanecer 05:30–06:30 y anochecer 19:30–20:30: transición suave de cielo/luz (30 s de mezcla).
- El **contador de día** sube a las 06:00. El reloj circular del HUD muestra "Día N" y un anillo que se llena de 06:00 a 06:00; icono de sol de día y luna de noche.
- **Victoria**: alcanzar las 06:00 del **Día 6** (has sobrevivido 5 días completos).

Iluminación (ver paleta §17):
- Día: sol bajo (elevación máx. 38° a mediodía, viene del suroeste), luz cálida-pálida `#FFF4E0`, sombras largas azuladas gracias a la luz ambiente `#8EB0DC`; cielo `#7FB3E6` arriba, `#D6E6F5` en el horizonte; niebla `#C9D8EA`, densidad 0.010.
- Atardecer: sol naranja `#FFB070`, horizonte `#F2A65A`, cielo `#6A4C93`.
- Noche: "luna" (segunda luz direccional) azul `#7D9BD1` energía 0.18; ambiente `#1B2A47`; cielo `#0B1A33`/`#1F3358`; niebla `#16233B`, densidad 0.022. Las ventanas de la casa (si la estufa está encendida), el farol del porche, la estufa y las fogatas brillan en naranja `#FFB454`.
- Nieve ligera cayendo **siempre**.

---

## 7. Clima: ventiscas

- Ninguna ventisca antes del Día 1 a las 14:00. Después, **cada hora de juego** se tira un dado: **8 %** de probabilidad de ventisca, con un mínimo de **6 h de juego** (105 s) entre el fin de una y el inicio de otra. Media ≈ 1.5 ventiscas por día.
- **Aviso** 10 s antes: toast `Se acerca una ventisca…` y el viento sube.
- **Duración**: 60–90 s. Durante la ventisca: banner `VENTISCA` bajo el reloj, nieve intensa (emisor extra) empujada por el viento, niebla `#B8C4D3` densidad 0.06 (el mundo se vuelve blanco-gris), drenaje de calor ×2, sonido de viento al máximo.
- Fin: toast `La ventisca amaina`. Las ventiscas no aumentan los lobos.

---

## 8. Mundo

- Terreno **160 × 160 m** generado por código (colinas suaves, ruido), nieve por todas partes, límite invisible en ±78 m con un anillo de pinos más densos y niebla que sugiere "no hay nada más allá".
- **Regiones** (banner superior "REGIÓN — NOMBRE" que aparece 3 s al cambiar de zona):

| Región (texto exacto) | Zona | Contenido |
|---|---|---|
| `CLARO` | círculo r = 26 m alrededor de la casa (origen) | Casa principal con porche, estufa, armario; camioneta abandonada; señal de madera; valla; leña suelta y piedras cerca |
| `LAGO HELADO` | círculo r = 20 m centrado en (−42, 30) | Hielo plano azul claro, rocas en la orilla, pocos árboles; caminar sobre el hielo es seguro |
| `CABAÑA DEL PESCADOR` | círculo r = 14 m centrado en (−20, 52) | Cabaña en A (decorativa, cerrada), valla, tronco caído, arbustos |
| `BOSQUE PROFUNDO` | resto del mapa | Pinos densos, árboles secos, rocas, bayas, ciervos; más lobos |

- La **señal** junto a la casa tiene dos tablas-flecha: `CABAÑA DEL PESCADOR` y `LAGO HELADO`, orientadas hacia esos lugares.
- **Huellas**: el jugador deja huellas (pequeñas depresiones azuladas) cada 0.6 m que se desvanecen en 20 s. Solo el jugador.
- **Ciervos** (3–4): fauna ambiental; pasean y huyen a 12 m del jugador. No se cazan en v1.

### La casa (refugio principal)
- Casa de tablones azul-gris con tejado oscuro, chimenea de ladrillo, porche cubierto con barandilla, escalones y farol colgante. Entrada abierta (sin puerta).
- Interior amueblado: **cama**, **escritorio + silla**, **estantería con tarros**, **reloj de pared** (sus agujas marcan la hora del juego), **armario** (contenedor) y **estufa de leña** de hierro con tubo.
- **Estufa**: fuente de calor de la casa. Consume 1 s de combustible por segundo. Máx 600 s. Cada madera añade **+90 s**. **Empieza con 45 s** (urgencia inicial: la misión 2 es alimentarla). Encendida: interior +4/s de calor, luz naranja en la estufa, ventanas brillando de noche, humo por la chimenea. Apagada: la casa solo protege del viento (−0.15/s). Toast al apagarse: `La estufa se ha apagado. La casa se enfría.`
- **Armario** (6 ranuras): al inicio contiene `Lata de judías ×2` (+40) y `Lata de sopa ×2` (+35).
- **Camioneta** (contenedor `CAMIONETA`, 6 ranuras): al inicio `Madera ×3`, `Lata de sopa ×1`.
- Los lobos **no entran** en la casa (mientras estás dentro, merodean fuera a 6–10 m).

---

## 9. Recursos, objetos y comida

Inventario = **barra de 10 ranuras** en la parte inferior. La ranura 1 es **MANO** (solo herramientas: hacha o antorcha). Las ranuras 2–10 son pilas de hasta **20** unidades. Si no hay hueco: toast `Inventario lleno`.

| id | Nombre (exacto) | Cómo se obtiene | Uso |
|---|---|---|---|
| `madera` | Madera | Leña suelta (clic, +1); tronco caído (2 golpes de hacha, +3); pino (3 golpes, +4); árbol seco (2 golpes, +2); camioneta | Recetas, combustible (estufa +90 s, fogata +60 s) |
| `piedra` | Piedra | Piedras sueltas junto a rocas (clic, +1) | Recetas |
| `bayas` | Bayas | Arbusto (clic, +3; rebrota en 240 s) | Comer: Hambre +12 |
| `carne_cruda` | Carne cruda | Lobo muerto ×2 | Comer: Hambre +8, Salud −5; cocinar |
| `carne_asada` | Carne asada | Receta Cocina | Comer: Hambre +40, Calor +10 |
| `bayas_calientes` | Bayas calientes | Receta Cocina | Comer: Hambre +25, Calor +10 |
| `lata_judias` | Lata de judías | Armario | Comer: Hambre +40 |
| `lata_sopa` | Lata de sopa | Armario, camioneta | Comer: Hambre +35 |
| `piel` | Piel de lobo | Lobo muerto ×1 | Receta Ropa |
| `hacha` | Hacha de piedra | Receta Herramientas | Herramienta (MANO): talar, cortar, atacar 20 |
| `antorcha` | Antorcha | Receta Fuego | Herramienta (MANO): luz, calor ×0.6, ahuyenta lobos; dura **180 s** en la mano (solo consume mientras está en MANO) |

Al comer: toast `Comes bayas (+12)` etc. Comer una lata deja `Lata vacía`? **No** (simplificación: la lata desaparece).

### Recolección — detalles
- **Pino** (`pine_a/b/c`): requiere hacha; 3 golpes (clic = 1 golpe, 0.5 s entre golpes, el personaje se coloca a ≤ 2.2 m y anima el hachazo; el árbol tiembla; al 3.º cae (rota 1 s) y desaparece; deja un **tocón** y **+4 madera**. Sacudida de cámara leve en cada golpe.
- **Árbol seco**: 2 golpes, +2 madera. Deja tocón.
- **Tronco caído**: 2 golpes, +3 madera, desaparece.
- **Leña suelta / piedra**: clic, desaparece. Reaparecen aleatoriamente: cada amanecer se generan hasta 20 leñas y 12 piedras nuevas en el mapa (máx. 60 y 40 existentes).
- **Bayas**: clic, +3; las bayas desaparecen del arbusto y reaparecen a los 240 s.

---

## 10. Fabricación

Barra vertical de **categorías** a la izquierda (iconos): 🔨 **Herramientas**, 🔥 **Fuego**, ⛺ **Refugio**, 📦 **Almacenaje**, 🍲 **Cocina**, 👕 **Ropa**. Clic → panel con la lista de recetas de esa categoría (icono, nombre, coste con iconos + número), línea de estado y botón **FABRICAR**.

Estados: `Materiales listos` (botón activo) · `Faltan materiales` · `Requiere fuego cerca` (cocina, a ≤ 3 m de fogata encendida **o** dentro de la casa con estufa encendida) · `Ya fabricado` (hacha, abrigo) · `Sin hueco en el inventario`.

| Categoría (título del panel) | Receta | Coste | Resultado | Prioridad |
|---|---|---|---|---|
| `HERRAMIENTAS` | Hacha de piedra | 2 Madera + 3 Piedra | 1 Hacha (única) | P0 |
| `FUEGO` | Antorcha | 2 Madera + 1 Piedra | 1 Antorcha (apilable) | P0 |
| `FUEGO` | Fogata | 3 Madera + 4 Piedra | **Modo colocación** (ver abajo) | P0 |
| `COCINA` | Carne asada | 1 Carne cruda | 1 Carne asada | P0 |
| `COCINA` | Bayas calientes | 3 Bayas | 1 Bayas calientes | P0 |
| `ROPA` | Abrigo de piel | 2 Piel de lobo | Se equipa automáticamente (drenaje de calor ×0.6, permanente) | P1 |
| `REFUGIO` | Tienda | 6 Madera + 2 Piedra | Colocable: refugio del viento (dentro, drenaje ×0.4) | P2 |
| `ALMACENAJE` | Caja de madera | 4 Madera | Colocable: contenedor de 6 ranuras | P2 |

Si una categoría no tiene recetas implementadas, el panel muestra `Nada que fabricar aquí todavía`. Al fabricar un objeto: toast `Fabricado: <nombre>` (p. ej. `Fabricado: Hacha de piedra`).

**Modo colocación** (fogata, tienda, caja): un "fantasma" del objeto sigue el cursor pegado al terreno; verde si válido (pendiente < 30°, a ≤ 6 m del jugador, a ≥ 1.5 m de árboles/rocas/otras fogatas, no dentro de la casa), rojo si no. Clic izquierdo confirma (se consumen los materiales **al confirmar**), clic derecho/Esc cancela. Toast `Fogata colocada`.

---

## 11. Fuego y calor

| Fuente | Radio de calor | Ganancia | Luz | Combustible | Miedo de lobos |
|---|---|---|---|---|---|
| Fogata | 4.5 m | +5/s | Omni naranja, alcance 9 m, parpadeo | Empieza con 60 s; +60 s por madera; máx 300 s; se apaga a 0 (queda el círculo de piedras, se puede reencender añadiendo leña) | 7 m |
| Estufa (casa) | todo el interior | +4/s | Omni en la estufa + ventanas | Empieza con 45 s; +90 s por madera; máx 600 s | (los lobos no entran) |
| Antorcha (en mano) | — | drenaje ×0.6 | Omni alcance 6 m | 180 s por antorcha; al agotarse toast `La antorcha se ha consumido` y se equipa la siguiente si hay | 4 m |
| Farol del porche | — | — | Omni cálida, solo de noche, decorativa | — | — |

Toasts: `La fogata se ha apagado`, `Añades leña a la fogata`, `Alimentas la estufa`.

---

## 12. Lobos (amenaza nocturna)

- Aparecen **solo de noche**. Número por noche: noche 1 → **2**, noche 2 → 3, noche 3 → 4, noche 4 en adelante → **5**. La mitad (redondeo arriba) aparece a las 20:00, el resto uno cada 60 s. Aparecen a 35–45 m del jugador, sobre terreno, nunca en el lago ni en el claro a < 15 m de la casa. Toast al primer aullido de la noche: `Los lobos merodean…`.
- A las **06:00** huyen y desaparecen al alejarse > 60 m.
- Stats: salud **60**, velocidad paseo 2.5 m/s, carrera **6.0 m/s** (igual que el jugador corriendo), mordisco **15** de daño, alcance 1.6 m, cadencia 1.5 s.
- Máquina de estados: **Merodear** (deambula a 15–25 m del jugador) → **Acechar** (rodea a 8–12 m, 4–8 s, gruñe) → **Perseguir** (corre al jugador) → **Atacar** (mordiscos) → **Huir** (8 s corriendo lejos) cuando: entra en el radio de miedo de una fogata/antorcha, recibe un golpe (30 % de probabilidad), o el jugador entra en la casa (entonces vuelve a Merodear alrededor de la casa a 6–10 m sin entrar nunca).
- Al morir sueltan `Carne cruda ×2` y `Piel de lobo ×1` como objetos recogibles y desaparecen tras 1.5 s (se encogen).
- Golpe del jugador: con hacha 20 de daño (cadencia 0.8 s), con las manos 6 (0.6 s), alcance 2.0 m. Retroceso de 1.5 m al lobo.

---

## 13. Misiones (panel derecho)

Panel `PRIMER DÍA` (pequeño) / `SOBREVIVE` (grande) / `3/8` + barra de progreso + lista: la última misión completada (tachada, con check), la actual (en negrita con una línea de pista) y la siguiente (atenuada). Al completar una: destello del panel y sonido.

**Día 1 (8 pasos, en orden):**

| # | Título | Pista | Condición |
|---|---|---|---|
| 1 | Recoge leña | Haz clic en la leña del suelo | Recoger 2 de madera (contador) |
| 2 | Entra en casa y alimenta la estufa | Si la estufa se apaga, la casa se enfría | Añadir leña a la estufa |
| 3 | Fabrica un hacha | Herramientas → Hacha de piedra | Fabricar `hacha` |
| 4 | Tala un árbol | Haz clic en un árbol con el hacha | Derribar un pino o árbol seco |
| 5 | Come algo | Busca latas en el armario | Comer cualquier comida |
| 6 | Fabrica una fogata | Fuego → Fogata, colócala cerca de casa | Colocar una fogata |
| 7 | Fabrica una antorcha | Los lobos temen al fuego | Fabricar `antorcha` |
| 8 | Sobrevive hasta el amanecer | Quédate cerca del fuego | Llega el Día 2 |

**Día 2 a 5 (`DÍA N` / `SOBREVIVE`, 4 pasos):** 1) Mantén la estufa encendida (añadir leña a la estufa) · 2) Consigue 6 de madera (contador desde el inicio del día) · 3) Come algo · 4) Sobrevive hasta el amanecer. El día 5 el último paso dice `Sobrevive hasta el amanecer final`.

El panel es guía, no obligación: las misiones no bloquean nada.

---

## 14. Victoria, derrota y puntuación

- **Derrota**: Salud = 0. Pantalla `HAS MUERTO` — `Sobreviviste N días y H horas` — `Causa: Frío | Hambre | Lobos` — botones `Reintentar`, `Menú principal`. N = día actual − 1; H = horas transcurridas del día actual desde las 06:00.
- **Victoria**: 06:00 del Día 6. Pantalla `¡HAS SOBREVIVIDO!` — `Cinco días en el bosque helado.` — `Jugar de nuevo`, `Menú principal`.
- Puntuación = días sobrevividos (se muestra también en el menú principal como `Mejor marca: N días`, guardada en `user://best.cfg`; es lo único que se persiste).

---

## 15. Pantallas e interfaz (textos exactos)

Estilo (§17): paneles azul pizarra translúcidos, bordes finos claros, títulos en mayúsculas condensadas, subtítulos en versalitas pequeñas, borde superior "escarchado" (línea clara + pequeños triángulos de hielo opcionales).

### Menú principal
Fondo: la escena del claro al atardecer con nieve cayendo (cámara fija). Título **VENTISCA**, subtítulo *Sobrevive 5 días en el bosque helado*. Botones: `Jugar`, `Controles`, `Salir`. Texto pequeño abajo: `Mejor marca: N días` (si existe). Panel `Controles`: tabla de §4.2 resumida + `Volver`.

### HUD (durante la partida)
- **Superior centro**: banner `REGIÓN` (pequeño) / `CLARO` (grande); aparece al cambiar de región (3 s), y permanece visible atenuado.
- **Superior derecha**: reloj circular `Día 1` con anillo de progreso e icono sol/luna; debajo tres anillos: Hambre (dorado), Salud (rojo), Calor (turquesa), con icono en el centro y número al pasar el cursor. Bajo ellos, cuando corresponde: `VENTISCA` (parpadeo) y el icono de abrigo si está equipado.
- **Derecha**: panel de misiones (§13).
- **Izquierda**: barra vertical de categorías (6 botones cuadrados con icono); el panel de fabricación se despliega a su derecha.
- **Inferior centro**: etiqueta de contexto (§4.3) y **barra de 10 ranuras**: ranura 1 con rótulo `MANO`, ranuras con icono + número, ranuras vacías con `+`. Tooltip al pasar el cursor: nombre y efecto (`Lata de judías · Hambre +40`).
- **Toasts**: columna superior centro (bajo el banner de región), 3 s, máximo 3 visibles.
- **Viñeta de escarcha** (calor < 30) y viñeta roja (salud < 25).
- Pista de inicio (toast largo de 6 s): `Recoge leña y alimenta la estufa antes de que anochezca.`

### Panel de contenedor
Título en mayúsculas (`ARMARIO`, `CAMIONETA`, `CAJA`), botón `✕`, 6 ranuras (icono, número, y para comida el bonus `+40` en la esquina), pie: `Clic: coger uno · Mayús+clic: coger la pila · Clic en tu barra: guardar`, botón `COGER TODO`. Se cierra con ✕, Esc, clic derecho o alejándose > 3.5 m.

### Panel de fabricación
Título = categoría (`HERRAMIENTAS`, `FUEGO`, `REFUGIO`, `ALMACENAJE`, `COCINA`, `ROPA`). Filas de recetas seleccionables; bajo la lista, estado (§10) y botón `FABRICAR`.

### Pausa
`PAUSA` — `Continuar`, `Reiniciar`, `Menú principal`, `Salir del juego`. El mundo se detiene (`process_mode` pausable).

### Fin de partida / Victoria
Ver §14.

---

## 16. Efectos ("juice")

Todo debe funcionar en el renderizador Compatibility: partículas **CPUParticles3D**, sin decals, sin volumétricos, sin SDFGI.

- Nieve constante (emisor en caja de 40×20×40 m que sigue a la cámara; 500 copos, quads sin sombreado); ventisca: segundo emisor de 900 copos con viento lateral.
- Humo de la chimenea cuando la estufa está encendida; llamas y humo en fogatas (dos emisores: llama naranja→amarillo con tamaño decreciente, humo gris translúcido subiendo); chispas al golpear un árbol (astillas color madera).
- Parpadeo de luz (ruido de energía ±15 % a ~12 Hz) en fogata, estufa, antorcha y farol.
- Vaho de respiración del jugador de noche o en ventisca (pequeñas partículas blancas desde la cara cada 3 s).
- Huellas del jugador (§8).
- Sacudida de cámara: 0.15 m/0.2 s al golpear un árbol, 0.35 m/0.35 s al recibir un mordisco.
- Resalte hover: anillo plano de color acento en la base del objeto.
- Árboles: temblor al golpear, caída con rotación al talar; objetos recogibles flotan/giran suavemente.
- Ventanas: emisión naranja de noche con estufa encendida (transición de 1 s).
- Corte de la casa: los nodos ocultos aparecen/desaparecen instantáneamente (v1), opcional fundido en v2.

---

## 17. Dirección de arte

**Low-poly, flat shading, sin texturas**: cada material es un color plano. Siluetas simples y reconocibles. Nieve "acumulada" como caras planas claras sobre las superficies superiores (tejados, copas de pinos, rocas, capó de la camioneta).

### Paleta (materiales del mundo)

| Material | Hex | Uso |
|---|---|---|
| `snow` | `#F1F5FA` | Nieve iluminada, gorros de nieve, copas |
| `snow_shadow` | `#B9CBE3` | Nieve en sombra (color de vértice del terreno en pendientes/norte), huellas |
| `ice` | `#BFE3F0` | Lago helado |
| `pine_dark` | `#2F5D3A` | Copas de pino (parte baja) |
| `pine_light` | `#4B8A55` | Copas de pino (parte alta, bajo la nieve) |
| `bark` | `#5B3F2E` | Troncos, ramas, árboles secos, tocones |
| `wood` | `#8B6543` | Madera trabajada: porche, mangos, muebles, señal, valla |
| `wood_light` | `#C7A16B` | Corte de troncos, leña, tablas claras |
| `wood_dark` | `#4A3426` | Tejados de madera oscuros, vigas, tubo/estufa (ver `iron`) |
| `stone` | `#7C8592` | Rocas, piedras, círculo de la fogata, cimientos |
| `stone_dark` | `#5A616B` | Rocas en sombra / hacha de piedra |
| `brick` | `#8E5A4A` | Chimenea |
| `iron` | `#2B2E33` | Estufa, tubo, farol, ruedas |
| `cabin_wall` | `#5D7FA6` | Tablones de la casa principal (azul-gris) |
| `cabin_trim` | `#DDE6F0` | Marcos de ventanas, esquinas, barandilla |
| `roof` | `#33383F` | Tejados (casa, cabaña en A, porche) |
| `window` | `#9CC4DD` | Cristales (de noche el código los pone emisivos `#FFB454`) |
| `truck_paint` | `#5B6B3F` | Camioneta verde oliva |
| `bush` | `#3E6B45` | Arbustos |
| `berry` | `#D9403D` | Bayas |
| `fire_orange` | `#FF8C2A` | Partículas de fuego (código), brasas |
| `fire_yellow` | `#FFD166` | Núcleo de llama (código) |
| `ember` | `#E63B12` | Puerta de la estufa encendida |
| `jacket` | `#B03A2E` | Chaqueta del jugador (rojo oscuro, contrasta con la nieve) |
| `hat` | `#2E4A7A` | Gorro y pantalón del jugador |
| `scarf` | `#E8B04B` | Bufanda, manoplas |
| `skin` | `#F1C9A5` | Cara |
| `boots` | `#2A2320` | Botas |
| `wolf_fur` | `#6E7378` | Lobo |
| `wolf_belly` | `#A9AEB2` | Vientre/hocico del lobo |
| `eyes` | `#F5D142` | Ojos de lobo/ciervo |
| `eyes_dark` | `#1E1E24` | Ojos del jugador, nariz del lobo |
| `deer_fur` | `#8A6A48` | Ciervo |
| `deer_belly` | `#C9B79C` | Vientre del ciervo |
| `cloth` | `#C9B79C` | Sábanas, tela de la antorcha |
| `paper` | `#EDE6D6` | Papeles del escritorio, esfera del reloj |
| `can_red` / `can_blue` | `#C23B3B` / `#3B6BC2` | Lata de judías (roja) / de sopa (azul) — tarros de la estantería e iconos |

### Paleta de UI

| Elemento | Hex |
|---|---|
| Fondo de panel | `#1E2A3A` al 88 % |
| Fondo de ranura | `#101826` al 70 % |
| Borde de panel | `#8FA6C0` al 45 % (1 px); borde superior "hielo" `#DCEBFA` al 70 % |
| Texto principal | `#EAF2FF` |
| Texto secundario | `#93A6BF` |
| Acento (botones, hover, anillo de resalte) | `#FFB454` |
| Botón principal (FABRICAR, COGER TODO) | fondo `#DCEBFA`, texto `#1E2A3A` |
| Hambre | `#E8A33C` |
| Salud | `#E85A6E` |
| Calor | `#4EC7B0` |
| Peligro / ventisca | `#FF5A5A` |
| Válido / inválido (colocación) | `#6FD08C` / `#FF5A5A` |

Tipografía: fuente por defecto de Godot; títulos en **mayúsculas**, negrita, espaciado de letras +1 px; subtítulos en versalitas pequeñas (`REGIÓN`, `PRIMER DÍA`) en texto secundario.

Iconos: SVG sencillos (blancos, se tintan por código), ver `ARCHITECTURE.md` §19: corazón, muslo, termómetro, sol, luna, martillo, fuego, tienda, caja, cuenco, camiseta, hacha, antorcha, madera, piedra, bayas, carne cruda/asada, lata, piel, fogata, abrigo, check.

---

## 18. Audio

No hay archivos de audio disponibles. Se diseña un **AudioManager** con ganchos por nombre; en v1 todos los sonidos pueden ser silencio o tonos generados proceduralmente (`AudioStreamGenerator`, opcional). Lista de eventos que el código dispara (para que el día que haya archivos, se enchufen sin tocar la lógica):

`ui_click`, `ui_open`, `ui_close`, `pickup`, `chop_hit`, `tree_fall`, `craft_done`, `craft_fail`, `place`, `fire_loop` (bucle, por fuente), `fire_add_wood`, `fire_out`, `stove_loop`, `eat`, `footstep_snow` (cada paso), `wolf_howl`, `wolf_growl`, `wolf_bite`, `wolf_hurt`, `wolf_die`, `player_hurt`, `player_die`, `wind_loop` (bucle con intensidad 0–1: sube de noche y en ventisca), `quest_done`, `day_start`, `win`.

Ambiente: viento como ruido blanco filtrado (opcional), intensidad 0.2 de día, 0.5 de noche, 1.0 en ventisca.

---

## 19. Alcance y prioridades

- **P0 (imprescindible)**: cámara, movimiento, clic/hover, casa con corte, estufa, armario, leña/piedra/bayas, pino/árbol seco/tronco caído, hacha, antorcha, fogata con colocación, cocina, tres stats, día/noche, ventiscas, lobos, misiones día 1–5, HUD completo, menús, victoria/derrota, huellas, nieve.
- **P1**: ciervos, camioneta como contenedor, señal con texto, valla, farol, reloj con agujas, abrigo de piel, mejor marca persistida, vaho.
- **P2**: tienda y caja de madera (recetas colocables), dormir en la cama (saltar la noche si no hay lobos a < 20 m), ocultar árboles que tapan al jugador, sonidos procedurales.
