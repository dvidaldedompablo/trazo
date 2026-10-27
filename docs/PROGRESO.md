# Diario del proyecto

Claude Code actualiza este archivo al final de cada etapa.

## Estado
- Etapa actual: 1 (CI en verde; falta probar Inicio en el iPhone)
- Último .ipa: `builds/Trazo.ipa`, versión 0.1 (7), compilación nº 7 del CI del 27-10-2026
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
