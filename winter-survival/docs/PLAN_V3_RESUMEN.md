# VENTISCA — El plan v3 en pocas palabras

> Para el propietario. 26‑sep‑2026. El detalle técnico está en `docs/PLAN_MAESTRO.md`, Parte II («Roadmap v3»), y el
> de diseño en `docs/v2/GDD_MUNDO_ABIERTO.md`, «Addendum v3».

## Qué cambia

- **Un mundo cuatro veces más grande (6 × 6 km).** El valle que ya conoces se queda tal cual, en una esquina. Al otro
  lado de un puerto de montaña aparece **Altavega**: casco viejo, ensanche, barrios de bloques y un distrito de
  rascacielos, partida por el **río Albo** helado, con puerto, polígono industrial y una autovía con un atasco de 2 km.
  La ciudad queda a medio día a pie: el coche se vuelve imprescindible. Al sur hay una sierra con estación de esquí y
  una base aérea (estas dos, en la versión 2.1).
- **Un mundo habitado, no vacío.** Atascos, pintadas, humo, campamentos, ventanas con la luz de un generador; cuervos que
  levantan el vuelo y te avisan de que algo se mueve; convoyes militares, helicópteros, una radio que avisa del tiempo,
  lanzamientos de suministros y comerciantes con los que hacer trueque. Pocas personas (como mucho 12 a la vez) y sin
  conversaciones. Los saqueadores armados llegan en la 2.1.
- **El invierno como enemigo con muchas caras.** Ventisca blanca, tormenta de hielo, ola de frío, aludes, hielo fino en
  el río, congelación de manos y pies, barrios sin luz que puedes reconectar (con sus alarmas) e incendios. Otros cinco
  peligros (tuberías que revientan, gas, vertidos, niebla tóxica y tejados que ceden) llegan en la 2.1.
- **Mejores gráficos con librerías gratuitas.** Rascacielos, coches y mobiliario urbano salen de librerías gratuitas de
  uso libre (Kenney, Quaternius), pasadas por un filtro nuestro que les pone nieve, escarcha y nuestros colores.
  Personajes, zombis, árboles y casas siguen siendo nuestros. Además: nieve nueva, niebla por capas, un color distinto
  para cada hora y cada clima, y ventanas encendidas de noche.
- **Un HUD que casi no se ve («Susurro»).** Cuando no pasa nada solo hay una tira fina abajo. Lo demás aparece cuando
  algo cambia y se va solo, o mientras mantienes la tecla de información. Al entrar en un sitio nuevo, su nombre aparece
  grande y elegante unos segundos; al salir no molesta. Misiones con «objetivo actualizado» y un rombo en el mundo. Sin
  minimapa: mapa de papel.

## Los rascacielos y la cámara

Nuestra cámara mira desde arriba, y eso tiene una consecuencia física: **nunca se ve lo que está más alto que la
cámara** (unos 18 metros). En juego, un rascacielos de 100 m es su planta baja y una sombra enorme, y si queda entre la
cámara y tu personaje lo tapa todo. Lo resolvemos así:

1. **Corte urbano**: lo que tapa a tu personaje se recorta con un tramado, y el edificio cortado se ve como el plano de
   un arquitecto. Tu personaje y tus compañeros se ven siempre.
2. **Cámara de ciudad**: en los barrios altos la cámara se inclina un poco menos y puede alejarse más, para ver más
   fachada (hasta unos 17 m por encima de ti). Nunca cambia en mitad de un combate y se puede desactivar.
3. **Miradores**: en azoteas y torres puedes «otear»: la cámara se levanta y ves la ciudad entera con su silueta.
4. **Mapa y menú**: la silueta de Altavega de noche es el fondo del menú principal y está dibujada en el mapa.

## Qué vas a ver, y en qué orden

Trabajamos en varios carriles a la vez: interfaz, mundo y gráficos, juego, y dos de arte. Cada «tramo» es,
aproximadamente, una tanda de trabajo de los agentes. Ahora mismo están en marcha el HUD nuevo, el corte urbano con los
gráficos de ciudad y la entrada de las librerías gratuitas; lo siguiente es el mapa de 6 km.

| Tramo | Lo que verás |
|---|---|
| 1 (ahora) | El HUD nuevo en el valle; una escena de prueba con rascacielos nevados, el corte urbano y la ciudad de noche; la nieve nueva en todo el valle |
| 2 | El mundo de 6 km para recorrer (sierras, río helado, autovía, carretera del puerto), aún sin ciudad; el nombre de cada zona al entrar; armas de fuego y partidas que se guardan de verdad |
| 3 | La primera manzana de Altavega en su sitio y su silueta en el menú; casas en las que se entra; los avisos y peligros del HUD nuevo |
| 4 | Niebla y color por hora y clima; la aldea de La Herrería; misiones nuevas con marcadores |
| 5 | **Altavega jugable** (casco viejo, ensanche, bloques y rascacielos, con miradores); coches; mapa de papel con la ciudad |
| 6 | La ciudad con vida (atascos, humo, pintadas, cuervos); frío, ropa, base y habilidades; opciones de accesibilidad |
| 7 | Detalle a pie de calle; el pueblo de Valdenieve completo |
| 8 | Tormentas de hielo, olas de frío, aludes y hielo fino en el río; zombis especiales y hordas |
| 9 | Catedral, hospital, estación, estadio, puerto y el gran atasco; convoyes, helicópteros, radio y comerciantes |
| 10 | Barrios que recuperan la luz, incendios y la partida completa de principio a fin |
| 11 | **Versión 2.0** lista |

Si en algún momento vamos más lentos de lo previsto, recortamos primero detalles gráficos (reflejos, manchas en el
suelo) y el número de edificios emblemáticos; nunca las pruebas ni lo esencial.

## Lo que necesitamos de ti

Cinco respuestas. Si no dices nada, aplicamos nuestra recomendación.

1. **Abrir unos dominios de internet** para descargar las librerías desde sus webs oficiales. Hoy usamos copias en
   GitHub, que funcionan pero son de terceros. Se cambia en la configuración del entorno en la nube: menú del entorno en
   la barra de título de la sesión → Editar → acceso a red → dominios permitidos.
   - Ya: `kenney.nl`, `quaternius.com`, `drive.google.com`, `drive.usercontent.google.com`, `www.googleapis.com`.
   - Hacia el tramo 4: `itch.io`, `api.itch.io` y su servidor de descargas, más una clave gratuita de la API de itch
     (para el kit urbano completo de Quaternius).
2. **¿Dar experiencia por descubrir zonas?** Recomendamos **no**: descubrir ya revela el mapa y añade una entrada al
   diario, y el diseño solo da experiencia por acciones importantes.
3. **¿Quieres ver Altavega pronto?** Recomendamos **sí**: una primera manzana de rascacielos en el tramo 3 (cuesta medio
   tramo de un carril) y la ciudad jugable en el tramo 5. No recomendamos hacer la ciudad jugable antes que las armas y
   el guardado: sin casas enterables ni coches sería una maqueta y habría que rehacerla.
4. **¿Te vale este reparto entre la 2.0 y la 2.1?** En la **2.0**: el valle, Altavega (centro, monumentos, puerto,
   polígono y gran atasco), 8 peligros del invierno, convoyes, helicópteros, radio y comerciantes, y el HUD completo. En
   la **2.1**: base aérea, estación de esquí y barrios del sur; saqueadores armados y perros; los 5 peligros urbanos
   restantes. Lo revisaremos contigo al terminar la ciudad jugable (tramo 5).
5. **Valores por defecto del HUD**: modo mínimo; el color ámbar señala en cada momento lo más urgente; sin cartel
   central de avisos; misiones con la tecla de información en vez de un panel fijo; mapa y zonas descubiertas
   compartidos por el grupo; posición exacta en el mapa (el servidor puede volverla aproximada). Recomendamos **sí a
   todo**.

## Lo que no cambia

- La cámara alta, el cooperativo de 1 a 4 en tu propio servidor, el frío como centro del juego y el ruido como préstamo.
- El valle, la cabaña del cazador, Valdenieve y todo lo ya hecho (hitos M0–M4).
- Sin minimapa, sin tráfico circulando y sin conversaciones con personajes.
- Cada hito se entrega jugable y con sus pruebas automáticas.
