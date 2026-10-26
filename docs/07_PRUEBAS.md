# Pruebas y criterios de aceptación

## Tests automáticos (CI)
- GolfCore: ImpactDetector (clic sintético en ruido, varios clics, sin clic), Loudness (seno de 997 Hz a 0 dBFS = −3,01 LUFS), Geometry, Smoothing, Kalman2D, TrajectoryFit (parábola con 20 % de atípicos; un punto fijo se respeta), BlobTracker (bola sintética que sube, también sembrada a mitad de vuelo hacia delante y hacia atrás), TracerCurve (la bola sale de S en t = 0 y llega a L en t = T), PhaseDetector (series sintéticas de un swing), Scoring (casos límite y pesos), ScriptWriter (sin frases vacías, números en español), Units.
- Capturas: cada pantalla con `-UITestScreen` y comparación visual con `design/capturas/` (la hace Claude Code mirando las imágenes).

## Pruebas en el iPhone por etapa
| Etapa | Qué hacer | Qué tiene que pasar |
|---|---|---|
| 0 | Instalar con Sideloadly y abrir | Abre y se ve "Trazo" con su fuente |
| 1 | Abrir Inicio, cambiar color, tocar Distancia | El arco cambia de color; la etiqueta aparece y desaparece; vibración suave al caer la bola en el arranque |
| 3 | Grabar 10 s en modo Tracer; abrir el modo diagnóstico | fps = 240; la duración coincide con lo grabado |
| 3 | Grabar 3 golpes seguidos con Corte auto | Propone 3 clips, uno por golpe |
| 3 | Importar un vídeo a cámara lenta de Fotos | Diagnóstico: 240 fps y duración real (no estirada) |
| 4 | Prueba de 5 golpes (ver abajo) | Resultado anotado en PROGRESO.md |
| 4 | Grabar 3 golpes seguidos con Corte auto y procesarlos | Se procesan en cola; en Tus vídeos se ve el estado de cada uno |
| 5 | Crear un tracer con distancia y otro sin ella, con dos colores distintos | El trazo arranca en el impacto, dura el tiempo de vuelo y se ve como s09 |
| 5 | En un golpe en que la app pierda la bola: Tocar la bola en un fotograma posterior | Sale el aviso "Perdí la bola a los X s"; tras el toque, el trazo pasa por donde tocaste y sigue a la bola; "Deshacer" lo devuelve como estaba |
| 6 | 3 swings: revisar posiciones y comparar el ritmo con tu cuenta manual | Posiciones correctas o corregidas en 2 o 3 toques; ritmo con un error de 0,2 como máximo |
| 7 | Escuchar la vista previa del guion | Voz natural para lo que da iOS, subtítulos palabra a palabra, pausas como en la referencia |
| 8 | Generar un análisis completo y uno corto | Estructura de docs/08; completo entre 60 y 90 s; corto entre 30 y 40 s |
| 9 | Mirar la fecha de caducidad en Ayuda | Coincide con el día de instalación más 7 días |

## Prueba de 5 golpes (tracer)
Graba cinco golpes distintos y rellena la tabla en `docs/PROGRESO.md`:

| Golpe | Cielo y fondo | fps | Móvil | ¿Sigue la bola sin saltos? | ¿Caída creíble? | Notas |
|---|---|---|---|---|---|---|
| 1 | Despejado | 240 | Trípode | | | |
| 2 | Nublado | 240 | Trípode | | | |
| 3 | Árboles detrás | 240 | Trípode | | | |
| 4 | Despejado | 240 | Apoyado en la bolsa | | | |
| 5 | Despejado | 240 | En la mano | | | |

Se cuenta sin toques de refuerzo (mide el automático). Criterio de la guía de javiggil: **4 de 5 o más**, automático por defecto. Menos de 4: semiautomático por defecto, una vuelta de ajuste con los vídeos que fallaron y, si sigue sin llegar, la etapa 4b (`docs/00`).

## Cuenta manual del ritmo (para validar)
En "Revisa las posiciones", con el modo diagnóstico activado, apunta el número de fotograma de: inicio de la subida, top e impacto. Ritmo = (top − inicio) / (impacto − top). Compáralo con el de la app.

## Objetivos de rendimiento
- Tracer de un clip de 10 s a 240 fps: menos de 60 s.
- Vídeo de análisis completo: menos de 2 min.
- Memoria máxima: por debajo de 1,5 GB.
- Sin calentamiento excesivo: si el iPhone se pone en estado térmico serio, la app avisa y baja el muestreo.

## Lista de aceptación de la versión 1.0
- [ ] Inicio igual que la maqueta, con la vista previa en vivo y la animación de arranque.
- [ ] Grabar a 240 fps con guías, nivel, cuenta atrás y corte automático.
- [ ] Importar desde Fotos conservando los tiempos de la cámara lenta.
- [ ] Tracer automático con ajuste manual siempre disponible, toque de refuerzo ("Tocar la bola") y aviso claro cuando se pierde la bola.
- [ ] Las seis claves de la guía de javiggil cumplidas según `docs/09` (sección A).
- [ ] Color del trazo (5 fijos y uno a elegir) y distancia activable, con palo y unidades.
- [ ] Vídeo del tracer a 1080p con audio original, guardado en Fotos.
- [ ] Análisis con 7 posiciones revisables, medidas, ritmo, nota, fallos y ejercicios.
- [ ] Vídeo de análisis con voz, subtítulos palabra a palabra, líneas, tarjetas de ritmo, nota e informe.
- [ ] Ayuda con todos los capítulos y aviso de caducidad con notificación.
- [ ] Ajustes completos, historial con gráfico y "Tus vídeos".
- [ ] Errores claros: sin permisos, sin espacio, sin audio, vídeo corto, interrupciones, segundo plano.
- [ ] Accesibilidad: Dynamic Type, VoiceOver, Reducir movimiento.
- [ ] Ninguna llamada de red (la única excepción posible es la integración en la nube de la etapa 4b, si el usuario la aprueba). Nada personal en el repositorio.
