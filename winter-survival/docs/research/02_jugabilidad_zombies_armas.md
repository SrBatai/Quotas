# 02 — Jugabilidad, zombis, armas y progresión

> Investigación de diseño para la evolución de **VENTISCA** hacia un juego de supervivencia zombi invernal de mundo abierto (pueblos, aldeas, vehículos, armas, hordas), cooperativo **1–4 jugadores** en servidores dedicados autoalojados, Godot 4.7.2, low-poly.
> Documentos hermanos: `../GDD.md` (vertical slice actual), `../ARCHITECTURE.md`, `../ASSET_SPEC.md`.
> Fecha: septiembre 2026. Autor: diseño (investigación web + análisis de referentes). Todas las cifras son **propuestas iniciales para prototipar**, no verdades: cada una lleva un rango para que el playtest la mueva.

---

## 0. Decisiones ya tomadas y resumen ejecutivo

Dos decisiones del usuario fijan el marco de este documento:

| Decisión | Valor | Consecuencia para el diseño |
|---|---|---|
| **Cámara** | **Opción A**: cámara alta en perspectiva, estilo isométrico, que sigue al jugador (como la referencia visual y el slice actual). Apuntado con ratón, interiores en corte ("casa de muñecas"). La tercera persona al hombro **no es objetivo**. | Todo el combate, el apuntado, la visibilidad y el *game feel* se diseñan para leer el mundo **desde arriba**: siluetas, anillos, conos de visión, cursor con magnetismo, cámara que se "inclina" hacia el cursor. |
| **Multijugador** | **Cooperativo PvE 1–4** en servidor dedicado. Fuego amigo y PvP son **opciones de configuración del servidor** (apagadas por defecto). | Mundo compartido y persistente; sistemas de derribado/reanimación, *pings*, botín no instanciado, reglas anti-abuso configurables; escalado de amenaza por nº de jugadores. |

### Las diez recomendaciones más importantes (resumen)

1. **El frío es el enemigo número uno; los zombis, el segundo.** Copiar a The Long Dark y a DayZ Sakhal: temperatura *sentida* = ambiente + aislamiento de la ropa − viento (solo capa exterior) − humedad. Mojarse anula el aislamiento (Valheim), y el frío no solo quita Calor: **congela** el mundo (zombis dormidos bajo la nieve, baterías que se agotan, lagos transitables, ventiscas que ciegan). §2.
2. **Director de IA ligero (Left 4 Dead) que reparte la presión entre frío y zombis.** Un solo controlador de ritmo con fases *acumulación → pico → alivio* (30–45 s), que decide **qué** presiona ahora (ventisca, horda errante, gritón, campo de congelados) y que nunca apila una ventisca con una horda salvo en eventos guionizados. §3.4.
3. **Ruido como moneda.** Toda acción tiene un radio de sonido en metros (tabla en §3.2) y las armas de fuego son el "préstamo" que se paga con zombis. Arco, ballesta y cuchillo son la vía silenciosa; escopeta y claxon son la vía "a propósito" (señuelos). §4.2.
4. **Zombis lentos por defecto (caminantes ~1.2 m/s) + variantes que rompen reglas**: corredor (poco frecuente, y se congela con el tiempo), reptador bajo la nieve, **congelado** (dormido, se despierta con ruido/calor), hinchado (nube de vapor), gritón y **acechador de ventisca** (solo aparece dentro de ventiscas). Cada variante castiga una conducta concreta y empuja al grupo a moverse junto (lección de L4D). §3.1.
5. **Combate para cámara alta**: cursor con magnetismo (radio 1.2 m), cono de precisión que se cierra al quedarse quieto (Project Zomboid), *hitstop* de 3–5 fotogramas, sangre sobre nieve persistente, contorno del objetivo cuerpo a cuerpo. Sin apuntar a la cabeza "de verdad": el **crítico = disparo a la cabeza** y depende de tiempo de apuntado + habilidad. §4.
6. **Tabla de 14 armas (12 principales + arrojadizas)** con daño, cadencia, alcance, ruido y durabilidad calibrados para un caminante de 100 PV: bate = 3–4 golpes, hacha = 2, pistola = 4 al cuerpo o 1–2 críticos, escopeta = 1 a ≤ 6 m. §4.6.
7. **Vehículos como base móvil ruidosa**: llaves/puentear, batería que muere con el frío, cadenas para nieve profunda, calefacción que gasta gasolina, ruido que trae hordas, maletero compartido por el grupo, motonieve como "moto de Days Gone". §5.
8. **Botín no instanciado, respawn tipo DayZ (nominal/mínimo/tiempo sin visitar)** con tablas por tipo de edificio y tres rarezas; peso real con umbrales de 80 % / 100 % / 120 %. §6.
9. **Progresión híbrida**: habilidades que suben por uso (Zomboid) pero con XP solo por acciones "significativas" (para evitar el *grind* que hizo que 7 Days to Die abandonara el sistema) + una elección de ventaja cada dos niveles + planos encontrados como llaves de progreso. Meta-objetivo: **la torre de radio → la evacuación**. §7.
10. **Co-op**: derribado con 60 s de desangrado y reanimación de 4 s; muerte = reaparecer en la cama de la base y recuperar la mochila del cadáver; *pings* contextuales (Apex); chat de texto siempre + voz opcional por proximidad; fuego amigo en tres niveles (0 % / 25 % / 100 %) y PvP como interruptor de servidor con zonas seguras. Escalado: zombis × (1 + 0.5·(n−1)), como 7 Days to Die. §10.

---

## 1. Análisis de referentes: qué copiar, qué evitar

### 1.1 Tabla resumen

| Juego | Cámara | Pilar que lo hace divertido | **Copiar** | **Evitar** |
|---|---|---|---|---|
| **Project Zomboid** | Isométrica (la más cercana a la nuestra) | "Así es como moriste": simulación honesta, zombis lentos pero infinitos, ruido y visión como sistema central, habilidades por uso, vehículos con llaves/puente | Cono de visión del personaje (lo que no ves no se dibuja); radios de ruido en losetas (pistola 50–100, rifle 100, escopeta 150–200; silenciador ×0.2); crosshair que cambia de color según la precisión; *melee target outline*; meta-eventos (helicóptero, disparos lejanos) que mueven población; 500 zombis máximo alrededor de cada jugador; ruido de vehículo = f(motor, tubo de escape, RPM) | Curva de aprendizaje brutal de la UI (menús contextuales por clic derecho para todo); olfato "de mentira" (opción que no hace nada: si ponemos olfato, que funcione); progresión pasiva lentísima (Fuerza/Forma); cero dirección de ritmo (semanas sin nada) |
| **DayZ** (+ mods Namalsk, DLC Frostline/Sakhal) | Tercera persona / primera | Tensión por escasez y persistencia; Sakhal demuestra que el frío puede ser el eje: *Heat Comfort* afectado por clima, ropa, acciones, comida; objetos con temperatura; comida congelada que hay que calentar; lagos helados sin pesca; fuentes termales como "hogueras eternas" | Economía central de botín (nominal / mínimo / vida / reposición por tipo y por etiqueta de edificio); infectados con estados **inactivo → búsqueda → persecución** con gruñido/chillido como aviso; Namalsk: "el frío mata más que los zombis" | Onboarding nulo; muerte permanente sin base (no encaja en co-op de 4 amigos); economía pensada para 60 jugadores |
| **State of Decay 2** | Tercera persona | Comunidad de supervivientes con permadeath, "freaks" muy legibles (gritón, hinchado, feral, juggernaut), armas que se rompen, coches como herramienta | Tipos de zombi especiales con contra-táctica única; categorías de cuerpo a cuerpo (contundente / cortante / pesado) con especializaciones; asaltos a la base como evento; vehículos con maletero | Co-op "de visita" (el invitado no progresa, botín amarillo/azul instanciado, correa de 450 m al anfitrión); reparación de armas con "piezas" tediosa; moral que se desploma y peleas que ocurren fuera de cámara; sensación de "mecánicas de videojuego" pegadas |
| **7 Days to Die** | Primera persona | Luna de sangre: **la fecha límite** que convierte el saqueo en preparación; zombis que corren de noche; *gamestage* que escala | Un evento periódico y anunciado (nosotros: la **Gran Ventisca** cada N días, con horda migratoria detrás); escalado co-op: recuento × (1 + 0.5·(n−1)) y *gamestage* de grupo = 0.5·máx + 0.5·media; gritona que aparece al acumular "calor" (actividad) | Zombis que excavan (rompe la lectura del mundo); abandonaron "aprender haciendo" por el *grind* → aviso para nuestro §7 |
| **Unturned** | Tercera / primera | Accesible, ligero, legible; zombis con botín temático por su ropa (policía → munición; médico → medicinas) | Zombi = contenedor temático (sin abrir menús: suelta al morir); variantes claras (sprinter, reptador, flanqueador, ácido, mega) | Estética "todo cubos" (nosotros tenemos ya identidad low-poly); PvP central |
| **The Long Dark** | Primera persona | El frío como sistema completo: ropa con calor/viento/agua/peso, humedad, congelación, hipotermia, ventiscas que ciegan, hielo débil | Fórmula térmica y la **capa exterior es la que corta el viento**; humedad quita 1 % de cortaviento por cada 1 % de humedad y hasta −15 % de calor; cruzar hielo débil = ropa 100 % mojada + hipotermia inmediata; congelación = pérdida permanente de vida máxima (−10 %); ventisca = visibilidad casi cero + movimiento −50 % contra el viento; arco silencioso y flechas recuperables | Ritmo contemplativo sin amenaza activa (no hay "director"); mucho tiempo en menús de cocina/curación |
| **Days Gone** | Tercera persona | Hordas de 50–500 con rutina (duermen de día en cuevas, beben y comen de noche), persistentes (los muertos no vuelven), moto como cordón umbilical (gasolina, ruido, reparación) | Rutina diaria de la horda y **rastros** (huellas en la nieve = nuestro equivalente perfecto); explosivos y cuellos de botella como forma de vencerla; motonieve = moto | Escala de horda irrealizable en Godot con 4 jugadores en red sin LOD de IA muy agresivo (§3.6) |
| **Dying Light 1/2/The Beast** | Primera persona | La noche cambia las reglas (volátiles, oscuridad real, linterna a pocos metros) con **doble XP** como recompensa por el riesgo; combate cuerpo a cuerpo con peso | Noche = riesgo/recompensa explícito (nosotros: de noche la nieve no se derrite, el botín "brilla" menos, pero los congelados están dormidos → ventana para saquear en silencio); "equipo de choque" iterando semanalmente sobre spawns y persecuciones | Parkour (no aplica); tienda de armas 1500 variantes (ruido de diseño) |
| **Left 4 Dead 1/2** | Primera persona | Director de IA: mide la **intensidad** de cada superviviente y regula la **frecuencia**, no la dificultad; especiales que castigan separarse (fumador tira, cazador inmoviliza, boomer atrae) | Fases *build-up → peak → relax (30–45 s)*; hordas de 10–30 cada 1–4 min a los lados/espalda; "nunca separes al grupo" como pilar co-op; derribado con 300 PV temporales y desangrado; 2 derribos → pantalla en blanco y negro → muerte | Linealidad (nosotros somos mundo abierto: el director trabaja por "zona activa", §3.4) |
| **Sons of the Forest** | Primera persona | Co-op 8 con base persistente; IA de caníbales con "curiosidad, miedo, agresión" y memoria de sentimiento | Estado herido: otro jugador mantiene E ~5 s y te levantas con 10 PV sin necesidad de botiquín (simple y funciona); IA con **memoria de agravios** (nosotros: hordas "recuerdan" la base si la atacan mucho) | IA que se queda mirando mientras saqueas su campamento; correr lo resuelve todo |
| **Winter Survival (2024–26)** | Primera persona | (Referente negativo) | Nada específico | Mecánicas "irrazonables" y rígidas, sistema de cordura sin explicar, colisiones con bugs, "¿para quién está hecho?" — recordatorio de que el frío tiene que ser **legible** (ver §2.2: cada penalización con icono, número y causa) |
| **Frostpunk** | Estrategia | El frío como presión de fondo a −120 °C y **Esperanza / Descontento** como medidores morales | Un "termómetro de la base" visible; eventos de frío anunciados (la temperatura baja en 48 h) para forzar preparación; leyes ≈ nuestras "reglas de la base" (racionar, turnos de guardia) — solo si añadimos NPC | Micromanagement de ciudad |
| **Valheim** | Tercera persona | Mundo compartido persistente en servidor dedicado; **Frío/Congelación** en montaña anulado por hidromiel/capa de lobo, pero **mojado anula la resistencia** | Regla "mojado anula el aislamiento" (una sola regla, muy legible); muerte = cadáver con inventario (*corpse run*) sin perder progreso de habilidades (solo un %); todos saquean, nadie es "invitado" | — |
| **Darkwood** | Cenital | Terror desde arriba: el cono de visión colorea lo que ves; lo demás es gris y engañoso | Demostración de que la cámara alta puede dar miedo: **cono de luz/visión** + sonido fuera del cono; en ventisca el cono se encoge a 6 m | Ritmo lento tipo *point & click* |
| **Survivalist: Invisible Strain** | Tercera/cenital | Zomboid-like con colonos; estética *cel-shaded* que se lee a distancia | Contornos gruesos y animaciones exageradas para leer situaciones desde lejos (aplica a nuestro low-poly) | Dureza sin explicación |
| **Alien Swarm** (Valve) | Cenital | Cooperativo cenital de 4 con fuego amigo, clases y oleadas | Prueba de que **cenital + 4 jugadores + fuego amigo** funciona: cursor, linternas, y los explosivos "gibean" al compañero (humor); interfaz de munición compartida y *pings* de botín | Clases rígidas (nosotros: roles emergentes por habilidad) |
| **Deep Rock Galactic** | Primera persona | Co-op "eficiencia de equipo, no héroes"; fuego amigo escalado por peligro (×0.1 en Hazard 1 → ×0.7 en Hazard 5, explosivos −50 % adicional) | **Fuego amigo escalado** como opción de servidor (0 % / 25 % / 100 %); recompensas compartidas al final de la sesión; enemigos que exigen flanqueo | — |

### 1.2 Pilares extraídos para nuestro juego

1. **Legible desde arriba** (heredado del GDD): siluetas, anillos, huellas, humo, luz = información. Todo peligro debe ser leíble a 20 m con la cámara a 22 m de distancia.
2. **El frío decide el ritmo**: cada bucle empieza y acaba en una fuente de calor. Los zombis son el obstáculo entre dos fuentes de calor.
3. **Ruido = préstamo**: el jugador elige cuándo ser ruidoso; el juego siempre le dice el precio (anillo de ruido en el suelo al disparar).
4. **Nunca separes al grupo, pero permite separarse**: los especiales castigan al lobo solitario (L4D), pero el mundo abierto permite dividirse para saquear con *pings* y radio.
5. **Persistencia honesta**: lo que matas no vuelve pronto; lo que rompes queda roto; el cadáver guarda tu mochila; la base se enfría si nadie alimenta la estufa.
6. **Un director, no un guion**: el ritmo lo lleva un algoritmo que combina presión térmica y presión zombi, con 30–45 s de alivio garantizados tras cada pico.

---

## 2. Bucles de juego y el frío como presión central

### 2.1 Tres escalas de bucle

**Momento a momento (10–60 s)** — mirar los tres anillos (Hambre / Salud / Calor) y el **termómetro exterior**; decidir: ¿me queda calor para llegar hasta allí y volver? → moverse en silencio o rápido → abrir contenedor / talar / disparar → reaccionar al ruido que acabo de hacer → volver al calor.

**Sesión (45–120 min, 1–4 jugadores)** — la "expedición": elegir objetivo en el mapa (gasolinera a 600 m, comisaría a 1.2 km), preparar (ropa seca, antorcha, munición, gasolina), ir (a pie o en coche), saquear con ventana de tiempo marcada por el frío y por el director, volver antes de la noche o de la ventisca anunciada, descargar en la base, mejorar algo (estufa mejor, cadenas, radio) y dormir para saltar la noche si todos están en la base.

**Meta (10–30 h por partida/servidor)** — de "sobrevivir la primera semana" a "repara la torre de radio", "encuentra un vehículo pesado", "llega a la evacuación". Cada 7 días de juego, la **Gran Ventisca** (evento anunciado 1 día antes) actúa como la luna de sangre: −20 °C extra durante 1 día de juego, visibilidad 6 m y una horda migratoria que sigue el viento hacia el asentamiento más ruidoso.

```
   Calor ─────► Salir ─────► Saquear/cazar/talar ─────► Ruido ─────► Zombis
     ▲                                                                  │
     │                                                                  ▼
   Base ◄──── Volver (coche/pie) ◄──── Ventisca/noche anunciada ◄──── Huir/luchar
     │
     └──► Fabricar / mejorar / dormir ──► nueva expedición (más lejos, más frío)
```

### 2.2 Modelo térmico propuesto (versión "Long Dark legible")

El slice actual usa un Calor 0–100 con drenajes fijos. Para el mundo abierto proponemos **mantener el anillo de Calor** (0–100) pero calcular su drenaje a partir de una **temperatura sentida** visible en el HUD:

```
T_sentida = T_ambiente
          + Aislamiento_ropa (suma de capas, 0…+40 °C)
          − Viento_efectivo   (0…25 °C; solo lo reduce la capa exterior "cortaviento")
          − Humedad_penal     (0…12 °C)
          + Fuente_calor      (hoguera/estufa/vehículo/termal: +10…+40 °C según distancia)
```

| Parámetro | Valor propuesto (rango) | Fuente / justificación |
|---|---|---|
| Temperatura ambiente día / noche | −8 °C / −18 °C (−4…−25) | Sakhal: "casi siempre bajo cero" |
| Ventisca | −10 °C adicionales + viento 25 | TLD: el viento puede duplicar el frío |
| Umbral de confort | T_sentida ≥ 0 °C → Calor sube +2/s hasta 100 | — |
| Drenaje | Calor −(0 − T_sentida) × 0.06 /s (a −10 °C sentidos: −0.6/s ≈ 100 → 0 en 2.8 min) | Calibrado al slice (día 250 s, noche 100 s) |
| Ropa: 3 capas (interior, media, exterior) + cabeza, manos, pies | Cada prenda: Aislamiento (°C), Cortaviento (%), Impermeable (%), Peso (kg), Estado (%) | TLD: 6 atributos; nosotros 5 |
| Humedad | 0–100 % por prenda. Nieve profunda / caer al agua / sudor al correr > 60 s. Cada 10 % de humedad: −1 °C de aislamiento **y** −10 % de cortaviento. Secado: 1 %/s junto al fuego, 0.1 %/s en interior | TLD: −1 % cortaviento por 1 % humedad; Valheim: mojado anula |
| Calor < 30 | Viñeta de escarcha, aviso "Tienes frío" (ya existe) | GDD §5 |
| Calor < 15 | Velocidad ×0.8, temblor en la mira (cono ×1.5), no puedes recargar rápido | Hipotermia como penalización a la puntería |
| Calor = 0 | Salud −4/s; tras 60 s a 0: **Congelación** en la parte del cuerpo desnuda → −10 % de salud máxima permanente | TLD frostbite |
| Correr | Genera humedad interna (+0.5 %/s a partir de 20 s corriendo) | Sudor: incentiva alternar |

**Regla de oro**: cada penalización se muestra con icono + número + causa ("−6 °C: guantes mojados"). Winter Survival fue castigado por lo contrario.

### 2.3 Formas del frío como presión de juego

| Forma | Mecánica | Por qué es divertida |
|---|---|---|
| **Ropa por capas** | Saqueas ropa de armarios, cadáveres y zombis (los zombis con abrigo son botín). El abrigo militar es raro y pesa. La capa exterior es la única que corta el viento. | Decisiones de inventario; lectura visual (el abrigo cambia el modelo) |
| **Humedad** | Nieve profunda (visible, más clara y "esponjosa"), caídas al hielo, correr. Se seca junto al fuego. | Castiga correr sin pensar; recompensa las hogueras "de camino" |
| **Calefacción del refugio** | La estufa consume leña (ya existe). Casas mejores retienen más calor (aislamiento del edificio 0–1). Ventanas rotas = −aislamiento. Generador + estufa eléctrica en la base final. | Base = tarea compartida; dos jugadores talan mientras dos saquean |
| **Ventiscas** | Aviso 60 s antes (viento sube, banner). Visibilidad 6 m (niebla densa + partículas), cono de visión de todos (jugadores y zombis) a 6 m; el ruido se propaga ×0.6; los congelados no se despiertan; aparece el **acechador de ventisca**. Duración 2–4 min de juego. | Convierte el mapa conocido en desconocido; obliga a llevar cuerda/bengalas/faros |
| **Zombis ocultos por la ventisca** | Dentro de la ventisca, los zombis se dibujan solo dentro del cono de 6 m y **suenan** fuera (gruñido posicional). | Miedo Darkwood; fomenta ir en pareja |
| **Lago helado** | Hielo grueso (azul claro, seguro) / hielo fino (más oscuro, cruje, icono "!") / agujero. Caer = ropa 100 % mojada + Calor −40 + 10 % de salud; los zombis pesados (hinchado, coloso) rompen el hielo fino → **arma ambiental**: atraer una horda al hielo fino. Pesca en agujero (comida). Los vehículos ligeros (motonieve) cruzan; los coches rompen el hielo. | Atajos con riesgo; táctica de horda |
| **Calefacción del vehículo** | Motor encendido: interior +25 °C sentidos (cabina cerrada) pero consume 0.3 L/min y hace ruido (20 m parado). Con ventana rota: +10 °C. | El coche como refugio de emergencia ruidoso |
| **Objetos con temperatura** | Latas congeladas (−50 % de hambre recuperada hasta calentarlas 30 s junto al fuego), pilas que rinden −50 % bajo −10 °C, agua que se congela en la cantimplora. | Sakhal: "los objetos tienen temperatura" |
| **Noche** | −10 °C, visibilidad 12 m, faroles y ventanas como referencia. Dormir en cama con ≥ 1 jugador en base y sin zombis a < 20 m: todos votan y se salta la noche (ya en GDD P2). | La noche como coste, no como muro |

### 2.4 Caza, saqueo, fabricación y base: cómo encajan

| Actividad | Aporta | Riesgo/ruido | Herramienta clave |
|---|---|---|---|
| **Caza** (ciervo, conejo, lobo; huellas en la nieve como pista) | Carne (calor + hambre), piel (ropa), grasa (antorchas, velas) | Arco silencioso (5 m de ruido); rifle atrae zombis pero mata a 45 m | Arco, trampas |
| **Saqueo** (pueblos) | Ropa, latas, medicinas, munición, piezas, planos | Ruido de puertas/ventanas, zombis dentro, alarmas | Palanca (abre sin ruido de cristal: 8 m vs 25 m) |
| **Tala/recolección** | Leña (calor), piedra, chatarra | Golpes de hacha = 10 m de ruido cada uno | Hacha, sierra (más leña por árbol, +ruido) |
| **Fabricación** | Herramientas, ropa, refugio, munición casera, cadenas, generador | Requiere estación (banco, forja, cocina) | Planos encontrados |
| **Base** | Calor, camas (respawn), almacenaje compartido, defensas (vallas, trampas, barricadas), radio | Los asaltos siguen al ruido acumulado ("calor" de 7DTD) | Martillo, clavos, tablones |

La base **no es una construcción libre tipo Minecraft**: proponemos un sistema de **reclamar edificios existentes** (SoD2) + **mejoras en ranuras** (estufa, camas, almacén, taller, radio, generador, barricadas) + colocación libre de un puñado de piezas (valla, barricada, hoguera, tienda, caja). Esto cabe en producción y se lee desde arriba.

### 2.5 Sesión y progresión para 1–4 jugadores

| Nº jugadores | Sesión típica | Cómo escala el juego |
|---|---|---|
| 1 | 45–60 min: una expedición corta + mantenimiento. El director usa el presupuesto base (×1.0) y, como no habrá NPC compañeros en v1, sube la probabilidad de vehículos con llave en el contacto (+10 %) para acortar viajes | Zombis ×1.0; botín ×1.0 |
| 2 | 60–90 min: uno conduce, otro dispara desde la ventanilla; uno tala, otro vigila | Zombis ×1.5; botín nominal ×1.25 |
| 3–4 | 90–120 min: dos parejas; una base con turnos; expediciones lejanas (comisaría, hospital, base militar) | Zombis ×2.0 / ×2.5; especiales +1 por cada 2 jugadores; botín nominal ×1.5 / ×1.75 (sub-lineal: escasez relativa) |

El día de juego pasa de 7 min (slice) a **30 min reales** (día 20 min / noche 10 min) para que una expedición quepa en un día y la noche siga siendo corta. La Gran Ventisca cada 7 días de juego = cada ~3.5 h de sesión acumulada.

---

## 3. Zombis

### 3.1 Tipos

Jugador de referencia: 100 PV, caminar 3.0 m/s, correr 6.0 m/s (GDD), aguante 100 (correr −5/s, golpear −8 por golpe).

| Tipo (nombre en juego) | PV | Velocidad | Daño / cadencia | Sentidos | Regla que rompe | Contra-táctica | Cuándo aparece | % población |
|---|---|---|---|---|---|---|---|---|
| **Caminante** | 100 | 1.2 m/s (1.0–1.4) | 12 / 1.2 s; agarre si 2+ adyacentes (−50 % velocidad 1.5 s) | Vista 25 m día / 12 m noche / 6 m ventisca, cono 120°; oído según tabla §3.2 | Ninguna: es el "ladrillo" | Caminar más rápido que él; cuellos de botella; palanca | Siempre | 70 % |
| **Corredor** | 70 | 5.5 m/s en ráfagas de 4 s, luego 3.0 m/s 3 s (se fatiga) | 10 / 0.9 s | Vista 30 m, cono 90° | Te alcanza corriendo | Puertas (no abre, golpea 3 s), disparo, lanza. **Se congela**: si pasa 10 min fuera bajo −10 °C sin estímulo, pasa a Caminante (frágil) | Día 3+ | 8 % (máx. 2 por horda) |
| **Reptador** | 50 | 1.0 m/s | 8 / 1.0 s + agarre de piernas (2 s inmóvil, puedes patear) | Oído ×1.5, vista 8 m | Invisible bajo nieve profunda (solo un bulto y vaho) | Mirar el vaho; bengala; caminar por nieve pisada | Siempre (zombis "rotos") | 7 % |
| **Congelado** ("dormido") | 100 (recibe ×1.5 daño contundente: "se astilla") | 0 hasta despertar; luego Caminante ×0.8 durante 30 s | 12 / 1.2 s | Solo despierta por: ruido ≥ 15 m de radio a ≤ 8 m, jugador a ≤ 1.5 m, calor (hoguera a 4 m, tubo de escape a 3 m, subida de T ambiente ≥ −2 °C) | El "campo de minas" del juego: un pueblo lleno de bultos que despiertan con tu escopeta | Silencio; matarlos dormidos con cuchillo (ejecución de 1.5 s, silenciosa); usarlos: atraer a otro grupo hacia el campo con un claxon | Siempre, en exteriores; a partir de −10 °C todo caminante sin estímulo durante 5 min se congela (esto **recicla población** y ahorra CPU) | 10 % activos + toda la población "parada" |
| **Hinchado** | 150 | 0.9 m/s | 15 / 1.5 s; al morir: nube de vapor 4 m de radio, 8 s: visibilidad 0 dentro, −5 Calor/s (humedad +10 %/s) y **olor** que atrae zombis a 30 m | Vista 15 m | Muerte = peligro (SoD2 Bloater) | Matarlo lejos con arco/rifle; nunca cuerpo a cuerpo dentro de casa | Pueblos, día 5+ | 3 % |
| **Gritón/a** | 60 | 2.0 m/s, mantiene 8–12 m | Grito: radio 60 m, 3 s de canal (interrumpible), atrae 6–15 zombis y despierta congelados a 20 m | Vista 25 m | Convierte sigilo en horda | Arco/ballesta desde lejos; matar en el canal | Día 4+ | 1.5 % |
| **Acechador de ventisca** | 120 | 4.0 m/s, silencioso (pasos 0 m) | 25 / 1.5 s, primer golpe por la espalda ×2 | Vista 6 m (como todos en ventisca) pero **te huele a 20 m** | Solo existe dentro de ventiscas; camuflaje blanco; ataca a quien se separe > 10 m del grupo | Ir en pareja; bengala (le hace huir 15 s, como el lobo); quedarse en interior | Ventiscas, día 6+; 1 por ventisca por cada 2 jugadores fuera | Evento |
| **Acorazado** (policía/SWAT/soldado) | 100 | 1.2 m/s | 12 | Como Caminante | Daño al cuerpo ×0.5 (chaleco); casco: crítico ×0.5 hasta que se le cae (2 golpes contundentes) | Contundente a la cabeza; quitar el casco; **suelta botín de su uniforme** (Unturned) | Comisaría, base militar | 0.5 % (local) |
| **Coloso** (opcional, v2) | 600 | 2.5 m/s; embestida 7 m/s | 40 / 2.0 s; rompe puertas y barricadas de un golpe; **rompe el hielo fino** | Vista 20 m, oído ×2 | Tanque | Explosivos, molotov, coche, hielo fino | Base militar / Gran Ventisca | 0 % fuera de eventos |

Notas:
- Cada tipo tiene **silueta única a 20 m** (reptador bajo, hinchado ancho, gritón sin brazos como SoD2, acechador blanco, acorazado con casco) y **sonido único** (gruñido, respiración, crujido de hielo, borboteo, grito).
- Infección: mordisco = 10 % de "Fiebre" (−1 Calor/s durante 10 min, curable con antibióticos raros o 8 h de cama). **Sin muerte por infección** en v1: el permadeath por infección de Zomboid es incompatible con un co-op de amigos que juega 90 min por sesión.

### 3.2 Sentidos y eventos de ruido

**Vista**: cono de 120° (90° corredor), rango según luz/clima; visión periférica 360° a 3 m. Comprobación cada 0.2 s a < 40 m (§3.6). Probabilidad de detección por segundo dentro del cono = `clamp(1 − d/R, 0, 1) × luz × postura` (agachado ×0.5, quieto ×0.7, corriendo ×1.3, antorcha/linterna encendida de noche ×2.0).

**Oído**: cada acción emite un `SoundEvent(pos, radio_m, prioridad)`. Un zombi a distancia `d ≤ radio` fija ese punto como objetivo de **investigación** con probabilidad `1 − d/radio` (mínimo 0.3 si es un arma de fuego). Muchos ruidos seguidos = "calor de zona" (contador que decae 1/min) que el director usa para enviar un gritón o una horda errante (7DTD Screamer).

**Olfato** (implementado, a diferencia de Zomboid): solo dos casos, ambos legibles: (1) jugador **sangrando** o con **> 3 carnes crudas** encima → detectable a 8 m sin línea de visión; (2) el vapor del hinchado y el acechador (20 m). Nada más.

**Memoria**: última posición conocida 20 s; si no hay estímulo nuevo en 45 s vuelve a vagar. Los zombis en estado *investigar* que llegan al punto y no ven nada se quedan 10–20 s (ventana para emboscar).

| Fuente de ruido | Radio (m) | Notas |
|---|---|---|
| Paso agachado / andando / corriendo | 2 / 6 / 14 | Nieve profunda ×0.7 (amortigua), hielo ×1.3 |
| Abrir puerta / cerrar de golpe / forzar con palanca | 6 / 15 / 8 | Zomboid: dentro de un edificio el radio se divide entre 2 |
| Romper ventana / cristal de coche | 25 / 20 | La palanca abre sin romper |
| Golpe cuerpo a cuerpo (bate, hacha) / cuchillo | 10 / 3 | El golpe que falla también suena (8) |
| Empujón / patada | 8 | — |
| Arco / ballesta | 5 / 6 | Silenciosos |
| Pistola 9 mm / revólver .357 | 80 / 90 | Zomboid: 50–100 losetas (≈ 1 loseta = 1 m) |
| Rifle de caza / carabina | 120 / 110 | — |
| Escopeta | 150 | Zomboid: 150–200 |
| Silenciador | ×0.3 | Zomboid: ×0.2 |
| Motor al ralentí / conduciendo / a fondo | 20 / 45 / 70 | Zomboid: radio = f(volumen, RPM); mínimo 8 |
| Claxon | 120 (mientras se pulse) | Señuelo deliberado |
| Alarma de coche / de casa | 150 durante 30 s / 60 s | 15 % al puentear; 5 % al forzar una puerta de tienda |
| Generador | 30 (constante) | Ubicarlo lejos de la casa |
| Bengala | 0 de ruido, pero **luz**: atrae zombis a 40 m durante 30 s | Señuelo silencioso y calor +5 |
| Bomba de tubo | 60 durante 6 s, luego explosión 5 m (150 daño) | L4D pipe bomb |
| Grito del gritón | 60 | — |
| Ventisca | Todo ×0.6 | El viento enmascara |
| Multijugador | Sin reducción por defecto (Zomboid divide entre 1.8: opción de servidor `NoiseScale`) | — |

### 3.3 Hordas, población y migración

- **Población por celda** (100 × 100 m): cada celda tiene una densidad objetivo según el tipo de zona (bosque 0–3, aldea 8–20, pueblo 25–60, comisaría/hospital 40–80, base militar 100+). La población **no reaparece** hasta que la celda lleva **72 h de juego sin ningún jugador a < 150 m** y solo hasta el 60 % de su valor original (Zomboid "respawn unseen hours"; DayZ *nominal/min*). Los cadáveres desaparecen a las 24 h de juego (o antes si se queman: el humo atrae).
- **Hordas errantes**: 8–20 zombis que siguen carreteras entre pueblos; 1–3 activas por 1 km² alrededor de los jugadores. Las genera el director (§3.4) fuera de la vista.
- **Gran horda migratoria** (Days Gone): 60–120 zombis, **una** por mapa, con rutina: de día duermen en un edificio grande (nave, iglesia, gimnasio) o congelados en un campo; de noche se mueven por la carretera hacia la zona con más "calor de ruido" acumulado en los últimos 3 días. Dejan **rastro** (nieve pisada, sangre, cadáveres de animales) que se puede seguir. Persistente: lo que matas no vuelve; si la reduces a < 15 se disuelve en errantes.
- **Meta-eventos** (Zomboid): helicóptero (día 6–9, mueve zombis hacia el jugador más ruidoso), disparos lejanos, aullidos, alarma remota. 1–2 por día de juego, nunca durante una ventisca.
- **Asalto a la base** (SoD2/7DTD): si el "calor de ruido" de la base supera un umbral (≈ 30 min de generador o 20 disparos en un día), a la noche siguiente llega una horda de 10 + 5·n_jugadores, anunciada 2 min antes por gruñidos y por el perro-de-radio (si hay radio: "movimiento al norte").

### 3.4 Director de IA (ritmo)

Un único nodo `Director` en el servidor, inspirado en Left 4 Dead pero por **zona activa** (radio 150 m alrededor de cada jugador; zonas solapadas se fusionan).

**Intensidad por jugador** (0–1):

| Evento | Δ intensidad |
|---|---|
| Recibir daño | +0.30 (+0.5 si te deja < 30 PV) |
| Matar a < 5 m | +0.10 |
| ≥ 4 zombis a < 8 m | +0.15/s mientras dure |
| Derribado | = 1.0 |
| Calor < 30 | +0.05/s (el frío también es intensidad) |
| Sin amenaza | −0.03/s (decae a 0 en ~30 s) |

**Intensidad del grupo** = máx. de los jugadores de la zona (L4D usa el máximo: un jugador en apuros = todo el grupo en pico).

| Fase | Entrada | Qué hace el director | Salida |
|---|---|---|---|
| **Acumulación** | Por defecto | Rellena el presupuesto de zombis activos fuera de vista (≥ 30 m, sin línea de visión, nunca "a la espalda" del jugador a < 15 m); lanza 1 evento cada 45–120 s (aleatorio, ponderado por zona y clima): horda errante, gritón, meta-sonido, despertar de congelados, acechador (solo en ventisca) | Intensidad ≥ 0.8 durante ≥ 15 s, o han pasado 4 min |
| **Pico** | — | Deja de generar; deja que la situación se resuelva | Intensidad < 0.3 |
| **Alivio** | — | 30–45 s **sin generar nada** (acorta si el grupo se mueve > 60 m); si la vida media del grupo < 40 %, sube la probabilidad de vendas/latas en los próximos 3 contenedores (+25 %) | Fin del temporizador |

**Presupuesto de zombis activos por zona** (L0+L1, §3.6): `12 × (1 + 0.5·(n−1))` → 12 / 18 / 24 / 30 para 1–4 jugadores, ± 30 % según tipo de zona; **máximo duro 60 activos por zona y 500 instancias por servidor**.

**Reglas de cortesía del director** (para que "no haga trampas"):
1. Nunca solapa ventisca + horda errante salvo Gran Ventisca.
2. Durante una ventisca reduce el presupuesto zombi ×0.5 (el frío ya es la presión) y añade el acechador.
3. Si el grupo lleva > 10 min sin ver un zombi, garantiza un evento menor (evita el vacío de Zomboid).
4. Los especiales aparecen con **anuncio** (grito, borboteo, respiración) ≥ 3 s antes de actuar.
5. El director no genera dentro de edificios ya limpiados por los jugadores (marcados durante 72 h).

**Escalado por número de jugadores** (7 Days to Die): recuento × (1 + 0.5·(n−1)); PV de zombi **sin cambios** (los zombis "esponja" se sienten injustos); especiales: +1 tipo por cada 2 jugadores en el evento; *gamestage* del grupo = 0.5·máx + 0.5·media de (días sobrevividos + nivel medio de habilidades).

### 3.5 Comportamiento por hora y temperatura

| Condición | Efecto sobre zombis |
|---|---|
| Día (−8 °C) | Normal |
| Noche (−18 °C) | Vista 12 m, oído ×1.3; los congelados **no despiertan por calor** (solo por ruido/contacto): la noche es la ventana de sigilo |
| T ambiente ≤ −10 °C, sin estímulo 5 min, exterior | Caminante → Congelado (reciclaje) |
| Zombi congelado recibe golpe contundente | Daño ×1.5 y "astillado" (partículas de hielo) |
| Cerca de fuego/tubo de escape/interior calentado | Congelado → despierta en 3 s (crujido); corredor recupera velocidad |
| Ventisca | Vista 6 m, ruido ×0.6, no despiertan, aparece el acechador |
| Gran Ventisca (cada 7 días) | Horda migratoria se mueve **con el viento** hacia la base más ruidosa; congelados en un radio de 200 m de la base despiertan en oleadas cada 5 min |
| Deshielo (evento raro de 1 día, T ≥ 0 °C) | Todo el campo de congelados de la zona despierta en 10 min: el mapa "explota"; anunciado 1 día antes por la radio/el cielo |

### 3.6 LOD de IA y presupuesto en pantalla

| Nivel | Distancia al jugador más cercano | Simulación | Render | Coste objetivo |
|---|---|---|---|---|
| **L0 (completo)** | < 40 m o en pantalla | `CharacterBody3D` + `NavigationAgent3D` con evasión; sentidos cada 0.2 s; ruta cada 0.5–1 s; ataques con *hitbox*; red: 20 Hz | Esqueleto completo, animación mezclada, sombras | ≤ 40 por zona |
| **L1 (simplificado)** | 40–120 m | Sin evasión; sentidos cada 1 s; ruta cada 2–3 s (`NavigationServer3D.map_get_path` escalonado por fotogramas); sin física, se mueve sobre la malla de navegación | Esqueleto de 4 huesos o `MultiMeshInstance3D` con animación por vértice (VAT) a 15 fps; sin sombras | ≤ 80 por zona |
| **L2 (grupo)** | 120–400 m | **Una entidad "grupo"**: posición, cuenta, estado, destino sobre el grafo de carreteras; sin instancias; al entrar en L1 se "desempaqueta" en posiciones alrededor del centro (World War Z Swarm: la IA de la masa es simple de lejos y se individualiza al acercarse) | Nada, o puntos de vaho | Casi cero |
| **L3 (celda)** | Fuera de las zonas activas | Solo cuenta y temporizadores de respawn por celda; congelados = lista de posiciones | Nada | Cero |

Presupuesto de pantalla para la cámara a 22 m (encuadre ≈ 30 × 17 m): **20–35 zombis L0 visibles** es el máximo legible y jugable; por encima, la lectura se pierde y el rendimiento cae. Las hordas "de 100" se representan como 30 L0 + 70 L1/L2 que fluyen desde fuera del encuadre. Reglas de Godot: escalonar consultas de ruta (módulo del índice de agente por fotograma), una `MultiMesh` por tipo de zombi, `NavigationRegion3D` por chunk de 100 m cargado/descargado con el mundo, servidor autoritativo con interpolación en el cliente y reconciliación solo para el jugador.

---

## 4. Armas y combate para cámara alta

### 4.1 Apuntado con ratón desde arriba (decisión clave)

- **Cursor proyectado a la altura del pecho** (plano a 1.2 m): el personaje **mira al cursor** siempre que tenga arma en mano (al andar sin arma mira hacia donde anda). Esto evita el error clásico de proyectar al suelo y disparar "bajo".
- **Magnetismo de cursor**: si hay un zombi a ≤ 1.2 m (radio en el plano) del cursor, el objetivo real es ese zombi (se resalta con contorno naranja, como el *melee target outline* de Zomboid). El magnetismo se desactiva para lanzables y para disparos de rifle a > 25 m (precisión manual).
- **Mando**: stick derecho = dirección; magnetismo ×2 (2.4 m); soft-lock al zombi más cercano dentro de 20° del stick.
- **Cámara inclinada hacia el cursor** ("lean", Hotline Miami / Alien Swarm): con arma en mano la cámara se desplaza hacia el cursor hasta **3 m** (rifle con mira: **6 m**), interpolado a 6/s. Permite ver más lejos en la dirección en la que apuntas sin cambiar el zoom.
- **Cono de precisión visible**: el retículo es un anillo cuyo radio = dispersión actual. Se **cierra** mientras estás quieto (0.8 s hasta mínimo) y se abre al moverte, al recibir daño y con Calor < 15. Colores: rojo (> 8°), ámbar (4–8°), verde (< 4°) — Zomboid. Con mando, el anillo se dibuja alrededor del objetivo bloqueado.
- **Crítico = disparo a la cabeza**: no hay apuntado a partes; la probabilidad de crítico = `base_arma + 4 %·nivel_Puntería + 15 % si el anillo está verde`, ×3 daño, con animación específica (cabeza que estalla en fragmentos low-poly, sin *gore* realista).
- **Cuerpo a cuerpo**: arco de 90–110° frente al personaje, alcance por arma (1.2–2.3 m); el golpe conecta con hasta N objetivos (1 cuchillo, 2 bate, 3 hacha pesada/lanza). **Empujón** (RMB sin arma o Espacio) derriba con 35 % (+5 %/nivel de Fuerza) y cuesta 8 de aguante. **Pisotón** a un zombi derribado = ejecución en 1.0 s (ruido 6 m). Mantener LMB = golpe cargado (×1.5 daño, +0.4 s, ruido +4 m).
- **Visibilidad honesta**: lo que el personaje no ve (fuera de su cono de 120° o detrás de paredes) se dibuja **desaturado y sin zombis**; los zombis fuera del cono se representan como **anillo de sonido** en el suelo si hacen ruido (Darkwood/Zomboid). El corte de la casa solo muestra el interior de las habitaciones con línea de visión. Esto es lo que impide que la cámara alta "regale" información y lo que hace que las ventiscas funcionen.

### 4.2 Cuerpo a cuerpo vs. armas de fuego: la economía

| | Cuerpo a cuerpo | Arco / ballesta | Armas de fuego |
|---|---|---|---|
| Coste | Aguante (8/golpe), durabilidad, riesgo de agarre | Tiempo de tensado, flechas (60–70 % recuperables) | **Ruido** (80–150 m), munición escasa (§6), ensuciamiento |
| Cuándo brilla | 1–3 zombis, interiores, silencio | Caza, gritones/hinchados a distancia, ejecuciones silenciosas | Hordas, colosos, urgencias, cubrir a un compañero derribado |
| Munición por semana de juego (4 jugadores, media) | — | 20–40 flechas fabricables | 9 mm: 60–90; escopeta: 20–30; .308: 10–15; 5.56: 30 solo en base militar |

Regla de escasez: **la munición nunca reaparece** en contenedores ya abiertos; solo en celdas no visitadas en 72 h y al 60 %. Fabricación de munición (pólvora + casquillos recogidos: 50 % de los disparados) es el "grifo" que controla el servidor (opción `AmmoCrafting`).

### 4.3 Durabilidad, mantenimiento, clima

- Cada golpe/disparo tiene **probabilidad 1/N de perder 1 punto de estado** (Zomboid: `ConditionLowerChance`); N sube +2 por nivel de Mantenimiento. Estado 0 = roto (reparable una vez con cinta/piezas al 70 %).
- Armas de fuego **mojadas o a < −15 °C sin mantenimiento**: +5 % de encasquillamiento por disparo (animación de 1.5 s para destrabar). Aceite de arma lo anula 1 día. Es la única regla "climática" de las armas: legible y tematiza el invierno.
- Las herramientas-arma (hacha, palanca, martillo) pierden estado también al usarse como herramienta.

### 4.4 Recarga, retroceso y dispersión

| Parámetro | Valor | Comentario |
|---|---|---|
| Recarga | Animación por clase (pistola 1.6 s, revólver 3.0/1.8 s con cargador rápido, escopeta 0.7 s/cartucho interrumpible, cerrojo 3.5 s, carabina 2.2 s) | Recarga **cancelable** por esquiva/empujón; la escopeta se recarga cartucho a cartucho (tensión) |
| Retroceso | Empuja el anillo +2° (pistola) … +9° (escopeta) por disparo; recuperación 12°/s | En cámara alta el retroceso se lee como apertura del anillo y sacudida de 0.1 m |
| Dispersión mínima | Pistola 1.5°, revólver 1.2°, carabina 1.0°, rifle 0.5°, escopeta cono fijo 10° | Con Puntería 10: ×0.6 |
| Penalización por movimiento | Andar +3°, correr +8°, agachado −1° | — |
| Penalización por frío | Calor < 15: ×1.5 | — |

### 4.5 Retroalimentación de impacto (capas)

| Capa | Parámetros propuestos |
|---|---|
| **Hitstop** | Cuerpo a cuerpo: 50–80 ms (3–5 fotogramas a 60 fps) en atacante y víctima; golpe cargado 100 ms; disparo 0 (solo en la víctima 30 ms). Street Fighter V usa 8/12/15 fotogramas para ligero/medio/fuerte; nosotros somos más rápidos porque hay más enemigos |
| **Flinch / retroceso** | Zombi: animación de golpe 0.3 s y empujón 0.4 m (bate) – 1.0 m (escopeta); derribo con 35 % (contundente) |
| **Sacudida de cámara** | Golpe 0.12 m/0.15 s; escopeta 0.25 m/0.2 s; recibir daño 0.35 m/0.35 s (GDD); explosión 0.6 m/0.5 s con caída |
| **Sangre sobre nieve** | Quads planos (sin *decals* para Compatibility) de 0.6–1.2 m, color `#8B1E1E` → se oscurecen y quedan 120 s; rastro de gotas si un jugador sangra (lo huelen los zombis, §3.2) |
| **Desmembramiento ligero** | Solo 3 eventos: cabeza (crítico), brazo (cortante, 20 %: el zombi sigue), piernas (escopeta a < 4 m, 30 %: se convierte en reptador). Piezas low-poly sin texturas de gore |
| **Audio** | 3 capas por impacto: golpe (madera/metal/hoja), carne, reacción del zombi; a distancia solo la 1.ª |
| **UI** | Número flotante **desactivado** por defecto (rompe el tono); en su lugar, contorno del objetivo parpadea y una marca "×" en el retículo al crítico |
| **Ruido visible** | Anillo blanco que se expande desde el emisor hasta el radio de ruido en 0.4 s, visible para todos los jugadores (el coste se enseña sin texto) |

### 4.6 Tabla de armas (propuesta inicial)

Caminante = 100 PV. "Golpes" = número de golpes al cuerpo para matar a un caminante. Durabilidad = usos medios hasta romperse a nivel 0.

| # | Arma | Clase | Daño (cuerpo) | Crít. base | Cadencia | Alcance | Objetivos/golpe | Ruido (m) | Durabilidad | Golpes | Peso | Notas |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Cuchillo de caza | Cortante 1M | 18 | 10 % | 0.40 s | 1.2 m | 1 | 3 | 250 | 6 | 0.4 kg | Ejecución silenciosa por la espalda / a congelados (1.5 s, instantánea); despieza animales |
| 2 | Palanca | Contundente 1M | 28 | 15 % | 0.70 s | 1.6 m | 1 | 8 | **800** | 4 | 2.0 kg | Fuerza puertas y maleteros (8 m de ruido vs 25 al romper) |
| 3 | Bate de béisbol | Contundente 2M | 30 | 20 % | 0.65 s | 1.7 m | 2 | 10 | 300 | 4 | 1.2 kg | Derribo 35 %; con clavos +8 daño, −50 % durabilidad |
| 4 | Hacha de leñador | Cortante 2M | 45 | 30 % | 0.90 s | 1.7 m | 2 | 10 | 400 | 3 (2 con crítico) | 2.5 kg | Herramienta de tala; se queda "clavada" 5 % (0.5 s) |
| 5 | Machete | Cortante 1M | 38 | 20 % | 0.55 s | 1.5 m | 1 | 8 | 350 | 3 | 0.9 kg | Desmembra brazos 20 % |
| 6 | Lanza artesanal | Perforante 2M | 35 | 25 % | 0.80 s | **2.3 m** | 3 (en línea) | 8 | 120 | 3 | 1.5 kg | Fabricable (madera + cuchillo); mantiene distancia; se rompe rápido |
| 7 | Arco de caza | Arco | 40 (flecha) | 25 % | 1.4 s tensar | 25 m eficaz | 1 | **5** | 300 disparos | 3 (1 con crítico) | 1.0 kg | Flechas recuperables 60 %; no se puede tensar a Calor < 15 sin guantes |
| 8 | Ballesta | Arco | 60 | 30 % | 2.5 s recarga | 35 m | 1 | 6 | 400 | 2 | 3.0 kg | Virotes recuperables 70 %; rara (tienda de caza) |
| 9 | Pistola 9 mm | Fuego | 25 | 15 % | 0.25 s | 15 m | 1 | 80 | 1500 | 4 | 0.9 kg | Cargador 15, recarga 1.6 s; común (comisaría, casas) |
| 10 | Revólver .357 | Fuego | 45 | 20 % | 0.50 s | 18 m | 1 | 90 | 2000 | 3 | 1.1 kg | 6 balas, recarga 3.0 s (1.8 con cargador rápido); atraviesa 2 zombis en línea |
| 11 | Escopeta de corredera 12 g | Fuego | 8 perdigones × 12 | 10 %/perdigón | 0.90 s | 10 m (cono 10°) | Hasta 4 | **150** | 1200 | 1 a ≤ 6 m, 2 a 10 m | 3.5 kg | Tubo 6, recarga 0.7 s/cartucho; derribo 70 %; recortada: cono 16°, ruido 130, 2 cartuchos |
| 12 | Rifle de caza .308 (cerrojo) | Fuego | 90 | 40 % | 1.5 s cerrojo | **45 m** | Atraviesa 2 | 120 | 2500 | 2 (1 con crítico) | 3.8 kg | Cargador 5, recarga 3.5 s; con mira la cámara se inclina 6 m; caza mayor |
| 13 | Carabina 5.56 (semiautomática) | Fuego | 35 | 15 % | 0.15 s | 30 m | 1 | 110 | 3000 | 3 | 3.2 kg | Cargador 30, recarga 2.2 s; **solo base militar**; se encasquilla ×2 con frío |
| 14 | Arrojadizas | — | Molotov: 4 m, 15/s durante 8 s, derrite nieve y **despierta congelados a 6 m**; Bengala: luz + señuelo 40 m/30 s + Calor +5 en 2 m; Bomba de tubo: pitido 60 m/6 s, 150 en 5 m; Lata/piedra: ruido 15 m (señuelo barato) | — | 0.8 s | 12 m | — | ver §3.2 | 1 uso | — | 0.5 kg | Trayectoria parabólica con marcador de aterrizaje en el suelo; fuego amigo según servidor |

**Modificaciones de arma** (pocas, todas encontradas): silenciador 9 mm (ruido ×0.3, −10 % daño), mira para rifle (inclinación 6 m + dispersión ×0.7), linterna bajo cañón (cono de luz 8 m, +detección de noche), cargador rápido revólver, correa (peso −30 % para el aguante), clavos para bate, cinta para mango (durabilidad +25 %).

### 4.7 Fuego amigo (configuración de servidor)

| Opción `FriendlyFire` | Daño a aliados | Cuándo |
|---|---|---|
| `off` (por defecto) | 0 % (los proyectiles atraviesan a aliados; el cuerpo a cuerpo no golpea aliados) | Grupos casuales |
| `reduced` | 25 % armas, 12 % explosivos (Deep Rock: ×0.1–0.7 según peligro, explosivos −50 %) | Grupos que quieren cuidado sin castigo |
| `full` | 100 % | Realismo; se combina con `PvP=on` |

Con `off`, los aliados **sí** bloquean la línea de tiro visualmente (el retículo se pone gris) para enseñar posicionamiento sin castigar.

---

## 5. Vehículos

| Vehículo | Asientos | Maletero | Depósito | Consumo (crucero) | Velocidad nieve pisada / profunda sin cadenas / con cadenas | Ruido (ralentí/conducción) | Rareza | Rol |
|---|---|---|---|---|---|---|---|---|
| Sedán | 4 | 20 kg | 40 L | 0.5 L/min | 60 / **atascado** / 35 km/h | 20 / 45 m | Común (30 % con llave cerca) | Primer coche; frágil |
| Camioneta (la del claro) | 3 + caja abierta 2 | 60 kg (caja: 100 kg sin techo, la nieve moja) | 60 L | 0.7 L/min | 55 / 15 / 45 km/h | 25 / 50 m | Común | Caballo de batalla; los pasajeros de la caja disparan 360° |
| Furgoneta | 2 + 4 detrás | 120 kg | 70 L | 0.8 L/min | 50 / atascada / 35 km/h | 25 / 55 m | Media | Base móvil; cama dentro (dormir) |
| Motonieve | 2 | 15 kg (+ trineo 40 kg) | 15 L | 0.4 L/min | 70 / 70 / — km/h | 30 / 60 m | Rara (cabaña del pescador, tienda de deportes) | Cruza lagos y bosque; ruidosa; la "moto de Days Gone" |
| Quitanieves / camión pesado | 2 | 200 kg | 150 L | 1.5 L/min | 40 / 40 / 40 km/h; **empuja zombis y coches, no se para ante hordas < 30** | 40 / 80 m | Única (depósito municipal, requiere batería de camión + 3 piezas) | Objetivo de mitad de partida; abre la carretera a la base militar / evacuación |

**Reglas**:
- **Llaves**: 25 % en el contacto, 15 % en la guantera, 20 % en un zombi cercano (el dueño, con "llavero" visible), 20 % en la casa más próxima, 20 % sin llave → **puentear**: Mecánica 2, 8 s de canal con anillo, 15 % de alarma (150 m/30 s); coches en mejor estado son más difíciles (+4 s). La llave se comparte: cualquier jugador del grupo puede conducir un coche "del grupo" (llave duplicable en el taller).
- **Batería**: 0–100 %. Arranque −2 %. Parado con luces −1 %/min. **Frío**: −1 %/h por debajo de −10 °C aparcado a la intemperie; en garaje/cobertizo 0. Por debajo del 20 %: arranque fallido con probabilidad (1 − carga/20 %)·80 %, cada intento hace 15 m de ruido. Pinzas + otro coche o cargador de base (generador) lo reviven.
- **Gasolina**: se sifona de otros coches (5 L/min, manguera) y de surtidores **solo con electricidad** (generador portátil = ruido 30 m) o bomba manual (lenta, 2 L/min, silenciosa, plano encontrado). Bidones de 20 L (peso 16 kg).
- **Cadenas para nieve**: fabricables (cadena + Mecánica 3) o encontradas (gasolinera, garaje). Sin cadenas: en nieve pisada (carreteras, huellas previas) tracción normal; en **nieve profunda** (visible) tracción ×0.4 y probabilidad de quedarse atascado (canal de 6 s para salir, ruido). Con cadenas: ×0.8 y nunca atascado. En hielo de lago: sin cadenas derrapa (control ×0.3), con cadenas ×0.7; el hielo fino se rompe con > 1200 kg (todo salvo la motonieve).
- **Daño**: piezas simplificadas a 4 (motor, ruedas, batería, carrocería/parabrisas). Atropellar un caminante a ≥ 30 km/h lo mata y daña carrocería 2 %; una horda de ≥ 10 en el capó **para el coche** (velocidad ×0.2) y los zombis golpean ventanas (parabrisas rompe a 5 golpes: entra el frío y entran ellos). Ruedas pinchadas: velocidad ×0.5, se cambian con gato + rueda (30 s).
- **Calefacción**: motor encendido +25 °C sentidos en cabina cerrada; ventana rota +10 °C. Dormir en un coche con motor encendido: gasolina 0.3 L/min y ruido 20 m: es una elección real.
- **Ruido**: tabla §3.2. La radio del coche (si hay emisora: evento de historia) atrae a 30 m.
- **Co-op**: el conductor tiene autoridad de física; los pasajeros disparan con el cursor por las ventanillas (cono 120° hacia su lado) o 360° desde la caja de la camioneta; el maletero es un contenedor **compartido** accesible por todos; entrar/salir 0.8 s (cancelable), en marcha no se puede.
- **Remolque**: trineo tras la motonieve (40 kg, se vuelca en curvas > 40 km/h); cable para arrastrar un coche atascado (2 jugadores).

---

## 6. Botín y economía

### 6.1 Rarezas

| Rareza | Peso base en tabla | Ejemplos |
|---|---|---|
| Común | 60 % | Latas, ropa de casa, vendas, madera, clavos, 9 mm (1–6) |
| Poco común | 30 % | Abrigo, botas de invierno, palanca, hacha, cartuchos, antibióticos, gasolina |
| Raro | 9 % | Rifle, ballesta, cadenas, batería de coche, planos, radio portátil |
| Único | 1 % (solo en su edificio) | Carabina 5.56, mira, generador, piezas del quitanieves, código de la torre |

### 6.2 Tablas por tipo de edificio (probabilidad de que un contenedor tenga algo: 65 %; 1–3 objetos)

| Edificio | Contenedores típicos | Común | Poco común | Raro / Único | Peligro |
|---|---|---|---|---|---|
| **Casa** | Armario, cocina, nevera (congelada), cómoda, garaje | Latas 35 %, ropa 25 %, vendas 10 %, herramientas de casa 10 % | Abrigo 8 %, cuchillo 5 %, pistola 3 % (dormitorio), gasolina (garaje) 4 % | Rifle de caza 0.5 % (casa rural con trofeos) | 2–6 zombis, 1 congelado en el porche |
| **Cabaña / cazador** | Baúl, pared de trofeos | Carne seca, cuerda, pieles | Arco 20 %, flechas 30 %, trampa 15 % | Rifle .308 8 %, ballesta 5 % | Lobos cerca |
| **Gasolinera** | Estanterías, caja, taller, surtidor | Latas, chocolate, bebidas (congeladas), cinta, mapa de zona (revela carreteras) | Gasolina 30 %, aceite, batería 10 %, piezas 20 %, **cadenas 12 %** | Bidón de 20 L 5 % | 6–12 zombis, alarma en la tienda 5 % |
| **Tienda de ropa/deportes** | Estantes, probadores | Ropa (capas media/exterior) 60 % | Botas 20 %, guantes 25 %, gorro, mochila grande 15 % | Motonieve (trasera) 3 %, ballesta 4 % | Media |
| **Farmacia / clínica** | Mostrador, armario de medicinas | Vendas 40 %, analgésicos 30 % | Antibióticos 15 %, kit de sutura 10 % | — | Gritón 20 % |
| **Hospital** | Carros, quirófano, farmacia central | Vendas, sueros | Antibióticos 30 %, kit de cirugía (cura congelación al 50 %) 10 % | Desfibrilador (reanima a un muerto reciente en 60 s, 1 uso) 3 % | 30–60 zombis, muchos acorazados de seguridad; **objetivo de sesión de 4** |
| **Comisaría** | Armería (cerrada: llave del sargento o Mecánica 4), taquillas, celdas | Ropa policial (chaleco: daño al cuerpo ×0.7, peso 4 kg), porra | Pistola 9 mm 40 %, munición 9 mm 60 %, escopeta 25 %, chaleco 20 % | Radio portátil 10 %, llaves de coche patrulla (con radio y luces) | 20–40 zombis, 30 % acorazados |
| **Base militar / puesto** | Contenedores, armería, garaje pesado | Raciones (no se congelan), mantas térmicas | Cartuchos, botas militares, cadenas 30 % | Carabina 5.56 15 %, munición 5.56, mira, **piezas del quitanieves**, generador 10 %, abrigo militar (mejor aislamiento) | 60–120 zombis + Coloso; **solo con quitanieves o motonieves** (carretera cortada) |
| **Depósito municipal / taller** | Bancos, estanterías | Piezas, clavos, tablones | Batería 20 %, gato, ruedas, cadenas 25 % | Quitanieves (vehículo) 100 % pero roto | 10–20 |
| **Torre de radio / repetidor** | Sala de control | Cables, pilas | Piezas de radio | Componente único de la torre (objetivo meta) | Custodiada por horda migratoria 1 de cada 3 días |
| **Zombi** (al morir, 20 %) | — | Lo que lleva puesto (ropa) | Policía: 9 mm; médico: vendas; soldado: 5.56; cazador: flechas | Llaves de coche 5 % | — |

### 6.3 Reglas de reaparición (DayZ + Zomboid)

- Cada objeto tiene `nominal` (objetivo en el mundo por 1 km² de zona), `min` y `lifetime`. El servidor repone solo hasta `nominal` y solo en **contenedores no abiertos en 72 h de juego dentro de celdas sin jugador a < 150 m durante 48 h**, al 60 % de la tabla original (opción `LootRespawn`: 0.0–1.0).
- Munición y armas de fuego: `nominal` bajo (por 4 jugadores: 9 mm 150, cartuchos 40, .308 25, 5.56 40) → escasez real a las 2–3 semanas de juego; la fabricación de munición es el grifo.
- Ropa y comida: `nominal` alto: no sufrir por comida, sufrir por **calor y balas**.
- Objetos en el suelo desaparecen a las 12 h de juego (cadáveres de jugador: 48 h, para el *corpse run*).
- **Sin botín instanciado por jugador** (evitar el amarillo/azul de SoD2): el mundo es uno; el grupo se reparte con *pings* y con la "caja común" de la base. Opción `PersonalLootBags=on` para grupos que prefieren mochilas de botín individuales al saquear (cada jugador ve su propia tirada en el contenedor): la dejamos como opción, no como norma.

### 6.4 Contenedores y peso

- Capacidad base **20 kg**; +Fuerza 1 kg/nivel; mochila pequeña +15, media +25, grande +35 (peso propio 1/2/3 kg); cinturón/funda: el arma equipada pesa ×0.5.
- Umbrales: > 80 % velocidad ×0.85 y aguante −20 %; > 100 % velocidad ×0.6 y no puedes correr; > 120 % no puedes moverte (suelta algo). Ropa mojada pesa hasta ×2 (TLD).
- Contenedores del mundo: 6–12 ranuras con peso; los de la base (cajas, estanterías, maletero) son compartidos y con **etiqueta de propietario opcional** (candado fabricable: solo el grupo/facción).

---

## 7. Progresión

### 7.1 Habilidades por uso + ventajas (híbrido Zomboid/7DTD)

Nueve habilidades 0–10, XP por uso, pero **solo por acciones significativas** (matar a un zombi que te ha visto, fabricar una receta por primera vez ×5, reparar una pieza en un coche que funciona, etc.) y con **rendimiento decreciente diario** (las 20 primeras acciones del día dan XP completa, luego ×0.25) para cortar el *grind* que hizo a 7DTD abandonar el sistema.

| Habilidad | Sube por | Efecto por nivel | Ventaja (elegir 1 de 2 cada 2 niveles) |
|---|---|---|---|
| Contundente | Bate, palanca, martillo | +3 % daño, +2 % derribo, durabilidad 1/N +1 | "Batazo": golpe cargado derriba a 3 / "Rompepuertas": puertas en 2 golpes |
| Cortante | Hacha, machete, cuchillo | +3 % daño, +2 % crítico | "Leñador": tala en 2 golpes / "Desollador": doble piel |
| Puntería | Armas de fuego, arco | Dispersión ×(1 − 0.04·n), crítico +2 % | "Frío como el hielo": el anillo no se abre al recibir daño / "Cazador": flechas recuperables 90 % |
| Sigilo | Moverse agachado cerca de zombis sin ser visto | Ruido de pasos −4 %, detección −5 % | "Sombra": ejecuciones desde el frente a congelados / "Pies de gato": la nieve profunda no hace ruido |
| Forma física | Correr, cargar peso | Aguante +4, capacidad +1 kg | "Segundo aliento": aguante se recarga al 100 % al derribar / "Mula": mochila +10 kg |
| Supervivencia | Cocinar, cazar, hogueras, pescar | Comida +5 % efecto, fuego dura +5 % | "Sangre caliente": Calor drena ×0.85 / "Nariz": huellas de animales resaltadas a 30 m |
| Carpintería | Barricadas, muebles, tala | Barricadas +10 % PV, coste −5 % | "Aislante": la casa retiene +20 % calor / "Trampero": trampas de oso |
| Mecánica | Reparar, puentear, cadenas | Puentear −0.5 s, piezas +10 % | "Silenciador casero": tubo de escape −30 % ruido / "Arranque en frío": batería no se drena por frío |
| Medicina | Curar a otros y a ti | Vendar −10 % tiempo, +5 % curación | "Camillero": reanimar en 2 s / "Cirujano": cura congelación al 100 % una vez |

Las ventajas se **muestran a los compañeros** (icono junto al nombre): fomenta roles emergentes sin clases.

### 7.2 Planos, base y objetivos a largo plazo

- **Planos** (revistas/manuales, como Zomboid) como llaves: cadenas, bomba manual de gasolina, munición casera, generador, radio, estufa de aceite, trineo, silenciador. Se leen en 60 s junto al fuego y quedan **desbloqueados para todo el servidor** (co-op: no repetir).
- **Base por niveles** (reclamar un edificio): N1 estufa + camas; N2 taller + almacén + barricadas; N3 generador + radio + cargador de baterías + invernadero interior (comida estable); N4 torre de vigilancia + luces (atraen y a la vez ven). Cada nivel exige un **objeto raro de una expedición** (batería de camión, generador, componente de radio) = motivo para las expediciones.
- **Meta-objetivos** (elegibles en cualquier orden, con pistas en notas/radios del mundo, "fragmentos de historia"):
  1. **Torre de radio**: reparar el repetidor (3 componentes en 3 edificios peligrosos) → escuchas una emisión que anuncia la evacuación en X días y su punto (carretera cortada).
  2. **Quitanieves**: abrir la carretera hacia el punto de evacuación y hacia la base militar.
  3. **Evacuación** (final): llegar con el convoy al punto en la fecha, defenderlo 8 min de juego contra la Gran Horda atraída por las bengalas de señalización, subir. Pantalla de final con estadísticas del grupo. El servidor puede continuar en modo "Nos quedamos" (sin fin, dificultad creciente).
- **Sistema de objetivos de mundo abierto**: un "tablón" por jugador con 1 objetivo principal (meta) + hasta 3 secundarios generados por el mundo: "Alarma en la comisaría: 20 zombis, 60 % de 9 mm", "Se acerca la Gran Ventisca en 1 día: la base necesita 60 leñas", "Rastro de la horda hacia el norte", "Radio: superviviente pidiendo ayuda en la cabaña (nota + botín)". Sin NPC hablando en v1: la historia se cuenta con notas, radios, cadáveres y escenografía.

---

## 8. Checklist de *game feel* (cámara alta) con parámetros

| Área | Regla | Parámetro propuesto |
|---|---|---|
| **Cámara** | Perspectiva, inclinación −52°, guiñada en pasos de 45°, zoom 14–30 m (GDD); seguimiento lerp 6/s; **adelanto** 1.5 m en movimiento y **hasta 3 m hacia el cursor** con arma (6 m con mira) | Nunca girar sola; nunca colisionar (está alta); ocultar árboles/techos que tapen al jugador con *fade* 0.15 s (Nesky: proteger la línea de visión); sacudidas con decaimiento exponencial, nunca > 0.6 m |
| **Latencia de entrada** | Movimiento con predicción en el cliente; golpe cuerpo a cuerpo: la animación empieza en el cliente el mismo fotograma, el servidor valida el impacto (≤ 100 ms de RTT tolerado con retroceso de reconciliación) | Objetivo local: < 50 ms desde tecla hasta primer fotograma de animación; en red < 120 ms percibidos gracias a la animación anticipada |
| **Anticipación y cancelación** | Golpe: 120–180 ms de *wind-up*, 60 ms activo, 250 ms de recuperación cancelable a los 150 ms por esquiva/empujón; *input buffer* 150 ms | Zomboid se siente "lento" por recuperaciones largas: acortar |
| **Movimiento** | Aceleración 0.1 s a andar, 0.2 s a correr; frenada 0.08 s; giro instantáneo hacia la entrada, el modelo rota a 720°/s | En nieve profunda ×0.7 y partículas de nieve levantada |
| **Hitstop** | 50–80 ms melee; 100 ms cargado | §4.5 |
| **Cono de precisión** | Cierra en 0.8 s quieto; colores rojo/ámbar/verde | §4.1 |
| **Feedback de ruido** | Anillo expandiéndose hasta el radio real (0.4 s) | Enseña el coste sin tutorial |
| **Sonido** | Voces de zombi con prioridad por distancia y **posicionadas en 2D de pantalla** (paneo por posición en el encuadre, no por la orientación del personaje); gruñido de "te he visto" ≥ 0.5 s antes de moverse; viento como capa continua 0.2/0.5/1.0 (GDD) que **enmascara** el resto en ventisca | Máximo 8 voces de zombi simultáneas, 24 SFX |
| **Claridad de UI** | Tres anillos + termómetro sentido + reloj; etiqueta de contexto (GDD §4.3); iconos de estado con causa; compañeros: nombre + barra + icono de ventaja + flecha de borde de pantalla cuando están fuera de encuadre | Nada de números flotantes de daño; sin minimapa por defecto (mapa de papel a pantalla completa, con marcas de *ping*) |
| **Capas de feedback** | Cada acción: animación + partícula + sonido + UI (4 capas) | P. ej. recoger: mano baja, destello, "pickup", ranura parpadea |
| **Onboarding** | Las 8 misiones del día 1 (GDD) se conservan; añadir día 2: "Sigue las huellas hasta la aldea", "Un zombi congelado: acércate en silencio", "Haz ruido a propósito con una lata", "Tu primer disparo: mira el anillo de ruido" | Enseñar el ruido y los congelados antes que las armas |
| **Legibilidad a 22 m** | Contornos de 2 px en personajes y zombis (SIS); colores de zombi desaturados vs jugadores saturados; sangre sobre nieve como mapa de la batalla | — |
| **Muerte** | Cámara lenta 0.5 s, viñeta, causa clara ("Frío", "Horda", "Acechador") y consejo de 1 línea | GDD §14 ampliado |

---

## 9. Lista de animaciones necesarias (por prioridad de jugabilidad)

Convención del *rig* low-poly (ver `ASSET_SPEC.md`): un solo esqueleto humano para jugadores y zombis, un esqueleto de cuadrúpedo (lobo/ciervo) y uno de reptador (variante del humano con IK apagado).

### 9.1 Jugador

| P | Animación | Notas de diseño |
|---|---|---|
| P0 | Idle (normal / con frío: brazos cruzados y temblor cuando Calor < 30 / con arma) | El frío se ve en el cuerpo, no solo en el HUD |
| P0 | Andar, correr, agachado (8 direcciones con *blend space* 2D; el torso mira al cursor) | Torso y piernas separados (upper/lower body) |
| P0 | Apuntar 1M / 2M (pistola, rifle, arco, lanza), disparar, tensar arco | Aditiva sobre locomoción |
| P0 | Golpe cuerpo a cuerpo 1M ligero, 2M pesado, golpe cargado, empujón, pisotón | 3 variantes de ligero para no repetir |
| P0 | Recarga: pistola (cargador), revólver (tambor), escopeta (cartucho a cartucho, en bucle), cerrojo, carabina (cargador), ballesta (estribo) | Una por clase; cancelables |
| P0 | Recibir golpe (frontal/lateral), agarrado por zombi (forcejeo, 2 s), derribado, arrastrarse derribado, ser reanimado, levantarse, morir | Estado derribado = 3 animaciones |
| P0 | Interacciones: recoger (bajo), abrir contenedor, abrir puerta, forzar con palanca, talar (ya), golpear ventana, encender hoguera, echar leña, comer/beber, vendarse, reanimar a otro (arrodillado) | Reutilizar el "canal con anillo" del GDD |
| P0 | Vehículo: entrar/salir (conductor, pasajero), conducir (volante), pasajero disparando por la ventanilla, subir a la caja | Entrar/salir 0.8 s |
| P1 | Cambiar cadenas (arrodillado junto a la rueda), pinzas de batería, sifonar, repostar | Canales de 6–30 s |
| P1 | Lanzar (molotov/bengala/lata), encender bengala | Trayectoria con marcador |
| P1 | Ejecución silenciosa a congelado/por la espalda (2 variantes), desatascar arma | — |
| P1 | Caer al hielo (chapoteo, salir a rastras), temblar mojado, secarse junto al fuego (manos al fuego, bucle) | Ventas del frío |
| P2 | Dormir (cama, coche), pescar, despiezar animal, sentarse en trineo, emotes de *ping* (señalar, "ven", "espera") | Los emotes refuerzan los *pings* |

### 9.2 Zombis

| P | Animación | Notas |
|---|---|---|
| P0 | Idle (3 variantes: balanceo, mirar alrededor, congelado-bulto), vagar, caminar rígido (2 variantes), caminar de investigación (cabeza hacia el ruido) | Con IK simple de pies en nieve |
| P0 | Correr (corredor), ráfaga → fatiga | — |
| P0 | Alertado (giro brusco + gruñido), ataque mordisco, ataque agarre a 2, golpear puerta/ventana/barricada | 3 s de aviso en especiales |
| P0 | Reacción al golpe: frontal, lateral, trasera; tambaleo (contundente), derribo y levantarse; astillado (congelado) | *Hitstop* sobre estas |
| P0 | Muertes: caer hacia delante/atrás, decapitado (crítico), a rastras tras perder piernas → transición a reptador, quemado | Con ragdoll parcial de 0.5 s si Forward+; en Compatibility, animación fija |
| P0 | Reptador: arrastrarse, agarrar piernas, morir | Esqueleto derivado |
| P0 | Congelado: despertar (3 s, crujido), sacudirse la nieve | Muy legible |
| P1 | Comer (cadáver de animal/jugador), beber en el agua (horda de noche), dormir en grupo (horda de día) | Rutina Days Gone |
| P1 | Hinchado: caminar pesado, explotar; Gritón: gritar (canal 3 s), retroceder; Acechador: acecho agachado, salto por la espalda; Acorazado: perder el casco; Coloso: embestida, romper puerta, romper hielo | Uno o dos clips por especial |
| P2 | Trepar por una ventana baja, caer desde altura, ser atropellado (ragdoll), arder | — |

### 9.3 Fauna (P1): lobo (ya), ciervo (huir, morir, ser despiezado), conejo (P2).

---

## 10. Cooperativo 1–4: especificaciones

### 10.1 Mundo y botín

- **Un mundo, un servidor dedicado, persistente** (estado de celdas, contenedores abiertos, base, vehículos, horda migratoria, día). Sin anfitrión: nadie es "invitado" (lección negativa de SoD2). Sin correa entre jugadores: el mundo se transmite por chunks alrededor de cada jugador; la única limitación es el presupuesto de zonas activas (máx. 4 zonas de 150 m).
- **Botín no instanciado** (primero que llega, coge). Herramientas anti-conflicto: *ping* de objeto ("hay un abrigo aquí"), "soltar para X" (arrastrar sobre el retrato del compañero a < 3 m = transferencia directa), caja común de la base con registro ("Ana ha cogido 20 de 9 mm"). Opción `PersonalLootBags` para grupos que prefieran tiradas individuales (§6.3).
- **Progresión individual** (habilidades, ventajas) + **progresión compartida** (planos, base, meta-objetivos, vehículos con llave del grupo).
- **Facciones** (Zomboid): un grupo por servidor por defecto; con `PvP=on` pueden existir varias, con casas seguras reclamadas tras 3 días sobrevividos y contenedores con candado.

### 10.2 Derribado, reanimación y muerte

| Estado | Regla |
|---|---|
| **Derribado** (Salud llega a 0) | El jugador cae, puede arrastrarse a 0.8 m/s y disparar con pistola (L4D). Desangrado: 60 s (Grounded: 30 s; L4D: 300 PV a −3/s ≈ 100 s); el frío lo acelera: a Calor < 30, 40 s. Los zombis a < 3 m siguen mordiendo (−5 s por mordisco). Icono de calavera con temporizador visible para **todos** (The Forest ocultaba el tiempo: peor) |
| **Reanimar** | Otro jugador mantiene E 4 s (2 s con "Camillero"); interrumpible por daño; se levanta con 30 PV y "Malherido" (velocidad ×0.85, 5 min). No hace falta botiquín (Sons of the Forest). Máx. **2 derribos** entre descansos: al tercero muere directamente (L4D "blanco y negro": la pantalla del jugador se desatura tras el 2.º) |
| **Rendirse** | Mantener X 3 s para morir si nadie puede llegar (Grounded) |
| **Muerte** | Reaparece en la cama de la base (o en el punto de inicio si no hay base) tras 20 s, con la ropa básica, Calor 60 y **sin mochila**: el cadáver guarda todo 48 h de juego (*corpse run*, Valheim). Pierde 10 % de la XP de cada habilidad hacia el siguiente nivel (no niveles). Con `Permadeath=on` (opción): el personaje se pierde y se crea otro; el servidor por defecto no |
| **Solo** (1 jugador) | Derribado = 20 s para "levantarse solo" con vendas (una vez por día), si no muere. Equivale a un "segundo aliento" |
| **Desfibrilador** (raro) | Reanima a un cadáver en 60 s desde la muerte con 10 PV; 1 uso |

### 10.3 Comunicación

- ***Pings* contextuales (Apex)**: una tecla (botón central) sobre lo que hay bajo el cursor: enemigo (icono rojo, 8 s), objeto (icono + nombre, hasta que se coge), lugar (bandera, 30 s), vehículo, "ven aquí", "peligro", "necesito calor/munición/vendas" (rueda al mantener). Los *pings* aparecen en el mundo (anillo + icono con distancia), en el borde de pantalla si están fuera del encuadre y en el mapa de papel. El personaje **no** lo vocaliza (el ruido importa): lo hace un sonido de UI solo para el grupo.
- **Chat de texto siempre** (accesibilidad y CVAA); burbujas sobre el personaje a < 20 m ("proximidad") y canal de grupo global con `[G]`. **Voz opcional por proximidad** (30 m, atenuada por paredes) + canal de radio si ambos llevan **walkie** (objeto raro, gasta pilas que el frío drena) — así la radio es progresión y la voz por proximidad da miedo en ventisca. Todo configurable en el servidor: `Voice=off/proximity/global`.
- **Gestos**: 4 emotes (señalar, ven, espera, silencio) sincronizados con los *pings* para quien no usa chat.

### 10.4 Reglas anti-abuso y PvP opcional

| Opción de servidor | Valores | Por defecto |
|---|---|---|
| `PvP` | off / on | off |
| `FriendlyFire` | off / reduced / full | off |
| `Safehouses` | on/off, `DaysToClaim` (3), `NoRaidWhenOffline` | on, 3, on |
| `ContainerLocks` | off / faction / owner | faction |
| `FireSpread` | off / on (molotov solo quema zombis y hierba) | off (Zomboid: los servidores serios lo apagan por incendios de pueblos enteros) |
| `VehicleTheft` | any / faction / owner | faction |
| `Permadeath` | off / on | off |
| `LootRespawn` | 0.0–1.0 | 0.6 |
| `ZombieCountScale`, `NoiseScale`, `ColdScale` | 0.5–2.0 | 1.0 |
| `SafetySystem` (PvP por jugador con retardo de 30 s para activar/desactivar) | on/off | on cuando PvP=on |
| Kick/ban y registro de acciones (quién cogió qué, quién rompió qué) | — | on |

Con PvP off, los jugadores **no** se bloquean (atraviesan) para evitar bloqueos de puertas; con PvP on sí colisionan.

### 10.5 Escalado por jugadores (resumen)

| Sistema | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| Zombis activos por zona | 12 | 18 | 24 | 30 |
| Especiales por evento | 1 | 1 | 2 | 2 |
| Horda de asalto a la base | 15 | 20 | 25 | 30 |
| Botín `nominal` | ×1.0 | ×1.25 | ×1.5 | ×1.75 |
| Frío | Igual (el frío no escala: es el gran igualador) | | | |
| Dormir/saltar noche | 1 vota | Todos en cama o voto 2/2 | Voto ≥ 2/3 en cama, resto en interior seguro | ≥ 3/4 |

---

## 11. Riesgos y lo que NO haremos en v1

1. **NPC supervivientes con moral** (SoD2): no. Historia por notas y radio.
2. **Zombis que excavan o construyen** (7DTD): no; rompen la lectura y la malla de navegación.
3. **Hordas de 500 individuales** (Days Gone): no; 100–120 con LOD L2 (§3.6).
4. **Infección mortal con permadeath por defecto** (Zomboid): no; fiebre curable.
5. **Construcción libre por vóxeles**: no; reclamar + ranuras + 6 piezas colocables.
6. **Botín instanciado** (SoD2): no por defecto.
7. **Olfato inexistente pero "configurable"**: si está en el menú, funciona (§3.2).
8. **Cientos de armas**: 12 + arrojadizas + 7 modificaciones. Cada arma con un rol.
9. **Tercera persona**: no es objetivo; toda la lectura se diseña para 22 m de altura.

---

## 12. Fuentes consultadas

Nota de método: el proxy de red de la sesión bloqueó la descarga directa de casi todas las páginas (wikis, GDC Vault, blogs); los datos se han obtenido a través de los extractos de búsqueda web de esas mismas páginas. Se listan las URL de las que proceden las cifras y afirmaciones usadas.

**Left 4 Dead / Director de IA**
- https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf (M. Booth, "The AI Systems of Left 4 Dead", AIIDE 2009)
- https://www.gameanim.com/2009/12/22/the-ai-systems-of-left-4-dead/
- https://left4dead.fandom.com/wiki/The_Director
- https://left4deadwiki.com/wiki/The_Director
- https://left4dead.fandom.com/wiki/Health
- https://www.dreadcentral.com/editorials/493467/monster-mania-left-4-deads-special-infected-are-perfected-simplicity/
- https://www.gamedeveloper.com/design/why-i-left-4-dead-i-works

**Project Zomboid**
- https://pzwiki.net/wiki/Zombie
- https://projectzomboid.fandom.com/wiki/Zombie
- https://steamcommunity.com/app/108600/discussions/0/540735426015526986/ (sentidos, olfato no implementado)
- https://steamcommunity.com/sharedfiles/filedetails/?id=3039302909 (radios de disparo por arma, silenciador ×0.2)
- https://steamcommunity.com/app/108600/discussions/0/592887157683650840/ (PSA sobre armas; multijugador ÷1.8)
- https://build42guide.wiki/survival/build-42-stealth-noise
- https://projectzomboid.wiki/guides/stealth-noise/
- https://pzfans.com/knock_tactics_breakdown_build_41_vs_42_zomboid_secrets/ (radios de grito)
- https://steamcommunity.com/app/108600/discussions/0/3415433633270928791/ (ruido de vehículos: volumen, tubo de escape, RPM, mínimo 8)
- https://www.pcgamer.com/project-zomboid-hotwire-a-car-how-to/
- https://xgamingserver.com/blog/project-zomboid-vehicles-guide/
- https://lootlore.online/en/project-zomboid/guides/how-to-hotwire-a-car
- https://xgamingserver.com/tools/project-zomboid/weapons
- https://www.bamboogaming.net/project-zomboid/weapons
- https://pzfans.com/what-is-the-best-melee-weapon-in-project-zomboid/
- https://pzfans.com/what-is-the-best-firearm-weapon-in-project-zomboid/
- https://projectzomboidmap.com/items/m9-pistol/
- https://steamcommunity.com/sharedfiles/filedetails/?id=3388063082 ([B42] How to Gunplay: anillo de precisión y colores)
- https://gamerempire.net/project-zomboid-how-to-attack/ (empujón, pisotón, contorno de objetivo)
- https://pzfans.com/shamblers-fast-shamblers-sprinters-and-customize-zombie-speed/
- https://pzfans.com/ProjectZomboidNightEvents/ (meta-eventos, helicóptero)
- https://projectzomboid.wiki/guides/zombie-types-guide/
- https://xgamingserver.com/blog/project-zomboid-skills-leveling-guide/
- https://projectzomboid.wiki/guides/encumbrance/
- https://pzfans.com/places-to-find-guns-in-project-zomboid/
- https://lootlore.online/en/project-zomboid/guides/loot-locations-guide
- https://winternode.com/blog/project-zomboid/server-settings-explained (población, respawn, 500 zombis por jugador)
- https://supercraft.host/wiki/project-zomboid/project_zomboid_pvp_server_guide/
- https://pzfans.com/project-zomboid-server-settings/
- https://low.ms/blog/best-project-zomboid-server-settings-2026

**DayZ (vanilla, Namalsk, Frostline/Sakhal)**
- https://dayz.fandom.com/wiki/Central_Loot_Economy
- https://xgamingserver.com/blog/dayz-central-loot-economy-explained/
- https://gamers.wiki/en/games/dayz/guides/dayz-central-economy-lifetimes-what-loot-timers-and-restocks-actually-do
- https://dayz.wiki.gg/wiki/Infected
- https://www.rottenz.eu/en/guide/vanilla/combat/zombie-combat/
- https://xgamingserver.com/blog/dayz-namalsk-map-guide/
- https://www.exitlag.com/blog/dayz-namalsk-map/
- https://guided.news/en/guides/survive-dayz-namalsk-stay-warm-guide/
- https://dayz.com/article/status-report/DayZ-Frostline-Dev-Blogs-recap
- https://gamers.wiki/en/games/dayz/guides/dayz-sakhal-plan-for-heat-and-water-not-for-loot
- https://xgamingserver.com/blog/dayz-sakhal-map-guide/

**State of Decay 2**
- https://en.wikipedia.org/wiki/State_of_Decay_2
- https://spritesanddice.com/reviews/state-decay-2-review-toybox-zombies/
- https://www.quartertothree.com/fp/2018/05/24/a-new-dawn-rises-in-state-of-decay-2/
- https://www.trueachievements.com/forum/viewthread.aspx?tid=1017100 (botín amarillo/azul)
- https://knowgameplay.blog/how-state-of-decay-2-coop-works (correa de 450 m)
- https://www.windowscentral.com/how-state-decay-2s-co-op-works-progression-tethering-and-more
- https://state-of-decay-2.fandom.com/wiki/Zombie_Types
- https://www.stateofdecay.com/state-of-decay-2/zombies/
- https://state-of-decay-2.fandom.com/wiki/Melee_Weapons

**7 Days to Die**
- https://7daystodie.fandom.com/wiki/Blood_Moon_Horde
- https://7daystodie.wiki.gg/wiki/Blood_Moon_Horde
- https://7daystodie.cloud/blog/how-blood-moon-scaling-works/ (gamestage de grupo y multiplicador por jugadores)
- https://saltyzombies.com/7-days-to-die-game-stage-explained/
- https://xgamingserver.com/blog/comprehensive-guide-to-zombie-types-in-7-days-to-die/
- https://www.holy.gg/en/post/7-days-to-die-zombie-types-special-infected
- https://steamcommunity.com/app/251570/discussions/0/1742226629867981456/ (retirada de "aprender haciendo")

**The Long Dark**
- https://thelongdark.fandom.com/wiki/Clothing
- https://thelongdark-archive.fandom.com/wiki/Clothing
- https://thelongdark.fandom.com/wiki/Weather
- https://thelongdark.fandom.com/wiki/Hypothermia
- https://thelongdark.fandom.com/wiki/Frostbite
- https://thelongdark.fandom.com/wiki/Weak_Ice
- https://thelongdark.fandom.com/wiki/Survival_Bow
- https://thelongdark.fandom.com/wiki/Hunting
- https://steamcommunity.com/sharedfiles/filedetails/?id=1375817441 (manual para principiantes)

**Days Gone**
- https://gamerant.com/days-gone-zombie-ai-gdc/
- https://wccftech.com/freak-o-system-days-gone-ps4-shadows/
- https://gdcvault.com/play/1027237/AI-Summit-Squad-Coordination-in
- https://gamingbolt.com/days-gones-hordes-will-be-persistent-can-have-up-to-500-freakers
- https://daysgone.fandom.com/wiki/Hordes
- https://www.thegamer.com/days-gone-track-horde-tips/
- https://www.scribd.com/document/868153384/Days-Gone-Weapon-Chart

**Dying Light**
- https://news.xbox.com/en-us/2025/07/18/dying-light-the-beast-interview/
- https://gamingbolt.com/dying-light-the-beast-develops-outlines-improvements-to-volatiles-for-more-terrifying-nights
- https://www.gamesradar.com/games/survival-horror/dying-light-the-beast-will-have-guns-that-feel-on-par-with-melee-combat-as-techland-struggles-to-solve-the-series-complicated-relationship-with-firearms/
- https://www.gamedeveloper.com/design/here-s-why-dying-light-2-s-open-world-is-hypnotic-to-navigate

**Sons of the Forest / The Forest**
- https://sonsoftheforest.fandom.com/wiki/Ai_System
- https://sonsoftheforest.wiki.gg/wiki/AI_System
- https://roundtablecoop.com/reviews/sons-of-the-forest-early-access-review/
- https://www.co-optimus.com/game/11891/pc/sons-of-the-forest.html (reanimación ~5 s, 10 PV)
- https://theforest.fandom.com/wiki/Death

**Winter Survival, Frostpunk, Valheim, Unturned, otros referentes**
- https://gamingbolt.com/winter-survival-early-access-review-winter-is-leaving
- https://thebetanetwork.net/articles/winter-survival-review/
- https://www.mkaugaming.com/all-review-list/winter-survival-steam-review/
- https://www.pcgamer.com/frostpunk-developers-on-hope-misery-and-the-ultimately-terrifying-book-of-laws/
- https://www.gamedeveloper.com/design/video-lessons-learned-in-making-i-this-war-of-mine-i-and-i-frostpunk-i-
- https://valheim.fandom.com/wiki/Freezing
- https://valheim.fandom.com/wiki/Cold
- https://unturned.fandom.com/wiki/Zombies
- https://mmos.com/review/unturned
- https://en.wikipedia.org/wiki/Unturned
- https://www.gamedeveloper.com/design/how-i-darkwood-i-s-visibility-mechanics-create-a-new-kind-of-horror
- https://medium.com/@spencer2457/darkwood-and-the-horror-of-the-top-down-view-281a4b9c4c9f
- https://geekgasm.org/2025/05/12/survivalist-invisible-strain-review-a-relentless-hardcore-survival-game/
- https://en.wikipedia.org/wiki/Alien_Swarm
- https://www.destructoid.com/review-alien-swarm/
- https://sourcegaming.info/2019/05/25/undead-horde-review/
- https://en.wikipedia.org/wiki/World_War_Z_(2019_video_game) (Swarm Engine: IA simplificada de lejos, individual de cerca)
- https://www.gamereactor.eu/world-war-z-dev-diary-dives-into-the-zombie-hordes/

**Co-op, comunicación, fuego amigo**
- https://uxdesign.cc/apex-legends-ping-system-gaming-ux-done-right-4661cd94954c
- https://www.gamesradar.com/the-apex-legends-ping-system-is-a-brilliant-solution-to-the-horror-of-playing-with-strangers-online/
- https://deeprockgalactic.wiki.gg/wiki/Damage (fuego amigo ×0.1–0.7 por peligro, explosivos −50 %)
- https://indiehellzone.com/2022/11/01/deep-rock-galactic/
- https://gameaccessibilityguidelines.com/full-list/
- https://www.kelleydrye.com/viewpoints/client-advisories/communications-accessibility-in-games-what-game-developers-need-to-know (CVAA)
- https://friendslop.online/guides/best-proximity-chat-horror-co-op-games

**Game feel, cámara, latencia**
- https://gdcvault.com/play/1020460/50-Camera (J. Nesky, "50 Game Camera Mistakes", GDC 2014)
- https://www.gamedeveloper.com/design/video-50-common-game-camera-mistakes----and-how-to-fix-them
- https://www.jasondeheras.com/gamedesign/2021/4/23/how-do-3rd-person-melee-combat-games-communicate-game-and-hit-feel
- https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/
- https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/
- https://shane-sicienski.com/blog/blog-post-title-one-55pmn (hitstop en Capcom; SFV 8/12/15 fotogramas)
- https://www.wayline.io/blog/input-latency-compensation-online-game-feel
- https://en.wikipedia.org/wiki/Input_lag
- https://forums.unrealengine.com/t/isometric-mouse-aim-how-to-make-it-precise/76601

**Godot (rendimiento de muchos agentes)**
- https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html
- https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html
- https://www.slashskill.com/godot-4-characterbody3d-vs-multimesh-scaling-hundreds-of-units-without-killing-performance/
- https://forum.godotengine.org/t/how-to-optimize-multiple-pathfinding-optimizing-a-huge-number-of-enemies/50709
- https://www.golden-tamarin.com/2024/10/10/godot-performant-nav-agent/
- https://abyo.net/godot-mcp/guides/godot4-navigation

**Vehículos y nieve**
- https://spintires.fandom.com/wiki/Tires_(SnowRunner) (cadenas: ignoran penalización en hielo)
- https://steamcommunity.com/app/1465360/discussions/0/3882722163304070705/
