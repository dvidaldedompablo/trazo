# Tracer

Base: la guía de javiggil adaptada a una app sin servidor. Qué se tomó de ella y por qué se cambió lo que se cambió: `docs/09_GUIA_JAVIGGIL.md`. Las referencias "clave N" de este documento son las seis claves de esa guía.

## Qué hace el usuario
1. En Inicio elige color y si quiere distancia (o lo deja como estaba).
2. Toca "Grabar golpe" (o "Elegir vídeo"). Con "Corte auto", tras parar elige el golpe.
3. La app crea el tracer sola. Si no está segura o pierde la bola, abre "Ajusta el vuelo" con una propuesta y dice en qué momento la perdió.
4. Ajusta si quiere (asas o "Tocar la bola") y toca "Crear vídeo". Guarda en Fotos o comparte.

## Cómo hay que grabar (clave 1, lo que más influye)
- Móvil quieto (trípode o apoyado), detrás del jugador, en la línea del golpe, a la altura de las manos.
- Vertical, a 240 fps (o 120), con la bola dentro del encuadre durante todo el vuelo que se pueda ver. Mejor con cielo despejado o fondo uniforme detrás de la subida de la bola.
- Obturación rápida activada con buena luz: la bola sale menos movida.
- A 240 fps el iPhone suele grabar en HEVC. Es normal: se lee sin problema y el vídeo final se exporta en H.264. Deja el códec que elija el sistema.
- Por qué 240 y no los 60 fps de la guía: la guía se queda en 60 por compatibilidad y coste, porque el vídeo sube a su servidor y cada fotograma cuesta tiempo de GPU. Aquí no se sube nada ni se paga GPU, y con más fps la bola salta menos píxeles entre fotogramas, que es justo lo que la guía señala como causa principal de las pérdidas.

## El proceso, paso a paso

### 1. Preparar el clip
Leer fps reales, orientación, duración y si hay audio. Si no hay audio, saltar al plan por movimiento del paso 2.

### 2. Encontrar el impacto
- `ImpactDetector` sobre el audio: paso banda 1,5 a 7 kHz; ventanas de 256 muestras con salto de 64 (a 48 kHz, unos 1,3 ms); flujo espectral; umbral adaptativo con mediana móvil de 500 ms más 6 veces la MAD; pico más fuerte; afinar con el máximo de la envolvente en ±5 ms.
- Comprobación por movimiento: la energía de la diferencia entre fotogramas en una caja alrededor de la bola salta en el impacto (la bola desaparece del tee). Si el audio y el movimiento discrepan en más de 2 fotogramas, manda el movimiento.
- En el campo de prácticas se oyen golpes de otros jugadores: elegir el pico que coincide con el movimiento del palo cerca de la bola.
- Si no hay confianza: el usuario arrastra el marcador rojo en la línea de tiempo.

### 3. Localizar la bola antes del impacto (clave 2, el primer toque)
- En el fotograma unos 0,3 s antes del impacto (sin el palo encima), buscar una mancha pequeña, clara y redonda (radio de 2 a 10 px a 1080 de ancho) cerca de donde la guía de cámara indicó "Bola aquí".
- Si ese fotograma sale movido (móvil en la mano), mirar los 10 anteriores y quedarse con el más nítido (más contraste alrededor de la bola).
- Si no hay una candidata clara: pedir un toque sobre la bola. Mostrar el fotograma con pasos de fotograma (atrás y adelante) y una lupa x3 bajo el dedo, para que el usuario elija uno nítido y toque justo encima.

### 4. Detectar la bola en vuelo
Se usan dos detectores a la vez y se quedan los mejores puntos.

**A. Vision** (`DetectTrajectoriesRequest`), solo en dispositivo real:
- Ventana: del impacto hasta 2,5 s después. Empezar analizando a 120 fps.
- Parámetros de partida: `trajectoryLength = 10` (mínimo 5; con menos salen falsos positivos), `objectMinimumNormalizedRadius ≈ 0,0015`, `objectMaximumNormalizedRadius ≈ 0,02`, zona de interés desde la bola hacia arriba con ±35 % de ancho alrededor de la bola.
- Ojo con las coordenadas: Vision usa origen abajo a la izquierda y coordenadas normalizadas.
- Quedarse con trayectorias cuyo primer punto está a menos del 8 % de la bola, que empiezan en los primeros 150 ms tras el impacto, que suben y con confianza > 0,8. Las observaciones con el mismo `uuid` crecen con los fotogramas: usar la más larga.
- Riesgo conocido: Vision ajusta parábolas en el plano de la imagen y está pensado para objetos que cruzan la imagen. Desde detrás del jugador la bola sube casi en vertical. Por eso existe el detector B.

**B. BlobTracker** (GolfCore; es el plan B de la guía, clave 4, sin entrenar nada):
- Fotogramas reducidos a unos 480 px de ancho, en gris.
- Fondo: mediana de 15 fotogramas antes del impacto (la cámara está fija).
- Tras el impacto: diferencia absoluta con el fondo (la bola puede verse más clara o más oscura que el cielo), umbral adaptativo, componentes conexas de 1 a 40 px y forma compacta.
- Kalman 2D: predice la siguiente posición; se acepta la mancha más cercana dentro de una puerta que crece con la incertidumbre. Si faltan puntos, seguir con la predicción; parar tras 12 fotogramas sin ver la bola.
- Arranque: la primera mancha que aparece cerca de la bola tras el impacto y se aleja de ella.
- Acepta semillas: una posición en cualquier fotograma desde la que sigue hacia delante y hacia atrás (la usa el toque de refuerzo).

### 4 bis. Toque de refuerzo y aviso de pérdida (clave 2)
La guía lo pide porque, según el artículo de SAM 2, un toque en otro fotograma recupera la predicción correcta en la mayoría de los casos. Con Vision y BlobTracker la idea es la misma: volver a sembrar el seguimiento donde el usuario ve la bola.
- **Aviso de pérdida**: si la bola se sigue menos de 0,5 s o la confianza del paso 5 queda por debajo de 0,5, la app lo dice claro ("Perdí la bola a los 0,6 s.", contando desde el impacto) y abre "Ajusta el vuelo" en ese fotograma.
- **Tocar la bola**: botón en "Ajusta el vuelo", siempre disponible. Pausa el vídeo y muestra pasos de fotograma y una lupa x3 bajo el dedo. El usuario busca un fotograma en el que vea la bola y la toca.
- **Volver a seguir**: con ese punto como semilla, BlobTracker sigue hacia delante y hacia atrás desde ese fotograma (Kalman arrancado en el toque, con la velocidad que den los puntos que ya había o, si no hay, la de la curva propuesta). Vision se relanza con una zona de interés centrada en el toque. Los puntos nuevos se juntan con los anteriores y se repite el paso 5.
- Los toques son puntos fijos: pesan más en el ajuste y nunca se descartan como atípicos.
- Hasta 5 toques por golpe. "Deshacer" quita el último. Los toques se guardan con el resultado para poder editarlo luego.
- Si un toque hace que el error medio suba en vez de bajar, avisar ("Ese toque no encaja con el resto. ¿Seguro que es la bola?") y dejar deshacerlo.

### 5. Unir, limpiar y completar (clave 5)
- Juntar los puntos de A, B y los toques.
- Quitar atípicos por tramos: ventanas de unos 0,25 s que se solapan, con RANSAC sobre un modelo x(t), y(t) cuadrático en el tiempo. Un punto es atípico si se aleja de su tramo más de 3 veces el error mediano. Los toques nunca son atípicos.
- Comprobaciones: la bola sube al principio, no vuelve hacia atrás y no salta más de lo que permite la velocidad máxima (en píxeles por fotograma, fijada con la prueba de 5 golpes).
- Confianza de 0 a 1 según puntos válidos, tiempo cubierto y error medio. Por debajo de 0,5, ir al ajuste manual con lo encontrado como punto de partida y el aviso de pérdida.
- La bola suele dejar de verse antes del vértice o de la caída. Completar con `TracerCurve`: dirección y curvatura de salida observadas más los valores típicos del palo (tabla de abajo). La caída es una estimación y el usuario la puede mover.

### 6. Propuesta inicial (cuando no hay detección útil)
- Salida: la bola. Dirección: hacia el punto de fuga de la línea del golpe (de la guía de cámara) o hacia el centro alto de la imagen.
- Horizonte: el cambio de brillo cielo-suelo por filas; si no se encuentra, al 44 % de la altura.
- Caída: sobre el horizonte, en la dirección de salida. Forma: recta.

| Palo | Tiempo de vuelo inicial | Vértice (desde arriba del encuadre) |
|---|---|---|
| Driver | 6,5 s | 14 % |
| Maderas | 6,0 s | 15 % |
| Hierros 5 a 7 | 5,5 s | 18 % |
| Hierros 8 a 9, PW | 5,0 s | 20 % |
| Wedges | 4,5 s | 23 % |

Son valores de partida para que la propuesta se vea bien, no medidas.

## Varios golpes a la vez (cola)
Si del corte automático salen varios golpes, se procesan en cola, uno detrás de otro, con estado visible en "Tus vídeos": en proceso, listo o falló (con el motivo en una frase). Un golpe que falla no para la cola.

## Modelo de la curva (TracerCurve)
- Controles: salida S, vértice A, caída L (en píxeles de la imagen), forma s de −1 (draw) a +1 (fade) y tiempo de vuelo T.
- Dos tramos Bézier cúbicos S→A y A→L con tangentes continuas en el vértice para que la cima sea redonda (ver la curva de la maqueta: el primer tramo sube casi recto, el segundo baja más corto). La forma desplaza el vértice y dobla la bajada hacia un lado.
- Tiempo: la bola parece muy rápida al salir y lenta al final (perspectiva y frenada). Fracción de recorrido f(τ) = 1 − (1 − τ)^2,4 con τ = t/T, ajustada para que el vértice se alcance hacia τ ≈ 0,5. Dejar las constantes en un solo sitio para afinarlas.
- El trazo arranca **en el instante exacto del impacto** y crece siguiendo a la bola (no aparece entero desde el principio). Al caer, se queda dibujado entero 1,5 s más y aparece la etiqueta (fundido de 0,3 s).

## Estilo (clave 6)
- Colores: los 5 fijos de `docs/02` más uno a elegir. El color elegido se recuerda.
- Tres capas (halo ancho difuminado, color, núcleo casi blanco), grosor decreciente con la distancia, cabeza brillante mientras vuela. Medidas en `docs/02`.
- Equivalencias con la receta de OpenCV de la guía: `GaussianBlur` es `CIGaussianBlur` o el desenfoque de la capa; `addWeighted` es la mezcla con transparencia de las capas; `LINE_AA` es el suavizado de bordes (activo por defecto en Core Graphics y Core Animation).
- Si Core Animation no da un halo difuminado convincente, dibujarlo con un compositor propio (ver `docs/01`).

## Distancia
- Interruptor "Distancia": sí o no. Si es sí, se muestra la etiqueta en la caída.
- De dónde sale el número, por orden: lo que escribe el usuario; si no, la distancia guardada para el palo elegido en "Mis palos".
- Unidades m o yd según ajustes. Formato "150 m" o "164 yd".
- La app **no mide** la distancia. La Ayuda lo explica y sugiere leerla del reloj GPS (medición del golpe) o de los carteles del campo de prácticas.
- Más adelante (opcional): modo GPS para el campo (marcar dónde se pega, caminar hasta la bola y marcar). Precisión de varios metros.

## Exportación
- MP4, H.264, con el audio original. Resolución del original hasta 1080p (vertical, como el original).
- `shouldOptimizeForNetworkUse = true`: pone el índice al principio del archivo para que el vídeo empiece a reproducirse antes de cargarse entero (es el `-movflags +faststart` de la guía). El H.264 de AVFoundation va en 4:2:0, que es lo que pide la guía con `-pix_fmt yuv420p` para que se vea en cualquier móvil.
- Guardar en Fotos y compartir. El resultado se guarda también en "Tus vídeos" con sus parámetros y toques, para poder editarlo luego.

## Modo diagnóstico
- Puntos de Vision en cian, de BlobTracker en magenta, toques en blanco con anillo, descartados en gris, curva ajustada en blanco discontinuo.
- Texto con confianza, número de puntos, tiempo de cada paso, fps reales e instante de pérdida.

## Parámetros para afinar (todos en un archivo de constantes)
| Parámetro | Valor inicial |
|---|---|
| Banda del detector de impacto | 1,5 a 7 kHz |
| Umbral de impacto | mediana + 6 × MAD |
| Muestreo de análisis | 120 fps |
| `trajectoryLength` | 10 |
| Radio normalizado mínimo y máximo | 0,0015 y 0,02 |
| Ancho de la zona de interés | ±35 % |
| Fotogramas para el fondo | 15 |
| Fotogramas sin bola para parar | 12 |
| Ventana de los tramos del ajuste | 0,25 s |
| Umbral de atípico | 3 × error mediano del tramo |
| Velocidad máxima de la bola | a fijar con la prueba de 5 golpes (px por fotograma) |
| Vuelo seguido mínimo para no avisar | 0,5 s |
| Confianza mínima para no pedir ajuste | 0,5 |
| Toques de refuerzo por golpe | 5 |
| Exponente del perfil de tiempo | 2,4 |

## Prueba de 5 golpes (clave 3, antes de dar por bueno el automático)
Graba cinco golpes distintos: cielo despejado, cielo nublado, árboles detrás, móvil apoyado y móvil en la mano. Cuenta en cuántos el trazo sigue a la bola sin saltos hasta que deja de verse y la caída parece creíble. Se cuenta sin toques de refuerzo: mide el automático.
- **4 de 5 o más** (el criterio de la guía): el automático queda por defecto, con revisión rápida.
- **Menos de 4**: el modo por defecto pasa a ser el semiautomático. La app sigue siendo útil: el impacto sale del sonido, y el usuario toca la bola o coloca vértice y caída en segundos. Además se sube de nivel, en este orden:
  1. Una vuelta de ajuste: con el modo diagnóstico y los vídeos que fallaron (en `feedback/`), Claude Code mira qué falla, afina los parámetros y se repite la prueba.
  2. Si sigue por debajo de 4: etapa 4b, SAM 2.1 de la guía en prueba de laboratorio (`docs/00` y `docs/09`, sección D).
  3. Si tampoco: plan C.

Anota cielo, fps y qué falló en `docs/PROGRESO.md`.

## Plan C (solo si A, B y la etapa 4b no bastan)
Entrenar un detector propio de bola de golf (tipo YOLO) con fotogramas propios anotados, convertirlo a Core ML con `coremltools` y usarlo como hace la guía: el filtro de Kalman predice dónde estará la bola y el detector la busca solo en un parche pequeño alrededor de esa predicción (artículo arXiv 2012.09393, que compara YOLO v3, YOLO v3-tiny, YOLO v4, Faster R-CNN, SSD y RefineDet). Los conjuntos públicos de bolas de golf son pequeños y de calidad sin comprobar (uno de Roboflow Universe tiene 128 imágenes), así que habría que anotar unos cientos de fotogramas propios. Es trabajo de varios días: no empezar sin acordarlo con el usuario.
