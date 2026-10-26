# Plan por etapas y mensajes para Claude Code

Cómo usar este documento:
- Haz **una etapa por sesión**. Antes de empezar una etapa nueva, escribe `/clear` en Claude Code para empezar con la memoria limpia (el archivo `CLAUDE.md` se vuelve a leer solo).
- Copia el bloque "Mensaje para pegar" tal cual en el panel de Claude Code.
- No pases a la siguiente etapa hasta cumplir "Está terminada cuando".
- Si llegas al límite de uso del plan Pro, espera a que se renueve y escribe: `Continúa la etapa N donde la dejaste. Lee docs/PROGRESO.md primero.`

Orden y dependencias:

| Etapa | Qué se construye | Depende de | Pruebas en el iPhone |
|---|---|---|---|
| 0 | Proyecto, compilación en la nube e instalación | nada | Sí: abrir la app |
| 1 | Sistema de diseño e Inicio | 0 | Sí: aspecto y animación |
| 2 | Lógica pura (GolfCore) con tests | 0 | No |
| 3 | Cámara, importación y biblioteca | 1, 2 | Sí: grabar a 240 fps |
| 4 | Tracer automático | 3 | Sí: prueba de 5 golpes |
| 4b | Opcional: SAM 2.1 de la guía en prueba de laboratorio (solo si la prueba de 5 golpes no llega a 4) | 4 | No: se prueba en el PC con los mismos 5 golpes |
| 5 | Tracer: ajuste manual, estilo y vídeo | 4 | Sí: vídeo final |
| 6 | Swing: pose, fases, revisión y medidas | 3 | Sí: 3 swings |
| 7 | Swing: guion, voz y subtítulos | 6 | Sí: escuchar |
| 8 | Swing: montaje del vídeo | 7 | Sí: vídeo final |
| 9 | Ayuda, ajustes, historial y caducidad | 5, 8 | Sí: repaso completo |
| 10 | Pulido y versión 1.0 | todo | Sí: lista final |

---

## Etapa 0. Proyecto, compilación en la nube e instalación

Objetivo: comprobar toda la cadena antes de escribir funciones. Una app mínima que se compila en GitHub, se descarga como `.ipa` y se instala en el iPhone.

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/01_ARQUITECTURA.md y docs/06_CI_INSTALACION.md.

Etapa 0: quiero una app mínima "Trazo" que se compile en GitHub Actions y que pueda instalar en mi iPhone con Sideloadly.

1. Comprueba que tengo git y gh instalados y que `gh auth status` incluye el permiso "workflow". Si falta algo, para y dime el comando exacto que tengo que ejecutar yo.
2. Crea la estructura del proyecto de docs/01_ARQUITECTURA.md: project.yml de XcodeGen, carpeta App/, paquete Packages/GolfCore con un test de ejemplo, Resources/Fonts, .gitignore y .gitattributes (eol=lf).
3. Descarga la fuente Archivo variable (licencia OFL) del repositorio google/fonts y añádela con su licencia. Registra la fuente y úsala en la pantalla de prueba.
4. La pantalla de prueba: fondo #F6F7F4, la palabra "Trazo" en Archivo (anchura 70, peso 850) y debajo la versión y la fecha de compilación.
5. Implementa el argumento de arranque -UITestScreen (por ahora solo "home").
6. Crea .github/workflows/ci.yml según docs/06: genera el proyecto, compila el .ipa sin firmar, pasa los tests de GolfCore y hace la captura en el simulador.
7. Crea un repositorio público llamado "trazo" en mi cuenta con gh, haz commit y push.
8. Vigila el CI con `gh run watch`. Si falla, lee el log, corrige y repite hasta que esté en verde.
9. Descarga el .ipa a builds/ y las capturas a ci-artifacts/. Mira la captura y confirma que se ve la fuente Archivo.
10. Crea docs/PROGRESO.md y termina con un resumen en español y los pasos que tengo que hacer yo para instalarlo (el Word los explica, solo dime dónde está el archivo).

No añadas funciones de la app todavía.
```

**Lo que haces tú**: instalar el `.ipa` con Sideloadly (Parte 5 del Word) y abrir la app.

**Está terminada cuando**: el CI está en verde, `builds/Trazo.ipa` existe, la captura muestra "Trazo" con la fuente correcta y la app abre en tu iPhone.

---

## Etapa 1. Sistema de diseño e Inicio

**Mensaje para pegar**
```
Lee CLAUDE.md y docs/02_DISENO.md. Mira design/maqueta.html (lee el código: los colores, tamaños y posiciones salen de ahí) y las capturas de design/capturas/.

Etapa 1: construye el sistema de diseño y la pantalla de Inicio igual que la captura s01.png.

1. App/DesignSystem: colores, tipografía (Archivo con ejes de anchura y peso mediante variaciones de fuente, y SF Pro del sistema), espaciados, radios y sombras de docs/02.
2. Componentes reutilizables de docs/02: botones (principal, secundario, amarillo, cristal), fila de colores, interruptor de distancia, tarjeta de instrumento, fila de ayuda, chips.
3. Inicio: marca "Trazo" con el arco rojo, botones "Tus vídeos" y "Ajustes", tarjeta del Tracer con la vista previa en vivo (el arco cambia de color al elegir muestra y la etiqueta de distancia aparece o desaparece con el interruptor), tarjeta de Análisis de swing con la figura de telestrador, y la fila de Ayuda.
4. El trazo de la vista previa se dibuja en tres capas (halo difuminado, color, núcleo blanco) y adelgaza hacia el final, como en la maqueta.
5. Animación de arranque: el arco se dibuja una vez, la distancia cuenta hasta "150 m" cuando la bola cae y hay una vibración suave en ese momento. Con "Reducir movimiento" activado, se muestra todo sin animar.
6. Las acciones abren pantallas provisionales con su título. El color y el interruptor se guardan en los ajustes.
7. Añade -UITestScreen home y haz que el CI capture Inicio.
8. Compara la captura del CI con design/capturas/s01.png. Escribe la lista de diferencias que veas y corrígelas hasta que sea casi idéntica. Repite el ciclo las veces que haga falta.
9. Actualiza docs/PROGRESO.md, push, CI en verde, descarga el .ipa y dime qué mirar en el iPhone.
```

**Está terminada cuando**: la captura del CI y `s01.png` se parecen casi del todo, y en el iPhone el arco cambia de color, la distancia aparece y desaparece, y la vibración llega cuando cae la bola.

---

## Etapa 2. Lógica pura en Swift (GolfCore) con tests

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/01_ARQUITECTURA.md (sección GolfCore), docs/03_TRACER.md (secciones de algoritmos) y docs/04_ANALISIS_SWING.md (medidas, fases, nota y guion).

Etapa 2: implementa en Packages/GolfCore, sin UIKit ni SwiftUI, estos módulos con tests unitarios de datos sintéticos:
1. ImpactDetector: encuentra el impacto en una señal de audio (filtro de banda, flujo espectral, umbral adaptativo). Test: un "clic" sintético dentro de ruido se detecta con un error menor de 2 ms; varios clics dan varios impactos.
2. Smoothing: filtro One Euro y Savitzky-Golay para series de puntos.
3. Geometry: ángulos entre segmentos, ángulo con la vertical, distancias, conversión de píxeles a cm con la estatura.
4. TrajectoryFit: ajuste robusto por tramos (RANSAC sobre x(t), y(t) cuadráticos) de puntos con atípicos, con puntos fijos que nunca se descartan (los toques del usuario), y extrapolación hasta la caída. Test: una parábola con un 20 % de atípicos se recupera; un punto fijo se respeta.
5. KalmanFilter2D: posición y velocidad constantes con predicción y corrección.
6. TracerCurve: modelo de vuelo editable (salida, altura, caída, forma draw/recta/fade, tiempo de vuelo) que devuelve la curva y la posición de la bola en cada instante con un perfil de velocidad creíble.
7. PhaseDetector: las 7 posiciones a partir de series de articulaciones y del instante de impacto.
8. SwingMetrics y Scoring: medidas, notas por fase, pesos y nota total según docs/04.
9. FaultLibrary y ScriptWriter: fallos, ejercicios y frases del guion en español según docs/04.
10. Units y formato de números en español (coma decimal, "2,8 : 1", "~2 cm").
11. Loudness: sonoridad integrada según BS.1770 y ganancia hasta un objetivo. Test: un seno de 997 Hz a 0 dBFS en un canal da −3,01 LUFS.
12. BlobTracker: plan B del tracer (docs/03): fondo por mediana, diferencia de fotogramas, manchas pequeñas y Kalman. Acepta una semilla en cualquier fotograma y sigue hacia delante y hacia atrás (para el toque de refuerzo). Test con fotogramas sintéticos de una bola que sube, también sembrando a mitad de vuelo.

Comentarios en español en cada algoritmo. Que el CI ejecute los tests. Actualiza docs/PROGRESO.md con qué cubre cada test.
```

**Está terminada cuando**: todos los tests pasan en el CI y `PROGRESO.md` explica qué hace cada módulo.

---

## Etapa 3. Cámara, importación y biblioteca

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/01_ARQUITECTURA.md (captura, importación, biblioteca) y docs/02_DISENO.md (pantalla Grabar). Mira design/capturas/s02.png.

Etapa 3:
1. Pantalla Grabar (modo Tracer y modo Swing) como s02.png: vista de cámara a 1080p y 240 fps (si no se puede, 120 y luego 60), con audio. Guías según el modo (silueta fantasma de dónde ponerse, línea del golpe y marca de la bola en Tracer; silueta de perfil en Swing), indicador de nivel con CoreMotion, cuenta atrás opcional (3, 5 o 10 s), botón de grabar, miniatura del último clip y "Corte auto".
2. Corte automático: al parar, usa ImpactDetector sobre el audio para proponer un clip por golpe (Tracer: 1 s antes y 8 s después del impacto; Swing: 2,5 s antes y 2 s después). El usuario elige cuáles guardar.
3. Importar desde Fotos con PhotosPicker. Si es un vídeo a cámara lenta, usa el original para conservar los tiempos reales (ver docs/01).
4. Biblioteca con SwiftData (Clip, ajustes, palos) y la pantalla "Tus vídeos", con la acción "Guardar original en Fotos" en cada clip (sin cambios, a sus fps reales), para que yo pueda pasarte vídeos al ordenador cuando necesites verlos.
5. Permisos con textos en español (cámara, micrófono, fotos) y pantallas claras si se deniegan.
6. Modo diagnóstico oculto (Ajustes, 5 toques en la versión) que muestra fps reales, duración y el instante de impacto encontrado.
7. -UITestScreen camera-tracer, camera-swing y library con datos de demostración; compara con las capturas y corrige.
8. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa descargado y lista de pruebas para el iPhone.
```

**Está terminada cuando**: en el iPhone grabas a 240 fps (lo ves en el modo diagnóstico), el corte automático propone un clip por golpe y un vídeo a cámara lenta importado conserva los tiempos reales.

---

## Etapa 4. Tracer automático

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/03_TRACER.md entero y docs/09_GUIA_JAVIGGIL.md (secciones A y B: el tracer sigue esa guía adaptada). Mira design/capturas/s03.png.

Etapa 4: el tracer automático.
1. Flujo: elegir clip, encontrar el impacto por el sonido (con la comprobación de movimiento de docs/03), localizar la bola antes del impacto (automático; si el fotograma sale movido, buscar uno nítido; si no hay confianza, pedir un toque con pasos de fotograma y lupa).
2. Detección de la bola en vuelo con DetectTrajectoriesRequest de Vision sobre la ventana posterior al impacto, con zona de interés y los parámetros de docs/03, y BlobTracker a la vez.
3. Montaje de la trayectoria: elegir la trayectoria correcta, quitar atípicos por tramos, ajustar y extrapolar hasta la caída con TrajectoryFit y TracerCurve. Calcular una confianza.
4. Toque de refuerzo y aviso de pérdida (docs/03, paso 4 bis): la función que vuelve a seguir la bola desde un punto tocado en cualquier fotograma, hacia delante y hacia atrás, y el aviso "Perdí la bola a los X s". La interfaz completa llega en la etapa 5; aquí deja la función lista y que se pueda probar desde el modo diagnóstico.
5. Pantalla "Creando tu tracer" como s03.png, con la onda real del sonido, el marcador de impacto y los puntos de la bola apareciendo en directo.
6. Si la confianza es baja o se pierde la bola, pasar al ajuste manual con una propuesta inicial razonable (docs/03, sección "propuesta inicial") y el aviso de pérdida.
7. Cola para varios golpes del corte automático, con estado visible en Tus vídeos (en proceso, listo, falló).
8. En el modo diagnóstico, dibujar los puntos brutos, los toques, los descartados y la curva ajustada sobre el vídeo.
9. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa y dime cómo hacer la prueba de 5 golpes de docs/07.
```

**Lo que haces tú**: la prueba de 5 golpes (Parte 7 del Word) y apuntar el resultado.

**Está terminada cuando**: has hecho la prueba de 5 golpes y el resultado está en `PROGRESO.md`. El criterio es el de la guía: 4 de 5 o más. Si no llega, el modo por defecto pasa a ser el semiautomático (eso no es un fracaso: está previsto) y se sigue el orden de `docs/03`: una vuelta de ajuste con los vídeos que fallaron y, si sigue sin llegar, la etapa 4b.

---

## Etapa 4b (opcional). SAM 2.1, el modelo de la guía, en prueba de laboratorio

Solo si la prueba de 5 golpes no llega a 4 después de la vuelta de ajuste. Si llega, sáltala.

**Lo que haces tú antes**: en "Tus vídeos", "Guardar original en Fotos" con los 5 golpes de la prueba; pasarlos al ordenador tal cual, a 240 fps (Parte 8 del Word); y copiarlos a `feedback/prueba5/` con los nombres `1.mov` a `5.mov`, en el orden de la tabla de la prueba.

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/09_GUIA_JAVIGGIL.md (sección D) y docs/PROGRESO.md (resultado de la prueba de 5 golpes).

Etapa 4b, prueba de laboratorio en mi PC: quiero saber si SAM 2.1, el modelo de la guía, sigue la bola mejor que la app en mis 5 golpes de feedback/prueba5/. No toques la app.

1. Crea lab/sam2/ (en .gitignore todo salvo los .py y un README). Comprueba si tengo Python 3.11 o posterior; si no, dime la orden de winget para instalarlo y espera.
2. Entorno virtual en lab/sam2/.venv con torch (versión para CPU), transformers, opencv-python y numpy. Comprueba en la documentación vigente de transformers las clases de SAM 2 para vídeo (la guía usa Sam2VideoModel y Sam2VideoProcessor con facebook/sam2.1-hiera-tiny) y ajústalo si han cambiado.
3. Para cada vídeo: encuentra el impacto por el sonido (pico de energía entre 1,5 y 7 kHz) y extrae la ventana desde 0,3 s antes del impacto hasta 2,5 s después, a 120 fps.
4. Abre una ventana con el fotograma de 0,3 s antes del impacto para que yo haga clic en la bola (con zoom). Guarda el punto.
5. Ejecuta SAM 2.1 tiny con ese punto como positivo, con vídeo y estado en la CPU, en dos variantes: A) el fotograma entero, como la guía; B) un recorte cuadrado por encima de la bola (lado: la mitad del ancho del vídeo) ampliado a 1024 px. Saca el centro de la máscara en cada fotograma; una máscara vacía o demasiado grande cuenta como bola perdida. Lánzalo en segundo plano con un archivo de progreso y vigila la memoria del PC.
6. Para cada vídeo y variante, genera un MP4 en feedback/prueba5/resultado/ con los puntos y la línea que los une, y apunta: fotogramas con bola, último instante con bola, saltos y tiempo de cálculo.
7. Escribe en PROGRESO.md una tabla que compare SAM 2.1 (A y B) con la app, y tu recomendación: ¿SAM 2.1 llega a 4 de 5 sin saltos donde la app no llega?
8. Si SAM 2.1 gana, no lo integres. Propónme las opciones de docs/09 sección D con pros, contras y coste, y espera a que elija.
```

**Lo que haces tú**: hacer clic en la bola de cada vídeo cuando se abra la ventana, dejar el ordenador trabajando (puede tardar una o dos horas) y mirar los vídeos de `feedback/prueba5/resultado/`.

**Está terminada cuando**: la tabla está en `PROGRESO.md` y has decidido entre seguir con la app como está, integrar SAM 2.1 con la opción que elijas o pasar al plan C de `docs/03`.

---

## Etapa 5. Tracer: ajuste manual, estilo y vídeo final

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/03_TRACER.md (ajuste, estilo, exportación) y docs/02_DISENO.md (gráficos del vídeo del tracer). Mira s04.png, s05.png y s09.png.

Etapa 5:
1. Pantalla "Ajusta el vuelo" como s04.png: vídeo encajado en negro, tres asas (salida, altura, caída) que se arrastran, línea de tiempo con el impacto, botón de cristal "Tocar la bola" (docs/03 paso 4 bis y docs/02: pausa, pasos de fotograma, lupa x3, toque, volver a seguir y deshacer), aviso "Perdí la bola a los X s" cuando toque, forma (draw, recta, fade), altura, tiempo de vuelo, colores (5 fijos más uno a elegir) e interruptor de distancia con valor y palo.
2. Distancia: valor manual o el de "Mis palos" (docs/03). Unidades m o yd según ajustes. Nunca se presenta como medida.
3. Render del vídeo con los gráficos de docs/02: trazo en tres capas que adelgaza con la distancia, cabeza de la bola brillante, dibujo progresivo sincronizado con el tiempo de vuelo desde el instante exacto del impacto, marca de caída y etiqueta de palo y distancia si está activada. Marca de agua "Trazo" opcional.
4. Exportar MP4 H.264 (4:2:0) a la resolución del original hasta 1080p, con el audio original y shouldOptimizeForNetworkUse para que se reproduzca sin cargarse entero (docs/03, Exportación). Guardar en Fotos y compartir.
5. Pantalla de resultado como s05.png. "Editar" vuelve al ajuste sin perder nada.
6. -UITestScreen adjust y tracer-result con datos de demostración; compara y corrige.
7. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa y lista de pruebas.
```

**Está terminada cuando**: el vídeo exportado se parece a `s09.png`, el trazo arranca justo en el impacto y dura el tiempo de vuelo elegido, el color y la distancia funcionan, y en un golpe en el que la app perdió la bola, "Tocar la bola" recompone el trazo.

---

## Etapa 6. Swing: pose, fases, revisión y medidas

**Mensaje para pegar**
```
Lee CLAUDE.md y docs/04_ANALISIS_SWING.md (grabación, pose, fases, revisión, medidas y nota). Mira s06.png y s07.png.

Etapa 6:
1. Pose por fotograma con DetectHumanBodyPoseRequest de Vision (revisión 2), muestreando como dice docs/04, suavizado y mano dominante según ajustes.
2. Impacto por el sonido y las 7 posiciones con PhaseDetector.
3. Pantalla "Revisa las posiciones" como s06.png: fotograma grande con el esqueleto, tira de 7 miniaturas, avanzar o retroceder fotograma a fotograma, toque en la cabeza del palo en la preparación y ajuste de la línea del palo en las posiciones 3 y 5.
4. Medidas, notas por fase, ritmo, fallos y prioridad según docs/04, con la escala de cm a partir de la estatura de ajustes.
5. Pantalla "Tu análisis" como s07.png (todavía sin vídeo: muestra el fotograma de la preparación con las líneas).
6. En el modo diagnóstico, superponer el esqueleto en todos los fotogramas y mostrar la tabla de medidas.
7. -UITestScreen review y swing-result con datos de demostración; compara y corrige.
8. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa y dime cómo validar con 3 swings (docs/07).
```

**Está terminada cuando**: con 3 swings tuyos, las posiciones caen en el fotograma correcto (o se corrigen con 2 o 3 toques), el ritmo coincide con tu cuenta manual de fotogramas y las medidas te parecen creíbles.

---

## Etapa 7. Swing: guion, voz y subtítulos

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/04_ANALISIS_SWING.md (guion, voz y audio) y docs/08_REFERENCIA_VIDEO.md (ritmo de la narración y análisis del audio).

Etapa 7:
1. Generar el guion con ScriptWriter a partir del análisis (frases cortas, de tú, números escritos para leerse bien).
2. Voz con AVSpeechSynthesizer.write(_:toBufferCallback:toMarkerCallback:) para obtener el audio y el tiempo de cada palabra. Una frase por llamada.
3. Selector de voz en ajustes: voces de español de España primero, con su calidad (normal, mejorada, premium), botón "Probar" y explicación de cómo descargar voces mejores. Voz personal opcional si está autorizada.
4. Montar la pista de voz con los silencios de docs/04 y normalizar el volumen al objetivo indicado allí.
5. Modelo de subtítulos palabra a palabra (lo dicho en blanco, lo que falta atenuado).
6. Pantalla de vista previa del guion: reproduce la voz con los subtítulos sincronizados sobre el fotograma de cada fase, antes de generar el vídeo.
7. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa y dime qué escuchar.
```

**Está terminada cuando**: escuchas la narración en el iPhone, los subtítulos van palabra a palabra con la voz y las pausas suenan naturales.

---

## Etapa 8. Swing: montaje del vídeo

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/04_ANALISIS_SWING.md (montaje), docs/02_DISENO.md (gráficos del vídeo del análisis) y docs/08_REFERENCIA_VIDEO.md (estructura). Mira s10.png y s11.png.

Etapa 8:
1. Constructor de la línea de tiempo con los bloques de docs/04: gancho a velocidad real, cámara lenta con líneas, 7 pausas, ritmo, nota, informe y cierre. La duración de cada bloque la manda su narración.
2. Gráficos de telestrador por fase, etiquetas de medidas, chip de fase "n/7", estado (pausa o cámara lenta), contador de fotograma y subtítulos sincronizados.
3. Tarjetas de datos: ritmo con barras animadas, nota con cuenta desde 0 y la tabla estilo tarjeta de golf (círculo punto fuerte, cuadrado a mejorar), informe con puntos fuertes, a mejorar, ejercicios y prioridad.
4. Exportar 1080x1920 a 30 fps, H.264 y AAC. Guardar en Fotos y compartir. Versión completa y versión corta según ajustes.
5. Barra de progreso de generación con pasos (como la del tracer).
6. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa y lista de pruebas.
```

**Está terminada cuando**: el vídeo generado sigue la estructura de `docs/08`, se parece a `s10.png` y `s11.png`, la voz y los subtítulos van sincronizados y la duración completa queda entre 60 y 90 s.

---

## Etapa 9. Ayuda, ajustes, historial y caducidad

**Mensaje para pegar**
```
Lee CLAUDE.md, docs/05_AYUDA_CONTENIDO.md y docs/02_DISENO.md (Ayuda, Ajustes, Tus vídeos). Mira s08.png.

Etapa 9:
1. Ayuda como s08.png con los capítulos y textos de docs/05.
2. Aviso de caducidad: lee la fecha de caducidad del perfil incrustado en la app (embedded.mobileprovision), muéstrala en Ayuda y en Inicio cuando falten 2 días o menos, y programa una notificación local 24 h antes.
3. Ajustes completos de docs/02: unidades, mano dominante, estatura, Mis palos y distancias, voz, duración del vídeo, subtítulos, marca de agua, color y distancia por defecto, modo diagnóstico.
4. Historial: lista de análisis y gráfico de nota y ritmo en el tiempo con Swift Charts.
5. Accesibilidad: Dynamic Type, etiquetas de VoiceOver en español, Reducir movimiento, tamaños táctiles de 44 pt.
6. Estados vacíos y de error con los textos de docs/02.
7. -UITestScreen help, settings y history; compara y corrige.
8. Actualiza docs/PROGRESO.md, push, CI en verde, .ipa y lista de pruebas.
```

**Está terminada cuando**: la fecha de caducidad que muestra la app coincide con la instalación más 7 días y todas las pantallas se parecen a la maqueta.

---

## Etapa 10. Pulido y versión 1.0

**Mensaje para pegar**
```
Lee CLAUDE.md y docs/07_PRUEBAS.md.

Etapa 10:
1. Repasa rendimiento y memoria con los objetivos de docs/07 (añade marcas de tiempo con os_signpost y un informe en el modo diagnóstico).
2. Revisa todos los caminos de error: sin permisos, sin espacio, vídeo sin audio, vídeo demasiado corto, rotación, interrupciones (llamada entrante), app en segundo plano durante la exportación.
3. Pasa la lista de aceptación de docs/07 punto por punto y dime cuáles tengo que comprobar yo en el iPhone.
4. README con qué es la app y cómo se compila e instala.
5. Etiqueta v1.0 y deja el .ipa de esa versión en builds/.
```

**Está terminada cuando**: la lista de aceptación de `docs/07` está completa.

---

## Mensajes útiles para cualquier momento

```
El CI ha fallado. Mira el último fallo con gh, explícame la causa en una frase y arréglalo.
```
```
He dejado un vídeo en feedback/. Extrae fotogramas y el audio con ffmpeg, mira qué falla respecto a lo que pide docs/ y corrígelo.
```
```
La pantalla X no se parece a design/capturas/sNN.png. Compáralas, haz la lista de diferencias y corrígelas.
```
```
Explícame cómo funciona el archivo NOMBRE.swift como si estuviera aprendiendo Swift: qué hace cada parte y por qué.
```
```
Antes de seguir: resume en 5 líneas en qué punto estamos según docs/PROGRESO.md.
```
