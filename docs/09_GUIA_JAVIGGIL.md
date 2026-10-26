# La guía de javiggil: qué se ha tomado y dónde está

Fuente: "El trazo de tu bola de golf, como en la tele: monta la web entera, paso a paso" (javiggil, 22 de octubre de 2026). El usuario la tiene en PDF.

La guía monta una **web de pago**: el vídeo sube a un servidor, SAM 2.1 sigue la bola en una GPU alquilada y se cobra con Stripe. Trazo es una **app personal** que lo hace todo en el iPhone. Por eso:
- Se toma todo lo que sirve para que el trazo salga bien: las seis claves, la petición por etapas, la prueba de cinco golpes, el plan B y la exportación.
- Se deja fuera lo que solo sirve para una web o para cobrar: subida de vídeos, almacén, GPU, Stripe, captación y cuentas de costes.
- El seguimiento con SAM 2.1 se sustituye por Vision y BlobTracker en el iPhone. SAM 2.1 queda como etapa 4b opcional (sección D).

**Regla para Claude Code**: si una decisión del tracer no está clara en `docs/03`, mira aquí qué dice la guía y por qué se adaptó. No reintroduzcas servidor, subida de vídeos ni cobro.

## A. Las seis claves (todas dentro)

| Clave de la guía | Cómo queda en Trazo | Dónde |
|---|---|---|
| 1. Graba para que la bola se vea | Móvil quieto, detrás del jugador, en la línea del golpe, con la bola dentro del encuadre todo el vuelo y cielo o fondo uniforme detrás. **Cambio**: 240 fps en lugar de 60. La guía se queda en 60 por compatibilidad y coste: el vídeo sube a su servidor y cada fotograma cuesta tiempo de GPU. Aquí no se sube nada ni se paga GPU, y su propio argumento (con más fps la bola salta menos píxeles entre fotogramas) pide más fps. | `docs/03` "Cómo hay que grabar", `docs/05`, Word Parte 7 |
| 2. Siembra el toque en el fotograma bueno y deja el clic de refuerzo | Toque inicial: la app busca la bola sola antes del impacto; si no hay candidata clara, pide el toque, y si el fotograma está movido deja pasar a otro. Toque de refuerzo: botón "Tocar la bola" en cualquier fotograma posterior, que vuelve a seguir desde ahí. Aviso claro cuando se pierde la bola. | `docs/03` pasos 3 y 4 bis, `docs/02` "Ajusta el vuelo", etapas 4 y 5 |
| 3. La prueba de cinco clips | Los mismos cinco golpes (despejado, nublado, árboles, apoyado, en la mano) y el mismo criterio: 4 de 5 o más. | `docs/03`, `docs/07`, Word 7.3 |
| 4. Plan B: detector de bola con filtro de Kalman | En dos niveles. BlobTracker (detector clásico por diferencia con el fondo, con Kalman, sin entrenar nada) se construye en la etapa 2 y funciona a la vez que Vision. El detector entrenado tipo YOLO que busca en un parche pequeño alrededor de la predicción de Kalman (el de la guía, artículo arXiv 2012.09393) es el plan C. | `docs/03` paso 4 y "Plan C", `docs/01` |
| 5. La parábola y el descarte de atípicos | RANSAC por tramos con un modelo cuadrático en el tiempo, comprobaciones de dirección y velocidad, y Kalman. Después, la curva editable (TracerCurve). | `docs/03` paso 5 |
| 6. El brillo en tres capas | Halo ancho difuminado, capa del color elegido y núcleo casi blanco; el trazo aparece siguiendo a la bola, no entero desde el principio. Equivalencias de las funciones de OpenCV que cita la guía: `GaussianBlur` es `CIGaussianBlur` o el desenfoque de la capa; `addWeighted` es la mezcla con transparencia de las capas; `LINE_AA` es el suavizado de bordes, activo por defecto en Core Graphics y Core Animation. | `docs/03` "Estilo", `docs/02` "Gráficos" |

## B. Las seis etapas de la petición

| Etapa de la guía | En Trazo |
|---|---|
| 1. Página y subida; primer fotograma y toque | Grabar o importar en la app (etapa 3) y localizar la bola o pedir el toque (etapa 4). Sin subida. |
| 2. Seguimiento con SAM 2.1 tiny en una GPU | Sustituido por Vision (`DetectTrajectoriesRequest`) y BlobTracker en el iPhone (etapa 4). SAM 2.1 queda como etapa 4b opcional. |
| 3. Limpiar la trayectoria; si el usuario toca otra vez, seguir desde ahí | Etapa 4: TrajectoryFit por tramos, Kalman y toque de refuerzo. |
| 4. Trazo con brillo y MP4 H.264 hasta 1080p que se reproduzca sin bajarse entero | Etapa 5. H.264 en 4:2:0 (lo que pide `-pix_fmt yuv420p`), `shouldOptimizeForNetworkUse = true` (lo mismo que `-movflags +faststart`: el índice va al principio del archivo) y la resolución del original hasta 1080p. |
| 5. Cobro con Stripe | Fuera: uso personal. |
| 6. Prueba con cinco vídeos | Etapa 4: la hace el usuario y se apunta en `PROGRESO.md`. |
| Nota de caducidad (confirmar versiones antes de ejecutar) | Regla en `CLAUDE.md`: comprobar la documentación vigente de cada API. |

## C. El resto de la guía

| Sección | En Trazo |
|---|---|
| 1. Qué construyes y por qué web | App nativa; todo en el iPhone. Sin cuenta de desarrollador de pago: se instala con Sideloadly. |
| 3. La subida (límite de 4,5 MB, almacén, R2, borrar a los 7 días) | No aplica: nada sale del teléfono. Sí se toman dos cosas: grabar a 1080p y entregar el vídeo final en H.264. A 240 fps el iPhone suele grabar en HEVC; es normal y la exportación sale en H.264. |
| 4. SAM 2.1 y sus límites | Sus límites (le cuestan los objetos pequeños y rápidos, solape medio de 0,461 en un banco de pruebas de objetos rápidos y ninguna cifra publicada con bolas de golf en vídeos de móvil) son parte del motivo para no ponerlo por defecto. Ver sección D. |
| 5. La prueba de cinco clips y el plan B | Dentro (claves 3 y 4). |
| 6. El trazo y las seis claves | Dentro (sección A). |
| 7. La exportación | Dentro (etapa 4 de la tabla B). El enlace que caduca y el borrado a los 7 días no aplican. Los valores CRF y preset de x264 tampoco: AVFoundation exporta con sus perfiles. |
| 8. El cobro | Fuera. |
| 9. La captación | Fuera. |
| 10. El mantenimiento | Cola con estado visible (en proceso, listo, falló) para los golpes del corte automático: dentro. Botón para corregir y aviso cuando se pierde la bola: dentro ("Tocar la bola"). GPU encendida: no aplica. Vigilar cambios de API: dentro (Vision y AVFoundation cambian con cada versión de iOS). Borrar vídeos de otros: no aplica. |
| 11. La cuenta honesta | Coste 0 €: no hay servidor ni comisiones. |
| 12. La letra pequeña | Punto 1 (lo difícil es el seguimiento): dentro, con prueba, toque de refuerzo, plan B, plan C y ajuste manual. Puntos 2, 3 y 5 (subida, cobro y privacidad): no aplican, nada sale del teléfono. Punto 4 (hay apps gratis que hacen lo mismo): no aplica a un uso personal. |
| "NO afirmamos" | Se mantiene el espíritu: la app no promete seguir siempre la bola ni dice que mide la distancia. |

## D. SAM 2.1: por qué no va por defecto y cuándo entra

**Por qué no va por defecto**
- Necesita una GPU fuera del iPhone: subir el vídeo, una cuenta en un servicio de nube, una clave y cobertura en el campo.
- La propia guía dice que no hay ninguna cifra publicada de SAM 2 siguiendo una bola de golf en un vídeo de móvil, y que le cuestan los objetos pequeños y rápidos.
- Vision y BlobTracker funcionan sin conexión, gratis y sin que el vídeo salga del teléfono. Si aguantan la prueba de cinco golpes, no hace falta más.

**Cuándo entra (etapa 4b, en `docs/00`)**
Solo si la prueba de cinco golpes da menos de 4 después de una vuelta de ajuste de parámetros.
1. **Prueba de laboratorio en el PC** con el código de la guía (librería `transformers`, modelo `facebook/sam2.1-hiera-tiny`) sobre los mismos cinco golpes. Gratis y sin cuentas. En el procesador de un portátil va lento (la guía cita unos 2 s por fotograma), así que solo se analiza la ventana del vuelo. Dos variantes: el fotograma entero, como en la guía, y un recorte cuadrado por encima de la bola ampliado a 1024 px (la bola sale más grande y SAM la ve mejor).
2. Si SAM 2.1 llega a 4 de 5 donde la app no llega, **se decide con el usuario** cómo meterlo:
   - **En el iPhone**: Apple publica SAM 2.1 tiny en Core ML (los archivos publicados son el codificador de imagen, el de puntos y el decodificador de máscaras; no aparece la memoria de vídeo). Se usaría fotograma a fotograma dentro de un recorte alrededor de la predicción de Kalman. Otra opción es EdgeTAM, la versión de SAM 2 para móviles de Meta (sus autores dan 16 fps en un iPhone 15 Pro Max), que no tiene conversión oficial a Core ML (hay alguna de la comunidad, sin revisar).
   - **En la nube, como en la guía**: una función en Modal (su web dice que el plan gratuito incluye 30 $ de cómputo al mes; no dice si pide tarjeta). La clave se escribe en Ajustes de la app y se guarda en el llavero, nunca en el repositorio, que es público. La app avisa de que el clip sale del teléfono.
3. Sin el visto bueno del usuario no se empieza ninguna integración.

## E. Fuentes

De la guía (leídas por su autor el 21 de octubre de 2026):
- SAM 2, artículo (límites y clics de refuerzo): https://arxiv.org/abs/2408.00714
- SAM 2 para vídeo en `transformers`: https://huggingface.co/docs/transformers/model_doc/sam2_video
- Banco de pruebas de objetos rápidos: https://arxiv.org/html/2512.09633v1
- Detección y seguimiento de bola de golf con CNN y Kalman: https://arxiv.org/abs/2012.09393
- Conjunto de imágenes de bolas de golf (pequeño, calidad sin comprobar): https://universe.roboflow.com/openlaunch/golf-ball-detection-mynhy
- ffmpeg, faststart: https://ffmpeg.org/ffmpeg-formats.html
- Apple, HEVC y compatibilidad: https://support.apple.com/en-us/116944

Añadidas para Trazo (leídas el 26 de octubre de 2026):
- Apple Vision, trayectorias: https://developer.apple.com/documentation/vision/detecting-moving-objects-in-a-video
- SAM 2.1 tiny en Core ML (Apple): https://huggingface.co/apple/coreml-sam2.1-tiny
- EdgeTAM, artículo: https://arxiv.org/abs/2501.07256 y modelo: https://huggingface.co/facebook/EdgeTAM
- Modal, precios: https://modal.com/pricing
