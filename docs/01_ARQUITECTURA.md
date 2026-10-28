# Arquitectura

## Decisiones de base (y por qué)
| Decisión | Motivo |
|---|---|
| App nativa en SwiftUI | El usuario quiere aprender Swift; Vision y AVFoundation solo existen en nativo y son gratis y rápidos. |
| Todo en el iPhone, sin servidor | Uso personal, gratis, privado y funciona sin cobertura en el campo. |
| La guía de javiggil como base del tracer | Sus seis claves están dentro, adaptadas a una app sin servidor. `docs/09` dice qué se tomó, qué se cambió y por qué. |
| Apple Vision y BlobTracker en lugar de SAM 2.1 | SAM 2.1 necesita una GPU fuera del iPhone (subir vídeos, cuenta, cobertura) y la guía no tiene cifras con bolas de golf. Vision tiene detección de trayectorias pensada para bolas en vuelo y pose corporal, en el propio iPhone; BlobTracker es el plan B de la guía. SAM 2.1 queda como etapa 4b opcional, solo si la prueba de 5 golpes falla. |
| Compilar en GitHub Actions | No hay Mac. Los runners de macOS son gratis en repositorios públicos. |
| XcodeGen | Un `project.yml` legible que Claude Code puede escribir sin Xcode; el `.xcodeproj` se genera en el CI. |
| `.ipa` sin firmar + Sideloadly | Instalación con Apple ID gratuito, sin pagar la cuenta de desarrollador. |
| GolfCore como paquete aparte | La lógica pura se prueba con tests en el CI sin cámara ni iPhone. |

## Estructura de carpetas
```
trazo/
├── CLAUDE.md
├── project.yml                      # XcodeGen
├── .github/workflows/ci.yml
├── App/
│   ├── TrazoApp.swift
│   ├── DesignSystem/                # Colors, Typography, Spacing, Components/
│   ├── Features/
│   │   ├── Home/
│   │   ├── Capture/                 # cámara, guías, corte automático
│   │   ├── Library/                 # Tus vídeos
│   │   ├── Tracer/                  # pipeline, editor, render, resultado
│   │   ├── Swing/                   # pose, revisión, voz, render, informe
│   │   ├── Help/
│   │   ├── Settings/
│   │   └── History/
│   ├── Media/                       # lectura de fotogramas y audio, exportación, Fotos, cámara lenta
│   ├── Support/                     # UITestHarness, ProvisioningInfo, Haptics, Diagnostics, Logging
│   └── Resources/                   # Fonts/, Assets.xcassets (icono), DemoData/
├── Packages/GolfCore/
│   ├── Package.swift
│   ├── Sources/GolfCore/            # Audio/, Math/, Tracer/, Swing/, Format/
│   └── Tests/GolfCoreTests/
├── design/                          # maqueta.html y capturas/
├── docs/
├── builds/        (ignorado)        # .ipa descargados
├── ci-artifacts/  (ignorado)        # capturas y logs del CI
└── feedback/      (ignorado)        # vídeos y capturas que deja el usuario
```

## GolfCore (lógica pura, con tests)
Sin UIKit, SwiftUI ni AVFoundation. Entradas y salidas con tipos simples (`[Float]`, `[CGPoint]` o un `struct Point2D`, `TimeInterval`).

| Módulo | Qué hace |
|---|---|
| `Audio/ImpactDetector` | Encuentra impactos en PCM mono. Filtro paso banda 1,5 a 7 kHz, envolvente, flujo espectral con vDSP o FFT propia, umbral adaptativo (mediana móvil + k·MAD), período refractario de 400 ms. Devuelve instantes con su fuerza. |
| `Audio/Loudness` | Sonoridad integrada según ITU-R BS.1770 (ponderación K y puertas) y ganancia para llegar a un objetivo. Test: un seno de 997 Hz a 0 dBFS en un canal da −3,01 LUFS. |
| `Math/Geometry` | Ángulos, ángulo con la vertical, intersecciones, distancia punto-recta, escala px a cm. |
| `Math/Smoothing` | Filtro One Euro y Savitzky-Golay. |
| `Math/Kalman2D` | Kalman de velocidad constante. |
| `Math/TrajectoryFit` | RANSAC por tramos + mínimos cuadrados de x(t), y(t) cuadráticos, puntos fijos (toques) que nunca se descartan, extrapolación, error medio. |
| `Tracer/TracerCurve` | Curva editable del vuelo (salida, altura, caída, forma, tiempo) y posición de la bola en el instante t. |
| `Tracer/BlobTracker` | Plan B: detección de la bola por diferencia de fotogramas en imágenes en gris reducidas (`[UInt8]`), con Kalman. Acepta semillas en cualquier fotograma y sigue hacia delante y hacia atrás (toque de refuerzo). |
| `Swing/PhaseDetector` | Las 7 posiciones a partir de series de articulaciones e impacto. |
| `Swing/SwingMetrics` | Medidas de `docs/04`. |
| `Swing/Scoring` | Notas por fase, pesos, nota total y etiqueta. |
| `Swing/FaultLibrary` | Fallos, reglas, frases y ejercicios. |
| `Swing/ScriptWriter` | Guion en español por bloques. |
| `Format/Units` | Números en español, m y yd, "2,8 : 1", "~2 cm". |

## Flujo de datos
```
Grabar o importar ──► Clip (archivo en el contenedor de la app + metadatos en SwiftData)
        │
        ├─ Tracer: audio ► ImpactDetector ► bola antes del impacto ► Vision trayectorias + BlobTracker
        │          ► TrajectoryFit + TracerCurve ► confianza ► (aviso de pérdida, toque de refuerzo ► volver a seguir)
        │          ► (ajuste manual) ► TracerRenderer ► MP4 ► Fotos
        │
        └─ Swing:  audio ► ImpactDetector ─┐
                   fotogramas ► Vision pose ► Smoothing ► PhaseDetector ► Revisión ► SwingMetrics ► Scoring
                   ► FaultLibrary ► ScriptWriter ► VoiceEngine (audio + tiempos de palabra)
                   ► TimelineBuilder ► SwingRenderer ► MP4 ► Fotos
```

## Captura a 240 fps
- Buscar en `AVCaptureDevice.formats` uno de 1920x1080 cuyo `videoSupportedFrameRateRanges` llegue a 240. Fijar `activeFormat`, `activeVideoMinFrameDuration` y `activeVideoMaxFrameDuration` a 1/240. Si no existe, 120 y luego 60.
- Cámara gran angular principal. Estabilización desactivada (va en trípode y la estabilización recorta y retrasa).
- Modo Tracer: opción "Obturación rápida" (por defecto activada con buena luz). Exposición personalizada con duración corta (empezar en 1/2000 s) e ISO automático dentro de los límites del formato. La bola sale menos movida y se detecta mejor.
- `AVCaptureMovieFileOutput` con audio (micrófono). Orientación vertical con `videoRotationAngle`.
- Indicador de nivel con CoreMotion (gravedad), verde cuando el móvil está recto.

## Importar desde Fotos sin perder la cámara lenta
- `PhotosPicker` con `photoLibrary: .shared()` para obtener el `itemIdentifier`.
- `PHAsset` ► `PHImageManager.requestAVAsset(forVideo:options:)` con `version = .original`. Así se recibe el archivo a 240 fps con tiempos reales, sin el efecto de cámara lenta aplicado.
  - Cómo quedó en la etapa 3: se copia el recurso original del `PHAsset` (`PHAssetResource` de tipo `.video`) con `PHAssetResourceManager.writeData(for:toFile:options:)`. Es el mismo archivo original, se escribe directamente en la carpeta de la app y funciona también si está en iCloud.
- Si el usuario no da acceso a Fotos, importar el archivo con `Transferable` y comprobar `nominalFrameRate` y duración. Si parece estirado, avisar: "Este vídeo viene con la cámara lenta aplicada. Las duraciones del ritmo pueden salir mal."

## Lectura de fotogramas y audio
- Fotogramas: `AVAssetReader` + `AVAssetReaderTrackOutput` en `420YpCbCr8BiPlanarFullRange` (formato cómodo para Vision). Recorrer con tiempos de presentación.
- Audio: `AVAssetReader` a PCM Float32 mono, 48 kHz.
- Miniaturas: `AVAssetImageGenerator`.

## Vision
- Pose: `DetectHumanBodyPoseRequest` (API de Swift, revisión 2). Descartar articulaciones con confianza < 0,3. Muestreo: 120 fps (uno de cada dos fotogramas a 240) en el swing completo.
- Trayectorias: `DetectTrajectoriesRequest` (o `VNDetectTrajectoriesRequest`). Es una petición con estado: misma instancia para toda la secuencia y fotogramas en orden. **Solo funciona en un dispositivo real**, no en el simulador. Parámetros de partida en `docs/03`.
- Seguimiento de apoyo: `TrackObjectRequest` sembrado con una caja pequeña alrededor de la bola en los primeros fotogramas tras el impacto, solo para confirmar la dirección de salida.

## Render y exportación
- Ediciones de tiempo con `AVMutableComposition`: tramo a velocidad real, cámara lenta con `scaleTimeRange`, pausas insertando un fotograma y estirándolo.
- Gráficos con `AVVideoCompositionCoreAnimationTool`: `CAShapeLayer` (trazo, líneas, arcos; `strokeEnd` animado para dibujar), `CATextLayer` (subtítulos, cifras), capas con imágenes. Animaciones con `beginTime = AVCoreAnimationBeginTimeAtZero + t`, `isRemovedOnCompletion = false`, `fillMode = .both`.
- Tarjetas de datos complejas: dibujarlas con SwiftUI y `ImageRenderer` a imagen, y usarlas como contenido de capa.
- Si Core Animation se queda corto (por ejemplo, el halo difuminado del trazo), usar un compositor propio (`AVVideoCompositing`) que dibuje con Core Image o Core Graphics fotograma a fotograma.
- Exportar con `AVAssetExportSession` (API asíncrona de iOS 18+), MP4, `shouldOptimizeForNetworkUse = true`. Tracer: 1080p con el audio original. Análisis: 1080x1920 a 30 fps, H.264 y AAC.
- Guardar en Fotos con `PHPhotoLibrary.shared().performChanges` (permiso de solo añadir).

## Voz (Análisis de swing)
- `AVSpeechSynthesizer.write(_:toBufferCallback:toMarkerCallback:)` (iOS 17+): una llamada por frase. Se recogen los `AVAudioPCMBuffer` y los marcadores de palabra.
- Convertir la posición de cada marcador a segundos con el formato real del búfer (frecuencia de muestreo y bytes por muestra). Comprobar que los tiempos son crecientes y caben en la duración; si no, repartir el tiempo de la frase entre palabras según su longitud, con pausas en las comas.
- Voces: `AVSpeechSynthesisVoice.speechVoices()` filtradas por español, primero `es-ES`, ordenadas por calidad (premium, mejorada, normal). Voz personal con `requestPersonalVoiceAuthorization` si el usuario la ha creado (Apple la ofrece en español de México).
- Velocidad: ajustar `rate` hasta unas 155 palabras por minuto medidas con los marcadores.
- Opcional (etapa 9 o posterior): reescribir el guion con el modelo de Apple en el dispositivo (Foundation Models) si está disponible, manteniendo números y estructura. El guion por plantillas es siempre la base.

## Datos (SwiftData)
- `Clip`: id, fecha, modo (tracer o swing), ruta del archivo, fps, duración, instante de impacto, miniatura.
- `TracerResult`: clip, parámetros de la curva, toques de refuerzo (fotograma y punto), color, mostrar distancia, distancia, unidad, palo, estado (en proceso, listo, falló y motivo), ruta del vídeo.
- `SwingAnalysis`: clip, 7 instantes, medidas, notas por fase, nota total, ritmo, fallos, guion, ruta del vídeo.
- `Club`: nombre, distancia de vuelo por defecto, orden.
- Ajustes sencillos con `@AppStorage`.

Lista inicial de palos (editable en Ajustes, solo "Hierro 7" con valor): Driver, Madera 3, Madera 5, Madera 7, Hierro 5, Hierro 6, Hierro 7 (150 m), Hierro 8, Hierro 9, PW, AW, Wedge 52°, Wedge 56°, Wedge 60°.

## Caducidad de la app
- Leer `embedded.mobileprovision` del bundle, extraer el bloque XML (de `<?xml` a `</plist>`) y obtener `ExpirationDate` con `PropertyListSerialization`.
- Mostrar la fecha en Ayuda y un aviso en Inicio cuando falten 2 días o menos. Notificación local 24 h antes.
- En el simulador no existe el archivo: no mostrar nada.

## Arnés de capturas para el CI
- Argumento `-UITestScreen <nombre>`: la app abre directamente esa pantalla con datos de `DemoData` (sin cámara ni permisos), animaciones desactivadas y hora fija.
- Nombres: home, camera-tracer, camera-swing, processing, adjust, tracer-result, review, swing-result, help, settings, library, history.

## Concurrencia y rendimiento
- Pipelines como funciones `async` o actores, con progreso por `AsyncStream` y cancelación.
- Nada pesado en el hilo principal. Liberar búferes de vídeo en cuanto se usan.
- Objetivos: tracer de un clip de 10 s a 240 fps en menos de 60 s; vídeo de análisis completo en menos de 2 min; memoria máxima por debajo de 1,5 GB. Si `thermalState` es `.serious`, avisar y bajar el muestreo.
- Registro con `os.Logger` por categorías y marcas `os_signpost` para medir tiempos.
