import Foundation

/// Nombres de los ajustes guardados con `@AppStorage` (se guardan en UserDefaults, dentro de la app).
/// Están juntos para que Inicio y, más adelante, la pantalla de Ajustes usen los mismos.
enum SettingsKey {
    /// Color del trazo por defecto: un `TracerColorChoice` guardado como texto.
    static let tracerColor = "tracer.color"
    /// "Otro color" del trazo, como número 0xRRGGBB.
    static let tracerCustomColor = "tracer.customColor"
    /// Si la etiqueta de distancia sale por defecto.
    static let tracerShowsDistance = "tracer.showsDistance"
    /// Obturación rápida al grabar en modo Tracer (por defecto sí; el interruptor llega con Ajustes).
    static let tracerFastShutter = "tracer.fastShutter"
    /// fps que se piden a la cámara: 240, 120 o 60.
    static let captureFrameRate = "capture.frameRate"
    /// Cuenta atrás antes de grabar, en segundos (0 = sin cuenta atrás).
    static let captureCountdown = "capture.countdown"
    /// Corte automático al parar.
    static let captureAutoCut = "capture.autoCut"
    /// Modo diagnóstico (5 toques en la versión, en Ajustes).
    static let diagnostics = "diagnostics.enabled"
    /// Mano dominante ("right" o "left"), para las reglas del swing.
    static let handedness = "user.handedness"
    /// Estatura en cm: la escala aproximada de las medidas del swing.
    static let heightCentimeters = "user.heightCm"
    /// Identificador de la voz elegida para el análisis (vacío = la mejor de español de España).
    static let analysisVoice = "analysis.voice"
    /// Generar la versión corta del vídeo del análisis (30 a 40 s) en vez de la completa.
    static let shortAnalysisVideo = "analysis.shortVideo"
    /// Subtítulos en el vídeo del análisis (activados por defecto).
    static let analysisSubtitles = "analysis.subtitles"

    static let all = [tracerColor, tracerCustomColor, tracerShowsDistance, tracerFastShutter,
                      captureFrameRate, captureCountdown, captureAutoCut, diagnostics,
                      handedness, heightCentimeters, analysisVoice, shortAnalysisVideo, analysisSubtitles]
}
