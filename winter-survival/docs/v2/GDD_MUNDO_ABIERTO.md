# VENTISCA v2 — Documento de Diseño (mundo abierto, zombis, co‑op 1–4)

> Diseño completo de la versión "mundo abierto". Sustituye a `docs/GDD.md` (slice) a partir del hito M2; hasta entonces el slice sigue siendo la referencia de lo que existe. Coherente con `docs/PLAN_MAESTRO.md` (decisiones §3, mundo §4, hitos §7), `ARQUITECTURA_V2.md` y `ASSET_SPEC_V2.md`.
>
> Convención de cifras: cada número es el **valor inicial** que implementa el código (constantes en `scripts/data/balance.gd` y tablas en `data/`). Donde se indica un rango entre paréntesis, es el margen que el *playtest* puede mover sin cambiar el diseño. Todo texto de juego entre comillas o en `código` es literal (español).

---

## 1. Ficha

| Campo | Valor |
|---|---|
| Título | **VENTISCA** |
| Lema | *El frío no perdona. Los muertos tampoco.* |
| Género | Supervivencia post‑apocalíptica invernal de mundo abierto, cámara alta tipo isométrica, ratón + WASD (mando soportado), cooperativo PvE 1–4 en servidor dedicado, PvP/fuego amigo opcionales |
| Sesión objetivo | 45–120 min (una expedición + mantenimiento de base); partida de 10–30 h por servidor |
| Mundo | 3 × 3 km (48 × 48 chunks de 64 m); pueblo, 3 aldeas, 3 granjas, carretera nacional, lago, ~15 POIs |
| Plataforma | PC (Windows/Linux). Forward+ por defecto, preset `compat` (OpenGL) |
| Idioma | Todo el texto en español; identificadores en inglés |

### 1.1 Los seis pilares (ver PLAN §1.3)

Legible desde arriba · El frío decide el ritmo · Ruido = préstamo · Nunca separes al grupo (pero permite separarse) · Persistencia honesta · Un director, no un guion.

---

## 2. Bucles de juego

### 2.1 Momento a momento (10–60 s)

Mirar los tres anillos (Hambre / Salud / Calor) + el **termómetro sentido** + el arco de **Aguante** → decidir: *¿me queda calor para ir y volver?* → moverse (andar en silencio / correr gastando aguante y sudando) → abrir contenedor / talar / forzar puerta / disparar → **ver el anillo de ruido** que acabas de emitir → reaccionar (zombis que investigan, congelados que despiertan) → volver al calor.

### 2.2 Sesión (45–120 min)

La **expedición**: elegir objetivo en el mapa de papel (gasolinera a 600 m, comisaría a 1.2 km) → preparar (ropa seca, antorcha, munición, bidón) → ir (a pie o en coche, por carretera o por el bosque) → saquear con ventana marcada por el frío, la noche y el director → volver antes de la noche o de la ventisca anunciada → descargar en la caja común → mejorar algo (estufa, cadenas, radio) → dormir por votación para saltar la noche.

### 2.3 Meta (10–30 h por servidor)

Semana 1: sobrevivir, reclamar una base, primer coche. Semana 2: comisaría/hospital, planos, base N2–N3. Semana 3+: torre de radio → quitanieves → evacuación (o "Nos quedamos": sin fin, dificultad creciente). Cada **7 días de juego** llega la **Gran Ventisca** (anunciada 1 día antes): −20 °C, visibilidad 6 m, horda migratoria hacia la base más ruidosa.

```
  Calor ───► Salir ───► Saquear / cazar / talar ───► Ruido ───► Zombis
    ▲                                                              │
    │                                                              ▼
  Base ◄─── Volver (coche / a pie) ◄─── Noche o ventisca anunciada ◄─── Huir / luchar
    │
    └──► Fabricar / mejorar / dormir (voto) ──► nueva expedición (más lejos, más frío)
```

### 2.4 Sesión y escalado por número de jugadores

| Jugadores | Sesión típica | Zombis activos por zona | Especiales por evento | Botín `nominal` | Horda de asalto | Dormir |
|---|---|---|---|---|---|---|
| 1 | 45–60 min: expedición corta + mantenimiento; +10 % de coches con llave en el contacto | 12 | 1 | ×1.0 | 15 | 1 vota |
| 2 | 60–90 min: uno conduce, otro dispara | 18 | 1 | ×1.25 | 20 | 2/2 en cama |
| 3 | 90–120 min | 24 | 2 | ×1.5 | 25 | ≥ 2/3 en cama, resto en interior seguro |
| 4 | 90–120 min: dos parejas, base con turnos, expediciones lejanas | 30 | 2 | ×1.75 | 30 | ≥ 3/4 |

Fórmula: zombis × (1 + 0.5·(n−1)). **Los PV de los zombis no escalan.** El frío no escala ("el gran igualador"). `gamestage` del grupo = 0.5·máx + 0.5·media de (días sobrevividos + nivel medio de habilidades).

### 2.5 Tiempo

- Día de juego = **1 800 s reales** (30 min): día 06:00–20:00 (20 min), noche 20:00–06:00 (10 min). Configurable (`day_length_sec`).
- Amanecer 05:30–06:30, anochecer 19:30–20:30 (fundidos de 30 s).
- Empieza el **Día 1 a las 08:00**. El contador de día sube a las 06:00. No hay fin por días: el mundo es persistente.
- Ventiscas normales: desde el Día 1 a las 14:00, tirada cada hora de juego con **8 %**, mínimo 6 h entre ventiscas, aviso 60 s antes ("Se acerca una ventisca…"), duración **2–4 min** reales. Gran Ventisca: cada 7 días, 1 día de juego entero.

---

## 3. Cámara y controles

### 3.1 Cámara (decisión de usuario: alta, estilo isométrico, seguimiento)

- Perspectiva, FOV vertical **35°**, inclinación **−52°**, guiñada en pasos de **45°** (Q/E, tween 0.35 s), distancia **22 m** (rueda: 14–30 m). Seguimiento lerp 6/s; adelanto 1.5 m en la dirección de movimiento.
- **Inclinación hacia el cursor**: con arma en mano la cámara se desplaza hacia el cursor hasta **3 m** (rifle con mira: **6 m**), interpolado a 6/s. Sin arma: 0.
- Nunca gira sola, nunca colisiona (está alta). Árboles y tejados que tapan al jugador local se atenúan (*fade* 0.15 s).
- Sacudidas con decaimiento exponencial, nunca > 0.6 m (§15).
- **Corte de interiores**: al entrar en un edificio desaparecen el tejado y las plantas superiores a la del jugador; las fachadas que dan a la cámara se sustituyen por un **muñón de 0.6 m** (se conserva el contorno). Solo edificios a < 30 m del jugador local. Cada cliente corta según *su* jugador.
- **Visibilidad honesta**: lo que el personaje no ve (fuera de su cono de 120° o tras paredes sin línea de visión) se dibuja **desaturado y sin zombis**; los zombis fuera del cono que hacen ruido se representan como **anillo de sonido** en el suelo. En ventisca el cono se encoge a 6 m.

### 3.2 Controles

| Acción | Teclado / ratón | Mando | Notas |
|---|---|---|---|
| Moverse | W A S D / flechas | Stick izq. | Relativo a la guiñada de cámara |
| Correr | Mayús (mantener) | L3 | 6.0 m/s; gasta Aguante 5/s; suda tras 20 s |
| Agacharse | Ctrl (conmuta) | R3 | 1.5 m/s; ruido 2 m; detección ×0.5 |
| Apuntar / mirar al cursor | Mantener clic derecho (o automático con arma en mano) | Stick der. | El torso mira al cursor |
| Interactuar / atacar objetivo bajo el cursor | Clic izquierdo (R: lo más cercano ≤ 2.5 m) | X | Si está lejos, camina solo (cancelable) |
| Disparar / golpear | Clic izquierdo con arma en mano | RT | Mantener = golpe cargado (melee) |
| Recargar | R (con arma de fuego) | X | Cancelable por esquiva/empujón |
| Empujón | Espacio | B | Derriba 35 %; cuesta 8 Aguante |
| Lanzar | G (con arrojadiza) | LB+RT | Marcador de aterrizaje |
| Cancelar / cerrar | Clic derecho (sin arma), Esc | B | |
| Pausa (menú local; el mundo no se para) | Esc | Start | |
| Girar cámara / zoom | Q, E / rueda | LB, RB / D‑pad ↑↓ | |
| Barra 1–9, MANO | 1–9 | D‑pad ←→ + A | Ranura 1 = MANO |
| Fabricación / inventario / ropa | Tab / I / C | Y / Back | |
| Mapa de papel | M | Back (mantener) | Con marcas de *ping* |
| Ping | Botón central (mantener: rueda) | RB (mantener: rueda) | Contextual (§12.3) |
| Chat | Enter | — | Texto siempre disponible |
| Antorcha / linterna | T | D‑pad ↓ (mantener) | |
| Comer lo mejor | F | — | Prioridad §9.4 |
| Vehículo: entrar/salir | E junto al coche / E | X | 0.8 s, cancelable |
| Vehículo: acelerar/frenar/girar/claxon/faros | W S A D / H / L | RT LT stick / Y / LB | |
| Rendirse (derribado) | Mantener X 3 s | Mantener Y | |

### 3.3 Etiqueta de contexto

Como en el slice: anillo de resalte en la base + etiqueta sobre la barra. Nuevas etiquetas: `Abrir puerta` / `Cerrar puerta` / `Forzar puerta (palanca)` / `Puerta cerrada con llave`; `Registrar armario` / `En uso`; `Romper ventana` / `Entrar por la ventana`; `Entrar (conductor)` / `Entrar (pasajero)` / `Abrir maletero` / `Sifonar (manguera)` / `Repostar (bidón)` / `Puentear (Mecánica 2)`; `Ejecutar` (congelado, por la espalda); `Reanimar (4 s)`; `Recoger mochila de <nombre>`; `Leer plano`; `Reclamar edificio`; `Mejorar: estufa (N2)`; `Pescar`; `Despiezar`. Objetivo lejano: ` · acércate`. Sin herramienta: `Necesitas una palanca`, etc.

---

## 4. El frío (sistema central)

### 4.1 Temperatura sentida

```
T_sentida = T_ambiente
          + Aislamiento_ropa      (suma de prendas: 0 … +40 °C)
          − Viento_efectivo       (0 … 25 °C; solo lo reduce el % cortaviento de la capa EXTERIOR)
          − Penalización_humedad  (0 … 12 °C)
          + Fuente_de_calor       (+10 … +40 °C según fuente y distancia)
          + Refugio               (aislamiento del edificio 0–1 × (0 − T_ambiente) × 0.6, ventanas rotas restan)
```

| Parámetro | Valor (rango) |
|---|---|
| T_ambiente día / noche | −8 °C / −18 °C (−4 … −25) |
| Ventisca | −10 °C adicionales, viento 25 |
| Gran Ventisca | −20 °C adicionales, viento 25, todo el día |
| Deshielo (evento raro) | T ≥ 0 °C durante 1 día |
| Confort | T_sentida ≥ 0 °C → Calor +2/s hasta 100 |
| Drenaje | Calor −(0 − T_sentida) × 0.06 /s (a −10 °C sentidos: −0.6/s ⇒ 100 → 0 en ≈ 2.8 min; a −25 °C: 1.1 min) |
| Fuentes | Fogata +25 (a ≤ 4.5 m, decae a 0 a 7 m); estufa +30 en todo el interior; vehículo con motor +25 en cabina cerrada (+10 con ventana rota); antorcha en mano +5; bengala +5 a 2 m; termal (v3) |

**Regla de oro**: toda penalización se muestra con icono + número + causa (`−6 °C: guantes mojados`). Panel de ropa (C) muestra la suma.

### 4.2 Ropa por capas

Ranuras: **interior, media, exterior** (torso) + **cabeza, manos, pies**. Cada prenda: Aislamiento (°C), Cortaviento (%), Impermeable (%), Peso (kg), Estado (%). Solo la **capa exterior** aporta cortaviento.

| Prenda | Ranura | Aisl. | Cortav. | Imperm. | Peso | Dónde |
|---|---|---|---|---|---|---|
| Camiseta | interior | +2 | 0 | 0 | 0.2 | inicio |
| Jersey de lana | media | +6 | 0 | 0 | 0.6 | casas |
| Sudadera | media | +4 | 10 | 0 | 0.5 | casas |
| Chaqueta (inicio) | exterior | +6 | 40 | 20 | 1.0 | inicio |
| Abrigo | exterior | +10 | 60 | 30 | 1.8 | casas, tienda |
| Parka | exterior | +14 | 80 | 60 | 2.4 | tienda de deportes (poco común) |
| Abrigo militar | exterior | +16 | 90 | 70 | 2.8 | base militar (raro) |
| Chaleco policial | media | +3 | 20 | 10 | 4.0 | comisaría; daño al cuerpo ×0.7 |
| Gorro de lana / gorro de piel | cabeza | +3 / +5 | 20 / 50 | 0 / 40 | 0.1 / 0.3 | casas / cazador |
| Casco | cabeza | +1 | 30 | 80 | 1.2 | comisaría/militar; crítico recibido ×0.5 |
| Guantes de lana / manoplas / guantes militares | manos | +2 / +4 / +4 | 10 / 40 / 60 | 0 / 30 / 60 | 0.1–0.3 | casas / cazador / militar |
| Botas de ciudad / botas de invierno / botas militares | pies | +2 / +5 / +6 | 20 / 60 / 70 | 20 / 70 / 80 | 0.8–1.4 | casas / tienda / militar |
| Abrigo de piel de lobo (fabricado) | exterior | +12 | 70 | 40 | 2.0 | receta ROPA |

Sin guantes: no se puede tensar el arco con Calor < 15; sin botas de invierno: nieve profunda moja ×2.

### 4.3 Humedad

0–100 % por prenda. Fuentes: nieve profunda (+0.3 %/s en piernas/pies), caída al agua (100 % todas), lluvia de deshielo, **sudor** al correr (+0.5 %/s a partir de 20 s corriendo, capas interior/media). Cada 10 % de humedad: **−1 °C de aislamiento y −10 % de cortaviento** de esa prenda; el peso sube hasta ×2. Secado: 1 %/s junto al fuego (≤ 3 m), 0.3 %/s en interior con estufa, 0.1 %/s en interior frío, 0 al exterior. **Mojado anula el abrigo**: una parka al 100 % aísla como una camiseta.

### 4.4 Umbrales del Calor

| Calor | Efecto |
|---|---|
| < 30 | Viñeta de escarcha, `Tienes frío`, idle tiritando |
| < 15 | Velocidad ×0.8, cono de precisión ×1.5, recarga ×1.5, `Te estás congelando` |
| = 0 | Salud −4/s. Tras 60 s a 0: **Congelación** en la parte desnuda (manos > pies > cabeza) → **−10 % de salud máxima permanente** (cura: kit de cirugía 50 %, "Cirujano" 100 % una vez) |

### 4.5 Formas del frío

| Forma | Mecánica |
|---|---|
| **Refugio** | Aislamiento del edificio 0–1 (cabaña 0.5, casa 0.7, hospital 0.6, granero 0.2, tienda de campaña 0.3, coche cerrado 0.4). Cada ventana rota −0.1, puerta abierta −0.2. Estufa encendida = fuente +30. |
| **Ventisca** | Aviso 60 s; visibilidad 6 m (niebla densa + partículas); cono de visión de todos a 6 m; ruido ×0.6; congelados no despiertan; aparece el **acechador** (día 6+); duración 2–4 min. Los zombis fuera del cono solo **suenan**. |
| **Lago helado** | Hielo grueso (azul claro, seguro), fino (más oscuro, cruje, icono `!` al pisar), agujero. Caer = ropa 100 % mojada, Calor −40, Salud −10, salir a rastras 3 s. Hinchado y Coloso rompen el hielo fino (arma ambiental). Coches lo rompen (> 1 200 kg); la motonieve no. Pesca en agujero (30 s, ruido 3 m, pescado). |
| **Calefacción del vehículo** | Motor encendido: +25 °C en cabina cerrada, consume 0.3 L/min y hace 20 m de ruido parado. Dormir en el coche con motor es una elección real. |
| **Objetos con temperatura** | Latas congeladas: Hambre −50 % hasta 30 s junto al fuego; pilas: rendimiento −50 % bajo −10 °C (linterna, walkie); agua de cantimplora se congela (no bebible hasta calentar). |
| **Noche** | −10 °C, visibilidad 12 m, faroles/ventanas como referencia; congelados no despiertan por calor (ventana de sigilo). Dormir en cama por votación salta la noche si no hay zombis a < 20 m de la base. |
| **Gran Ventisca** | Cada 7 días. −20 °C todo el día, visibilidad 6 m, horda migratoria con el viento hacia la base más ruidosa, congelados en 200 m de la base despiertan en oleadas cada 5 min. |
| **Deshielo** | Evento raro (1 día, T ≥ 0). Todo el campo de congelados de la zona despierta en 10 min. Anunciado 1 día antes por la radio/el cielo. |

---

## 5. Estadísticas del jugador

| Stat | Máx | Inicio | Regla |
|---|---|---|---|
| **Salud** | 100 (menos congelaciones) | 100 | −4/s con Calor 0; −2/s con Hambre 0; +0.5/s si Calor > 40 y Hambre > 40 y sin Fiebre; daño de zombis/armas/caídas |
| **Calor** | 100 | 80 | §4 |
| **Hambre** | 100 | 70 | −0.15/s (×2 corriendo). Comer: §9.4 |
| **Aguante** | 100 | 100 | Correr −5/s; golpe melee −8; empujón −8; cargado −12; recupera +8/s quieto, +4/s andando; < 20: no puedes correr ni cargar golpes; peso > 80 % → −20 % máx. |
| **Fiebre** | 0–100 | 0 | Mordisco +10 (por mordisco); mientras > 0: Calor −1/s extra y regeneración 0; baja −0.1/s en cama, −1/s con antibióticos (rara). **Sin muerte por infección.** |

Muerte: Salud = 0 → **Derribado** (§12.2); tercer derribo sin descanso o desangrado → muerte. Causa registrada: `Frío`, `Hambre`, `Horda`, `Acechador`, `Lobos`, `Caída`, `Hielo`, `<nombre del jugador>` (PvP), `Explosión`.

---

## 6. Zombis

Jugador de referencia: 100 PV, andar **2.2**, correr **6.0**, agachado **1.3** m/s (decisión M1, PLAN C19: las animaciones de locomoción se autoran a estas velocidades; el caminante a 1.2 m/s sigue siendo más lento que andar).

### 6.1 Roster

| Tipo | PV | Velocidad | Daño / cadencia | Sentidos | Regla que rompe | Contra‑táctica | Aparece | % población | Hito |
|---|---|---|---|---|---|---|---|---|---|
| **Caminante** | 100 | 1.2 m/s (1.0–1.4) | 12 / 1.2 s; agarre si 2+ adyacentes (−50 % vel. 1.5 s) | Vista 25 m día / 12 m noche / 6 m ventisca, cono 120° | Ninguna: el ladrillo | Andar más rápido; cuellos de botella; palanca | Siempre | 70 % | M4 |
| **Corredor** | 70 | 5.5 m/s en ráfagas de 4 s, luego 3.0 m/s 3 s | 10 / 0.9 s | Vista 30 m, cono 90° | Te alcanza | Puertas (no abre, golpea 3 s); se congela: 10 min al exterior bajo −10 °C sin estímulo → Caminante frágil | Día 3+ | 8 % (máx. 2 por horda) | M4 |
| **Reptador** | 50 | 1.0 m/s | 8 / 1.0 s + agarre de piernas (2 s inmóvil, se patea) | Oído ×1.5, vista 8 m | Invisible en nieve profunda (bulto + vaho) | Mirar el vaho; bengala; nieve pisada | Siempre | 7 % | M4 |
| **Congelado** | 100 (contundente ×1.5: "se astilla") | 0 hasta despertar; luego Caminante ×0.8 durante 30 s | 12 / 1.2 s | Despierta por: ruido ≥ 15 m de radio a ≤ 8 m, jugador ≤ 1.5 m, calor (fuego a 4 m, escape a 3 m, T ≥ −2 °C) | El campo de minas | Silencio; ejecución con cuchillo (1.5 s, silenciosa); atraer a otros al campo con el claxon | Siempre, exteriores; todo caminante sin estímulo 5 min bajo −10 °C se congela (recicla población) | 10 % activos + toda la población parada | M4 |
| **Hinchado** | 150 | 0.9 m/s | 15 / 1.5 s; al morir: nube 4 m / 8 s (visibilidad 0, Calor −5/s, humedad +10 %/s, olor 30 m) | Vista 15 m | Muerte = peligro | Arco/rifle de lejos; nunca melee en interior | Pueblos, día 5+ | 3 % | M4 |
| **Gritón/a** | 60 | 2.0 m/s, mantiene 8–12 m | Grito: radio 60 m, canal 3 s interrumpible, atrae 6–15 zombis y despierta congelados a 20 m | Vista 25 m | Convierte sigilo en horda | Arco/ballesta; matar en el canal | Día 4+ | 1.5 % | M9b |
| **Acechador de ventisca** | 120 | 4.0 m/s, silencioso | 25 / 1.5 s; por la espalda ×2 | Vista 6 m, **olfato 20 m** | Solo en ventiscas; ataca a quien se separe > 10 m | Ir en pareja; bengala (huye 15 s); interior | Ventiscas, día 6+; 1 por cada 2 jugadores fuera | Evento | M9b |
| **Acorazado** (policía/SWAT/soldado) | 100 | 1.2 m/s | 12 | Como caminante | Cuerpo ×0.5 (chaleco); casco: crítico ×0.5 hasta caer (2 golpes contundentes) | Contundente a la cabeza; suelta uniforme y munición | Comisaría, control militar | 0.5 % (local) | M9b |
| **Coloso** | 600 | 2.5 m/s; embestida 7 m/s | 40 / 2.0 s; rompe puertas y barricadas de un golpe; rompe hielo fino | Vista 20 m, oído ×2 | Tanque | Explosivos, molotov, coche, hielo fino | Control militar / Gran Ventisca | Solo eventos | M9b |

Cada tipo tiene silueta única a 20 m y sonido único. Infección: mordisco = Fiebre +10 (§5).

### 6.2 Sentidos

- **Vista**: cono 120° (90° corredor); periférica 360° a 3 m; comprobación cada 0.2 s a < 40 m. Probabilidad de detección por segundo = `clamp(1 − d/R, 0, 1) × luz × postura` (agachado ×0.5, quieto ×0.7, corriendo ×1.3, antorcha/linterna de noche ×2.0).
- **Oído**: cada acción emite `SoundEvent(pos, radio, prioridad)`. Zombi a `d ≤ radio` fija ese punto como **investigación** con probabilidad `1 − d/radio` (mín. 0.3 para armas de fuego). Ruidos seguidos suben el **calor de zona** (decae 1/min); el director lo usa (gritón, horda errante).
- **Olfato** (solo dos casos, ambos legibles): jugador sangrando o con > 3 carnes crudas → detectable a 8 m sin línea de visión; vapor del hinchado y acechador (20 m).
- **Memoria**: última posición 20 s; sin estímulo 45 s → vagar; al llegar al punto investigado sin ver nada se queda 10–20 s (ventana de emboscada).

### 6.3 Tabla de ruido (radio en metros)

| Fuente | Radio | Notas |
|---|---|---|
| Paso agachado / andando / corriendo | 2 / 6 / 14 | Nieve profunda ×0.7, hielo ×1.3; en interior ÷2 |
| Abrir puerta / cerrar de golpe / forzar con palanca | 6 / 15 / 8 | |
| Romper ventana / cristal de coche | 25 / 20 | La palanca abre sin romper |
| Golpe melee (bate, hacha) / cuchillo / fallo | 10 / 3 / 8 | |
| Empujón / patada / pisotón | 8 / 8 / 6 | |
| Arco / ballesta | 5 / 6 | |
| Pistola 9 mm / revólver .357 | 80 / 90 | |
| Rifle .308 / carabina 5.56 | 120 / 110 | |
| Escopeta / recortada | 150 / 130 | |
| Silenciador | ×0.3 | |
| Motor ralentí / conduciendo / a fondo / motonieve | 20 / 45 / 70 / 60 | mínimo 8 |
| Claxon | 120 (mientras se pulse) | Señuelo |
| Alarma de coche / de tienda | 150 (30 s) / 150 (60 s) | 15 % al puentear; 5 % al forzar tienda |
| Generador | 30 constante | |
| Bengala | 0 ruido; luz atrae a 40 m durante 30 s | Señuelo silencioso |
| Bomba de tubo | 60 (6 s) + explosión 5 m / 150 daño | |
| Lata / piedra lanzada | 15 | Señuelo barato |
| Grito del gritón | 60 | |
| Ventisca | todo ×0.6 | |
| Multijugador | sin reducción (`noise_scale` de servidor) | |

**Feedback**: anillo blanco que se expande desde el emisor hasta el radio real en 0.4 s, visible para todos los jugadores.

### 6.4 Población, hordas, migración

- **Densidad por chunk** (64 m): bosque 0–1, aldea 3–8, pueblo 10–25, comisaría/hospital 16–33, control militar 40+. Los interiores tienen zombis dormidos según edificio (§9.2).
- **Reaparición**: no hasta **72 h de juego** sin jugador a < 150 m del chunk, y solo hasta el **60 %** del valor original. Cadáveres desaparecen a las 24 h de juego (o al quemarlos: humo atrae).
- **Reciclaje por frío**: caminantes al exterior sin estímulo 5 min a ≤ −10 °C pasan a Congelado (ahorra CPU y crea el campo de minas).
- **Hordas errantes**: 8–20 zombis siguiendo carreteras entre asentamientos; 1–3 activas por km² alrededor de los jugadores, generadas por el director fuera de la vista.
- **Gran horda migratoria** (una por mapa): 60–120. De día duerme en un edificio grande (nave del aserradero, iglesia, gimnasio de la escuela) o congelada en un campo; de noche se mueve por carretera hacia la zona con más calor de ruido de los últimos 3 días. Deja **rastro** (nieve pisada, sangre, cadáveres de animales). Persistente: lo que matas no vuelve; con < 15 se disuelve en errantes.
- **Meta‑eventos**: helicóptero (día 6–9: mueve zombis hacia el jugador más ruidoso), disparos lejanos, aullidos, alarma remota. 1–2 por día, nunca en ventisca.
- **Asalto a la base**: si el calor de ruido de la base supera el umbral (≈ 30 min de generador o 20 disparos en un día), la noche siguiente llega una horda de 10 + 5·n, anunciada 2 min antes (gruñidos; la radio de la base avisa: "movimiento al norte").

### 6.5 Comportamiento por hora y temperatura

| Condición | Efecto |
|---|---|
| Día (−8 °C) | Normal |
| Noche (−18 °C) | Vista 12 m, oído ×1.3, congelados no despiertan por calor |
| T ≤ −10 °C, exterior, sin estímulo 5 min | Caminante → Congelado |
| Golpe contundente a congelado | Daño ×1.5 + astillado |
| Fuego / escape / interior calentado cerca | Congelado despierta en 3 s (crujido); corredor recupera velocidad |
| Ventisca | Vista 6 m, ruido ×0.6, no despiertan, acechador |
| Gran Ventisca | Horda con el viento; congelados a 200 m de la base despiertan en oleadas cada 5 min |
| Deshielo | Todo el campo despierta en 10 min |

### 6.6 Director de IA

Un `Director` en el servidor, por **zona activa** (radio 150 m por jugador; zonas solapadas se fusionan; máx. 4 zonas).

**Intensidad por jugador (0–1)**: recibir daño +0.30 (+0.5 si queda < 30 PV); matar a < 5 m +0.10; ≥ 4 zombis a < 8 m +0.15/s; derribado = 1.0; Calor < 30 +0.05/s; sin amenaza −0.03/s. **Intensidad del grupo = máximo** de la zona.

| Fase | Entrada | Acción | Salida |
|---|---|---|---|
| **Acumulación** | Por defecto | Rellena el presupuesto de activos fuera de vista (≥ 30 m, sin línea de visión, nunca a la espalda a < 15 m); 1 evento cada 45–120 s ponderado por zona y clima: horda errante, gritón, meta‑sonido, despertar de congelados, acechador (solo ventisca) | Intensidad ≥ 0.8 durante ≥ 15 s, o 4 min |
| **Pico** | — | Deja de generar | Intensidad < 0.3 |
| **Alivio** | — | 30–45 s sin generar (acorta si el grupo se mueve > 60 m); si vida media < 40 %: +25 % de vendas/latas en los 3 próximos contenedores | Fin del temporizador |

Presupuesto de activos por zona: 12 × (1 + 0.5·(n−1)) ± 30 % por tipo de zona; **máximo duro 60 por zona, 150 L0 por servidor**.

**Reglas de cortesía**: (1) nunca ventisca + horda errante salvo Gran Ventisca; (2) en ventisca presupuesto ×0.5 + acechador; (3) > 10 min sin ver un zombi ⇒ evento menor garantizado; (4) especiales con anuncio ≥ 3 s (grito, borboteo, respiración); (5) no genera dentro de edificios limpiados por los jugadores (72 h).

### 6.7 LOD de IA (resumen de la decisión C9)

L0 Activo < 40 m (cuerpo físico, 10 Hz) · L1 Cercano 40–120 m (sin cuerpo, 2 Hz) · L2 Grupo 120–400 m (una entidad) · L3 Celda. Presupuesto de pantalla: **20–35 L0 visibles** es el máximo legible; una horda "de 100" son 30 L0 + 70 L1 fluyendo desde fuera del encuadre.

---

## 7. Combate para cámara alta

### 7.1 Apuntado

- Cursor proyectado al **plano del pecho (1.2 m)**; el personaje mira al cursor con arma en mano (sin arma mira hacia donde anda).
- **Magnetismo**: zombi a ≤ 1.2 m del cursor → objetivo real (contorno naranja). Desactivado para lanzables y rifle a > 25 m. Mando: ×2 (2.4 m) + *soft‑lock* al más cercano dentro de 20° del stick.
- **Cono de precisión visible**: retícula = anillo cuyo radio es la dispersión. Se cierra quieto (0.8 s hasta mínimo), se abre al moverse, al recibir daño y con Calor < 15. Colores: rojo (> 8°), ámbar (4–8°), verde (< 4°).
- **Crítico = cabeza**: sin apuntado por partes. `P(crít) = base_arma + 4 %·Puntería + 15 % si el anillo está verde`; ×3 daño; cabeza que estalla en fragmentos low‑poly.
- **Melee**: arco 90–110° frente al personaje; alcance por arma (1.2–2.3 m); hasta N objetivos (1 cuchillo, 2 bate, 3 hacha pesada/lanza). **Empujón**: 35 % derribo (+5 %/nivel Fuerza), 8 Aguante. **Pisotón** a derribado = ejecución 1.0 s (ruido 6). Mantener = **golpe cargado** (×1.5, +0.4 s, ruido +4).

### 7.2 Economía melee / arco / fuego

| | Melee | Arco / ballesta | Fuego |
|---|---|---|---|
| Coste | Aguante 8/golpe, durabilidad, riesgo de agarre | Tiempo de tensado; flechas 60–70 % recuperables | Ruido 80–150 m, munición escasa, encasquillamiento |
| Brilla en | 1–3 zombis, interiores, silencio | Caza, gritones/hinchados a distancia, ejecuciones | Hordas, colosos, urgencias, cubrir a un derribado |
| Munición por semana (4 jugadores) | — | 20–40 flechas fabricables | 9 mm 60–90; cartuchos 20–30; .308 10–15; 5.56 30 (solo militar) |

La munición **nunca reaparece** en contenedores abiertos (solo en chunks no visitados 72 h, al 60 %). Fabricar munición (pólvora + casquillos: 50 % de los disparados) es el grifo (`ammo_crafting` de servidor).

### 7.3 Durabilidad y clima

Cada golpe/disparo: probabilidad 1/N de perder 1 punto de estado (N +2 por nivel de Mantenimiento; N base en la tabla). Estado 0 = roto (reparable una vez con cinta/piezas al 70 %). Armas de fuego mojadas o a < −15 °C sin aceite: +5 % de encasquillamiento por disparo (1.5 s para destrabar). Aceite de arma lo anula 1 día. Herramientas‑arma también se desgastan al usarse como herramienta.

### 7.4 Recarga, retroceso, dispersión

| Parámetro | Valor |
|---|---|
| Recarga | pistola 1.6 s; revólver 3.0 / 1.8 s (cargador rápido); escopeta 0.7 s/cartucho interrumpible; cerrojo 3.5 s; carabina 2.2 s; ballesta 2.5 s. Cancelable por esquiva/empujón |
| Retroceso | +2° (pistola) … +9° (escopeta) por disparo; recuperación 12°/s; sacudida 0.1 m |
| Dispersión mínima | pistola 1.5°, revólver 1.2°, carabina 1.0°, rifle 0.5°, escopeta cono fijo 10° (recortada 16°). Puntería 10: ×0.6 |
| Penalizaciones | andar +3°, correr +8°, agachado −1°, Calor < 15 ×1.5 |

### 7.5 Retroalimentación de impacto

| Capa | Parámetros |
|---|---|
| Hitstop | melee 50–80 ms (atacante y víctima); cargado 100 ms; disparo 0 (víctima 30 ms) |
| Flinch | zombi: animación 0.3 s + empujón 0.4 m (bate) … 1.0 m (escopeta); derribo 35 % contundente |
| Sacudida | golpe 0.12 m/0.15 s; escopeta 0.25/0.2; recibir daño 0.35/0.35; explosión 0.6/0.5 con caída |
| Sangre en nieve | quads planos 0.6–1.2 m `#8B1E1E`, se oscurecen, 120 s; rastro de gotas si sangras (olfato) |
| Desmembramiento ligero | cabeza (crítico), brazo (cortante 20 %: sigue), piernas (escopeta ≤ 4 m 30 %: se vuelve reptador) |
| Audio | 3 capas: golpe (madera/metal/hoja), carne, reacción; a distancia solo la 1.ª |
| UI | sin números flotantes; contorno parpadea; `×` en la retícula al crítico |
| Ruido visible | anillo hasta el radio real en 0.4 s |

### 7.6 Tabla de armas (caminante = 100 PV)

| # | Arma | Clase | Daño | Crít. base | Cadencia | Alcance | Obj./golpe | Ruido | Durab. (N) | Golpes | Peso | Notas | Hito |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Cuchillo de caza | Cortante 1M | 18 | 10 % | 0.40 s | 1.2 m | 1 | 3 | 250 | 6 | 0.4 | Ejecución silenciosa (espalda/congelados, 1.5 s); despieza | M4 |
| 2 | Palanca | Contundente 1M | 28 | 15 % | 0.70 s | 1.6 m | 1 | 8 | 800 | 4 | 2.0 | Fuerza puertas/maleteros (8 m vs 25) | M4 |
| 3 | Bate | Contundente 2M | 30 | 20 % | 0.65 s | 1.7 m | 2 | 10 | 300 | 4 | 1.2 | Derribo 35 %; con clavos +8 daño, −50 % durab. | M4 |
| 4 | Hacha de leñador | Cortante 2M | 45 | 30 % | 0.90 s | 1.7 m | 2 | 10 | 400 | 3 (2 crít.) | 2.5 | Tala; se queda clavada 5 % (0.5 s) | M4 |
| 5 | Machete | Cortante 1M | 38 | 20 % | 0.55 s | 1.5 m | 1 | 8 | 350 | 3 | 0.9 | Desmembra brazos 20 % | M4 |
| 6 | Lanza artesanal | Perforante 2M | 35 | 25 % | 0.80 s | 2.3 m | 3 en línea | 8 | 120 | 3 | 1.5 | Fabricable; se rompe rápido | M8 |
| 7 | Arco de caza | Arco | 40 | 25 % | 1.4 s tensar | 25 m | 1 | 5 | 300 | 3 (1 crít.) | 1.0 | Flechas 60 % recuperables; sin guantes y Calor < 15 no tensa | M5 |
| 8 | Ballesta | Arco | 60 | 30 % | 2.5 s | 35 m | 1 | 6 | 400 | 2 | 3.0 | Virotes 70 %; rara | M9a |
| 9 | Pistola 9 mm | Fuego | 25 | 15 % | 0.25 s | 15 m | 1 | 80 | 1500 | 4 | 0.9 | Cargador 15; común | M5 |
| 10 | Revólver .357 | Fuego | 45 | 20 % | 0.50 s | 18 m | 1 | 90 | 2000 | 3 | 1.1 | 6 balas; atraviesa 2 en línea | M5 |
| 11 | Escopeta de corredera | Fuego | 8 × 12 | 10 %/perdigón | 0.90 s | 10 m (10°) | ≤ 4 | 150 | 1200 | 1 (≤ 6 m), 2 (10 m) | 3.5 | Tubo 6; derribo 70 %; recortada: 16°, ruido 130, 2 cartuchos | M5 |
| 12 | Rifle .308 (cerrojo) | Fuego | 90 | 40 % | 1.5 s | 45 m | atraviesa 2 | 120 | 2500 | 2 (1 crít.) | 3.8 | Cargador 5; mira: cámara 6 m; caza mayor | M5 |
| 13 | Carabina 5.56 | Fuego | 35 | 15 % | 0.15 s | 30 m | 1 | 110 | 3000 | 3 | 3.2 | Cargador 30; solo militar; encasquilla ×2 con frío | M9b |
| 14 | Arrojadizas | — | Molotov 4 m, 15/s × 8 s, despierta congelados a 6 m; Bengala luz + señuelo 40 m/30 s + Calor +5; Bomba de tubo 60 m/6 s pitido, 150 en 5 m; Lata/piedra ruido 15 m | — | 0.8 s | 12 m | — | tabla ruido | 1 uso | — | 0.5 | Parábola con marcador; fuego amigo según servidor | M5 (lata, bengala), M9b (resto) |

**Modificaciones** (todas encontradas): silenciador 9 mm (ruido ×0.3, −10 % daño), mira de rifle (cámara 6 m, dispersión ×0.7), linterna bajo cañón (cono 8 m; +detección de noche), cargador rápido de revólver, correa (peso −30 % para el aguante), clavos para bate, cinta para mango (durabilidad +25 %).

### 7.7 Fuego amigo y PvP (opciones de servidor; decisión C20)

| `friendly_fire` | Daño jugador→jugador (misma facción) | Cuándo |
|---|---|---|
| `off` (defecto) | 0 % (proyectiles atraviesan aliados; melee no golpea aliados). Los aliados sí bloquean la línea de tiro visualmente (retícula gris) | Grupos casuales |
| `reduced` | 25 % armas, 12 % explosivos | Grupos que quieren cuidado sin castigo |
| `full` | 100 % | Realismo |

`pvp = true`: daño entre facciones distintas ×1.0 siempre; los jugadores colisionan; sistema de seguridad (30 s de retardo para activar/desactivar PvP personal, `safety_system`); facciones; casas seguras (`safehouses`, `days_to_claim = 3`, `no_raid_when_offline`); candados (`container_locks = faction`); robo de vehículos (`vehicle_theft = faction`). Con `pvp = false` los jugadores **no colisionan** entre sí (evita bloqueos de puertas).

---

## 8. Vehículos

| Vehículo | Asientos | Maletero | Depósito | Consumo | Vel. nieve pisada / profunda sin cadenas / con cadenas | Ruido ralentí / conduc. | Rareza | Rol | Hito |
|---|---|---|---|---|---|---|---|---|---|
| Sedán (+ patrulla) | 4 | 20 kg | 40 L | 0.5 L/min | 60 / atascado / 35 km/h | 20 / 45 | Común (30 % con llave cerca) | Primer coche; frágil; patrulla con radio y luces | M7 |
| Camioneta | 3 + caja 2 | 60 kg (caja 100, se moja) | 60 L | 0.7 | 55 / 15 / 45 | 25 / 50 | Común | Caballo de batalla; caja dispara 360° | M7 |
| Furgoneta (+ ambulancia) | 2 + 4 | 120 kg | 70 L | 0.8 | 50 / atascada / 35 | 25 / 55 | Media | Base móvil; cama dentro | M7 |
| Motonieve | 2 (+ trineo 40 kg) | 15 kg | 15 L | 0.4 | 70 / 70 / — | 30 / 60 | Rara (embarcadero, deportes) | Cruza lagos y bosque; ruidosa | M7 |
| Quitanieves / camión pesado | 2 | 200 kg | 150 L | 1.5 | 40 / 40 / 40; empuja coches y zombis; no se para ante hordas < 30 | 40 / 80 | Única (depósito municipal: batería de camión + 3 piezas) | Abre la carretera al control militar y la evacuación | M10 |

**Reglas**:
- **Llaves**: 25 % en el contacto, 15 % guantera, 20 % en un zombi cercano (llavero visible), 20 % en la casa más próxima, 20 % sin llave → **puentear** (Mecánica 2, canal 8 s, 15 % alarma; +4 s en coches en buen estado). La llave es del grupo (duplicable en el taller).
- **Batería** 0–100 %: arranque −2 %, luces parado −1 %/min, frío −1 %/h bajo −10 °C a la intemperie (0 en garaje). < 20 %: fallo de arranque con `(1 − carga/20 %) · 80 %`, cada intento 15 m de ruido. Pinzas + otro coche o cargador de base.
- **Gasolina**: sifón 5 L/min (manguera); surtidor solo con electricidad (generador: 30 m de ruido) o bomba manual (2 L/min, silenciosa, plano). Bidón 20 L = 16 kg.
- **Cadenas**: fabricables (cadena + Mecánica 3) o encontradas (gasolinera, garaje, militar). Sin cadenas en nieve profunda: tracción ×0.4 y atasco (canal 6 s para salir, ruido); con cadenas ×0.8 y nunca atascado. Hielo: sin cadenas control ×0.3, con cadenas ×0.7; hielo fino se rompe con > 1 200 kg.
- **Daño** en 4 piezas (motor, ruedas, batería, carrocería/parabrisas). Atropello ≥ 30 km/h mata caminante, carrocería −2 %; horda ≥ 10 en el capó frena (×0.2) y golpea ventanas (parabrisas rompe a 5 golpes: entra el frío y entran ellos). Rueda pinchada: ×0.5, cambio 30 s con gato + rueda.
- **Calefacción**: §4.5. **Radio del coche**: evento de historia, atrae 30 m.
- **Co‑op**: el conductor tiene la física; pasajeros disparan por la ventanilla (cono 120° a su lado) o 360° desde la caja; maletero compartido; entrar/salir 0.8 s, no en marcha. Trineo tras la motonieve (vuelca > 40 km/h); cable para arrastrar un coche (2 jugadores).
- **Restos**: los coches de atascos/aparcamientos son props con contenedor; 1 de cada 8 (por semilla) es funcional.

---

## 9. Botín y economía

### 9.1 Rarezas

| Rareza | Peso | Ejemplos |
|---|---|---|
| Común | 60 % | Latas, ropa de casa, vendas, madera, clavos, 9 mm (1–6) |
| Poco común | 30 % | Abrigo, botas de invierno, palanca, hacha, cartuchos, antibióticos, gasolina |
| Raro | 9 % | Rifle, ballesta, cadenas, batería de coche, planos, radio portátil |
| Único | 1 % (solo en su edificio) | Carabina 5.56, mira, generador, piezas del quitanieves, código de la torre |

### 9.2 Tablas por tipo de edificio (65 % de que un contenedor tenga algo; 1–3 objetos)

| Edificio | Contenedores | Común | Poco común | Raro / único | Peligro (zombis dormidos) |
|---|---|---|---|---|---|
| Casa | armario, cocina, nevera (congelada), cómoda, garaje | latas 35 %, ropa 25 %, vendas 10 %, herramientas 10 % | abrigo 8 %, cuchillo 5 %, pistola 3 % (dormitorio), gasolina 4 % (garaje) | rifle 0.5 % (casa rural con trofeos) | 2–6, 1 congelado en el porche |
| Cabaña / cazador | baúl, trofeos | carne seca, cuerda, pieles | arco 20 %, flechas 30 %, trampa 15 % | rifle .308 8 %, ballesta 5 % | lobos cerca |
| Gasolinera | estanterías, caja, taller, surtidor | latas, chocolate, bebidas (congeladas), cinta, mapa de zona (revela carreteras) | gasolina 30 %, aceite, batería 10 %, piezas 20 %, cadenas 12 % | bidón 5 % | 6–12, alarma 5 % |
| Tienda ropa/deportes | estantes, probadores | ropa (media/exterior) 60 % | botas 20 %, guantes 25 %, gorro, mochila grande 15 % | motonieve (trasera) 3 %, ballesta 4 % | media |
| Farmacia / clínica | mostrador, armario | vendas 40 %, analgésicos 30 % | antibióticos 15 %, sutura 10 % | — | gritón 20 % |
| Hospital | carros, quirófano, farmacia central | vendas, sueros | antibióticos 30 %, kit de cirugía 10 % | desfibrilador 3 % | 30–60, acorazados de seguridad; **objetivo de sesión de 4** |
| Comisaría | armería (cerrada: llave del sargento o Mecánica 4), taquillas, celdas | ropa policial, porra | pistola 40 %, 9 mm 60 %, escopeta 25 %, chaleco 20 % | radio portátil 10 %, llaves de patrulla | 20–40, 30 % acorazados |
| Control militar | contenedores, armería, garaje | raciones (no se congelan), mantas térmicas | cartuchos, botas militares, cadenas 30 % | carabina 15 %, 5.56, mira, piezas del quitanieves, generador 10 %, abrigo militar | 60–120 + Coloso; solo con quitanieves/motonieve |
| Depósito municipal / taller | bancos, estanterías | piezas, clavos, tablones | batería 20 %, gato, ruedas, cadenas 25 % | quitanieves (roto) 100 % | 10–20 |
| Aserradero | almacén, oficina | madera, clavos, cuerda | sierra, cadenas 15 %, planos de carpintería | — | 8–15 |
| Iglesia / escuela | sacristía, aulas | velas, ropa, latas | botiquín escolar, mapa | — | refugio de horda |
| Torre de radio | sala de control | cables, pilas | piezas de radio | componente único | horda 1 de cada 3 días |
| Zombi (20 % al morir) | — | su ropa | policía: 9 mm; médico: vendas; soldado: 5.56; cazador: flechas | llaves de coche 5 % | — |

### 9.3 Reaparición (decisión C22)

`nominal`/`min` por objeto y km²; el servidor repone solo hasta `nominal`, en contenedores no abiertos en 72 h dentro de chunks sin jugador a < 150 m durante 48 h, al 60 % (`loot_respawn` 0.0–1.0). Nominal bajo para armas/munición (por 4 jugadores: 9 mm 150, cartuchos 40, .308 25, 5.56 40); alto para ropa y comida. Objetos en el suelo desaparecen a 12 h de juego; cadáveres de jugador 48 h. **Sin botín instanciado** (opción `personal_loot_bags`).

### 9.4 Peso, contenedores, comida

- Capacidad 20 kg + 1 kg/nivel de Forma física; mochila pequeña/media/grande +15/+25/+35 (peso 1/2/3); arma equipada ×0.5. Umbrales: > 80 % velocidad ×0.85 y aguante −20 %; > 100 % ×0.6 y no corres; > 120 % no te mueves. Ropa mojada pesa hasta ×2.
- Barra de **10 ranuras** (1 = MANO) + **mochila** (panel I) por peso. Contenedores del mundo 6–12 ranuras; los de base compartidos con etiqueta de propietario opcional (candado).
- Comida (Hambre / Calor / Salud): bayas +12; bayas calientes +25/+10; carne cruda +8/0/−5; carne asada +40/+10; lata de judías +40 (congelada +20); lata de sopa +35; chocolate +15/+5; ración militar +45/+5; pescado asado +35/+8; carne seca +20. Prioridad de `F`: asada > ración > lata > bayas calientes > pescado > chocolate > bayas > cruda.

---

## 10. Fabricación y base

### 10.1 Categorías y recetas (barra izquierda: 🔨 Herramientas, 🔥 Fuego, ⛺ Refugio, 📦 Almacenaje, 🍲 Cocina, 👕 Ropa, ⚙ Mecánica, 🔫 Munición)

| Categoría | Receta | Coste | Requiere | Resultado | Hito |
|---|---|---|---|---|---|
| Herramientas | Hacha de piedra | 2 madera + 3 piedra | — | hacha (única) | slice |
| Herramientas | Lanza artesanal | 3 madera + 1 cuchillo (no se consume) | banco | lanza | M8 |
| Herramientas | Flechas ×5 | 2 madera + 1 piedra + 1 pluma/tela | — | flechas | M5 |
| Herramientas | Trampa de oso | 4 chatarra + 2 cuerda | banco + "Trampero" | trampa | M8 |
| Fuego | Antorcha / Fogata | 2 madera + 1 piedra / 3 madera + 4 piedra | — | antorcha / colocable | slice |
| Fuego | Bengala casera | 1 pólvora + 1 lata + 1 tela | banco + plano | bengala | M8 |
| Refugio | Tienda | 6 madera + 2 tela | — | colocable (aislamiento 0.3) | slice |
| Refugio | Barricada de ventana / puerta | 3 tablones + 4 clavos | martillo | ranura de base | M8 |
| Refugio | Valla / alambre | 2 madera / 2 chatarra | martillo | colocable | M8 |
| Almacenaje | Caja de madera | 4 madera | — | colocable 6 ranuras | slice |
| Almacenaje | Estantería de base | 6 tablones + 8 clavos | banco | ranura de base 24 ranuras | M8 |
| Cocina | Carne asada / bayas calientes / pescado asado / descongelar lata | 1 / 3 / 1 / 1 | fuego cerca | comida | slice, M5, M8 |
| Ropa | Abrigo de piel | 2 pieles de lobo | — | abrigo (§4.2) | slice |
| Ropa | Reparar prenda | 1 tela + aguja | — | +30 % estado | M8 |
| Mecánica | Cadenas de nieve | 4 cadena + 2 chatarra | banco + Mecánica 3 o plano | cadenas | M8 |
| Mecánica | Bomba manual de gasolina | 3 tubo + 2 chatarra + 1 manguera | banco + plano | herramienta | M8 |
| Mecánica | Reparar pieza de coche | 2 piezas + 1 cinta | gato | +50 % pieza | M7 |
| Mecánica | Silenciador casero | 2 tubo + 1 lata + 1 tela | banco + "Silenciador casero" | mod 9 mm | M9b |
| Munición | 9 mm ×10 / cartuchos ×4 / .308 ×5 | pólvora + casquillos (+ perdigones) | banco de recarga + plano; `ammo_crafting` | munición | M8 |

Estados del panel: `Materiales listos` · `Faltan materiales` · `Requiere fuego cerca` · `Requiere banco de trabajo` · `Requiere plano` · `Requiere Mecánica 3` · `Ya fabricado` · `Sin hueco`. Colocación con fantasma verde/rojo (pendiente < 30°, ≤ 6 m, sin bloqueadores, no dentro de edificio salvo piezas de interior).

### 10.2 Base: reclamar + ranuras (no construcción libre)

`Reclamar edificio` (cualquier enterable con puerta) crea la base de la facción; una base por facción (se puede mudar). Cada nivel exige un **objeto raro de una expedición**:

| Nivel | Ranuras que desbloquea | Requisito | Efecto |
|---|---|---|---|
| N1 | Estufa (mejorada), camas ×4 (reaparición), caja común | Reclamar + 10 tablones | Fuente +30, dormir por voto, respawn |
| N2 | Taller (banco), almacén (estantería), barricadas de ventanas/puertas | Batería de coche | Recetas de banco; barricadas +100 PV; llaves duplicables |
| N3 | Generador, radio, cargador de baterías, invernadero interior | Generador (militar/gasolinera) + componente de radio | Luz y electricidad (surtidor, cargador); radio avisa de asaltos y meta‑eventos; comida estable |
| N4 | Torre de vigilancia, luces exteriores, banco de recarga | Piezas del quitanieves o 20 chatarra + plano | Ver a 60 m de noche (y ser visto); munición casera |

Piezas colocables libres (6): valla, barricada, fogata, tienda, caja, trampa. La base acumula **calor de ruido** (generador 30 m, disparos) que dispara asaltos (§6.4). El servidor registra quién cogió qué de la caja común ("Ana ha cogido 20 de 9 mm").

---

## 11. Progresión

### 11.1 Habilidades por uso (0–10) + ventajas

XP solo por **acciones significativas** (matar a un zombi que te ha visto, fabricar una receta por primera vez ×5, reparar una pieza de un coche que funciona, reanimar…) y **rendimiento decreciente diario** (las 20 primeras acciones del día XP completa, luego ×0.25). Cada 2 niveles: elegir 1 ventaja de 2. Las ventajas se **muestran a los compañeros** (icono junto al nombre).

| Habilidad | Sube por | Por nivel | Ventajas (nivel 2/4/6/8/10: una de dos) |
|---|---|---|---|
| Contundente | bate, palanca, martillo | +3 % daño, +2 % derribo, N +1 | "Batazo" (cargado derriba a 3) / "Rompepuertas" (puertas en 2 golpes) |
| Cortante | hacha, machete, cuchillo | +3 % daño, +2 % crítico | "Leñador" (tala en 2) / "Desollador" (doble piel) |
| Puntería | armas de fuego, arco | dispersión ×(1 − 0.04n), crítico +2 % | "Frío como el hielo" (el anillo no se abre al recibir daño) / "Cazador" (flechas 90 %) |
| Sigilo | agachado cerca de zombis sin ser visto | pasos −4 %, detección −5 % | "Sombra" (ejecuciones frontales a congelados) / "Pies de gato" (nieve profunda silenciosa) |
| Forma física | correr, cargar | aguante +4, +1 kg | "Segundo aliento" (aguante 100 % al derribar) / "Mula" (+10 kg) |
| Supervivencia | cocinar, cazar, hogueras, pescar | comida +5 %, fuego +5 % | "Sangre caliente" (Calor drena ×0.85) / "Nariz" (huellas de animales a 30 m) |
| Carpintería | barricadas, muebles, tala | barricadas +10 % PV, coste −5 % | "Aislante" (casa +20 % calor) / "Trampero" (trampas de oso) |
| Mecánica | reparar, puentear, cadenas | puentear −0.5 s, piezas +10 % | "Silenciador casero" (escape −30 % ruido) / "Arranque en frío" (batería no se drena) |
| Medicina | curar | vendar −10 % tiempo, +5 % curación | "Camillero" (reanimar 2 s) / "Cirujano" (cura congelación 100 % una vez) |

### 11.2 Planos

Revistas/manuales: cadenas, bomba manual, munición casera, generador (reparación), radio, estufa de aceite, trineo, silenciador, bengala casera. Se leen en 60 s junto al fuego y quedan **desbloqueados para todo el servidor**.

### 11.3 Meta‑objetivos (en cualquier orden, con pistas en notas/radios)

1. **Torre de radio**: reparar el repetidor (3 componentes en 3 edificios peligrosos: hospital, comisaría, presa) → emisión que anuncia la evacuación en X días y su punto (puente norte, carretera cortada por el control militar).
2. **Quitanieves**: batería de camión (control militar o taller) + 3 piezas (depósito municipal, aserradero, gasolinera) → abre la carretera hacia el control y la evacuación.
3. **Evacuación** (final): llegar con el convoy al punto en la fecha, defenderlo **8 min de juego** contra la Gran Horda atraída por las bengalas, subir. Pantalla final con estadísticas del grupo. El servidor puede continuar en modo **"Nos quedamos"** (sin fin, dificultad creciente, +1 horda migratoria por semana).

### 11.4 Tablón de objetivos (sustituye al panel de misiones)

Por jugador: 1 objetivo principal (meta actual) + hasta 3 secundarios generados por el mundo: `Alarma en la comisaría: 20 zombis, 60 % de 9 mm`, `Se acerca la Gran Ventisca en 1 día: la base necesita 60 leñas`, `Rastro de la horda hacia el norte`, `Radio: superviviente pidiendo ayuda en la cabaña (nota + botín)`. Sin NPC hablando: la historia se cuenta con notas, radios, cadáveres y escenografía.

---

## 12. Cooperativo 1–4

### 12.1 Mundo y botín

Un mundo, un servidor dedicado, persistente (estado de chunks, contenedores, base, vehículos, horda migratoria, día). Sin anfitrión ni invitados. Sin correa: el mundo se transmite por chunks alrededor de cada jugador; el único límite es el presupuesto de zonas activas (4 zonas de 150 m). Botín no instanciado; herramientas anti‑conflicto: *ping* de objeto, "soltar para X" (arrastrar sobre el retrato a < 3 m), caja común con registro. Progresión individual (habilidades, ventajas) + compartida (planos, base, meta, llaves). Facciones: una por servidor por defecto; con `pvp` varias.

### 12.2 Derribado, reanimación y muerte

| Estado | Regla |
|---|---|
| **Derribado** (Salud 0) | Cae; se arrastra a 0.8 m/s; dispara con pistola. Desangrado **60 s** (40 s con Calor < 30); zombis a < 3 m siguen mordiendo (−5 s por mordisco). Calavera con temporizador visible para todos |
| **Reanimar** | Otro jugador mantiene E **4 s** (2 s "Camillero"); interrumpible por daño; se levanta con 30 PV y `Malherido` (×0.85 velocidad, 5 min). Sin botiquín. Máx. **2 derribos** entre descansos (dormir): al tercero muere; tras el 2.º la pantalla se desatura |
| **Rendirse** | Mantener X 3 s |
| **Muerte** | Reaparece en la cama de la base (o punto de inicio) tras 20 s, con ropa básica, Calor 60, **sin mochila**: el cadáver guarda todo 48 h de juego. −10 % XP hacia el siguiente nivel de cada habilidad. `permadeath = true`: personaje nuevo |
| **Solo** | Derribado = 20 s para "levantarse solo" con vendas (una vez por día) |
| **Desfibrilador** (raro) | Reanima a un cadáver en 60 s desde la muerte con 10 PV; 1 uso |

### 12.3 Comunicación

- **Pings contextuales**: una tecla sobre lo que hay bajo el cursor: enemigo (rojo, 8 s), objeto (icono + nombre hasta que se coge), lugar (bandera 30 s), vehículo, y rueda: "ven aquí", "peligro", "necesito calor / munición / vendas". Aparecen en el mundo (anillo + icono + distancia), en el borde de pantalla si están fuera de encuadre y en el mapa. Sin voz del personaje (el ruido importa): sonido de UI solo para el grupo.
- **Chat de texto siempre**: burbujas a < 20 m (proximidad) y canal `[G]`. Enter; `/comandos` para admin.
- **Voz**: `voice = off` en v2.0 (reservado `proximity/global`). **Walkie** (raro, pilas que el frío drena) como canal de radio futuro.
- **Emotes**: señalar, ven, espera, silencio (sincronizados con los *pings*).
- **Compañeros en HUD**: nombre + barra + icono de ventaja + flecha en el borde de pantalla + calavera con temporizador si está derribado.

### 12.4 Opciones de servidor (`server.cfg`, replicadas y visibles en el HUD)

| Opción | Valores | Defecto |
|---|---|---|
| `pvp` | false / true | false |
| `friendly_fire` | off / reduced / full | off |
| `safehouses` (+ `days_to_claim`, `no_raid_when_offline`) | on/off, 3, on | on |
| `container_locks` | off / faction / owner | faction |
| `fire_spread` | off / on | off |
| `vehicle_theft` | any / faction / owner | faction |
| `permadeath` | off / on | off |
| `loot_respawn` | 0.0–1.0 | 0.6 |
| `zombie_count_scale`, `noise_scale`, `cold_scale` | 0.5–2.0 | 1.0 |
| `ammo_crafting` | off / on | on |
| `personal_loot_bags` | off / on | off |
| `safety_system` | on/off | on (si pvp) |
| `day_length_sec` | 600–3600 | 1800 |
| `great_blizzard_days` | 0 (off) – 30 | 7 |
| `max_players` | 1–4 | 4 |
| `sleep_vote` | majority / all | majority |
| Kick/ban y registro de acciones | — | on |

---

## 13. Interfaz y HUD (extensión del estilo de referencia)

Estilo: paneles azul pizarra translúcidos con borde superior "escarchado", títulos en mayúsculas condensadas, subtítulos en versalitas, acento `#FFB454` (paleta del slice §17). **Todo lo del slice se conserva** (banner de región, reloj de día, tres anillos, categorías a la izquierda, barra de 10 ranuras, etiqueta de contexto, toasts, viñetas).

Añadidos v2:

| Elemento | Dónde | Qué muestra |
|---|---|---|
| **Termómetro sentido** | junto a los anillos | `−12 °C` con flecha (subiendo/bajando) y, al pasar el cursor, el desglose (`ambiente −18 · ropa +12 · viento −6 · guantes mojados −1 · estufa +30`) |
| **Aguante** | arco fino bajo los anillos | solo visible cuando < 100 |
| **Estados** | fila de iconos con causa | `Mojado 40 %`, `Fiebre`, `Malherido`, `Congelación (mano)`, `Sobrepeso` |
| **Arma** | sobre la barra, derecha | icono, munición `12/15 · 44`, estado, mod |
| **Retícula** | en el cursor | anillo de dispersión (rojo/ámbar/verde), `×` al crítico, gris si un aliado bloquea |
| **Anillo de ruido** | en el mundo | expansión hasta el radio real |
| **Compañeros** | columna superior izquierda bajo las categorías | retrato, nombre, barra, ventaja, distancia; flecha de borde si está fuera; calavera + temporizador si derribado |
| **Pings** | mundo + borde + mapa | icono + distancia |
| **Chat** | inferior izquierda | 100 líneas, se atenúa a los 8 s |
| **Tablón** | panel derecho (antes "misiones") | 1 principal + 3 secundarios, con progreso |
| **Mapa de papel** | pantalla completa (M) | regiones descubiertas, carreteras, marcas de ping, base, "tú estás aquí" aproximado (sin minimapa) |
| **Ropa** (C) / **Mochila** (I) / **Habilidades** (K) | paneles | ranuras por capa con números; peso `14.2 / 25 kg`; habilidades con XP y ventajas |
| **Servidor** | icono junto al reloj | `PvP` / `FF 25 %` / jugadores `3/4` / ping |
| **Vehículo** | abajo cuando conduces | velocidad, gasolina, batería, daño por pieza, `Cadenas` |
| **Ventisca / Gran Ventisca** | bajo el reloj | `VENTISCA` parpadeo; cuenta atrás de la Gran Ventisca `GRAN VENTISCA EN 1 DÍA` |
| **Derribado** | centro | `DESANGRÁNDOTE · 47 s` + `Mantén X para rendirte` |
| **Muerte** | pantalla | cámara lenta 0.5 s, `HAS MUERTO`, causa, consejo de 1 línea (`Los congelados despiertan con el ruido: usa el cuchillo`), `Reaparecer en la base (20 s)` |
| **Menú principal** | | `Jugar solo` (servidor local), `Unirse` (IP:puerto + contraseña, recientes, LAN), `Crear partida` (config → lanza servidor), `Opciones`, `Salir` |
| **Pausa** | | `Continuar`, `Opciones`, `Salir al menú` (el mundo sigue) |

Sin números flotantes de daño. Sin minimapa. Texto de UI en español.

---

## 14. Dirección de audio

- Sin archivos en el repo por defecto: `AudioManager` con ganchos por nombre (lista del slice + v2). SFX CC0 se enchufan por tabla si están disponibles; hasta entonces, tonos procedurales (`AudioStreamGenerator`) para viento, crujidos y golpes básicos.
- **Viento** como capa continua (0.2 día / 0.5 noche / 1.0 ventisca) que **enmascara** el resto en ventisca.
- **Voces de zombi** con prioridad por distancia y **paneo por posición en pantalla** (no por orientación del personaje); gruñido de "te he visto" ≥ 0.5 s antes de moverse; máx. 8 voces y 24 SFX simultáneos.
- Eventos nuevos: `zombie_groan`, `zombie_alert`, `zombie_attack`, `zombie_hit`, `zombie_die`, `frozen_crack`, `frozen_wake`, `runner_breath`, `bloater_gurgle`, `bloater_pop`, `screamer_scream`, `stalker_breath`, `colossus_roar`, `gun_pistol`, `gun_revolver`, `gun_shotgun`, `gun_rifle`, `gun_carbine`, `gun_dry`, `gun_jam`, `reload_*`, `bow_draw`, `bow_release`, `melee_swing`, `melee_hit_flesh`, `melee_hit_wood`, `door_open`, `door_close`, `door_break`, `window_break`, `car_start`, `car_fail`, `car_engine_loop`, `car_horn`, `car_crash`, `car_alarm`, `snowmobile_loop`, `ice_crack`, `ice_break`, `water_splash`, `revive_loop`, `downed`, `ping`, `chat`, `objective_done`, `great_blizzard_warning`, `radio_static`, `radio_broadcast`, `generator_loop`.
- Música: ninguna en bucle; **stingers** cortos en pico/alivio del director y en la Gran Ventisca.

---

## 15. Parámetros de *game feel*

| Área | Regla | Parámetro |
|---|---|---|
| Latencia de entrada | Movimiento predicho; melee: la animación empieza el mismo frame en el cliente; el servidor valida | Local < 50 ms tecla→primer frame; red < 120 ms percibidos |
| Anticipación / cancelación | Golpe: *wind‑up* 120–180 ms, activo 60 ms, recuperación 250 ms cancelable a 150 ms por esquiva/empujón; *input buffer* 150 ms | Animaciones: anticipación ≥ 0.25 s, impacto ≤ 0.12 s, poses exageradas 20–30 % |
| Movimiento | Aceleración 0.1 s a andar, 0.2 s a correr; frenada 0.08 s; giro instantáneo; el modelo rota a 720°/s | Nieve profunda ×0.7 + nieve levantada |
| Hitstop | 50–80 ms melee; 100 ms cargado | |
| Cono | cierra en 0.8 s quieto | rojo/ámbar/verde |
| Cámara | seguimiento 6/s, adelanto 1.5 m, inclinación 3/6 m | sacudida ≤ 0.6 m |
| Capas de feedback | cada acción: animación + partícula + sonido + UI | p. ej. recoger: mano baja, destello, `pickup`, ranura parpadea |
| Legibilidad a 22 m | contornos 2 px en personajes y zombis; zombis desaturados vs jugadores saturados; sangre como mapa de la batalla | |
| Muerte | cámara lenta 0.5 s, viñeta, causa y consejo | |

---

## 16. Onboarding y objetivos iniciales

Las 8 misiones del día 1 del slice se conservan (leña → estufa → hacha → talar → comer → fogata → antorcha → amanecer). Se añaden:

- **Día 2**: `Sigue las huellas hasta la aldea` (rastro autorado hacia La Herrería), `Un zombi congelado: acércate en silencio` (uno en el porche de la primera casa), `Haz ruido a propósito con una lata` (enseña el anillo), `Fuerza una puerta con la palanca`.
- **Día 3**: `Tu primer disparo: mira el anillo de ruido`, `Reclama un edificio`, `Encuentra las llaves de la camioneta` (llavero visible en un zombi cercano), `Vuelve antes de la noche`.
- Enseñar **ruido y congelados antes que armas**. En co‑op, los objetivos de onboarding son compartidos (los completa cualquiera del grupo).

---

## 17. Mundo (resumen; el mapa y las regiones están en PLAN §4)

3 × 3 km; claro del cazador en el centro; Valdenieve al noreste; N‑140 al este; lago al suroeste; aldeas La Herrería (NO), El Embarcadero (SO), San Blas (SE); granjas ×3; control militar al norte (corta la carretera a la evacuación); repetidor en el pico oeste; presa, aserradero, torre de vigilancia como hitos. Borde: montaña + bosque + niebla. Superficies: nieve pisada (carreteras, huellas), nieve profunda (visible, más clara y "esponjosa"), asfalto, hielo, interior.

---

## 18. Lo que NO haremos en v2.0

NPC con moral; zombis que excavan; hordas de 500 individuales; infección mortal por defecto; construcción por vóxeles; botín instanciado por defecto; olfato "de mentira"; cientos de armas; tercera persona; voz; Steam; móvil/web.
