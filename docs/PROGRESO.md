# Diario del proyecto

Claude Code actualiza este archivo al final de cada etapa.

## Estado
- Etapa actual: 0 (CI en verde; falta instalar y abrir la app en el iPhone)
- Último .ipa: `builds/Trazo.ipa`, versión 0.1 (1), run 40309500887 del 26-10-2026
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
