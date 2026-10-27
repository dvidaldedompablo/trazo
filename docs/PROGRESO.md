# Diario del proyecto

Claude Code actualiza este archivo al final de cada etapa.

## Estado
- Etapa actual: 2 terminada (CI en verde, 97 tests de GolfCore). Sigue pendiente probar Inicio de la etapa 1 en el iPhone.
- Último .ipa: `builds/Trazo.ipa`, versión 0.1 (9), compilación nº 9 del CI del 27-10-2026 (por fuera, igual que la 7)
- Repositorio: https://github.com/dvidaldedompablo/trazo (público)
- Última instalación en el iPhone: (fecha)
- Caduca: (fecha + 7 días)

## Registro

### Etapa 0: proyecto, compilación en la nube e instalación (26-10-2026)
- Hecho:
  - `project.yml` de XcodeGen: un target `Trazo`, iOS 26.0, solo iPhone, Swift 6, identificador `io.github.dvidaldedompablo.trazo`. El `.xcodeproj` y `App/Info.plist` los genera XcodeGen en el CI y no se suben.
  - `App/`: `TrazoApp.swift`, pantalla de prueba `Features/Home/HomeView.swift`, tokens mínimos en `DesignSystem/` (colores Bola, Pino y Texto 2; espacios; función `archivo()` y estilos `marca` y `sub`), `Support/BuildInfo.swift` y `Support/UITestHarness.swift`.
  - Fuente Archivo variable de google/fonts (`ofl/archivo/Archivo[wdth,wght].ttf`) en `App/Resources/Fonts/Archivo-Variable.ttf`, con su licencia `Archivo-OFL.txt`. Se registra con `UIAppFonts`.
  - Icono de la app (`design/AppIcon-1024.png`) en `App/Resources/Assets.xcassets`.
  - `Packages/GolfCore`: `Format/BuildLabel.swift` (texto de versión y fecha en español) con 4 tests de Swift Testing. La app lo usa, así que el CI comprueba también que el paquete enlaza.
  - Argumento de arranque `-UITestScreen home`. Un nombre desconocido muestra "Pantalla de prueba desconocida: X" en vez de otra pantalla.
  - `.github/workflows/ci.yml` con dos jobs en `macos-26`: "IPA y tests" (tests de GolfCore, `.ipa` sin firmar, artefactos `ipa` y `test-results`) y "Capturas del simulador" (`scripts/screenshots.sh`, artefacto `screenshots`).
- Decisiones:
  - Número de compilación = número de run del CI (`CURRENT_PROJECT_VERSION`), para saber qué compilación tienes instalada.
  - Fecha de compilación: el CI pasa el ajuste `TRAZO_BUILD_DATE` (ISO 8601, UTC) y el Info.plist la guarda en la clave `TrazoBuildDate`. La app la enseña en la hora del iPhone. Si falta, dice "Sin fecha de compilación".
  - Las capturas se hacen con `SIMCTL_CHILD_TZ=Europe/Madrid` para que las horas salgan en hora de Madrid.
  - Simulador: "iPhone 17e" con el iOS más nuevo instalado (en este run, iOS 26.5).
  - Acciones: `actions/checkout@v7`, `actions/upload-artifact@v7`, `maxim-lobanov/setup-xcode@v1` con `latest-stable` (Xcode 26.6, Swift 6.3.3).
  - `trazo-kit.zip` queda fuera del repo (su contenido ya está en `docs/` y `design/`).
- Notas técnicas:
  - El nombre PostScript de la fuente variable es `Archivo-SemiBold` (su instancia por defecto: peso 600, anchura 100). Ejes: `wght` 100 a 900 y `wdth` 62 a 125. Los demás pesos y anchuras se piden con `kCTFontVariationAttribute`.
  - Comprobación de la fuente en la captura: "Trazo" mide 236 x 79 px. Un render local con la misma fuente en anchura 70 y peso 850 da 245 x 80 (la diferencia es el kerning de iOS). La instancia por defecto daría 294 x 79. Las formas coinciden: iOS aplica bien los ejes.
- Problemas y cómo se resolvieron: ninguno; el CI salió en verde a la primera.
- Pendiente: instalar con Sideloadly y abrir la app en el iPhone (lo hace el usuario).
- Pruebas para el iPhone:
  - La app aparece como "Trazo" con el icono del arco rojo sobre fondo verde oscuro.
  - Al abrirla se ve el fondo blanco roto, "Trazo" en letra estrecha y gruesa, "Versión 0.1 (1)" y "Compilada el 26 de octubre de 2026, 11:43".
  - No aparece el aviso "No se ha cargado la fuente Archivo".
- Qué he aprendido de Swift en esta etapa:
  - `@main` marca dónde arranca la app. `TrazoApp` cumple el protocolo `App` y su `body` devuelve una ventana (`WindowGroup`) con la primera vista.
  - Cada pantalla es un `struct` que cumple `View`: SwiftUI vuelve a dibujarla a partir de su `body`, y los modificadores (`.font`, `.background`) se encadenan.
  - Un `enum` sin casos (`Typography`, `BuildInfo`) sirve de espacio de nombres para agrupar constantes y funciones. `@MainActor` obliga a usarlas desde el hilo principal, donde vive la interfaz: Swift 6 lo comprueba al compilar.
  - Una fuente variable lleva todos los pesos y anchuras en un solo archivo; se elige un punto de cada eje (`wght`, `wdth`) con un descriptor de fuente de UIKit, y `UIFontMetrics` la adapta al tamaño de texto de Ajustes.
  - iOS convierte los argumentos de arranque `-Clave valor` en valores de `UserDefaults`. Así funciona `-UITestScreen home` sin leer los argumentos a mano.
  - Swift Testing: los tests son funciones marcadas con `@Test` y `#expect` comprueba cada condición. `swift test` los ejecuta en el CI.

### Etapa 1: sistema de diseño e Inicio (27-10-2026)
- Hecho:
  - Tokens en `App/DesignSystem/`: paleta completa de docs/02 (`Colors.swift`, con los colores de las ilustraciones aparte en `SceneColors`), colores del trazo (`TracerColors.swift`), espacios, radios y tamaños (`Spacing.swift`), sombra de la tarjeta del Tracer (`Shadows.swift`) y estilos de texto (`Typography.swift`).
  - Tipografía: `TypeStyle` con los 12 estilos de la tabla de docs/02 y algunos más de la maqueta (`etiqueta`, `filaTitulo`, `filaSub`, `subCompacto`). Se aplican con `.typeStyle(.sub)`. Archivo y SF Pro crecen con Dynamic Type (el modificador lee el tamaño de texto del entorno, así cambian en el acto). El alto de línea se reparte como en CSS: medio arriba, medio abajo y entero entre líneas.
  - Componentes en `App/DesignSystem/Components/`: botones en cápsula `.principal`, `.secundario` y `.amarillo` con `RecordDot`; botón redondo `.circleIcon`; botón de cristal `CrystalButtonStyle` (Liquid Glass sobre vídeo y "cristal oscuro" plano en la tarjeta de Análisis); `ColorSwatchRow` (5 colores y "Otro color", que abre el selector de colores de iOS); `DistanceToggle` con interruptor de 48 x 29 pt; `InstrumentCard`; `HelpRow`; `Chip` (claro y sobre vídeo); `TracerStroke` (trazo en capas que adelgaza, con la bola en la punta mientras vuela).
  - Inicio (`App/Features/Home/`): marca con el arco, botones Tus vídeos y Ajustes, tarjeta del Tracer con la escena de la maqueta dibujada en un `Canvas` (cielo, sol, dos filas de árboles, calle con franjas, carteles de 100 y 150), tarjeta de Análisis con la figura del telestrador y fila de Ayuda.
  - Vista previa en vivo: el trazo funde al color nuevo en 0,2 s; la etiqueta "Hierro 7, 150 m" aparece y desaparece con un muelle de 0,25 s, creciendo desde el punto de caída.
  - Animación de arranque: el arco se dibuja una vez en 1,3 s (tras 0,3 s, con una curva que sube rápido y frena) y, al caer la bola, hay una vibración ligera, aparece el punto de caída y la distancia cuenta de 0 a 150 m en 0,6 s. Con "Reducir movimiento" (y en las capturas del CI) todo sale ya en su sitio, sin vibración.
  - Color, "Otro color" e interruptor se guardan con `@AppStorage` (claves en `Support/SettingsKey.swift`, las mismas que usará Ajustes).
  - Las acciones abren pantallas provisionales con su título y la etapa en que llegan. Grabar golpe y Grabar swing son negras (pantallas de vídeo). La de Ajustes enseña de momento la versión y la fecha de compilación, que antes estaban en Inicio.
  - CI: captura `home` y una nueva `components` (catálogo de componentes, con cristal y chips sobre el fotograma de `design/demo/escena_tracer.png`, copiado a `App/Resources/DemoData/`).
- Decisiones:
  - Iconos: SF Symbols de docs/02 (`film.stack`, `gearshape`, `book.pages`, `photo.on.rectangle`) en vez de los dibujados en la maqueta. Si hay conflicto, manda el documento.
  - Interruptor propio (un `Toggle` con estilo) en vez del de iOS 26, que es más ancho y no cabe junto a las seis muestras. VoiceOver lo lee como un interruptor normal.
  - "Otro color" se dibuja como en la maqueta (anillo arcoíris; si es el elegido, con el color dentro) y al tocarlo abre `UIColorPickerViewController`. El `ColorPicker` de SwiftUI tiene un botón de aspecto fijo.
  - El "cristal oscuro" de la tarjeta de Análisis es plano (blanco al 12 % con borde al 16 %), como en la maqueta: docs/02 reserva Liquid Glass para controles sobre vídeo.
  - La escena de la vista previa usa las coordenadas exactas del SVG de la maqueta (358 x 180) y se escala al ancho de la tarjeta; en el iPhone 17e la escala es 1.
  - La etiqueta de la vista previa usa "Hierro 7" y 150 m, la distancia por defecto de "Mis palos" (docs/01). Unidades fijas en metros hasta que exista Ajustes.
  - Con letra muy grande (tamaños de accesibilidad), la fila de colores y las parejas de botones se ponen una debajo de otra, y los textos de los botones encogen un poco antes de cortarse.
- Comparación con s01 (un script en Python mide filas y columnas de tinta y colores de píxel en las dos capturas, a la misma escala):
  - Vuelta 1: las tarjetas medían 370 pt en vez de 358. La fila de colores no cabía porque el `HStack` ponía 8 pt a cada lado del `Spacer`; la tarjeta crecía, la ventana se escalaba (6 pt más alta) y todo lo de abajo bajaba 7-8 pt. Corregido con separación 0 y `Spacer(minLength: 4)`, como el `space-between` de la maqueta.
  - Vuelta 2: tarjeta del Tracer 2,5 pt más alta (SF Pro deja la descripción 1 pt más abajo que Inter); halo del trazo más flojo; figura del golfista 3 pt a la izquierda; flecha de Ayuda 4 pt a la derecha. Corregido: huecos de la tarjeta ajustados a SF Pro, halo al 64 % (la maqueta pinta 56 segmentos al 42 % que se solapan; medido por el color de los píxeles), columna de texto y figura recolocadas, flecha de 13 pt en una caja de 18.
  - Vuelta 3: fila de Ayuda 2 pt más alta; corregida con una guía de alineación.
  - Resultado: cabecera, ventana (cielo, sol, hierba, árboles y carteles iguales al píxel), trazo, etiqueta, textos, muestras, botones y tarjetas coinciden con 0,5 pt o menos.
  - Diferencias que quedan a propósito: iconos SF Symbols; barra de estado real del simulador; "Trazo" 1,5 pt más ancha (el interletraje de iOS, ya visto en la etapa 0); en la maqueta el botón "Elegir vídeo" se sale 6 pt del margen derecho de la tarjeta, aquí los dos botones quedan a 18 pt de cada lado.
- Problemas y cómo se resolvieron:
  - Cambio de API: iOS 26 trae su propio `GlassButtonStyle` y `.buttonStyle(.glass)`. Con un estilo propio del mismo nombre, `.glass` era ambiguo y no compilaba. El nuestro se llama `CrystalButtonStyle` (`.crystal`).
  - Para que la distancia cuente desde 0 al caer la bola, la etiqueta existe ya (invisible) antes de la caída: a una vista recién insertada SwiftUI no le puede animar la cifra porque no tiene valor anterior.
- Pendiente:
  - Probar en el iPhone la animación de arranque, la vibración, el selector de "Otro color" y el aspecto general (lista de abajo).
  - Aviso amarillo de caducidad bajo la cabecera: llega con la lectura de la caducidad en la etapa 9.
  - Palo, distancia y unidades reales en la etiqueta: con "Mis palos" y Ajustes (etapas 3 y 9).
- Pruebas para el iPhone:
  - Al abrir la app, el arco rojo se dibuja de abajo a la izquierda hasta la caída en algo más de un segundo, con una bola brillante en la punta.
  - Justo cuando la bola cae notas una vibración ligera, aparece el punto blanco de caída y la etiqueta "Hierro 7" cuenta hasta "150 m".
  - Toca cada color: el arco cambia con un fundido corto. El elegido lleva un anillo blanco y otro verde oscuro.
  - Toca el anillo arcoíris: se abre el selector de colores de iOS; al elegir uno, el arco toma ese color y el centro del anillo también.
  - Toca "Distancia": la etiqueta desaparece encogiéndose hacia el punto de caída; tócalo otra vez y vuelve.
  - Cierra la app del todo (deslizando hacia arriba en el selector de apps) y ábrela: el color y la distancia siguen como los dejaste, y la animación se repite.
  - Activa Ajustes > Accesibilidad > Movimiento > Reducir movimiento y abre la app desde cero: todo aparece ya dibujado, sin animación ni vibración.
  - Toca Tus vídeos, Ajustes, Grabar golpe, Elegir vídeo, Grabar swing, el botón redondo de la tarjeta de Análisis y Ayuda: cada uno abre su pantalla provisional con el título; Grabar golpe y Grabar swing en negro. Ajustes enseña "Versión 0.1 (7)" y la fecha de compilación.
  - Si quieres, prueba con el texto grande (Ajustes > Pantalla y brillo > Tamaño del texto): nada debe cortarse ni salirse de las tarjetas.
- Qué he aprendido de Swift en esta etapa:
  - Un `ButtonStyle` o un `ToggleStyle` cambia solo el aspecto de un control: sigue siendo un botón o un interruptor para VoiceOver. `extension ButtonStyle where Self == PillButtonStyle` permite escribir `.buttonStyle(.principal)`.
  - `@AppStorage` es como `@State`, pero guarda el valor en el iPhone; con un `enum` de texto (`TracerColorChoice`) se guarda su `rawValue`.
  - Una animación de SwiftUI interpola `animatableData`: el trazo (`Shape`) y el contador de metros (una `View` que cumple `Animatable`) se redibujan con cada valor intermedio. En Swift 6 esa propiedad lleva `nonisolated` porque SwiftUI puede pedirla fuera del hilo principal.
  - `Canvas` dibuja muchas formas de una vez con un `GraphicsContext` (rellenos, trazos, degradados, texto y capas con opacidad), como un `<svg>`.
  - `.task` lanza trabajo asíncrono al aparecer la vista y lo cancela al desaparecer; `Task.sleep` lanza un error si se cancela, y eso se usa para dejar la animación terminada.
  - `.sensoryFeedback` hace vibrar cuando cambia un valor; `@Environment(\.accessibilityReduceMotion)` dice si el usuario pidió menos movimiento.

### Etapa 2: lógica pura en GolfCore con tests (27-10-2026)
- Hecho (todo en `Packages/GolfCore`, solo Foundation: nada de UIKit, SwiftUI, AVFoundation ni Accelerate):
  - `Math/`: `Point2D` (y hacia abajo, como los fotogramas), álgebra lineal mínima (Gauss con pivote, mínimos cuadrados, mediana) y `SeededRandom` (aleatorio con semilla, para que el RANSAC y los tests salgan siempre igual).
  - `Math/Geometry`: ángulo en un vértice, entre segmentos y entre rectas, con la vertical y con la horizontal, intersección, distancia a recta y a segmento, y `PixelScale` (px por cm con la cadena tobillo-rodilla-cadera-cuello-nariz = 87 % de la estatura).
  - `Math/Smoothing`: One Euro (muestra a muestra, para puntos y números), Savitzky-Golay con derivadas y extremos bien resueltos, y relleno de huecos de hasta 4 muestras.
  - `Math/Kalman2D`: velocidad constante, predicción y corrección, distancia de Mahalanobis y radio de la puerta de búsqueda.
  - `Math/TrajectoryFit`: tramos de 0,25 s solapados, RANSAC (variante LMedS) sobre x(t) e y(t) de segundo grado, atípico si se aleja más de 3 × el error mediano del tramo, toques fijos con peso 100 que nunca se descartan, error medio y extrapolación hasta la caída.
  - `Audio/`: biquads (filtrado ida y vuelta sin retraso), FFT propia de base 2, `ImpactDetector` (paso banda 1,5 a 7 kHz, flujo espectral en ventanas de 256 cada 64, umbral mediana + 6 MAD en 500 ms, 400 ms de periodo refractario, afinado con la envolvente en ±5 ms) y `Loudness` (BS.1770: ponderación K, puertas de −70 LUFS y −10 LU, pico real con sobremuestreo x4, ganancia hasta −16 LUFS con techo de −1 dBTP).
  - `Tracer/TracerConstants`: la tabla de parámetros de docs/03 en un solo archivo, con la tabla de palos.
  - `Tracer/TracerCurve`: dos Bézier con la cima redonda, forma draw/recta/fade, tiempo de vuelo, posición de la bola en cada instante, trozo de trazo dibujado hasta un instante y propuesta inicial por palo.
  - `Tracer/BlobTracker`: fondo por mediana de 15 fotogramas, umbral por píxel según su ruido, manchas de 1 a 40 px compactas, Kalman con puerta, arranque desde el tee, semilla en cualquier fotograma hacia delante y hacia atrás, y motivo del final (perdida, fuera de la imagen o fin del clip).
  - `Swing/`: articulaciones de Vision y mano dominante (`Pose`), `PhaseDetector` (inicio de la subida, 7 posiciones con sus alternativas, orden y ritmo), `SwingMetrics` (las 16 medidas de docs/04), `Scoring`, `FaultLibrary`, `ScriptWriter` y `SwingRules` (todas las constantes del swing en un sitio).
  - `Format/Units`: números en español, "2,8 : 1" y "2,8 a 1", "~2 cm", grados, segundos, m y yd, nota "78/100" y duraciones habladas ("siete décimas").
  - CI: no hizo falta tocarlo; el paso "Tests de GolfCore" ya ejecuta `swift test` y ahora pasa 97 tests en 14 suites (8,7 s en el runner).
  - `scripts/test-golfcore.sh`: los mismos tests en el PC con Docker (imagen oficial `swift:6.3`, la misma versión que el CI). Explicado en docs/06.
- Qué cubre cada test (`Packages/GolfCore/Tests/GolfCoreTests/`, datos sintéticos de `SyntheticData.swift`):
  | Suite | Qué comprueba |
  |---|---|
  | `ImpactDetectorTests` | La FFT pone un seno en su frecuencia. Un clic en ruido se detecta con menos de 2 ms de error (3 semillas). Tres clics dan tres impactos en su sitio. Solo ruido, silencio o audio demasiado corto: ningún impacto. Dos clics a menos de 400 ms cuentan como uno (el fuerte). Con golpes de otros jugadores, el más fuerte es el propio. Un tono grave fuerte no es un impacto. |
  | `LoudnessTests` | Los coeficientes de la ponderación K a 48 kHz son los de la tabla de BS.1770. Un seno de 997 Hz a 0 dBFS en un canal da −3,01 LUFS (en mono y en estéreo con un canal mudo); a −20 dBFS, −23,01. Las pausas no bajan la cifra. Silencio o menos de 400 ms: sin valor. El pico real encuentra el pico escondido entre muestras. La ganancia se limita por el techo de pico. |
  | `GeometryTests` | Ángulos (recto, pierna estirada, vertical, horizontal sin sentido, segmentos y rectas), segmentos de longitud cero sin ángulo, intersección y paralelas, distancias con signo y a segmento, escala de px a cm con 175 cm. |
  | `SmoothingTests` | Savitzky-Golay deja intacto un polinomio de grado 3 (también en los extremos), da la derivada exacta de una parábola, quita ruido y se adapta a series cortas. One Euro calma el temblor y, con beta, se queda menos atrás en un movimiento rápido. Relleno de huecos cortos sí, largos y de los extremos no. |
  | `KalmanFilter2DTests` | La predicción mueve con la velocidad; la duda crece al predecir y baja al corregir; la puerta crece sin medidas; aprende la velocidad de un movimiento con ruido; Mahalanobis crece con la distancia. |
  | `TrajectoryFitTests` | Una parábola con un 20 % de atípicos se recupera: todos los atípicos fuera, como mucho un 2 % de puntos buenos descartados y la curva a menos de 1 px de la verdadera. Un toque fijo se respeta (no es atípico y la curva pasa a menos de 1 px). Un toque muy desviado sube el error medio. La extrapolación cae a menos de 0,1 s y 15 px de la caída verdadera; si la bola no tiende a bajar, no se inventa la caída. Con menos de 3 instantes no hay ajuste. Los tramos se solapan. |
  | `TracerCurveTests` | La bola sale de S en t = 0 y llega a L en t = T; pasa por el vértice a mitad del vuelo; la curva pasa por las tres asas con cualquier forma; la velocidad baja siempre, sin saltos en el vértice, y al final va a menos de un tercio de la de salida; el perfil llega al vértice en τ = 0,5 y sale 2,4 cuando la subida es el 81 %; draw y fade doblan a lados opuestos (y al revés en zurdos); el trazo crece con el tiempo; la curva por defecto queda a menos de 1,5 px de la de la maqueta; la propuesta inicial usa la tabla de palos. |
  | `BlobTrackerTests` | Con fotogramas sintéticos (cielo, suelo, jugador, palo que barre, pájaro y ruido), sigue la bola desde el tee hasta el final (90 % de los fotogramas, error < 1 px). Sembrada a mitad de vuelo sin velocidad, sigue hacia delante y hacia atrás; sembrada cerca del final con velocidad, también. Si la bola deja de verse, para a los 12 fotogramas y dice dónde la perdió (0,2 s). El fondo borra el palo, el palo alargado no cuenta como bola y el pájaro está lejos del vuelo. Sin fotogramas antes del impacto no arranca. |
  | `PhaseDetectorTests` | En un swing sintético (brazo en péndulo), las 7 posiciones caen donde deben y en orden; ritmo = subida / bajada; sin sonido, el impacto sale de las manos; un zurdo reflejado da las mismas posiciones; sin el brazo de delante se usa la alternativa del 55 %; sin movimiento no hay swing; un impacto antes del top marca posiciones dudosas. |
  | `SwingMetricsTests` | Un swing correcto: todas las medidas en rango (inclinación 32°, plano de unos 40°, escala de 5 px/cm). Un swing con fallos: takeaway por dentro, palo plano, cabeza 8 cm, se levanta 12° (de 32 a 20) y cadera 6 cm, cada uno con su fallo. Sin palo se omiten las medidas del palo. Un zurdo da las mismas medidas. Reglas: penalización proporcional y fallo solo pasado su umbral. |
  | `ScoringTests` | Todo bien da 100; los pesos dan 81 en un caso calculado a mano; mínimo 2 por fase; etiquetas en sus límites; a mejorar son las 3 más bajas por debajo de 7; prioridad por peso × (10 − nota); cadena de causa (takeaway por dentro antes que palo plano); una fase sin medidas no cuenta; sin medidas no hay nota; de punta a punta con el swing sintético. |
  | `ScriptWriterTests` | En 6 escenarios y 8 variantes, todas las frases tienen de 4 a 14 palabras, sin huecos, sin punto decimal y con punto final. Gancho según la nota. "Por eso," en la cadena de causa. Números dichos bien ("2,8 a 1", "de 35 a 23 grados", "unos 8 centímetros", "N sobre 100"). Ritmo rápido y lento. Lo que no se mide se dice. Misma semilla, mismo guion. La biblioteca de fallos está completa. |
  | `UnitsTests` | Coma decimal, redondeo (2,85 → 2,9), signo menos, sin separador hasta 4 cifras, ritmo, "~2 cm", grados, segundos, "150 m" y "164 yd", y duraciones habladas. |
  | `BuildLabelTests` | Los de la etapa 0 (versión y fecha). |
- Decisiones:
  - Asas siempre sobre la curva: la forma (draw o fade) abomba el vuelo hacia un lado entre las asas en vez de mover el vértice fuera de su asa (docs/03 actualizado). Constantes de los Bézier ajustadas para parecerse a la curva de la maqueta.
  - Perfil de tiempo: 1 − (1 − τ)^k con k elegido en cada curva para llegar al vértice en τ = 0,5 (entre 1,2 y 4; con la subida en el 81 % sale el 2,4 de docs/03). Probé antes a mantener 2,4 en la subida y repartir la bajada, pero con la curva de la maqueta la bola no frenaba al final (docs/03 actualizado).
  - Impacto: además de "mediana + 6 MAD", el pico tiene que superar 4 veces la mediana local. Probado en Python: con ruido blanco, "mediana + 6 MAD" daba hasta 4 falsos impactos en 3 s (sus picos no pasan de 2,9 veces la mediana); un clic claro la supera de 10 a 80 veces.
  - Extrapolación: si todo lo visto encaja en una parábola, se usa entera; si no, los últimos 0,5 s. Con solo 0,5 s la caída salía a 23 px de la verdadera en el test.
  - BlobTracker: umbral por píxel con su ruido en los 15 fotogramas del fondo (las hojas con viento piden más diferencia que el cielo), se ignora el "hueco" que deja la bola en el tee, un toque se ajusta a la mancha más cercana a menos de 6 px y una mancha que toca el borde de la zona de búsqueda se descarta (es un trozo de algo grande). Solo se buscan manchas cerca de la predicción, no en toda la imagen.
  - Fallos: a los 13 de docs/04 se suman 4 para que cada medida tenga su fallo y su ejercicio por los dos lados: brazos pegados, bajada plana, ritmo lento y final corto. "Cadera hacia la bola" usa el fallo "Te levantas en el impacto" (mismo ejercicio de la silla).
  - Nota: docs/04 solo fija 0,25 puntos por grado de inclinación. Las demás penalizaciones están en `SwingRules` como valores de partida "(a afinar)" con el profesor. Una fase sin ninguna medida (por ejemplo, sin tocar la cabeza del palo) no cuenta en la nota total y el informe lo dice.
  - Guion: solo se nombra un fallo si la medida pasa su umbral de fallo (por ejemplo, "Subida corta" por debajo de 0,10 aunque la fase ya reste por debajo de 0,35).
  - FFT propia en vez de Accelerate: para 256 muestras es de sobra rápida y así GolfCore compila en Linux (tests en el PC con Docker).
- Problemas y cómo se resolvieron:
  - `Measurement` chocaba con el tipo del mismo nombre de Foundation. Se llama `MetricResult` (también habría chocado en la app).
  - Swift Testing no deja anidar `#require` dentro de otro `#require` (expansión recursiva de la macro): se sacan a variables.
  - Por precaución no se usan rutas de clave a elementos de tuplas (`\.0`); se usan cierres (`{ $0.0 }`).
  - En el CI aparecía un aviso de concurrencia de la etapa 1 en la fila de Ayuda (`Cards.swift`): la constante se marca `nonisolated`.
- Pendiente (para las etapas que los usan):
  - Etapa 4: comprobaciones de dirección y velocidad máxima de la bola (`maximumBallSpeed`, a fijar con la prueba de 5 golpes), confianza de 0 a 1 y aviso de pérdida con el tiempo de `BlobTrack`. Los valores de `BlobTrackerOptions` (umbral, ruido del Kalman, radio de arranque) están probados solo con datos sintéticos: se afinan con vídeos reales.
  - Etapa 6: el takeaway por "palo paralelo al suelo" (alternativa con la cabeza del palo) y "a dónde apunta la empuñadura" en la mitad de subida no están (hacen falta los puntos del palo de la pantalla de revisión). La tolerancia de "manos quietas" (1 % de la estatura) se revisa con swings reales: en el sintético la preparación cae unos fotogramas después del arranque teórico.
  - Etapa 7: `Loudness` mide y calcula la ganancia; aplicarla y montar la pista es de la etapa 7.
- Pruebas para el iPhone: ninguna en esta etapa (no cambia nada que se vea). El `.ipa` nuevo se ve igual que el de la etapa 1.
- Qué he aprendido de Swift en esta etapa:
  - Los `struct` son valores: al pasarlos se copian, y un método que los cambia se marca `mutating` (como `KalmanFilter2D.predict`). Por eso el filtro de ida y el de vuelta del toque de refuerzo no se pisan.
  - Un `enum` sin casos agrupa funciones (`Geometry`, `Scoring`); un `enum` con casos y `switch` (`FaultID`, `MetricKind`) obliga al compilador a comprobar que no falta ningún caso.
  - `Sendable` le dice a Swift 6 que un tipo se puede pasar entre hilos sin peligro; en tipos de valor con datos simples basta con declararlo.
  - Cumplir un protocolo de la biblioteca estándar (`RandomNumberGenerator` en `SeededRandom`) hace que funcionen cosas que ya existen, como `Int.random(in:using:)`.
  - Swift Testing permite repetir un test con varios datos (`arguments:`) y `#require` para el test en seco si falta un valor, en vez de seguir con un `nil`.
  - `guard let … else { return nil }` es la forma de Swift de decir "si falta esto, no invento nada": se usa en todas las medidas.

<!-- Plantilla por etapa:
### Etapa N: título (fecha)
- Hecho:
- Decisiones:
- Problemas y cómo se resolvieron:
- Pendiente:
- Pruebas para el iPhone:
- Qué he aprendido de Swift en esta etapa:
-->

## Prueba de 5 golpes
Criterio de la guía de javiggil: 4 de 5 o más, sin toques de refuerzo (`docs/03`).
(pendiente)

## Etapa 4b: SAM 2.1 en prueba de laboratorio
Solo si la prueba de 5 golpes no llega a 4 después de la vuelta de ajuste.
(no hace falta por ahora)
