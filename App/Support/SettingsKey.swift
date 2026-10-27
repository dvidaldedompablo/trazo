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

    static let all = [tracerColor, tracerCustomColor, tracerShowsDistance]
}
